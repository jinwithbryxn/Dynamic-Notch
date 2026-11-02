import Foundation
import Network
import Security

/// 로컬 개발자 API: 127.0.0.1 TCP, 줄바꿈으로 끝나는 JSON 한 줄, 요청마다 `token`.
/// HTTP 서버가 아니다. HTTP 요청 줄은 형식 오류로 거절한다.
///
/// 토큰은 두 가지다.
/// - 개발자 토큰: 키체인에만 둔다. 모든 명령 가능 (사용자가 설정에서 복사해 스크립트에 쓴다).
/// - 훅 토큰: 에이전트 훅·셸 훅 전용 명령만 가능. 훅 프로세스(perl·zsh)는 이 앱의 키체인 항목을 프롬프트 없이 읽을 수 없어서
///   키체인 값과 같은 것을 0600 파일(`endpoint`)에도 둔다. 다시 만들면 이전 값은 바로 무효.
final class LocalAPIServer {
    static let shared = LocalAPIServer(config: .live)

    enum Scope: String { case developer, hook }

    /// 명령 처리 결과
    enum Reply {
        case now([String: Any])
        /// 처리기가 연결을 들고 있다가 나중에 `reply`로 답한다 (승인 요청)
        case hold
    }

    struct Request {
        let command: String
        let json: [String: Any]
        let scope: Scope
        let connection: LocalAPIConnection
    }

    typealias Handler = (Request) -> Reply

    struct Config {
        /// 개발자 토큰 읽기·쓰기 (기본: 키체인)
        var loadToken: (String) -> String?
        var saveToken: (String, String?) -> Void
        /// 훅이 읽는 endpoint 파일을 둘 폴더 (nil이면 쓰지 않음)
        var endpointDir: URL?
        /// 설정된 포트 (기본 9999)
        var port: () -> UInt16
        /// 설정 포트가 쓰이는 중이면 임시 포트로 대신 열지
        var fallbackToEphemeral: Bool

        static let live = Config(
            loadToken: { KeychainStore.get($0) },
            saveToken: { KeychainStore.set($1, for: $0) },
            endpointDir: LocalAPIServer.defaultEndpointDir,
            port: { UInt16(clamping: ModuleDefaults(module: "localapi").int("port", default: 9999)) },
            fallbackToEphemeral: true)
    }

    static let developerTokenKey = "localapi.token"
    static let hookTokenKey = "localapi.hookToken"

    /// 이 앱 전용 지원 폴더 아래 훅 폴더 (번들 ID별로 따로)
    static var defaultEndpointDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.dynamicnotch.app")
            .appendingPathComponent("agent-hooks")
    }

    // 한도
    static let maxLineBytes = 512 * 1024
    static let maxConnections = 16
    static let perConnectionRate = 20.0     // 초당
    static let perConnectionBurst = 40.0
    static let firstLineTimeout: TimeInterval = 5
    static let idleTimeout: TimeInterval = 30

    let config: Config
    let queue = DispatchQueue(label: "com.dynamicnotch.localapi")

    // 아래 상태는 메인 스레드에서만 바꾼다
    private var handlers: [String: (owner: String, scopes: Set<Scope>, run: Handler)] = [:]
    private var owners: Set<String> = []
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: LocalAPIConnection] = [:]   // queue에서만
    private var developerToken: String?
    private var hookToken: String?

    /// 상태 (UI 표시용, 메인 스레드)
    enum State: Equatable {
        case stopped
        case starting(UInt16)
        case listening(UInt16, fallbackFrom: UInt16?)
        case failed(String)
    }
    private(set) var state: State = .stopped { didSet { NotificationCenter.default.post(name: Self.stateChanged, object: self) } }
    static let stateChanged = Notification.Name("LocalAPIServer.stateChanged")

    init(config: Config) {
        self.config = config
    }

    // MARK: 사용 등록 (모듈이 켜질 때 acquire, 꺼질 때 release)

    func register(owner: String, command: String, scopes: Set<Scope>, handler: @escaping Handler) {
        handlers[command] = (owner, scopes, handler)
    }

    func unregister(owner: String) {
        handlers = handlers.filter { $0.value.owner != owner }
    }

    func acquire(_ owner: String) {
        owners.insert(owner)
        if listener == nil { start() }
    }

    func release(_ owner: String) {
        owners.remove(owner)
        unregister(owner: owner)
        if owners.isEmpty { stop() }
    }

    var isRunning: Bool { listener != nil }
    var registeredCommands: [String] { handlers.keys.sorted() }

    /// 포트 설정이 바뀌면 다시 연다
    func restartIfRunning() {
        guard listener != nil else { return }
        stop()
        if !owners.isEmpty { start() }
    }

    // MARK: 토큰

    /// 개발자 토큰 (없으면 만든다)
    func ensureDeveloperToken() -> String {
        if let t = developerToken { return t }
        if let t = config.loadToken(Self.developerTokenKey), !t.isEmpty { developerToken = t; return t }
        let t = Self.randomToken()
        config.saveToken(Self.developerTokenKey, t)
        developerToken = t
        return t
    }

    func ensureHookToken() -> String {
        if let t = hookToken { return t }
        if let t = config.loadToken(Self.hookTokenKey), !t.isEmpty { hookToken = t; return t }
        let t = Self.randomToken()
        config.saveToken(Self.hookTokenKey, t)
        hookToken = t
        return t
    }

    /// 다시 만들기: 이전 토큰은 바로 무효
    @discardableResult
    func regenerateDeveloperToken() -> String {
        let t = Self.randomToken()
        config.saveToken(Self.developerTokenKey, t)
        developerToken = t
        return t
    }

    func regenerateHookToken() {
        let t = Self.randomToken()
        config.saveToken(Self.hookTokenKey, t)
        hookToken = t
        writeEndpointFile()
    }

    /// 설정 도우미가 키체인 값을 바꿨을 때 다시 읽는다
    func reloadTokens() {
        developerToken = nil
        hookToken = nil
        if listener != nil {
            _ = ensureDeveloperToken()
            _ = ensureHookToken()
            writeEndpointFile()
        }
    }

    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 상수 시간 비교
    static func tokensEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = UInt8(x.count == y.count ? 0 : 1)
        for i in 0..<max(x.count, y.count) {
            diff |= (i < x.count ? x[i] : 0) ^ (i < y.count ? y[i] : 0)
        }
        return diff == 0
    }

    // MARK: 시작·정지

    private func start() {
        let wanted = config.port()
        _ = ensureDeveloperToken()
        _ = ensureHookToken()
        open(port: wanted, fallbackFrom: nil)
    }

    private func open(port: UInt16, fallbackFrom: UInt16?) {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = false
        params.acceptLocalOnly = true
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any)
        let l: NWListener
        do {
            l = try NWListener(using: params)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        listener = l
        state = .starting(port)
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.stateUpdateHandler = { [weak self, weak l] st in
            DispatchQueue.main.async {
                guard let self, let l, self.listener === l else { return }
                switch st {
                case .ready:
                    let actual = l.port?.rawValue ?? port
                    self.state = .listening(actual, fallbackFrom: fallbackFrom)
                    self.writeEndpointFile()
                case .failed(let err), .waiting(let err):
                    l.cancel()
                    self.listener = nil
                    if case .posix(let code) = err, code == .EADDRINUSE, fallbackFrom == nil, port != 0, self.config.fallbackToEphemeral {
                        // 설정 포트가 쓰이는 중: 임시 포트로 열고 화면에 알린다 (훅은 endpoint 파일의 실제 포트를 쓴다)
                        self.open(port: 0, fallbackFrom: port)
                    } else if case .posix(let code) = err, code == .EADDRINUSE {
                        self.state = .failed(T("포트 \(port)를 다른 프로그램이 쓰는 중", "Port \(port) is in use by another program"))
                    } else {
                        self.state = .failed(err.localizedDescription)
                    }
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }
        l.start(queue: queue)
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        queue.async { [weak self] in
            guard let self else { return }
            for c in self.connections.values { c.close() }
            self.connections.removeAll()
        }
        removeEndpointFile()
        state = .stopped
    }

    var boundPort: UInt16? {
        if case .listening(let p, _) = state { return p }
        return nil
    }

    // MARK: endpoint 파일 (훅 스크립트가 읽음: 1줄 포트, 2줄 훅 토큰, 3줄 승인 대기 초)

    static let approvalTimeout: TimeInterval = 110

    func writeEndpointFile() {
        guard let dir = config.endpointDir, let port = boundPort else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let file = dir.appendingPathComponent("endpoint")
        let text = "\(port)\n\(ensureHookToken())\n\(Int(Self.approvalTimeout))\n"
        // 0600으로 만든 뒤 내용을 쓴다
        let tmp = dir.appendingPathComponent(".endpoint.\(getpid())")
        fm.createFile(atPath: tmp.path, contents: nil, attributes: [.posixPermissions: 0o600])
        if let h = FileHandle(forWritingAtPath: tmp.path) {
            h.write(Data(text.utf8))
            try? h.close()
            _ = try? fm.replaceItemAt(file, withItemAt: tmp)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    private func removeEndpointFile() {
        guard let dir = config.endpointDir else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("endpoint"))
    }

    // MARK: 연결 (queue)

    private func accept(_ nw: NWConnection) {
        // 루프백 상대만 받는다
        if case .hostPort(let host, _) = nw.endpoint {
            var ok = false
            switch host {
            case .ipv4(let a): ok = a.isLoopback
            case .ipv6(let a): ok = a.isLoopback
            default: ok = false
            }
            if !ok { nw.cancel(); return }
        }
        guard connections.count < Self.maxConnections else {
            nw.start(queue: queue)
            nw.send(content: Self.encode(["ok": false, "error": "too_many_connections"]), completion: .contentProcessed { _ in nw.cancel() })
            return
        }
        let c = LocalAPIConnection(nw, server: self)
        connections[ObjectIdentifier(c)] = c
        c.start()
    }

    fileprivate func forget(_ c: LocalAPIConnection) {
        connections[ObjectIdentifier(c)] = nil
    }

    /// 한 줄 처리 (queue에서 불림). 결과는 연결로 돌려보낸다.
    fileprivate func handle(line: Data, from c: LocalAPIConnection) {
        // HTTP 요청 줄 거절
        if let head = String(data: line.prefix(16), encoding: .utf8),
           ["GET ", "POST ", "PUT ", "HEAD ", "DELETE ", "OPTIONS ", "PATCH ", "CONNECT "].contains(where: { head.hasPrefix($0) }) {
            c.reply(["ok": false, "error": "http_not_supported"], close: true)
            return
        }
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            c.reply(["ok": false, "error": "invalid_json"], close: true)
            return
        }
        guard let token = obj["token"] as? String, !token.isEmpty else {
            c.reply(["ok": false, "error": "unauthorized"], close: true)
            return
        }
        // 명령 없이 제목만 보내면 Notchy처럼 안내 카드로 본다
        var command = obj["command"] as? String ?? ""
        if command.isEmpty, obj["title"] != nil { command = "show" }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let scope: Scope?
            if let d = self.developerToken, Self.tokensEqual(token, d), self.owners.contains("localapi") { scope = .developer }
            else if let h = self.hookToken, Self.tokensEqual(token, h) { scope = .hook }
            else { scope = nil }
            guard let scope else {
                c.reply(["ok": false, "error": "unauthorized"], close: true)
                return
            }
            if command == "status" {
                c.reply(self.statusReply(scope: scope), close: false)
                return
            }
            guard let h = self.handlers[command] else {
                c.reply(["ok": false, "error": "unknown_command"], close: false)
                return
            }
            guard h.scopes.contains(scope) else {
                c.reply(["ok": false, "error": "forbidden"], close: false)
                return
            }
            switch h.run(Request(command: command, json: obj, scope: scope, connection: c)) {
            case .now(let reply): c.reply(reply, close: false)
            case .hold: c.hold()
            }
        }
    }

    private func statusReply(scope: Scope) -> [String: Any] {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let cmds = (["status"] + handlers.filter { $0.value.scopes.contains(scope) }.map(\.key)).sorted()
        return ["ok": true, "app": "Dynamic Notch", "version": version, "scope": scope.rawValue, "commands": cmds]
    }

    static func encode(_ obj: [String: Any]) -> Data {
        var d = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{\"ok\":false}".utf8)
        d.append(0x0A)
        return d
    }
}

/// 연결 하나. 줄 단위로 읽고, 초당 요청 수와 줄 길이를 제한한다.
final class LocalAPIConnection {
    private let nw: NWConnection
    private weak var server: LocalAPIServer?
    private var buffer = Data()
    private var tokens = LocalAPIServer.perConnectionBurst
    private var lastRefill = Date()
    private var violations = 0
    private var held = false
    private var closed = false
    private var gotFirstLine = false
    private var idleWork: DispatchWorkItem?
    /// 연결이 닫히면 메인 스레드에서 불린다 (훅 프로세스가 끝남 = 터미널에서 먼저 답함)
    private var onClose: (() -> Void)?

    init(_ nw: NWConnection, server: LocalAPIServer) {
        self.nw = nw
        self.server = server
    }

    private var queue: DispatchQueue { server?.queue ?? .global() }

    func start() {
        nw.stateUpdateHandler = { [weak self] st in
            switch st {
            case .failed, .cancelled: self?.finish()
            default: break
            }
        }
        nw.start(queue: queue)
        scheduleIdle(LocalAPIServer.firstLineTimeout)
        receive()
    }

    private func scheduleIdle(_ seconds: TimeInterval) {
        idleWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, !self.held else { return }
            self.close()
        }
        idleWork = w
        queue.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    private func receive() {
        nw.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drain()
            }
            if isComplete || error != nil {
                self.finish()
                return
            }
            if !self.closed { self.receive() }
        }
    }

    private func drain() {
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            let trimmed = line.last == 0x0D ? line.dropLast() : line
            if trimmed.isEmpty { continue }
            if trimmed.count > LocalAPIServer.maxLineBytes {
                buffer.removeAll()
                reply(["ok": false, "error": "request_too_large"], close: true)
                return
            }
            guard allow() else {
                violations += 1
                send(["ok": false, "error": "rate_limited"])
                if violations >= 3 {
                    buffer.removeAll()
                    close()
                    return
                }
                continue
            }
            gotFirstLine = true
            scheduleIdle(LocalAPIServer.idleTimeout)
            server?.handle(line: Data(trimmed), from: self)
        }
        if buffer.count > LocalAPIServer.maxLineBytes {
            buffer.removeAll()
            reply(["ok": false, "error": "request_too_large"], close: true)
        }
    }

    /// 토큰 버킷
    private func allow() -> Bool {
        let now = Date()
        tokens = min(LocalAPIServer.perConnectionBurst, tokens + now.timeIntervalSince(lastRefill) * LocalAPIServer.perConnectionRate)
        lastRefill = now
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }

    private func send(_ obj: [String: Any], then: (() -> Void)? = nil) {
        nw.send(content: LocalAPIServer.encode(obj), completion: .contentProcessed { _ in then?() })
    }

    /// 아무 스레드에서나 부를 수 있다
    func reply(_ obj: [String: Any], close shouldClose: Bool) {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            if shouldClose { self.held = false }
            self.send(obj) { [weak self] in if shouldClose { self?.close() } }
        }
    }

    /// 닫힘 알림 등록. 이미 닫혔으면 바로 부른다.
    func observeClose(_ cb: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.closed { DispatchQueue.main.async { cb() } } else { self.onClose = cb }
        }
    }

    func hold() {
        queue.async { [weak self] in
            self?.held = true
            self?.idleWork?.cancel()
        }
    }

    func close() {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            self.nw.cancel()
            self.finish()
        }
    }

    private func finish() {
        guard !closed else { return }
        closed = true
        idleWork?.cancel()
        server?.forget(self)
        let cb = onClose
        onClose = nil
        if let cb { DispatchQueue.main.async { cb() } }
    }
}

import AppKit
import SwiftUI

/// 로컬 개발자 API (M-K-026): 스크립트·CI가 127.0.0.1 TCP로 노치 안내·라이브 활동을 띄운다.
/// 기본 꺼짐. 켜면 서버를 열고, 끄면 닫는다 (에이전트·셸 훅 모듈이 켜져 있으면 서버는 훅 전용으로 계속 열려 있다).
final class LocalAPIModule: NotchModule {
    let id = "localapi"
    var title: String { T("로컬 API", "Local API") }
    let symbol = "network"
    var enabledByDefault: Bool { false }

    private let server: LocalAPIServer
    private var context: ModuleContext?
    /// 지금 API로 띄운 상시 활동 id
    private var activityID: String?
    let model = LocalAPIViewModel()

    init(server: LocalAPIServer = .shared) {
        self.server = server
    }

    func start(context: ModuleContext) {
        guard self.context == nil else { return }
        self.context = context
        register(on: server)
        server.acquire(id)
        model.attach(server)
    }

    func stop() {
        server.release(id)
        if activityID != nil { context?.center.removePersistent(.notice) }
        activityID = nil
        context = nil
        model.detach()
    }

    func settingsChanged() {
        server.reloadTokens()
        server.restartIfRunning()
        model.refresh()
    }

    func tabView() -> AnyView? { AnyView(LocalAPITab(model: model, module: self)) }
    var tabContentSize: CGSize { CGSize(width: 470, height: 196) }

    func settingsView() -> AnyView? { AnyView(LocalAPISettings()) }

    // MARK: 명령

    func register(on server: LocalAPIServer) {
        server.register(owner: id, command: "show", scopes: [.developer]) { [weak self] req in
            self?.show(req.json) ?? .now(["ok": false, "error": "not_running"])
        }
        server.register(owner: id, command: "activity.set", scopes: [.developer]) { [weak self] req in
            self?.setActivity(req.json) ?? .now(["ok": false, "error": "not_running"])
        }
        server.register(owner: id, command: "activity.clear", scopes: [.developer]) { [weak self] req in
            self?.clearActivity(req.json) ?? .now(["ok": false, "error": "not_running"])
        }
    }

    /// 사용자 입력 글자: 한 줄로, 제어 문자 제거, 길이 제한
    static func clean(_ any: Any?, limit: Int) -> String {
        guard let s = any as? String else { return "" }
        let flat = String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" }
            .map(Character.init)).replacingOccurrences(of: "\n", with: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespaces)
        return trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
    }

    /// SF Symbol 이름은 실제로 있는 것만
    static func symbol(_ any: Any?, fallback: String) -> String {
        guard let s = any as? String, !s.isEmpty, s.count < 64, NSImage(systemSymbolName: s, accessibilityDescription: nil) != nil else { return fallback }
        return s
    }

    static func progress(_ any: Any?) -> Double? {
        guard let n = any as? NSNumber else { return nil }
        let v = n.doubleValue
        guard v.isFinite else { return nil }
        return min(1, max(0, v > 1 ? v / 100 : v))
    }

    private func show(_ json: [String: Any]) -> LocalAPIServer.Reply {
        guard let context else { return .now(["ok": false, "error": "not_running"]) }
        let title = Self.clean(json["title"], limit: 120)
        guard !title.isEmpty else { return .now(["ok": false, "error": "title_required"]) }
        let message = Self.clean(json["message"] ?? json["subtitle"], limit: 500)
        let duration = min(10, max(1, (json["duration"] as? NSNumber)?.doubleValue ?? 4))
        var a = NotchActivity(kind: .notice, priority: ActivityPriority.info, presentation: .detail, duration: duration,
                              symbol: Self.symbol(json["symbol"], fallback: "terminal"), tint: .white,
                              title: title, subtitle: message.isEmpty ? nil : message)
        if let p = Self.progress(json["progress"]) { a.value = .ringPercent(p) }
        context.center.post(a)
        model.noteRequest("show")
        return .now(["ok": true])
    }

    private func setActivity(_ json: [String: Any]) -> LocalAPIServer.Reply {
        guard let context else { return .now(["ok": false, "error": "not_running"]) }
        let title = Self.clean(json["title"], limit: 120)
        guard !title.isEmpty else { return .now(["ok": false, "error": "title_required"]) }
        let id = Self.clean(json["id"], limit: 64)
        let subtitle = Self.clean(json["subtitle"] ?? json["message"], limit: 200)
        var a = NotchActivity(kind: .notice, priority: ActivityPriority.pinned, presentation: .compact,
                              symbol: Self.symbol(json["symbol"], fallback: "bolt.horizontal.circle"), tint: .white,
                              title: title, subtitle: subtitle.isEmpty ? nil : subtitle, moduleTab: self.id)
        if let p = Self.progress(json["progress"]) { a.value = .ringPercent(p) } else { a.value = .spinner }
        context.center.setPersistent(a)
        activityID = id.isEmpty ? "default" : id
        model.noteRequest("activity.set")
        return .now(["ok": true, "id": activityID ?? "default"])
    }

    private func clearActivity(_ json: [String: Any]) -> LocalAPIServer.Reply {
        guard let context else { return .now(["ok": false, "error": "not_running"]) }
        let id = Self.clean(json["id"], limit: 64)
        guard activityID != nil else { return .now(["ok": true, "cleared": false]) }
        if !id.isEmpty, id != activityID { return .now(["ok": false, "error": "unknown_id"]) }
        context.center.removePersistent(.notice)
        activityID = nil
        model.noteRequest("activity.clear")
        return .now(["ok": true, "cleared": true])
    }

    // MARK: 자체 검사: 임시 포트에 서버를 열고 실제 TCP로 주고받는다 (키체인·실제 포트·endpoint 파일은 쓰지 않음)

    func selfTest() -> [String] {
        var out: [String] = []
        var store: [String: String] = [:]
        let dir = AIDevTest.dir("localapi")
        let test = LocalAPIServer(config: .init(loadToken: { store[$0] }, saveToken: { store[$0] = $1 },
                                                endpointDir: dir, port: { 0 }, fallbackToEphemeral: false))
        let ctx = ModuleContext(center: ActivityCenter(), openTab: { _ in }, collapse: {}, focusInput: {})
        let module = LocalAPIModule(server: test)
        module.context = ctx
        module.register(on: test)
        test.acquire("localapi")
        guard AIDevTest.wait(3, until: { test.boundPort != nil }), let port = test.boundPort else {
            return ["FAIL listener did not start: \(test.state)"]
        }
        out.append("listening on 127.0.0.1:\(port) (ephemeral, loopback only)")
        let dev = test.ensureDeveloperToken()
        let hook = test.ensureHookToken()

        func check(_ name: String, _ line: String, expect: (([String: Any]) -> Bool)) {
            let r = AIDevTest.ask(port: port, line: line) ?? ""
            let obj = (try? JSONSerialization.jsonObject(with: Data(r.utf8))) as? [String: Any] ?? [:]
            out.append("\(expect(obj) ? "PASS" : "FAIL") \(name) -> \(r.isEmpty ? "(no reply)" : r)")
        }
        check("status with developer token", #"{"command":"status","token":"\#(dev)"}"#) { $0["ok"] as? Bool == true && $0["scope"] as? String == "developer" }
        check("bad token rejected", #"{"command":"status","token":"wrong"}"#) { $0["error"] as? String == "unauthorized" }
        check("missing token rejected", #"{"command":"status"}"#) { $0["error"] as? String == "unauthorized" }
        check("HTTP request line rejected", "GET / HTTP/1.1") { $0["error"] as? String == "http_not_supported" }
        check("invalid JSON rejected", "{nope") { $0["error"] as? String == "invalid_json" }
        check("unknown command rejected", #"{"command":"run","token":"\#(dev)"}"#) { $0["error"] as? String == "unknown_command" }
        check("show posts a notice", #"{"command":"show","token":"\#(dev)","title":"Build done","message":"42 tests"}"#) {
            $0["ok"] as? Bool == true && ctx.center.transient?.title == "Build done" }
        check("command-less title = show (Notchy style)", #"{"token":"\#(dev)","title":"CI","subtitle":"green","progress":0.5}"#) {
            $0["ok"] as? Bool == true && ctx.center.transient?.title == "CI" }
        check("activity.set", #"{"command":"activity.set","token":"\#(dev)","id":"deploy","title":"Deploying","progress":0.3}"#) {
            $0["ok"] as? Bool == true && ctx.center.persistent[.notice]?.title == "Deploying" }
        check("activity.clear wrong id", #"{"command":"activity.clear","token":"\#(dev)","id":"other"}"#) { $0["error"] as? String == "unknown_id" }
        check("activity.clear", #"{"command":"activity.clear","token":"\#(dev)","id":"deploy"}"#) {
            $0["ok"] as? Bool == true && ctx.center.persistent[.notice] == nil }
        check("hook token cannot use show", #"{"command":"show","token":"\#(hook)","title":"x"}"#) { $0["error"] as? String == "forbidden" }
        check("hook token status", #"{"command":"status","token":"\#(hook)"}"#) { $0["scope"] as? String == "hook" }

        // 크기 제한: 한 줄이 512KB를 넘으면 거절
        let big = String(repeating: "a", count: LocalAPIServer.maxLineBytes + 10)
        check("oversized request rejected", #"{"token":"\#(dev)","title":"\#(big)"}"#) { $0["error"] as? String == "request_too_large" }

        // 초당 요청 수 제한: 한 연결에서 60줄을 몰아 보내면 일부는 rate_limited
        let burst = (0..<60).map { _ in #"{"command":"status","token":"\#(dev)"}"# }.joined(separator: "\n")
        let limited = AIDevTest.askAll(port: port, payload: burst, expectLines: 60)
        out.append("\(limited.contains("rate_limited") ? "PASS" : "FAIL") rate limit (60 lines in one burst -> \(limited.components(separatedBy: "rate_limited").count - 1) limited)")

        // 토큰 재발급: 이전 토큰 즉시 무효
        let newDev = test.regenerateDeveloperToken()
        check("old token invalid after regenerate", #"{"command":"status","token":"\#(dev)"}"#) { $0["error"] as? String == "unauthorized" }
        check("new token works", #"{"command":"status","token":"\#(newDev)"}"#) { $0["ok"] as? Bool == true }

        // endpoint 파일 권한 (훅 토큰만 들어 있고 0600)
        let ep = dir.appendingPathComponent("endpoint")
        let perm = (try? FileManager.default.attributesOfItem(atPath: ep.path)[.posixPermissions] as? Int) ?? 0
        let epText = (try? String(contentsOf: ep, encoding: .utf8)) ?? ""
        out.append("\((perm == 0o600 && epText.contains(hook) && !epText.contains(newDev)) ? "PASS" : "FAIL") endpoint file 0\(String(perm, radix: 8)), hook token only")

        // 포트 충돌 감지: 같은 포트로 두 번째 서버를 열면 실패
        let second = LocalAPIServer(config: .init(loadToken: { _ in "x" }, saveToken: { _, _ in }, endpointDir: nil,
                                                  port: { port }, fallbackToEphemeral: false))
        second.acquire("localapi")
        AIDevTest.wait(3) { if case .failed = second.state { return true }; return false }
        if case .failed(let why) = second.state { out.append("PASS port conflict detected: \(why)") } else { out.append("FAIL port conflict not detected: \(second.state)") }
        second.release("localapi")

        let fallback = LocalAPIServer(config: .init(loadToken: { _ in "x" }, saveToken: { _, _ in }, endpointDir: nil,
                                                    port: { port }, fallbackToEphemeral: true))
        fallback.acquire("localapi")
        AIDevTest.wait(3) { fallback.boundPort != nil }
        if case .listening(let p, let from) = fallback.state, from == port { out.append("PASS busy port falls back to ephemeral \(p)") } else { out.append("FAIL fallback: \(fallback.state)") }
        fallback.release("localapi")

        test.release("localapi")
        AIDevTest.wait(1) { test.boundPort == nil }
        out.append("\(test.isRunning ? "FAIL" : "PASS") stop closes the listener; endpoint removed: \(!FileManager.default.fileExists(atPath: ep.path))")
        return out
    }
}

/// 탭·설정 화면용 상태
final class LocalAPIViewModel: ObservableObject {
    @Published var state: LocalAPIServer.State = .stopped
    @Published var requests = 0
    @Published var last: String = ""
    private weak var server: LocalAPIServer?
    private var observer: NSObjectProtocol?

    func attach(_ s: LocalAPIServer) {
        server = s
        observer = NotificationCenter.default.addObserver(forName: LocalAPIServer.stateChanged, object: s, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func detach() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        state = .stopped
    }

    func refresh() { state = server?.state ?? .stopped }

    func noteRequest(_ command: String) {
        requests += 1
        last = "\(command) · \(AIDevFormat.clock(Date()))"
    }

    var token: String { server?.ensureDeveloperToken() ?? "" }
    func regenerate() { server?.regenerateDeveloperToken(); objectWillChange.send() }
}

private struct LocalAPITab: View {
    @ObservedObject var model: LocalAPIViewModel
    let module: LocalAPIModule
    @State private var confirming = false
    @State private var copied = false

    private var portText: String {
        switch model.state {
        case .listening(let p, let from):
            return from.map { T("127.0.0.1:\(p)에서 수신 중 (포트 \($0)는 다른 프로그램이 사용 중)", "Listening on 127.0.0.1:\(p) (port \($0) is busy)") }
                ?? T("127.0.0.1:\(p)에서 수신 중", "Listening on 127.0.0.1:\(p)")
        case .starting(let p): return T("포트 \(p) 여는 중…", "Opening port \(p)…")
        case .failed(let why): return T("열지 못함: \(why)", "Couldn't open: \(why)")
        case .stopped: return T("꺼짐", "Off")
        }
    }

    private var port: UInt16 {
        if case .listening(let p, _) = model.state { return p }
        return 9999
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(model.state == .stopped ? Color.gray : (model.state.isListening ? Color.green : Color.orange)).frame(width: 7, height: 7)
                Text(portText).font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text(model.requests > 0 ? T("요청 \(model.requests)건 · \(model.last)", "\(model.requests) requests · \(model.last)") : T("요청 없음", "No requests yet"))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            AIDevBox {
                VStack(alignment: .leading, spacing: 4) {
                    Text(T("예시 (터미널)", "Example (Terminal)")).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
                    Text(#"echo '{"command":"show","title":"Build done","token":"…"}' | nc 127.0.0.1 \#(port)"#)
                        .font(.system(size: 10.5, design: .monospaced)).lineLimit(2).textSelection(.enabled)
                    Text(T("명령: status · show · activity.set · activity.clear (줄바꿈 JSON, HTTP 아님)", "Commands: status · show · activity.set · activity.clear (newline JSON, not HTTP)"))
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
                }
            }
            HStack(spacing: 6) {
                AIDevPill(title: copied ? T("복사됨", "Copied") : T("토큰 복사", "Copy Token"), symbol: "key") {
                    AIDevPasteboard.copySecret(model.token)
                    copied = true
                }
                if confirming {
                    Text(T("이전 토큰은 바로 무효가 됩니다", "The old token stops working at once")).font(.system(size: 11)).foregroundStyle(.orange)
                    AIDevPill(title: T("다시 만들기", "Regenerate"), role: .destructive) { model.regenerate(); confirming = false; copied = false }
                    AIDevPill(title: T("취소", "Cancel")) { confirming = false }
                } else {
                    AIDevPill(title: T("토큰 다시 만들기", "Regenerate Token"), symbol: "arrow.triangle.2.circlepath") { confirming = true }
                }
                Spacer()
            }
            Text(T("이 Mac 안(루프백)에서만 받고, 요청마다 토큰을 확인합니다. 파일·셸 명령은 실행하지 않습니다.",
                   "Accepts only on this Mac (loopback) and checks the token on every request. Never runs files or shell commands."))
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
        }
        .foregroundStyle(.white)
    }
}

private extension LocalAPIServer.State {
    var isListening: Bool { if case .listening = self { return true }; return false }
}

/// 설정 창 (설정 도우미 프로세스). 포트·토큰.
private struct LocalAPISettings: View {
    @State private var port = ModuleDefaults(module: "localapi").int("port", default: 9999)
    @State private var shown = false
    @State private var confirming = false
    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(T("포트", "Port"))
                TextField("9999", value: $port, format: .number.grouping(.never)).frame(width: 80)
                Button(T("적용", "Apply")) {
                    port = min(65535, max(1024, port))
                    ModuleDefaults(module: "localapi").set(port, "port")
                }
            }
            Text(T("127.0.0.1에만 열립니다. 이 포트를 다른 프로그램이 쓰면 임시 포트로 열고 탭에 표시합니다.",
                   "Opens on 127.0.0.1 only. If another program uses this port, a temporary port is used and shown in the tab."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(T("토큰", "Token"))
                Text(shown ? token : String(repeating: "•", count: 16)).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Button(shown ? T("숨기기", "Hide") : T("보기", "Show")) {
                    token = LocalAPIServer.shared.ensureDeveloperToken()
                    shown.toggle()
                }
                Button(T("복사", "Copy")) { AIDevPasteboard.copySecret(LocalAPIServer.shared.ensureDeveloperToken()) }
            }
            if confirming {
                HStack {
                    Text(T("다시 만들면 이전 토큰을 쓰는 스크립트가 바로 멈춥니다.", "Scripts using the old token stop working immediately."))
                        .foregroundStyle(.orange)
                    Button(T("다시 만들기", "Regenerate")) {
                        token = LocalAPIServer.shared.regenerateDeveloperToken()
                        // 본 앱이 키체인을 다시 읽도록 알린다
                        ModuleDefaults(module: "localapi").set(Date().timeIntervalSince1970, "tokenVersion")
                        confirming = false
                    }
                    Button(T("취소", "Cancel")) { confirming = false }
                }
            } else {
                Button(T("토큰 다시 만들기…", "Regenerate Token…")) { confirming = true }
            }
        }
    }
}

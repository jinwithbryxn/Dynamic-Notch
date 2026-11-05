import CryptoKit
import Foundation
import Security

/// 분산 알림으로 오가는 명령·알림을 봉투에 넣는다.
/// 분산 알림은 같은 로그인 세션의 어떤 프로세스든 보내고 엿들을 수 있다. 그래서 내용(명령, 끝난 작업 문구)은
/// 이 앱만 아는 열쇠로 암호화·서명(ChaCha20-Poly1305)하고, 받는 쪽은 열쇠가 맞고 30초 안에 만들어졌으며
/// 처음 보는 봉투만 받는다. 열쇠가 없는 프로세스는 명령을 꾸미거나 엿보거나 같은 봉투를 다시 보낼 수 없다.
/// 열쇠는 번들 ID별 데이터 폴더의 0600 파일(`command.key`)에 두고 본 앱·설정 도우미·훅 프로세스(같은 실행 파일)가 읽는다.
/// 한계: 같은 사용자 권한으로 도는 샌드박스 밖 프로그램은 이 파일을 읽을 수 있다 (그런 프로그램은 대화 기록도 직접 읽을 수 있다).
enum CommandEnvelope {
    static let maxAge: TimeInterval = 30
    private static let lock = NSLock()
    private static var seen: [Data: Date] = [:]

    static var keyURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.dynamicnotch.app", isDirectory: true)
            .appendingPathComponent("command.key")
    }

    /// 열쇠(32바이트). 없거나 깨졌으면 새로 만든다. 여러 프로세스가 동시에 만들어도 하나만 남는다.
    static func key(at url: URL = keyURL) -> SymmetricKey? {
        if let data = try? Data(contentsOf: url), data.count == 32 { return SymmetricKey(data: data) }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        // 임시 파일(0600)에 다 쓴 뒤 link로 붙인다: 이미 있으면 실패하므로 먼저 만든 쪽이 이긴다
        let temp = dir.appendingPathComponent(".command.key.\(UUID().uuidString)")
        let fd = Darwin.open(temp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { return nil }
        let written = write(fd, bytes, bytes.count)
        close(fd)
        defer { unlink(temp.path) }
        guard written == bytes.count else { return nil }
        if link(temp.path, url.path) != 0 {
            if let data = try? Data(contentsOf: url), data.count == 32 { return SymmetricKey(data: data) }
            guard rename(temp.path, url.path) == 0 else { return nil }   // 깨진 파일은 바꾼다
        }
        return SymmetricKey(data: Data(bytes))
    }

    static func seal(_ payload: [String: Any], using provided: SymmetricKey? = nil) -> String? {
        guard let key = provided ?? key() else { return nil }
        var body = payload
        body["ts"] = Date().timeIntervalSince1970
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let box = try? ChaChaPoly.seal(data, using: key) else { return nil }
        return box.combined.base64EncodedString()
    }

    /// 열쇠가 맞고, 30초 안에 만들어졌고, 처음 보는 봉투면 내용을 돌려준다.
    static func open(_ text: String, using provided: SymmetricKey? = nil, now: Date = Date()) -> [String: Any]? {
        guard text.utf8.count < 16_384, let combined = Data(base64Encoded: text), let key = provided ?? key(),
              let box = try? ChaChaPoly.SealedBox(combined: combined),
              let data = try? ChaChaPoly.open(box, using: key),
              let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let ts = body["ts"] as? Double else { return nil }
        let age = now.timeIntervalSince1970 - ts
        guard age <= maxAge, age >= -5 else { return nil }
        let nonce = box.nonce.withUnsafeBytes { Data($0) }
        lock.lock(); defer { lock.unlock() }
        seen = seen.filter { now.timeIntervalSince($0.value) < maxAge * 2 }
        guard seen[nonce] == nil else { return nil }
        seen[nonce] = now
        return body
    }

    static func sealCommand(_ command: String) -> String? { seal(["c": command]) }
    static func openCommand(_ text: String) -> String? { open(text)?["c"] as? String }

    /// `--send-command=<명령>`: 명령을 봉투에 넣어 본 앱에 보내고 끝나는 짧은 실행.
    /// 앱 밖의 알림 스크립트(예: ~/.local/bin/notch-agent-done)는 이것으로 `agent:<claude|codex>|<프로젝트>[|<세션 주소나 번들 ID>]`를 보낸다.
    static func sendCommand(from arguments: [String]) -> String? {
        arguments.first { $0.hasPrefix("--send-command=") }.map { String($0.dropFirst("--send-command=".count)) }
    }

    /// `--module-selftest=core`
    static func selfTest() -> [String] {
        var lines: [String] = []
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dmn-envelope-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("command.key")
        guard let k1 = key(at: url), let k2 = key(at: url) else { return ["FAIL could not create a key file"] }
        let perms = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? 0
        let same = k1.withUnsafeBytes { a in k2.withUnsafeBytes { b in Data(a) == Data(b) } }
        lines.append(same && perms == 0o600 ? "PASS key file is created once and kept (0600)"
                                            : "FAIL key file: same=\(same) perms=\(String(perms, radix: 8))")
        let other = SymmetricKey(size: .bits256)
        guard let env = seal(["c": "restart"], using: k1) else { return lines + ["FAIL seal"] }
        lines.append(open(env, using: other) == nil ? "PASS another key cannot open it" : "FAIL opened with another key")
        lines.append(open(env, using: k1)?["c"] as? String == "restart" ? "PASS right key opens it" : "FAIL right key did not open it")
        lines.append(open(env, using: k1) == nil ? "PASS the same envelope is refused the second time" : "FAIL replay accepted")
        let old = seal(["c": "restart"], using: k1)!
        lines.append(open(old, using: k1, now: Date().addingTimeInterval(maxAge + 1)) == nil
                     ? "PASS an envelope older than \(Int(maxAge)) s is refused" : "FAIL stale envelope accepted")
        var bytes = Data(base64Encoded: seal(["c": "restart"], using: k1)!)!
        bytes[bytes.count - 1] ^= 0x01
        lines.append(open(bytes.base64EncodedString(), using: k1) == nil ? "PASS a changed envelope is refused" : "FAIL tampered envelope accepted")
        lines.append(open("restart", using: k1) == nil ? "PASS a plain command is refused" : "FAIL plain command accepted")
        lines.append(env.contains("restart") ? "FAIL command text visible in the envelope" : "PASS command text is not visible in the envelope")
        return lines
    }
}

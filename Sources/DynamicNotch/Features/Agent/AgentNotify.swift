import AppKit
import SwiftUI

/// 코딩 에이전트 (Claude Code · Codex)
enum AgentSource: String, CaseIterable, Identifiable {
    case claude, codex

    var id: String { rawValue }
    var name: String { self == .claude ? "Claude Code" : "Codex" }
    var symbol: String { self == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right" }
    var tint: Color { self == .claude ? Color(red: 0.85, green: 0.47, blue: 0.34) : Color(red: 0.55, green: 0.62, blue: 1.0) }
}

/// 작업 완료 알림.
/// Claude Code(Stop 훅)·Codex(notify)가 작업을 끝내면 이 앱 실행 파일을 `--agent-done=<에이전트>`로 잠깐 실행하고,
/// 그 짧은 프로세스가 분산 알림으로 본 앱에 알린 뒤 바로 끝난다. 알림을 누르면 에이전트가 돌던 앱(터미널·Claude·Codex 등)을 연다.
/// 알림 내용(프로젝트, 끝난 작업 문구)은 CommandEnvelope로 봉인해 다른 프로세스가 엿보거나 꾸밀 수 없다.
enum AgentNotify {
    static let notification = Notification.Name("com.dynamicnotch.app.agent")

    static func source(from arguments: [String]) -> AgentSource? {
        arguments.first { $0.hasPrefix("--agent-done=") }.flatMap { AgentSource(rawValue: String($0.dropFirst("--agent-done=".count))) }
    }

    // MARK: 훅 쪽 (짧게 실행되고 끝남)

    static func runHook(_ source: AgentSource, arguments: [String]) -> Never {
        var payloadArgs = arguments
        // Codex notify를 이어받은 경우: 원래 notify 명령도 그대로 실행한다 (--chain 원래명령... --end-chain [Codex가 붙인 인자])
        if let i = arguments.firstIndex(of: "--chain"), let j = arguments.firstIndex(of: "--end-chain"), i < j {
            let previous = Array(arguments[(i + 1)..<j])
            payloadArgs = Array(arguments[(j + 1)...])
            if let exe = previous.first {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = Array(previous.dropFirst()) + payloadArgs
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                try? p.run()
            }
        }
        // 설정 파일에서 이미 빠진 훅이면 알리지 않는다 (위의 원래 notify 명령은 그대로 실행).
        // Claude Code·Codex는 세션을 시작할 때 설정을 읽어 두므로, 연결을 해제하거나 되돌린 뒤에도
        // 그 전에 시작한 세션이 옛 훅을 계속 부른다 (2026-11-02, 알림이 두 번 뜸).
        guard AgentHooks.isInstalled(source) else {
            if source == .claude { _ = try? FileHandle.standardInput.readToEnd() }
            exit(0)
        }
        // 프로젝트 폴더와 끝난 작업(사용자가 마지막으로 보낸 요청)
        var folder = FileManager.default.currentDirectoryPath
        var task = ""
        switch source {
        case .codex:
            // Codex는 마지막 인자로 JSON을 넘긴다: {"cwd": ..., "input-messages": [...], "last-assistant-message": ...}
            if let last = payloadArgs.last, let data = last.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let cwd = obj["cwd"] as? String { folder = cwd }
                task = (obj["input-messages"] as? [String])?.last ?? ""
            }
        case .claude:
            // Claude Code는 표준 입력으로 JSON을 준다: {"cwd": ..., "transcript_path": ...}
            if let data = try? FileHandle.standardInput.readToEnd(),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let cwd = obj["cwd"] as? String { folder = cwd }
                if let path = obj["transcript_path"] as? String { task = lastUserPrompt(transcript: path) }
            }
        }
        let app = guiAncestor()
        let payload: [String: Any] = ["source": source.rawValue,
                                      "project": URL(fileURLWithPath: folder).lastPathComponent,
                                      "task": oneLine(task, limit: 80),
                                      "bundle": app?.bundleIdentifier ?? "",
                                      "pid": Int(app?.processIdentifier ?? 0)]
        if let envelope = CommandEnvelope.seal(payload) {
            DistributedNotificationCenter.default().postNotificationName(notification, object: envelope,
                                                                         userInfo: nil, deliverImmediately: true)
        }
        exit(0)
    }

    /// 대화 기록(JSONL)에서 사용자가 마지막으로 보낸 요청. 파일 끝 512KB만 읽는다.
    /// 도구 결과·시스템이 붙인 메시지·요약·하위 작업·태그로 시작하는 메시지는 건너뛴다.
    static func lastUserPrompt(transcript path: String) -> String {
        guard let h = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 524_288 ? size - 524_288 : 0)
        guard let data = try? h.readToEnd(), let text = String(data: data, encoding: .utf8) else { return "" }
        for line in text.split(separator: "\n").reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["type"] as? String == "user",
                  obj["isMeta"] as? Bool != true, obj["isSidechain"] as? Bool != true,
                  obj["isCompactSummary"] as? Bool != true, obj["toolUseResult"] == nil,
                  let message = obj["message"] as? [String: Any] else { continue }
            var parts: [String] = []
            if let s = message["content"] as? String { parts = [s] }
            else if let list = message["content"] as? [[String: Any]] {
                parts = list.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            }
            let prompt = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty && !$0.hasPrefix("<") } ?? ""
            if !prompt.isEmpty { return prompt }
        }
        return ""
    }

    /// 한 줄로 줄이고 길면 자른다
    static func oneLine(_ s: String, limit: Int) -> String {
        let flat = s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }

    /// 이 프로세스를 띄운 화면 앱 (부모 프로세스를 거슬러 올라가 처음 만나는 일반 앱: 터미널·VS Code·Claude 등)
    private static func guiAncestor() -> NSRunningApplication? {
        var pid = getppid()
        for _ in 0..<40 where pid > 1 {
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular { return app }
            pid = parent(of: pid)
        }
        return nil
    }

    private static func parent(of pid: pid_t) -> pid_t {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return 0 }
        return info.kp_eproc.e_ppid
    }

    // MARK: 본 앱 쪽

    /// 알림을 받아 노치에 띄운다. 누르면 열 앱은 activity.targetApp("번들ID|pid")에 담는다.
    static func observe(center: ActivityCenter) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: notification, object: nil, queue: .main) { note in
            guard AppSettings.shared.agentAlerts, let raw = note.object as? String,
                  let info = CommandEnvelope.open(raw),
                  let source = (info["source"] as? String).flatMap(AgentSource.init(rawValue:)) else { return }
            let project = info["project"] as? String ?? ""
            let bundle = info["bundle"] as? String ?? ""
            let pid = info["pid"] as? Int ?? 0
            let task = info["task"] as? String ?? ""
            center.post(activity(source, project: project, task: task, target: bundle.isEmpty ? nil : "\(bundle)|\(pid)"))
        }
    }

    /// 컴팩트: 왼쪽 에이전트 아이콘, 오른쪽 '완료'.
    /// 상세(설정): 제목 'Claude Code · 프로젝트', 아래에 끝난 작업(마지막으로 보낸 요청)을 한 줄로.
    static func activity(_ source: AgentSource, project: String, task: String, target: String?,
                         style: AlertStyle? = nil) -> NotchActivity {
        let detailed = (style ?? AppSettings.shared.agentStyle) == .detail
        let title = project.isEmpty ? T("\(source.name) 작업 완료", "\(source.name) Finished") : "\(source.name) · \(project)"
        let subtitle = task.isEmpty
            ? (target == nil ? T("작업 완료", "Finished") : T("작업 완료 · 눌러서 열기", "Finished · Click to open"))
            : task
        return NotchActivity(kind: .agent, priority: ActivityPriority.info, presentation: detailed ? .detail : .compact,
                             duration: detailed ? 7 : 5, symbol: source.symbol, tint: source.tint,
                             value: .text(T("완료", "Done")), title: title, subtitle: subtitle, targetApp: target)
    }

    /// 알림을 눌렀을 때: 에이전트가 돌던 앱을 앞으로 (같은 창이 남아 있으면 그 앱 그대로)
    static func open(_ target: String?) {
        guard let target else { return }
        let parts = target.split(separator: "|").map(String.init)
        let running = parts.count > 1 ? NSRunningApplication(processIdentifier: pid_t(Int(parts[1]) ?? 0)) : nil
        let url = running?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: parts.first ?? "")
        guard let url else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}

// MARK: - 훅 설치 (설정 창에서 '연결'을 눌렀을 때만)

/// Claude Code: ~/.claude/settings.json 의 hooks.Stop 에 명령 하나를 더한다.
/// Codex: ~/.codex/config.toml 의 notify 를 이 앱으로 바꾸되, 원래 notify 명령은 이어서 그대로 실행한다.
/// 처음 바꾸기 전에 원본을 *.dynamicnotch.bak 으로 남긴다.
enum AgentHooks {
    enum HookError: LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self { case .unreadable(let why): return why }
        }
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var claudeFile: URL { home.appendingPathComponent(".claude/settings.json") }
    static var codexFile: URL { home.appendingPathComponent(".codex/config.toml") }
    private static var exe: String { Bundle.main.executablePath ?? "/Applications/Dynamic Notch.app/Contents/MacOS/DynamicNotch" }

    static func isInstalled(_ s: AgentSource) -> Bool {
        let file = s == .claude ? claudeFile : codexFile
        return (try? String(contentsOf: file, encoding: .utf8))?.contains("--agent-done=\(s.rawValue)") ?? false
    }

    /// 따로 쓰는 완료 알림 스크립트(~/.local/bin/notch-agent-done)가 이미 연결돼 있는지.
    /// 그 스크립트는 백그라운드 작업·하위 에이전트가 끝날 때까지 알림을 미루고 실제 앱 아이콘을 보낸다.
    /// 앱 훅을 겹쳐 넣으면 알림이 두 번 뜨고 그 거르기도 빠지므로 (2026-11-02), 이때는 연결하지 않는다.
    static func usesScript(_ s: AgentSource, file: URL? = nil) -> Bool {
        let file = file ?? (s == .claude ? claudeFile : codexFile)
        return (try? String(contentsOf: file, encoding: .utf8))?.contains("notch-agent-done") ?? false
    }

    static func install(_ s: AgentSource) throws {
        guard !usesScript(s) else { return }
        s == .claude ? try installClaude() : try installCodex()
    }

    static func uninstall(_ s: AgentSource) throws {
        s == .claude ? try uninstallClaude() : try uninstallCodex()
    }

    private static func backup(_ file: URL) {
        let bak = file.appendingPathExtension("dynamicnotch.bak")
        if FileManager.default.fileExists(atPath: file.path), !FileManager.default.fileExists(atPath: bak.path) {
            try? FileManager.default.copyItem(at: file, to: bak)
        }
    }

    // Claude Code

    // 키 순서와 글자 모양을 지키는 OrderedJSON으로 읽고 쓴다. 예전 JSONSerialization은 파일 전체의
    // 키 순서와 띄어쓰기를 바꿔, 훅 한 줄을 넣고 빼도 원래 파일로 돌아가지 않았다 (2026-11-02).

    private static func readClaude(_ file: URL) throws -> (root: OrderedJSON, text: String?) {
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return (.object([]), nil) }
        guard let root = try? OrderedJSON.parse(text), root.isObject else {
            throw HookError.unreadable(T("~/.claude/settings.json을 읽을 수 없습니다 (JSON 형식 확인)", "Can't read ~/.claude/settings.json (check the JSON)"))
        }
        return (root, text)
    }

    private static func writeClaude(_ root: OrderedJSON, original: String?, to file: URL) throws {
        var out = root.stringify()
        if original?.hasSuffix("\n") ?? true { out += "\n" }
        guard out != original else { return }
        backup(file)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(out.utf8).write(to: file, options: .atomic)
    }

    static func installClaude(file: URL = claudeFile) throws {
        guard !((try? String(contentsOf: file, encoding: .utf8))?.contains("--agent-done=claude") ?? false) else { return }
        var (root, text) = try readClaude(file)
        var hooks = root["hooks"].flatMap { $0.isObject ? $0 : nil } ?? .object([])
        var stop = hooks["Stop"]?.arrayValue ?? []
        stop.append(.obj([("hooks", .array([.obj([("type", .str("command")), ("command", .str("\"\(exe)\" --agent-done=claude"))])]))]))
        hooks.set("Stop", .array(stop))
        root.set("hooks", hooks)
        try writeClaude(root, original: text, to: file)
    }

    static func uninstallClaude(file: URL = claudeFile) throws {
        var (root, text) = try readClaude(file)
        guard var hooks = root["hooks"], let stop = hooks["Stop"]?.arrayValue else { return }
        // 이 앱 훅만 빼고, 그 때문에 빈 그룹만 지운다 (다른 그룹은 그대로)
        let kept = stop.compactMap { group -> OrderedJSON? in
            guard let list = group["hooks"]?.arrayValue else { return group }
            let left = list.filter { !($0["command"]?.stringValue ?? "").contains("--agent-done=claude") }
            if left.count == list.count { return group }
            if left.isEmpty { return nil }
            var g = group
            g.set("hooks", .array(left))
            return g
        }
        guard kept != stop else { return }
        if kept.isEmpty { hooks.remove("Stop") } else { hooks.set("Stop", .array(kept)) }
        if case .object(let left) = hooks, left.isEmpty { root.remove("hooks") } else { root.set("hooks", hooks) }
        try writeClaude(root, original: text, to: file)
    }

    // Codex

    /// 맨 위(첫 [표] 앞) 영역의 notify 줄 위치
    private static func notifyLine(_ lines: [String]) -> Int? {
        let top = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
        return lines[..<top].firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("notify") && $0.contains("=") }
    }

    /// notify = ["a", "b"] 의 문자열들
    private static func tomlStrings(_ line: String) -> [String]? {
        guard let open = line.firstIndex(of: "["), let close = line.lastIndex(of: "]"), open < close else { return nil }
        let body = String(line[line.index(after: open)..<close])
        let re = try! NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
        return re.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap {
            Range($0.range(at: 1), in: body).map { body[$0].replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\") }
        }
    }

    private static func tomlLine(_ items: [String]) -> String {
        "notify = [" + items.map { "\"" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
            .joined(separator: ", ") + "]"
    }

    private static func readCodex() -> [String] {
        ((try? String(contentsOf: codexFile, encoding: .utf8)) ?? "").components(separatedBy: "\n")
    }

    private static func writeCodex(_ lines: [String]) throws {
        backup(codexFile)
        try FileManager.default.createDirectory(at: codexFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: codexFile, atomically: true, encoding: .utf8)
    }

    private static func installCodex() throws {
        guard !isInstalled(.codex) else { return }
        var lines = readCodex()
        var previous: [String] = []
        if let i = notifyLine(lines) {
            guard let items = tomlStrings(lines[i]) else {
                throw HookError.unreadable(T("config.toml의 notify 설정을 읽을 수 없습니다 (한 줄 배열만 지원)", "Can't read notify in config.toml (single-line array only)"))
            }
            previous = items
            lines.remove(at: i)
            lines.insert(tomlLine([exe, "--agent-done=codex", "--chain"] + previous + ["--end-chain"]), at: i)
        } else {
            lines.insert(tomlLine([exe, "--agent-done=codex"]), at: 0)
        }
        try writeCodex(lines)
    }

    private static func uninstallCodex() throws {
        var lines = readCodex()
        guard let i = notifyLine(lines), lines[i].contains("--agent-done=codex"), let items = tomlStrings(lines[i]) else { return }
        // 원래 notify 명령이 있었으면 되돌린다
        if let a = items.firstIndex(of: "--chain"), let b = items.firstIndex(of: "--end-chain"), a < b, b > a + 1 {
            lines[i] = tomlLine(Array(items[(a + 1)..<b]))
        } else {
            lines.remove(at: i)
        }
        try writeCodex(lines)
    }
}

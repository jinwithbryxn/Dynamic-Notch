import AppKit
import SwiftUI

/// 에이전트 세션 하나 (Claude Code·Codex)
struct AgentSessionState: Identifiable {
    enum Phase: Int, Comparable {
        case idle = 0, done, working, error, needsInput, approval
        static func < (a: Phase, b: Phase) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .idle: return T("대기", "Idle")
            case .working: return T("작업 중", "Working")
            case .done: return T("완료", "Done")
            case .error: return T("오류", "Error")
            case .needsInput: return T("입력 기다림", "Waiting for input")
            case .approval: return T("승인 기다림", "Waiting for approval")
            }
        }
    }

    let source: AgentSource
    let sessionID: String
    var id: String { "\(source.rawValue):\(sessionID)" }
    var cwd = ""
    var projectDir = ""
    var phase: Phase = .idle
    var detail = ""
    var updated = Date()
    var turnStart: Date?
    var target: String?
    var pid: pid_t = 0
    var transcript: String?

    var folder: String { projectDir.isEmpty ? cwd : projectDir }
    var project: String { folder.isEmpty ? source.name : URL(fileURLWithPath: folder).lastPathComponent }
}

/// 대기 중인 승인 요청 하나. 응답은 이 요청을 보낸 훅 연결로만 돌려보낸다.
struct PendingApproval: Identifiable {
    let id: String
    let source: AgentSource
    let sessionID: String
    let tool: String
    /// 카드 한 줄 요약
    let summary: String
    /// 숨은 문자를 드러낸 전체 내용 (탭에서 보여 줌)
    let fullText: String
    let hasHidden: Bool
    /// "항상 허용" 제안 (Claude Code의 addRules allow 제안만)
    let suggestions: [[String: Any]]
    let projectDir: String
    let cwd: String
    let target: String?
    let created: Date
    let connection: LocalAPIConnection

    var project: String {
        let f = projectDir.isEmpty ? cwd : projectDir
        return f.isEmpty ? source.name : URL(fileURLWithPath: f).lastPathComponent
    }

    /// 카드에서 바로 허용해도 될 만큼 짧고 숨은 문자가 없는지 (잘린 명령으로는 승인하지 않는다)
    var fitsOnCard: Bool { !hasHidden && !fullText.contains("\n") && fullText.count <= 140 }

    /// "항상 허용"으로 저장될 규칙 글자들 (Claude Code 규칙 형식: Tool(내용))
    var alwaysRules: [String] { AgentHub.ruleStrings(suggestions) }
}

/// 사용자의 결정
enum AgentDecision: String { case allow, allowAlways, deny, ask }

/// 훅 이벤트를 받아 세션 상태·승인 카드·라이브 활동을 관리한다 (메인 스레드).
final class AgentHub: ObservableObject {
    @Published private(set) var sessions: [String: AgentSessionState] = [:]
    @Published private(set) var approvals: [PendingApproval] = []
    /// 마지막 안내 ("이미 처리됨" 등)
    @Published var message: String?

    var center: ActivityCenter?
    var openTab: ((String) -> Void)?
    var costSummaryEnabled: () -> Bool = { false }
    let ledger: AgentAllowLedger
    var approvalTimeout: TimeInterval = LocalAPIServer.approvalTimeout + 3
    /// 프로세스 확인 (검사에서 바꿈)
    var processAlive: (pid_t) -> Bool = AgentProcessTree.isAlive
    var resolveTarget: (pid_t) -> String? = AgentProcessTree.target

    private var timers: [String: DispatchWorkItem] = [:]
    private var sweepTimer: Timer?
    private var shownApprovalID: String?

    init(ledger: AgentAllowLedger) {
        self.ledger = ledger
    }

    func start(center: ActivityCenter, openTab: @escaping (String) -> Void) {
        self.center = center
        self.openTab = openTab
        sweepTimer?.invalidate()
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.sweep() }
    }

    /// 끌 때: 대기 중인 요청은 결정 없이 돌려보내 터미널 프롬프트로 넘긴다
    func stop() {
        sweepTimer?.invalidate()
        sweepTimer = nil
        for a in approvals { a.connection.reply(["ok": true, "decision": "ask"], close: true) }
        approvals.removeAll()
        timers.values.forEach { $0.cancel() }
        timers.removeAll()
        center?.dismissTransient(kind: .agentApproval)
        center?.removePersistent(.agent)
        sessions.removeAll()
        shownApprovalID = nil
    }

    // MARK: 이벤트 (agent.event)

    func handleEvent(_ json: [String: Any]) -> LocalAPIServer.Reply {
        guard let src = (json["source"] as? String).flatMap(AgentSource.init(rawValue:)),
              let event = json["event"] as? String else { return .now(["ok": false, "error": "bad_event"]) }
        let payload = json["payload"] as? [String: Any] ?? [:]
        let sid = (payload["session_id"] as? String).map { String($0.prefix(128)) } ?? "default"
        let key = "\(src.rawValue):\(sid)"
        var s = sessions[key] ?? AgentSessionState(source: src, sessionID: sid)
        if let cwd = payload["cwd"] as? String, !cwd.isEmpty { s.cwd = cwd }
        if let pd = json["project_dir"] as? String, !pd.isEmpty { s.projectDir = pd }
        if let t = payload["transcript_path"] as? String, !t.isEmpty { s.transcript = t }
        if let ppid = (json["ppid"] as? NSNumber)?.int32Value, ppid > 1, s.pid != ppid {
            s.pid = ppid
            s.target = resolveTarget(ppid)
        }
        s.updated = Date()
        var notice: (String, String)?
        switch event {
        case "SessionStart":
            if s.phase == .done || s.phase == .error { s.phase = .idle }
        case "UserPromptSubmit":
            s.phase = .working
            s.turnStart = Date()
            s.detail = Self.oneLine(payload["prompt"] as? String ?? "", 80)
        case "Notification":
            let type = payload["notification_type"] as? String ?? ""
            let text = Self.oneLine(payload["message"] as? String ?? "", 100)
            switch type {
            case "permission_prompt":
                // 노치 승인 요청이 이미 떠 있으면 그대로, 아니면 터미널에서 기다리는 중
                if !approvals.contains(where: { $0.sessionID == sid && $0.source == src }) {
                    s.phase = .needsInput
                    s.detail = text.isEmpty ? T("터미널에서 권한 확인을 기다림", "Waiting for permission in the terminal") : text
                }
            case "idle_prompt":
                s.phase = .needsInput
                s.detail = T("다음 요청을 기다림", "Waiting for your next prompt")
            case "elicitation_dialog", "agent_needs_input":
                s.phase = .needsInput
                s.detail = text
                notice = (T("\(src.name) · \(s.project) 입력 필요", "\(src.name) · \(s.project) needs input"), text)
            default:
                break
            }
        case "Stop":
            s.phase = .done
            s.detail = Self.oneLine(payload["last_assistant_message"] as? String ?? "", 80)
            schedule(key, after: 6) { [weak self] in self?.setPhase(key, .idle, only: .done) }
            if src == .claude, costSummaryEnabled(), let t = s.transcript { postCostSummary(transcript: t, session: s) }
        case "StopFailure":
            s.phase = .error
            s.detail = Self.oneLine(payload["error"] as? String ?? (payload["last_assistant_message"] as? String ?? ""), 100)
            notice = (T("\(src.name) · \(s.project) 오류", "\(src.name) · \(s.project) error"), s.detail)
            schedule(key, after: 30) { [weak self] in self?.setPhase(key, .idle, only: .error) }
        case "SessionEnd":
            sessions[key] = nil
            resolveApprovals(session: sid, source: src, reason: "session_end")
            refreshActivity()
            return .now(["ok": true])
        default:
            break
        }
        if s.phase == .working || s.phase == .needsInput { timers[key]?.cancel() }
        sessions[key] = s
        refreshActivity()
        if let n = notice {
            center?.post(NotchActivity(kind: .notice, priority: ActivityPriority.info, presentation: .detail, duration: 6,
                                       symbol: s.phase == .error ? "exclamationmark.triangle.fill" : "questionmark.bubble.fill",
                                       tint: s.phase == .error ? .red : .orange, title: n.0, subtitle: n.1.isEmpty ? nil : n.1,
                                       targetApp: s.target, moduleTab: "agents"))
        }
        return .now(["ok": true])
    }

    private func setPhase(_ key: String, _ phase: AgentSessionState.Phase, only: AgentSessionState.Phase) {
        guard var s = sessions[key], s.phase == only else { return }
        s.phase = phase
        sessions[key] = s
        refreshActivity()
    }

    private func schedule(_ key: String, after: TimeInterval, _ body: @escaping () -> Void) {
        timers[key]?.cancel()
        let w = DispatchWorkItem(block: body)
        timers[key] = w
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: w)
    }

    /// 에이전트 프로세스가 사라진 세션 정리
    func sweep() {
        for (k, s) in sessions where s.pid > 1 && !processAlive(s.pid) {
            sessions[k] = nil
        }
        refreshActivity()
    }

    // MARK: 라이브 활동 (상시 표시 하나: 가장 급한 세션)

    func refreshActivity() {
        guard let center else { return }
        let active = sessions.values.filter { $0.phase != .idle }
        guard let top = active.max(by: { ($0.phase, $0.updated) < ($1.phase, $1.updated) }) else {
            center.removePersistent(.agent)
            return
        }
        let working = active.filter { $0.phase == .working }.count
        var subtitle = top.phase.label
        if !top.detail.isEmpty { subtitle += " · " + top.detail }
        if working > 1 { subtitle += T(" · 작업 중 \(working)개", " · \(working) working") }
        let value: ActivityValue
        let tint: Color
        switch top.phase {
        case .approval: value = .text(T("승인", "Approve")); tint = .orange
        case .needsInput: value = .text(T("대기", "Waiting")); tint = .orange
        case .error: value = .text(T("오류", "Error")); tint = .red
        case .done: value = .check; tint = top.source.tint
        default: value = .spinner; tint = top.source.tint
        }
        center.setPersistent(NotchActivity(kind: .agent, priority: ActivityPriority.pinned, presentation: .compact,
                                           symbol: top.source.symbol, tint: tint, value: value,
                                           title: "\(top.source.name) · \(top.project)", subtitle: subtitle,
                                           targetApp: top.target, moduleTab: "agents"))
    }

    // MARK: 승인 요청 (approval.request)

    func handleApproval(_ req: LocalAPIServer.Request) -> LocalAPIServer.Reply {
        let json = req.json
        guard let src = (json["source"] as? String).flatMap(AgentSource.init(rawValue:)),
              let payload = json["payload"] as? [String: Any] else { return .now(["ok": false, "error": "bad_request"]) }
        let sid = (payload["session_id"] as? String).map { String($0.prefix(128)) } ?? "default"
        let tool = String((payload["tool_name"] as? String ?? "Tool").prefix(80))
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        let full = Self.fullText(tool: tool, input: input)
        let revealed = AIDevFormat.revealHidden(full)
        let ppid = (json["ppid"] as? NSNumber)?.int32Value ?? 0
        // 같은 세션의 이전 요청은 결정 없이 정리 (터미널 프롬프트로)
        resolveApprovals(session: sid, source: src, reason: "superseded")
        let suggestions: [[String: Any]] = src == .claude
            ? (payload["permission_suggestions"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "addRules" && $0["behavior"] as? String == "allow" }
            : []
        let a = PendingApproval(id: UUID().uuidString, source: src, sessionID: sid, tool: tool,
                                summary: Self.oneLine(revealed, 140), fullText: revealed, hasHidden: AIDevFormat.hasHidden(full),
                                suggestions: suggestions, projectDir: json["project_dir"] as? String ?? "",
                                cwd: payload["cwd"] as? String ?? "", target: ppid > 1 ? resolveTarget(ppid) : nil,
                                created: Date(), connection: req.connection)
        approvals.append(a)
        // 훅 프로세스가 끝나면(터미널에서 먼저 답함·시간 초과·Ctrl-C) 바로 카드를 지운다
        req.connection.observeClose { [weak self] in self?.connectionClosed(a.id) }
        let id = a.id
        schedule("approval:\(id)", after: approvalTimeout) { [weak self] in self?.finish(id, reply: ["ok": true, "decision": "timeout"]) }
        // 세션 상태
        let key = "\(src.rawValue):\(sid)"
        var s = sessions[key] ?? AgentSessionState(source: src, sessionID: sid)
        s.phase = .approval
        s.detail = "\(tool): \(a.summary)"
        s.updated = Date()
        if s.cwd.isEmpty { s.cwd = a.cwd }
        if s.projectDir.isEmpty { s.projectDir = a.projectDir }
        if ppid > 1 { s.pid = ppid; s.target = a.target ?? s.target }
        sessions[key] = s
        refreshActivity()
        showCard(a)
        return .hold
    }

    /// 버튼에서 부른다. 이미 처리된 요청이면 무시하고 안내만 한다.
    func decide(_ id: String, _ decision: AgentDecision) {
        guard let a = approvals.first(where: { $0.id == id }) else {
            message = T("이미 처리된 요청입니다", "That request was already handled")
            center?.post(NotchActivity(kind: .notice, priority: ActivityPriority.info, presentation: .compact, duration: 2,
                                       symbol: "checkmark.circle", value: .text(T("처리됨", "Handled"))))
            return
        }
        var d = decision
        if d == .allowAlways, a.source != .claude || a.suggestions.isEmpty { d = .allow }
        if d == .allowAlways {
            ledger.record(rules: a.alwaysRules, file: AgentAllowLedger.localSettingsFile(projectDir: a.projectDir.isEmpty ? a.cwd : a.projectDir))
        }
        var reply: [String: Any] = ["ok": true, "decision": d.rawValue]
        if let out = Self.hookOutput(source: a.source, decision: d, suggestions: a.suggestions) { reply["hook_output"] = out }
        finish(id, reply: reply)
        message = nil
    }

    static func hookOutput(source: AgentSource, decision: AgentDecision, suggestions: [[String: Any]]) -> [String: Any]? {
        var body: [String: Any]
        switch decision {
        case .ask: return nil
        case .allow: body = ["behavior": "allow"]
        case .allowAlways:
            body = ["behavior": "allow"]
            // Claude Code만: 제안된 규칙을 프로젝트 로컬 설정(.claude/settings.local.json)에 저장하게 한다
            if source == .claude, !suggestions.isEmpty {
                body["updatedPermissions"] = suggestions.map { s -> [String: Any] in
                    var c = s
                    c["destination"] = "localSettings"
                    return c
                }
            }
        case .deny: body = ["behavior": "deny", "message": "Denied from the notch (Dynamic Notch)."]
        }
        return ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": body]]
    }

    /// 응답을 보내고 정리
    private func finish(_ id: String, reply: [String: Any]) {
        guard let i = approvals.firstIndex(where: { $0.id == id }) else { return }
        let a = approvals.remove(at: i)
        timers["approval:\(id)"]?.cancel()
        timers["approval:\(id)"] = nil
        a.connection.reply(reply, close: true)
        afterResolve(a)
    }

    private func connectionClosed(_ id: String) {
        guard let i = approvals.firstIndex(where: { $0.id == id }) else { return }
        let a = approvals.remove(at: i)
        timers["approval:\(id)"]?.cancel()
        timers["approval:\(id)"] = nil
        afterResolve(a)
    }

    private func resolveApprovals(session: String, source: AgentSource, reason: String) {
        for a in approvals where a.sessionID == session && a.source == source {
            finish(a.id, reply: ["ok": true, "decision": reason])
        }
    }

    private func afterResolve(_ a: PendingApproval) {
        if shownApprovalID == a.id {
            center?.dismissTransient(kind: .agentApproval)
            shownApprovalID = nil
        }
        let key = "\(a.source.rawValue):\(a.sessionID)"
        if var s = sessions[key], s.phase == .approval, !approvals.contains(where: { $0.sessionID == a.sessionID && $0.source == a.source }) {
            s.phase = .working
            s.detail = ""
            sessions[key] = s
        }
        refreshActivity()
        if let next = approvals.last, shownApprovalID == nil { showCard(next) }
    }

    // MARK: 카드

    func showCard(_ a: PendingApproval) {
        guard let center else { return }
        let id = a.id
        var actions: [ActivityAction] = []
        if a.fitsOnCard {
            actions.append(ActivityAction(id: "allow-\(id)", title: T("허용", "Allow"), role: .primary) { [weak self] in self?.decide(id, .allow) })
            if !a.alwaysRules.isEmpty {
                actions.append(ActivityAction(id: "always-\(id)", title: T("항상 허용", "Always Allow")) { [weak self] in self?.decide(id, .allowAlways) })
            }
        } else {
            // 길거나 숨은 문자가 있으면 카드에서는 승인하지 않고 탭에서 전체를 본다
            actions.append(ActivityAction(id: "review-\(id)", title: T("전체 보기", "Review"), role: .primary) { [weak self] in self?.openTab?("agents") })
        }
        actions.append(ActivityAction(id: "deny-\(id)", title: T("거부", "Deny"), role: .destructive) { [weak self] in self?.decide(id, .deny) })
        if a.target != nil {
            actions.append(ActivityAction(id: "jump-\(id)", title: T("터미널", "Terminal")) { AgentProcessTree.jump(a.target) })
        }
        let title = "\(a.source.name) · \(a.project) — \(a.tool)"
        let subtitle = a.hasHidden ? T("⚠︎ 숨은 문자 있음 · ", "⚠︎ Hidden characters · ") + a.summary : a.summary
        center.post(NotchActivity(kind: .agentApproval, priority: ActivityPriority.call - 3, presentation: .detail,
                                  duration: max(5, approvalTimeout - Date().timeIntervalSince(a.created)),
                                  symbol: "hand.raised.fill", tint: .orange, value: .text(T("승인?", "Allow?")),
                                  title: title, subtitle: subtitle, targetApp: a.target,
                                  ignoresHoverPause: true, moduleTab: "agents", actions: actions))
        shownApprovalID = id
    }

    // MARK: 비용 요약 (M-K-012)

    private func postCostSummary(transcript: String, session: AgentSessionState) {
        let url = URL(fileURLWithPath: transcript)
        let since = session.turnStart
        let project = session.project
        let target = session.target
        // 대화 기록이 마지막 답변까지 쓰이도록 잠깐 기다린 뒤 읽는다
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) { [weak self] in
            let r = ClaudeLogScanner.sessionCost(transcript: url, turnSince: since)
            DispatchQueue.main.async {
                guard let self, let center = self.center, r.tokens > 0 else { return }
                center.post(Self.costActivity(project: project, total: r.total, turn: r.turn, unpriced: r.unpriced, target: target))
            }
        }
    }

    static func costActivity(project: String, total: Double, turn: Double?, unpriced: Bool, target: String?) -> NotchActivity {
        var sub = turn.map { T("이번 답변 \(AIDevFormat.usd($0)) · ", "This reply \(AIDevFormat.usd($0)) · ") } ?? ""
        sub += T("대화 전체 \(AIDevFormat.usd(total))", "Conversation \(AIDevFormat.usd(total))")
        sub += unpriced ? T(" (일부 모델 요금 모름)", " (some models unpriced)") : ""
        sub += T(" · API 요금 기준 추정", " · API-rate estimate")
        return NotchActivity(kind: .notice, priority: ActivityPriority.info - 5, presentation: .detail, duration: 6,
                             symbol: "dollarsign.circle", tint: AgentSource.claude.tint, value: .text(AIDevFormat.usd(turn ?? total)),
                             title: "Claude Code · \(project)", subtitle: sub, targetApp: target, moduleTab: "localusage")
    }

    // MARK: 도우미

    static func oneLine(_ s: String, _ limit: Int) -> String {
        let flat = s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }

    /// 도구 입력 전체를 사람이 볼 글자로 (명령은 그대로, 나머지는 JSON)
    static func fullText(tool: String, input: [String: Any]) -> String {
        if let c = input["command"] as? String { return c }
        if let c = input["command"] as? [String] { return c.joined(separator: " ") }
        if let p = input["file_path"] as? String {
            if let old = input["old_string"] as? String, let new = input["new_string"] as? String {
                return "\(p)\n− \(old)\n+ \(new)"
            }
            if let content = input["content"] as? String { return "\(p)\n\(content)" }
            return p
        }
        if let u = input["url"] as? String { return u }
        guard let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes]) else { return tool }
        return String(decoding: data, as: UTF8.self)
    }

    /// addRules 제안 → "Tool(내용)" 규칙 글자
    static func ruleStrings(_ suggestions: [[String: Any]]) -> [String] {
        suggestions.flatMap { s -> [String] in
            (s["rules"] as? [[String: Any]] ?? []).compactMap { r in
                guard let tool = r["toolName"] as? String else { return nil }
                if let c = r["ruleContent"] as? String, !c.isEmpty { return "\(tool)(\(c))" }
                return tool
            }
        }
    }
}

/// "항상 허용"으로 이 앱이 저장하게 한 규칙의 기록 (M-K-020). 철회할 때 이 기록에 있는 것만 뺀다.
final class AgentAllowLedger {
    struct Rule: Codable, Equatable {
        var file: String
        var rule: String
        var added: Date
    }

    private let load: () -> Data?
    private let save: (Data?) -> Void
    var now: () -> Date = Date.init

    init(load: @escaping () -> Data?, save: @escaping (Data?) -> Void) {
        self.load = load
        self.save = save
    }

    static let live = AgentAllowLedger(load: { ModuleDefaults(module: "agents").data("allowLedger") },
                                       save: { ModuleDefaults(module: "agents").set($0, "allowLedger") })

    static func localSettingsFile(projectDir: String) -> URL {
        URL(fileURLWithPath: projectDir).appendingPathComponent(".claude/settings.local.json")
    }

    var rules: [Rule] {
        guard let d = load(), let list = try? JSONDecoder().decode([Rule].self, from: d) else { return [] }
        return list
    }

    private func store(_ list: [Rule]) {
        save(list.isEmpty ? nil : try? JSONEncoder().encode(list))
    }

    /// 기록. 이미 그 파일에 있는 규칙(사용자가 둔 것)은 기록하지 않는다.
    func record(rules new: [String], file: URL) {
        let existing = Set(Self.allowList(file) ?? [])
        var list = rules
        for r in new where !existing.contains(r) && !list.contains(where: { $0.file == file.path && $0.rule == r }) {
            list.append(Rule(file: file.path, rule: r, added: now()))
        }
        store(list)
    }

    static func allowList(_ file: URL) -> [String]? {
        guard let text = try? String(contentsOf: file, encoding: .utf8), let root = try? OrderedJSON.parse(text) else { return nil }
        return root["permissions"]?["allow"]?.arrayValue?.compactMap(\.stringValue)
    }

    struct RevokeResult { var removed = 0; var backups: [URL] = []; var errors: [String] = [] }

    /// 기록된 규칙만 각 파일의 permissions.allow에서 뺀다 (파일마다 백업 후 한 번에 쓰기)
    func revokeAll() -> RevokeResult {
        var result = RevokeResult()
        var keep: [Rule] = []
        let byFile = Dictionary(grouping: rules, by: \.file)
        for (path, list) in byFile {
            let url = URL(fileURLWithPath: path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }   // 파일이 없으면 철회할 것도 없음
            guard var root = try? OrderedJSON.parse(text), root.isObject else {
                result.errors.append(T("\(path): JSON을 읽을 수 없어 그대로 둠", "\(path): unreadable JSON, left as is"))
                keep += list
                continue
            }
            let targets = Set(list.map(\.rule))
            guard var perms = root["permissions"], let allow = perms["allow"]?.arrayValue else { continue }
            let kept = allow.filter { item in !(item.stringValue.map(targets.contains) ?? false) }
            guard kept.count != allow.count else { continue }
            perms.set("allow", .array(kept))
            root.set("permissions", perms)
            var out = root.stringify()
            if text.hasSuffix("\n") { out += "\n" }
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            f.locale = Locale(identifier: "en_US_POSIX")
            let backup = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".dmn-backup-" + f.string(from: now()))
            do {
                if !FileManager.default.fileExists(atPath: backup.path) { try Data(text.utf8).write(to: backup) }
                try Data(out.utf8).write(to: url, options: .atomic)
                result.removed += allow.count - kept.count
                result.backups.append(backup)
            } catch {
                result.errors.append("\(path): \(error.localizedDescription)")
                keep += list
            }
        }
        store(keep)
        return result
    }
}

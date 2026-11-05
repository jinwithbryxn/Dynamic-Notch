import AppKit
import SwiftUI

/// 코딩 에이전트 (M-K-016·018·019·020·021·023, M-K-012 비용 요약):
/// Claude Code·Codex 훅이 로컬 API로 보내는 이벤트로 작업 중·완료·오류·입력 대기·승인 대기를 라이브 활동으로 보여 주고,
/// 실제 권한 요청(PermissionRequest)을 노치에서 허용·거부한다.
/// 기본 꺼짐. 훅 설치·제거는 설정 창에서 미리보기를 확인한 뒤에만 한다.
final class AgentHubModule: NotchModule {
    let id = "agents"
    var title: String { T("코딩 에이전트", "Coding Agents") }
    let symbol = "terminal"
    var enabledByDefault: Bool { false }

    let hub = AgentHub(ledger: .live)
    private let server: LocalAPIServer
    private var context: ModuleContext?
    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }

    init(server: LocalAPIServer = .shared) {
        self.server = server
    }

    func start(context: ModuleContext) {
        guard self.context == nil else { return }
        self.context = context
        hub.costSummaryEnabled = { ModuleDefaults(module: "agents").bool("costSummary", default: false) }
        hub.start(center: context.center, openTab: context.openTab)
        Self.registerCommands(on: server, hub: hub, owner: id) { ModuleDefaults(module: "agents").bool("approvals", default: true) }
        server.acquire(id)
        // 설치된 훅이 쓰는 스크립트를 최신으로 (설치 여부와 상관없이 앱 폴더 안에만 씀)
        _ = try? AgentHookInstaller.writeScript(to: LocalAPIServer.defaultEndpointDir)
    }

    func stop() {
        hub.stop()
        server.release(id)
        context = nil
    }

    static func registerCommands(on server: LocalAPIServer, hub: AgentHub, owner: String, approvalsOn: @escaping () -> Bool) {
        server.register(owner: owner, command: "agent.event", scopes: [.hook, .developer]) { [weak hub] req in
            hub?.handleEvent(req.json) ?? .now(["ok": false])
        }
        server.register(owner: owner, command: "approval.request", scopes: [.hook]) { [weak hub] req in
            guard let hub, approvalsOn() else { return .now(["ok": true, "decision": "ask"]) }
            return hub.handleApproval(req)
        }
    }

    func tabView() -> AnyView? { AnyView(AgentHubTab(hub: hub)) }
    var tabContentSize: CGSize { CGSize(width: 560, height: 270) }
    func settingsView() -> AnyView? { AnyView(AgentHubSettings()) }

    func paletteActions() -> [PaletteAction] {
        hub.approvals.map { a in
            PaletteAction(id: "agents.allow.\(a.id)", title: T("허용: \(a.tool) \(a.summary)", "Allow: \(a.tool) \(a.summary)"),
                          subtitle: "\(a.source.name) · \(a.project)", symbol: "hand.raised", keywords: ["allow", "허용", "approve"]) { [weak self] in
                guard let self, a.fitsOnCard else { self?.context?.openTab("agents"); return }
                self.hub.decide(a.id, .allow)
            }
        }
    }

    // MARK: 자체 검사 (사본 파일과 임시 포트만 사용)

    func selfTest() -> [String] {
        AgentHubSelfTest.run()
    }
}

// MARK: - 탭

private struct AgentHubTab: View {
    @ObservedObject var hub: AgentHub
    @State private var claudeStatus = AgentHookInstaller.Status.notInstalled
    @State private var codexStatus = AgentHookInstaller.Status.notInstalled

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let a = hub.approvals.last {
                ApprovalPanel(a: a, hub: hub, count: hub.approvals.count)
            }
            if hub.sessions.isEmpty && hub.approvals.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(T("진행 중인 에이전트 세션이 없습니다", "No agent sessions right now")).font(.island(.subhead, .semibold))
                    Text(T("Claude Code나 Codex에서 요청을 보내면 여기에 작업 중·입력 대기·승인 대기가 보입니다. 훅 연결은 설정 → 코딩 에이전트에서 미리보기를 확인한 뒤 합니다.",
                           "Send a prompt in Claude Code or Codex to see working, waiting and approval states here. Connect the hooks in Settings → Coding Agents after reviewing the preview."))
                        .font(.island(.footnote)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(hub.sessions.values.sorted { ($0.phase, $0.updated) > ($1.phase, $1.updated) }) { s in
                            SessionRow(s: s)
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                statusChip("Claude Code", claudeStatus)
                statusChip("Codex", codexStatus)
                Spacer()
                if let m = hub.message { Text(m).font(.island(.caption)).foregroundStyle(.orange) }
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            claudeStatus = AgentHookInstaller.live(.claude).status()
            codexStatus = AgentHookInstaller.live(.codex).status()
        }
    }

    private func statusChip(_ name: String, _ s: AgentHookInstaller.Status) -> some View {
        let (text, color): (String, Color) = {
            switch s {
            case .installed: return (T("연결됨", "connected"), .green)
            case .partial: return (T("일부 연결", "partly connected"), .orange)
            case .notInstalled: return (T("연결 안 됨", "not connected"), .gray)
            case .unreadable: return (T("설정 읽기 실패", "settings unreadable"), .red)
            }
        }()
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(name) \(text)").font(.island(.caption)).foregroundStyle(.white.opacity(0.6))
        }
    }
}

private struct ApprovalPanel: View {
    let a: PendingApproval
    @ObservedObject var hub: AgentHub
    let count: Int

    var body: some View {
        AIDevBox {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                    Text("\(a.source.name) · \(a.project) — \(a.tool)").font(.island(.subhead, .semibold)).lineLimit(1)
                    Spacer()
                    if count > 1 { Text(T("대기 \(count)건", "\(count) waiting")).font(.island(.caption)).foregroundStyle(.white.opacity(0.6)) }
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(AIDevFormat.elapsed(max(0, hub.approvalTimeout - ctx.date.timeIntervalSince(a.created))))
                            .font(.island(.caption)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
                    }
                }
                if a.hasHidden {
                    Text(T("⚠︎ 숨은 문자가 있습니다 (⟨U+…⟩로 표시)", "⚠︎ Contains hidden characters (shown as ⟨U+…⟩)"))
                        .font(.island(.caption, .semibold)).foregroundStyle(.orange)
                }
                ScrollView {
                    Text(a.fullText).font(.island(.footnote, .medium, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .frame(maxHeight: 64)
                HStack(spacing: 6) {
                    AIDevPill(title: T("허용", "Allow"), symbol: "checkmark", role: .primary) { hub.decide(a.id, .allow) }
                    if !a.alwaysRules.isEmpty {
                        AIDevPill(title: T("항상 허용", "Always Allow"), help: T("저장될 규칙: ", "Rules to save: ") + a.alwaysRules.joined(separator: ", ")) {
                            hub.decide(a.id, .allowAlways)
                        }
                    }
                    AIDevPill(title: T("거부", "Deny"), symbol: "xmark", role: .destructive) { hub.decide(a.id, .deny) }
                    AIDevPill(title: T("터미널에서 답하기", "Answer in Terminal"), help: T("노치에서 답하지 않고 원래 터미널 프롬프트로 넘깁니다", "Hand it back to the terminal prompt")) {
                        hub.decide(a.id, .ask)
                    }
                    Spacer()
                    if a.target != nil {
                        AIDevPill(title: AgentProcessTree.appName(a.target) ?? T("터미널", "Terminal"), symbol: "arrow.up.forward.app") { AgentProcessTree.jump(a.target) }
                    }
                }
            }
        }
    }
}

private struct SessionRow: View {
    let s: AgentSessionState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: s.source.symbol).foregroundStyle(s.source.tint).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(s.source.name) · \(s.project)").font(.island(.subhead, .semibold)).lineLimit(1)
                Text(s.detail.isEmpty ? s.phase.label : "\(s.phase.label) · \(s.detail)")
                    .font(.island(.caption)).foregroundStyle(color).lineLimit(1)
            }
            Spacer()
            Text(AIDevFormat.clock(s.updated)).font(.island(.caption)).foregroundStyle(.white.opacity(0.45))
            if !s.folder.isEmpty {
                Button { AgentProcessTree.openFolder(s.folder) } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain).help(T("프로젝트 폴더 열기", "Open project folder")).accessibilityLabel(T("프로젝트 폴더 열기", "Open project folder"))
            }
            if s.target != nil {
                Button { AgentProcessTree.jump(s.target) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.plain).help(T("에이전트를 돌린 앱으로 이동", "Go to the app running the agent")).accessibilityLabel(T("터미널로 이동", "Go to terminal"))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    }

    private var color: Color {
        switch s.phase {
        case .approval, .needsInput: return .orange
        case .error: return .red
        case .done: return .green
        default: return .white.opacity(0.6)
        }
    }
}

// MARK: - 설정 (설정 도우미 프로세스)

private struct AgentHubSettings: View {
    @State private var refresh = 0
    @State private var confirming: AgentHookInstaller.Agent?
    @State private var result: String?
    @State private var revokeConfirm = false
    @State private var costSummary = ModuleDefaults(module: "agents").bool("costSummary", default: false)
    @State private var approvals = ModuleDefaults(module: "agents").bool("approvals", default: true)

    var body: some View {
        let _ = refresh
        VStack(alignment: .leading, spacing: 12) {
            Toggle(T("노치에서 승인·거부 (110초 안에 답이 없으면 터미널 프롬프트로)", "Approve & deny from the notch (falls back to the terminal prompt after 110 s)"), isOn: $approvals)
                .onChange(of: approvals) { _, v in ModuleDefaults(module: "agents").set(v, "approvals") }
            Toggle(T("Claude Code 답변이 끝나면 대화 비용 요약 (API 요금 기준 추정)", "Session cost summary when a Claude Code reply ends (API-rate estimate)"), isOn: $costSummary)
                .onChange(of: costSummary) { _, v in ModuleDefaults(module: "agents").set(v, "costSummary") }
            ForEach([AgentHookInstaller.Agent.claude, .codex], id: \.rawValue) { agent in
                agentSection(agent)
            }
            Divider()
            let rules = AgentAllowLedger.live.rules
            HStack {
                Text(T("노치에서 '항상 허용'으로 저장한 규칙: \(rules.count)개", "Rules saved with Always Allow from the notch: \(rules.count)"))
                Spacer()
                if revokeConfirm {
                    Button(T("모두 철회", "Revoke All"), role: .destructive) {
                        let r = AgentAllowLedger.live.revokeAll()
                        result = T("철회 \(r.removed)개, 백업 \(r.backups.count)개", "Revoked \(r.removed), \(r.backups.count) backups") + (r.errors.isEmpty ? "" : " · " + r.errors.joined(separator: "; "))
                        revokeConfirm = false
                        refresh += 1
                    }
                    Button(T("취소", "Cancel")) { revokeConfirm = false }
                } else {
                    Button(T("상시 승인 철회…", "Revoke Standing Approvals…")) { revokeConfirm = true }.disabled(rules.isEmpty)
                }
            }
            if revokeConfirm {
                ForEach(rules, id: \.rule) { r in
                    Text("− \(r.rule)  (\(r.file))").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
                Text(T("이 앱이 저장하게 한 규칙만 각 프로젝트의 .claude/settings.local.json에서 빼고, 고치기 전에 백업합니다.",
                       "Only rules this app saved are removed from each project's .claude/settings.local.json, after a backup."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let result { Text(result).font(.caption).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder
    private func agentSection(_ agent: AgentHookInstaller.Agent) -> some View {
        let inst = AgentHookInstaller.live(agent)
        let status = inst.status()
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(agent.name).font(.headline)
                Text(statusText(status)).foregroundStyle(status == .installed ? .green : .secondary)
                Spacer()
                if status == .installed || { if case .partial = status { return true }; return false }() {
                    Button(T("연결 해제", "Disconnect")) {
                        do {
                            let b = try inst.uninstall()
                            result = T("\(agent.name) 훅을 뺐습니다", "Removed the \(agent.name) hooks") + (b.map { T(" · 백업: ", " · backup: ") + $0.lastPathComponent } ?? "")
                        } catch { result = error.localizedDescription }
                        refresh += 1
                    }
                }
                if confirming != agent, status != .installed {
                    Button(T("연결…", "Connect…")) { confirming = agent }
                        .disabled({ if case .unreadable = status { return true }; return false }())
                }
            }
            let others = inst.otherHookCommands()
            if !others.isEmpty {
                Text(T("그대로 두는 기존 훅:", "Existing hooks kept as is:")).font(.caption).foregroundStyle(.secondary)
                ForEach(others, id: \.self) { Text("  \($0)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1) }
            }
            if confirming == agent {
                Text(T("바뀔 내용 (이 앱 항목만 더함, 고치기 전에 백업):", "Changes (only this app's entries are added, after a backup):"))
                    .font(.caption)
                ForEach(inst.preview(), id: \.self) { Text($0).font(.system(.caption, design: .monospaced)).lineLimit(2) }
                if agent == .codex {
                    Text(T("Codex는 새 훅을 한 번 신뢰해야 동작합니다: Codex에서 /hooks 를 열어 확인하세요. config.toml의 notify는 건드리지 않습니다.",
                           "Codex runs new hooks only after you trust them once: open /hooks in Codex. notify in config.toml is not touched."))
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button(T("연결", "Connect")) {
                        do {
                            _ = try AgentHookInstaller.writeScript(to: LocalAPIServer.defaultEndpointDir)
                            let b = try inst.install()
                            result = T("\(agent.name) 훅을 넣었습니다", "Added the \(agent.name) hooks") + (b.map { T(" · 백업: ", " · backup: ") + $0.lastPathComponent } ?? "")
                        } catch { result = error.localizedDescription }
                        confirming = nil
                        refresh += 1
                    }
                    Button(T("취소", "Cancel")) { confirming = nil }
                }
            }
        }
    }

    private func statusText(_ s: AgentHookInstaller.Status) -> String {
        switch s {
        case .installed: return T("연결됨", "Connected")
        case .notInstalled: return T("연결 안 됨", "Not connected")
        case .partial(let missing): return T("일부만 연결 (빠짐: \(missing.joined(separator: ", ")))", "Partly connected (missing: \(missing.joined(separator: ", ")))")
        case .unreadable(let why): return T("설정 파일을 읽을 수 없어 고치지 않음: \(why)", "Settings unreadable, not changed: \(why)")
        }
    }
}

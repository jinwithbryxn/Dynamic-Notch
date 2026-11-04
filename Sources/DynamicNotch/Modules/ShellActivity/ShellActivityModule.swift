import AppKit
import SwiftUI

/// 오래 걸리는 셸 명령 라이브 활동 (M-K-024).
/// 켜고 설정에서 '연결'하면 ~/.zshrc 끝에 표식 주석으로 감싼 블록을 넣는다. 블록은 명령 시작·끝을 로컬 API(127.0.0.1, 훅 토큰)로 보낸다.
/// 10초 넘게 걸리는 명령만 경과 시간을 보여 주고, 끝나면 ✓·✗와 걸린 시간을 띄운다. 개발 서버·편집기·watch 류는 뺀다.
/// 앱이 꺼져 있으면 블록은 조용히 아무것도 하지 않는다 (연결 실패를 무시, 셸 출력 없음). zsh만 지원.
final class ShellActivityModule: NotchModule {
    let id = "shellactivity"
    var title: String { T("오래 걸리는 명령", "Long-Running Commands") }
    let symbol = "terminal.fill"
    var enabledByDefault: Bool { false }

    struct Running {
        let id: String
        let pid: Int32
        let command: String
        let cwd: String
        let start: Date
    }

    private(set) var running: [String: Running] = [:]
    private let server: LocalAPIServer
    private var context: ModuleContext?
    private var sweepTimer: Timer?
    private var finishedWork: DispatchWorkItem?
    /// 이 시간 넘게 걸린 명령만 보여 준다 (검사에서 짧게 바꿈)
    var threshold: TimeInterval = 10
    var processAlive: (Int32) -> Bool = { AgentProcessTree.isAlive($0) }

    init(server: LocalAPIServer = .shared) {
        self.server = server
    }

    static let defaultExcluded = ["vim", "nvim", "vi", "nano", "emacs", "less", "more", "man", "top", "htop", "btop", "ssh", "mosh",
                                  "tmux", "screen", "watch", "tail -f", "npm run dev", "npm start", "pnpm dev", "yarn dev", "bun dev",
                                  "next dev", "vite", "nodemon", "rails s", "rails server", "python -m http.server", "docker compose up",
                                  "claude", "codex", "fzf", "lazygit", "tig", "jupyter", "ipython", "python", "node", "irb"]

    var excluded: [String] { ModuleDefaults(module: id).strings("excluded", default: Self.defaultExcluded) }

    static func isExcluded(_ command: String, list: [String]) -> Bool {
        var words = command.split(separator: " ").map(String.init)
        // 앞의 환경 변수 지정·sudo·time·nohup은 건너뛴다
        while let w = words.first, w.contains("=") || ["sudo", "time", "nohup", "env", "exec"].contains(w) { words.removeFirst() }
        let cmd = words.joined(separator: " ")
        guard let first = words.first.map({ URL(fileURLWithPath: $0).lastPathComponent }) else { return true }
        return list.contains { e in e.contains(" ") ? cmd.hasPrefix(e) : first == e }
    }

    func start(context: ModuleContext) {
        guard self.context == nil else { return }
        self.context = context
        register(on: server)
        server.acquire(id)
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.sweep() }
    }

    func stop() {
        server.release(id)
        sweepTimer?.invalidate()
        sweepTimer = nil
        finishedWork?.cancel()
        running.removeAll()
        context?.center.removePersistent(.shell)
        context = nil
    }

    func register(on server: LocalAPIServer) {
        server.register(owner: id, command: "shell.event", scopes: [.hook, .developer]) { [weak self] req in
            self?.handle(req.json) ?? .now(["ok": false])
        }
    }

    func handle(_ json: [String: Any]) -> LocalAPIServer.Reply {
        guard let phase = json["phase"] as? String, let cid = (json["id"] as? String).map({ String($0.prefix(64)) }) else {
            return .now(["ok": false, "error": "bad_event"])
        }
        let pid = (json["pid"] as? NSNumber)?.int32Value ?? 0
        switch phase {
        case "start":
            let cmd = AgentHub.oneLine(json["cmd"] as? String ?? "", 300)
            guard !cmd.isEmpty else { return .now(["ok": true]) }
            // 같은 셸의 이전 명령은 끝난 것으로 본다
            running = running.filter { $0.value.pid != pid || pid == 0 }
            running[cid] = Running(id: cid, pid: pid, command: cmd, cwd: json["cwd"] as? String ?? "", start: Date())
            DispatchQueue.main.asyncAfter(deadline: .now() + threshold) { [weak self] in self?.refreshActivity() }
        case "end":
            guard let r = running.removeValue(forKey: cid) else { return .now(["ok": true]) }
            let duration = Date().timeIntervalSince(r.start)
            let exit = (json["exit"] as? NSNumber)?.intValue ?? 0
            if duration >= threshold, !Self.isExcluded(r.command, list: excluded) { finished(r, exit: exit, duration: duration) }
            refreshActivity()
        default:
            return .now(["ok": false, "error": "bad_phase"])
        }
        return .now(["ok": true])
    }

    private func finished(_ r: Running, exit: Int, duration: TimeInterval) {
        guard let context else { return }
        let ok = exit == 0
        let title = AgentHub.oneLine(r.command, 60)
        let sub = (ok ? T("완료", "Done") : (exit == 130 ? T("중단됨", "Interrupted") : T("실패 (종료 코드 \(exit))", "Failed (exit \(exit))")))
            + " · " + AIDevFormat.elapsed(duration) + (r.cwd.isEmpty ? "" : " · " + URL(fileURLWithPath: r.cwd).lastPathComponent)
        context.center.post(NotchActivity(kind: .notice, priority: ActivityPriority.info, presentation: .detail, duration: 6,
                                          symbol: ok ? "checkmark.circle.fill" : "xmark.circle.fill", tint: ok ? .green : .red,
                                          value: ok ? .check : .text("✗"), title: title, subtitle: sub, moduleTab: id))
        // 자리를 비웠어도 볼 수 있게 결과를 5분 동안 작게 남긴다 (새 긴 명령이 시작되면 바뀜)
        lastFinished = (title, sub, ok, Date())
        finishedWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.lastFinished = nil; self?.refreshActivity() }
        finishedWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: w)
    }

    private var lastFinished: (title: String, subtitle: String, ok: Bool, at: Date)?

    func refreshActivity() {
        guard let context else { return }
        let now = Date()
        let long = running.values.filter { now.timeIntervalSince($0.start) >= threshold - 0.05 && !Self.isExcluded($0.command, list: excluded) }
            .sorted { $0.start > $1.start }
        if let top = long.first {
            var sub = top.cwd.isEmpty ? T("실행 중", "Running") : URL(fileURLWithPath: top.cwd).lastPathComponent
            if long.count > 1 { sub += T(" · 외 \(long.count - 1)개", " · +\(long.count - 1) more") }
            context.center.setPersistent(NotchActivity(kind: .shell, priority: ActivityPriority.timer, presentation: .compact,
                                                       symbol: "terminal", tint: .white, value: .elapsed(top.start),
                                                       title: AgentHub.oneLine(top.command, 60), subtitle: sub, moduleTab: id))
        } else if let f = lastFinished {
            context.center.setPersistent(NotchActivity(kind: .shell, priority: ActivityPriority.pinned, presentation: .compact,
                                                       symbol: f.ok ? "checkmark.circle" : "xmark.circle", tint: f.ok ? .green : .red,
                                                       value: f.ok ? .check : .text("✗"), title: f.title, subtitle: f.subtitle, moduleTab: id))
        } else {
            context.center.removePersistent(.shell)
        }
    }

    /// 창을 닫아 셸이 사라진 명령 정리
    func sweep() {
        running = running.filter { $0.value.pid <= 1 || processAlive($0.value.pid) }
        refreshActivity()
    }

    func tabView() -> AnyView? { AnyView(ShellActivityTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 480, height: 200) }
    func settingsView() -> AnyView? { AnyView(ShellActivitySettings()) }

    func selfTest() -> [String] { ShellActivitySelfTest.run() }
}

/// ~/.zshrc 블록 설치기 (대상 파일·endpoint 경로 주입)
struct ShellHookInstaller {
    // 사용자 셸 설정에 넣은 블록을 찾아 지우는 표시라, 제품 이름이 바뀌어도 옛 문구를 그대로 쓴다
    static let begin = "# >>> Dynamic Notch shell activity >>>"
    static let end = "# <<< Dynamic Notch shell activity <<<"
    /// 원래 파일이 줄바꿈으로 끝나지 않아 줄바꿈을 하나 더했다는 표시 (뺄 때 같이 뺀다)
    static let addedNewlineTag = " [nl]"

    let file: URL
    let endpointPath: String

    static var liveFile: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc") }
    static var liveEndpoint: String { LocalAPIServer.defaultEndpointDir.appendingPathComponent("endpoint").path }

    var isInstalled: Bool {
        guard let t = try? String(contentsOf: file, encoding: .utf8) else { return false }
        return t.contains(Self.begin) && t.contains(Self.end)
    }

    /// 블록 본문 (zsh). 포크 없이 내장 기능만 쓴다: zsh/net/tcp, read, 매개변수 치환.
    var block: String {
        let ep = endpointPath.replacingOccurrences(of: "'", with: "'\\''")
        return #"""
# Added by Dynamic Notch (Long-Running Commands). Turning the feature off removes this block.
if [[ -o interactive ]] && zmodload zsh/net/tcp 2>/dev/null; then
  typeset -g _dmn_ep='\#(ep)' _dmn_cmd_id=''
  _dmn_esc() {
    REPLY=${1//\\/\\\\}; REPLY=${REPLY//\"/\\\"}; REPLY=${REPLY//$'\n'/\\n}; REPLY=${REPLY//$'\t'/\\t}; REPLY=${REPLY//[[:cntrl:]]/ }
  }
  _dmn_send() {
    [[ -r $_dmn_ep ]] || return 0
    local _p _t _fd
    { IFS= read -r _p; IFS= read -r _t; } < $_dmn_ep 2>/dev/null || return 0
    [[ $_p == <-> && -n $_t ]] || return 0
    ztcp 127.0.0.1 $_p 2>/dev/null || return 0
    _fd=$REPLY
    print -r -u $_fd -- "{\"command\":\"shell.event\",\"token\":\"$_t\",$1}" 2>/dev/null
    ztcp -c $_fd 2>/dev/null
    return 0
  }
  _dmn_preexec() {
    _dmn_cmd_id="$$-$RANDOM$RANDOM"
    local _c _d
    _dmn_esc "${1[1,500]}"; _c=$REPLY
    _dmn_esc "$PWD"; _d=$REPLY
    _dmn_send "\"phase\":\"start\",\"id\":\"$_dmn_cmd_id\",\"pid\":$$,\"cwd\":\"$_d\",\"cmd\":\"$_c\""
  }
  _dmn_precmd() {
    local _st=$?
    if [[ -n $_dmn_cmd_id ]]; then
      _dmn_send "\"phase\":\"end\",\"id\":\"$_dmn_cmd_id\",\"pid\":$$,\"exit\":$_st"
      _dmn_cmd_id=''
    fi
    return $_st
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _dmn_preexec
  add-zsh-hook precmd _dmn_precmd
fi
"""# + "\n"
    }

    /// 넣기. 이미 있으면 새 블록으로 바꾼다. 바뀐 게 있으면 백업 경로.
    @discardableResult
    func install() throws -> URL? {
        let original = try? String(contentsOf: file, encoding: .utf8)
        var text = original ?? ""
        if text.contains(Self.begin) { text = Self.removing(text) }
        let needsNewline = !text.isEmpty && !text.hasSuffix("\n")
        let out = text + (needsNewline ? "\n" : "") + Self.begin + (needsNewline ? Self.addedNewlineTag : "") + "\n" + block + Self.end + "\n"
        return try write(out, original: original)
    }

    @discardableResult
    func uninstall() throws -> URL? {
        guard let original = try? String(contentsOf: file, encoding: .utf8), original.contains(Self.begin) else { return nil }
        return try write(Self.removing(original), original: original)
    }

    /// 표식 사이(표식 포함)만 뺀다
    static func removing(_ text: String) -> String {
        guard let b = text.range(of: begin) else { return text }
        guard let e = text.range(of: end, range: b.upperBound..<text.endIndex) else { return text }
        var lower = b.lowerBound
        var upper = e.upperBound
        if upper < text.endIndex, text[upper] == "\n" { upper = text.index(after: upper) }
        let beginLineEnd = text[b.upperBound...].firstIndex(of: "\n") ?? text.endIndex
        let tagged = text[b.upperBound..<beginLineEnd].hasPrefix(addedNewlineTag)
        if tagged, lower > text.startIndex, text[text.index(before: lower)] == "\n" { lower = text.index(before: lower) }
        return String(text[..<lower]) + String(text[upper...])
    }

    private func write(_ out: String, original: String?) throws -> URL? {
        guard out != original else { return nil }
        var backup: URL?
        if let original {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            f.locale = Locale(identifier: "en_US_POSIX")
            let b = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".dmn-backup-" + f.string(from: Date()))
            if !FileManager.default.fileExists(atPath: b.path) { try Data(original.utf8).write(to: b) }
            backup = b
        }
        try Data(out.utf8).write(to: file, options: .atomic)
        return backup
    }
}

private struct ShellActivityTab: View {
    let module: ShellActivityModule
    @State private var installed = ShellHookInstaller(file: ShellHookInstaller.liveFile, endpointPath: ShellHookInstaller.liveEndpoint).isInstalled

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 6) {
                let list = module.running.values.sorted { $0.start > $1.start }
                if list.isEmpty {
                    Text(T("실행 중인 명령이 없습니다", "No commands running")).font(.system(size: 13, weight: .semibold))
                    Text(installed
                         ? T("터미널(zsh)에서 10초 넘게 걸리는 명령은 여기와 노치에 경과 시간이 보이고, 끝나면 ✓·✗로 알립니다.",
                             "Commands in zsh that take over 10 s show their elapsed time here and in the notch, then ✓ or ✗ when done.")
                         : T("아직 ~/.zshrc에 연결하지 않았습니다. 설정 → 오래 걸리는 명령에서 미리보기를 확인하고 연결하세요.",
                             "Not connected to ~/.zshrc yet. Review the preview and connect in Settings → Long-Running Commands."))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                } else {
                    ForEach(list, id: \.id) { r in
                        HStack {
                            Image(systemName: "terminal")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.command).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                                Text(URL(fileURLWithPath: r.cwd).lastPathComponent).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
                            }
                            Spacer()
                            Text(AIDevFormat.elapsed(ctx.date.timeIntervalSince(r.start))).font(.system(size: 14, design: .rounded)).monospacedDigit()
                        }
                        .padding(6).background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                    }
                }
                Spacer(minLength: 0)
                Text(T("zsh 전용 · 개발 서버·편집기·watch는 제외 · 앱이 꺼져 있으면 셸에 영향 없음", "zsh only · dev servers, editors and watch are skipped · no effect on the shell when the app is off"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }
        }
        .foregroundStyle(.white)
    }
}

private struct ShellActivitySettings: View {
    @State private var refresh = 0
    @State private var confirming = false
    @State private var result: String?
    @State private var excludedText = ModuleDefaults(module: "shellactivity").strings("excluded", default: ShellActivityModule.defaultExcluded).joined(separator: ", ")

    var body: some View {
        let _ = refresh
        let inst = ShellHookInstaller(file: ShellHookInstaller.liveFile, endpointPath: ShellHookInstaller.liveEndpoint)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("~/.zshrc")
                Text(inst.isInstalled ? T("연결됨", "Connected") : T("연결 안 됨", "Not connected")).foregroundStyle(inst.isInstalled ? .green : .secondary)
                Spacer()
                if inst.isInstalled {
                    Button(T("연결 해제 (블록 제거)", "Disconnect (remove block)")) {
                        do { let b = try inst.uninstall(); result = T("블록을 뺐습니다", "Removed the block") + (b.map { " · " + $0.lastPathComponent } ?? "") }
                        catch { result = error.localizedDescription }
                        refresh += 1
                    }
                } else if !confirming {
                    Button(T("연결…", "Connect…")) { confirming = true }
                }
            }
            if confirming {
                Text(T("~/.zshrc 끝에 아래 블록을 더합니다 (고치기 전에 백업, 끄면 표식 사이만 제거). 새 터미널 창부터 적용됩니다.",
                       "This block is appended to ~/.zshrc (backed up first; disconnecting removes only the marked block). Applies to new terminal windows."))
                    .font(.caption)
                ScrollView { Text(ShellHookInstaller.begin + "\n" + inst.block + ShellHookInstaller.end).font(.system(.caption2, design: .monospaced)).textSelection(.enabled) }
                    .frame(height: 140)
                HStack {
                    Button(T("연결", "Connect")) {
                        do { let b = try inst.install(); result = T("블록을 넣었습니다", "Added the block") + (b.map { " · " + $0.lastPathComponent } ?? "") }
                        catch { result = error.localizedDescription }
                        confirming = false
                        refresh += 1
                    }
                    Button(T("취소", "Cancel")) { confirming = false }
                }
            }
            Text(T("제외할 명령 (쉼표로 구분)", "Commands to skip (comma-separated)")).font(.caption)
            TextField("", text: $excludedText, axis: .vertical).lineLimit(2...4)
                .onSubmit {
                    let list = excludedText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    ModuleDefaults(module: "shellactivity").set(list, "excluded")
                }
            if let result { Text(result).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

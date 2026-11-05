import AppKit
import SwiftUI

/// 노치 안 터미널 상태 (셸 하나)
final class TerminalController: ObservableObject {
    enum Status: Equatable { case idle, running, exited(Int32), failed(String) }
    @Published private(set) var status: Status = .idle
    @Published private(set) var title = ""
    private(set) var session: TerminalSession?
    var onFocus: (() -> Void)?
    var fontSize: CGFloat
    /// (실행 파일, 인자). 검사·렌더링은 DMN_TERMINAL_SHELL="/bin/zsh -f"로 사용자 설정 파일을 안 읽게 할 수 있다.
    var command: (path: String, args: [String])
    var cwd: String?
    /// 기능이 켜져 있을 때만 셸을 띄운다
    var enabled = false
    private(set) lazy var view = TerminalNSView(controller: self, fontSize: fontSize)

    init(fontSize: CGFloat = 12, command: (path: String, args: [String]) = TerminalController.resolveCommand(), cwd: String? = nil) {
        self.fontSize = fontSize
        self.command = command
        self.cwd = cwd
    }

    static func resolveCommand() -> (path: String, args: [String]) {
        if let env = ProcessInfo.processInfo.environment["DMN_TERMINAL_SHELL"], !env.isEmpty {
            let parts = env.split(separator: " ").map(String.init)
            return (parts[0], Array(parts.dropFirst()))
        }
        let custom = ModuleDefaults(module: "terminal").string("shell", default: "")
        if !custom.isEmpty, FileManager.default.isExecutableFile(atPath: custom) { return (custom, ["-l"]) }
        return (TerminalSession.loginShell, ["-l"])
    }

    var shellName: String { URL(fileURLWithPath: command.path).lastPathComponent }

    func requestFocus() { onFocus?() }

    /// 탭이 처음 보일 때 화면 크기를 알고 나서 셸을 띄운다. 끝난 셸은 다시 시작 버튼으로만.
    func ensureStarted(cols: Int, rows: Int) {
        guard enabled, session == nil, status == .idle else { return }
        launch(cols: cols, rows: rows)
    }

    private func launch(cols: Int, rows: Int) {
        let s = TerminalSession(cols: cols, rows: rows)
        s.onChange = { [weak self, weak s] in
            guard let self, let s else { return }
            self.view.needsDisplay = true
            if s.screen.title != self.title { self.title = s.screen.title }
        }
        s.onExit = { [weak self] code in self?.status = .exited(code) }
        do {
            try s.start(shell: command.path, args: command.args, cwd: cwd)
            session = s
            status = .running
        } catch {
            session = nil
            status = .failed(error.localizedDescription)
        }
        view.needsDisplay = true
    }

    func restart() {
        guard enabled else { return }
        session?.terminate()
        session = nil
        status = .idle
        title = ""
        let g = view.gridSize
        launch(cols: g.cols, rows: g.rows)
        view.focus()
    }

    func applyFont(_ size: CGFloat) {
        fontSize = size
        view.setFont(size: size)
    }

    func stop() {
        session?.terminate()
        session = nil
        status = .idle
        title = ""
    }
}

/// 노치 안 터미널 (M-K-025): 로그인 셸을 PTY로 띄워 기본 ANSI·256색·한글 입력을 그린다.
final class TerminalModule: NotchModule {
    let id = "terminal"
    var title: String { T("터미널", "Terminal") }
    let symbol = "terminal"
    var enabledByDefault: Bool { false }

    /// 탭 화면이 먼저 만들어질 수 있어서 기능 수명 내내 하나를 쓴다
    private(set) lazy var controller = TerminalController(fontSize: Self.fontSize)
    private var context: ModuleContext?

    static var fontSize: CGFloat { CGFloat(min(max(ModuleDefaults(module: "terminal").double("fontSize", default: 12), 9), 18)) }

    func start(context: ModuleContext) {
        self.context = context
        controller.enabled = true
        controller.onFocus = { [weak self] in self?.context?.focusInput() }
        controller.view.needsLayout = true
    }

    func stop() {
        controller.enabled = false
        controller.stop()
        controller.view.needsDisplay = true
        context = nil
    }

    func settingsChanged() {
        controller.applyFont(Self.fontSize)
        controller.command = TerminalController.resolveCommand()
    }

    func tabView() -> AnyView? { AnyView(TerminalTab(controller: controller)) }
    var tabContentSize: CGSize { CGSize(width: 620, height: 300) }

    func paletteActions() -> [PaletteAction] {
        guard controller.enabled else { return [] }
        return [PaletteAction(id: "terminal.open", title: T("노치 터미널 열기", "Open Notch Terminal"), symbol: "terminal", keywords: ["shell", "셸", "zsh", "터미널"]) { [weak self] in self?.context?.openTab("terminal") }]
    }

    func settingsView() -> AnyView? { AnyView(TerminalSettings()) }
    func selfTest() -> [String] { TerminalSelfTest.run() }
}

private struct TerminalTab: View {
    @ObservedObject var controller: TerminalController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "terminal").font(.island(.footnote, .semibold))
                Text(controller.title.isEmpty ? controller.shellName : controller.title)
                    .font(.island(.subhead, .semibold)).lineLimit(1).truncationMode(.middle)
                statusText
                Spacer(minLength: 6)
                switch controller.status {
                case .exited, .failed:
                    AIDevPill(title: T("다시 시작", "Restart"), symbol: "arrow.clockwise", role: .primary) { controller.restart() }
                case .running:
                    AIDevPill(title: T("붙여넣기", "Paste"), symbol: "doc.on.clipboard", help: T("클립보드 글자를 셸에 보냄 (⌘V)", "Send clipboard text to the shell (⌘V)")) { controller.view.paste(nil) }
                    AIDevPill(title: T("끝내기", "End"), symbol: "xmark", help: T("셸과 그 안의 프로그램에 종료 신호(SIGHUP)를 보냅니다", "Send SIGHUP to the shell and its programs")) { controller.stop(); controller.view.needsDisplay = true }
                case .idle:
                    AIDevPill(title: T("시작", "Start"), symbol: "play.fill", role: .primary) { controller.restart() }
                }
            }
            .foregroundStyle(.white)
            TerminalHost(controller: controller)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .center) { overlay }
        }
    }

    @ViewBuilder private var statusText: some View {
        switch controller.status {
        case .running:
            Text(T("실행 중", "Running")).font(.island(.caption)).foregroundStyle(.green.opacity(0.85))
        case .exited(let code):
            Text(T("종료됨 (코드 \(code))", "Exited (code \(code))")).font(.island(.caption)).foregroundStyle(.white.opacity(0.6))
        case .failed:
            Text(T("시작 실패", "Failed to start")).font(.island(.caption)).foregroundStyle(.red.opacity(0.85))
        case .idle:
            Text(T("멈춤", "Stopped")).font(.island(.caption)).foregroundStyle(.white.opacity(0.6))
        }
    }

    @ViewBuilder private var overlay: some View {
        switch controller.status {
        case .failed(let msg):
            AIDevUnsupported(title: T("셸을 시작하지 못했습니다", "Couldn't start the shell"), reason: msg, alternative: T("설정에서 셸 경로를 확인하거나 터미널 앱을 사용하세요.", "Check the shell path in Settings or use the Terminal app."))
                .frame(maxWidth: 420)
        case .idle where controller.session == nil:
            Text(T("셸이 멈춰 있습니다. 시작을 누르세요.", "The shell is stopped. Press Start."))
                .font(.island(.footnote)).foregroundStyle(.white.opacity(0.6))
        default:
            EmptyView()
        }
    }
}

private struct TerminalSettings: View {
    @State private var fontSize = ModuleDefaults(module: "terminal").double("fontSize", default: 12)
    @State private var shell = ModuleDefaults(module: "terminal").string("shell", default: "")

    var body: some View {
        Form {
            Section {
                Stepper(value: $fontSize, in: 9...18, step: 1) {
                    Text(T("글자 크기: \(Int(fontSize)) pt", "Font size: \(Int(fontSize)) pt"))
                }
                .onChange(of: fontSize) { _, v in ModuleDefaults(module: "terminal").set(v, "fontSize") }
                TextField(T("셸 경로 (비우면 로그인 셸 \(TerminalSession.loginShell))", "Shell path (empty = login shell \(TerminalSession.loginShell))"), text: $shell)
                    .onSubmit { ModuleDefaults(module: "terminal").set(shell.isEmpty ? nil : shell, "shell") }
                if !shell.isEmpty, !FileManager.default.isExecutableFile(atPath: shell) {
                    Text(T("실행할 수 없는 경로라 로그인 셸을 사용합니다.", "Not an executable path, so the login shell is used.")).font(.caption).foregroundStyle(.orange)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(T("셸은 탭을 처음 열 때 홈 폴더에서 로그인 셸(-l)로 시작하고, 탭을 오가도 계속 실행됩니다. 기능을 끄면 셸과 그 안의 프로그램에 종료 신호를 보냅니다.",
                           "The shell starts as a login shell (-l) in your home folder the first time you open the tab and keeps running across tab switches. Turning the feature off sends a hangup to the shell and its programs."))
                    Text(T("지원: 기본 ANSI·256색·트루컬러, 전체 화면 프로그램(vim·less·top), 한글 입력, ⌘V 붙여넣기, 드래그 선택 후 ⌘C, 스크롤백 1000줄. 마우스 보고와 여러 탭은 지원하지 않습니다.",
                           "Supported: basic ANSI, 256 colours and true colour, full-screen programs (vim, less, top), Korean input, ⌘V paste, drag to select then ⌘C, 1000 lines of scrollback. No mouse reporting and no multiple tabs."))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

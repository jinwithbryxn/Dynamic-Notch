import AppKit
import ServiceManagement
import SwiftUI

/// 확장 기능 개발·검증용 명령줄 모드. 앱 창을 띄우지 않고 결과를 출력한 뒤 끝난다.
///
///   --list-modules                         기능 목록
///   --module-selftest=<id|all|permissions|core>  기능 자체 검사 (실제 macOS 기능 호출). core = 명령 봉투·AppleScript 큐·공통 부품
///   --render-notch=<home|palette|module:id|detail-actions|compact-two> --out=<png> [--wait=<초>]
///                                          노치 전체를 실제 뷰로 그려 PNG로 저장
///   --render-tab=<id> --out=<png> [--start] [--wait=<초>] [--size=<폭>x<높이>]
///                                          탭 화면을 노치 모양 배경에 그려 PNG로 저장 (화면 녹화 권한 불필요)
///   --render-permissions --out=<png> [--wait=<초>] [--height=<pt>]
///                                          권한 관리 창을 밝은 배경에 그려 PNG로 저장 (이 앱의 실제 권한 상태로)
///   --login-item=off|on                    이 앱 번들의 '로그인 시 열기' 등록을 지우거나 넣는다 (검토용 앱 정리, 설치본 옮기기용)
enum ModuleDevTools {
    static func handle(_ arguments: [String]) {
        func value(_ name: String) -> String? {
            arguments.first { $0.hasPrefix("--\(name)=") }.map { String($0.dropFirst(name.count + 3)) }
        }
        if value("login-item") == "off" {
            do {
                try SMAppService.mainApp.unregister()
                print("login item: unregistered \(Bundle.main.bundleIdentifier ?? "")")
            } catch {
                print("login item: \(error.localizedDescription) (status \(SMAppService.mainApp.status.rawValue))")
            }
            exit(0)
        }
        if value("login-item") == "on" {
            do {
                try SMAppService.mainApp.register()
                print("login item: registered \(Bundle.main.bundleIdentifier ?? "") (status \(SMAppService.mainApp.status.rawValue))")
            } catch {
                print("login item: \(error.localizedDescription) (status \(SMAppService.mainApp.status.rawValue))")
            }
            exit(0)
        }
        if arguments.contains("--list-modules") {
            for m in ModuleCatalog.makeAll() {
                print("\(m.id)\t\(m.title)\tdefault=\(m.enabledByDefault ? "on" : "off")\ttab=\(m.tabView() != nil)\tsize=\(Int(m.tabContentSize.width))x\(Int(m.tabContentSize.height))")
            }
            exit(0)
        }
        if let id = value("module-selftest") {
            AppSettings.isHelper = true
            let modules = ModuleCatalog.makeAll().filter { id == "all" || $0.id == id }
            if modules.isEmpty && id != "permissions" && id != "core" { print("unknown module: \(id)"); exit(2) }
            for m in modules {
                print("== \(m.id)")
                for line in m.selfTest() { print("  \(line)") }
            }
            if id == "all" || id == "permissions" {
                print("== permissions")
                for line in PermissionNeeds.selfTest() { print("  \(line)") }
            }
            if id == "all" || id == "core" {
                print("== core")
                for line in CoreSelfTest.run() { print("  \(line)") }
            }
            exit(0)
        }
        if let state = value("render-notch"), let out = value("out") {
            AppSettings.isHelper = true
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            renderNotch(state, wait: Double(value("wait") ?? "") ?? 1.2, to: URL(fileURLWithPath: out))
            exit(0)
        }
        if arguments.contains("--render-permissions"), let out = value("out") {
            AppSettings.isHelper = true
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            let view = AnyView(PermissionsView(onboarding: false, embedded: value("height") != nil) {})
            let height = Double(value("height") ?? "") ?? 640
            render(view, contentSize: CGSize(width: 560, height: height), wait: Double(value("wait") ?? "") ?? 1.5,
                   to: URL(fileURLWithPath: out), light: true)
            exit(0)
        }
        if let id = value("render-tab"), let out = value("out") {
            AppSettings.isHelper = true
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            guard let m = ModuleCatalog.makeAll().first(where: { $0.id == id }), let view = m.tabView() else {
                print("unknown module or no tab: \(id)"); exit(2)
            }
            if arguments.contains("--start") {
                m.start(context: ModuleContext(center: ActivityCenter(), openTab: { _ in }, collapse: {}, focusInput: {}))
            }
            var size = m.tabContentSize
            if let s = value("size"), let x = s.split(separator: "x").map({ Double($0) ?? 0 }) as [Double]?, x.count == 2 {
                size = CGSize(width: x[0], height: x[1])
            }
            let wait = Double(value("wait") ?? "") ?? 1.0
            render(view, contentSize: size, wait: wait, to: URL(fileURLWithPath: out))
            if arguments.contains("--start") { m.stop() }
            exit(0)
        }
    }

    /// 노치 전체(도형·독·카드)를 실제 뷰 그대로 회색 바탕에 그린다.
    ///   home | palette | module:<id> | detail-actions | compact-two
    private static func renderNotch(_ state: String, wait: TimeInterval, to url: URL) {
        let center = ActivityCenter()
        let vm = NotchViewModel(center: center)
        if let screen = NotchGeometry.targetScreen(for: .builtIn) {
            vm.notchSize = NotchGeometry.notchRect(on: screen).size
            vm.hasPhysicalNotch = NotchGeometry.hasPhysicalNotch(screen)
        }
        if ProcessInfo.processInfo.environment["DMN_NO_NOTCH"] == "1" {   // 노치 없는 화면 흉내
            vm.hasPhysicalNotch = false
            vm.notchSize = CGSize(width: 190, height: 24)
        }
        let features = NotchFeatures(media: MediaController(center: center), screenshot: ScreenshotMonitor(center: center),
                                     recording: RecordingMonitor(center: center), tray: TrayStore(center: center),
                                     calendar: CalendarController(center: center), call: CallMonitor(center: center),
                                     usage: UsageStore(center: center), memo: MemoStore())
        let timer = TimerController(center: center, viewModel: vm)
        ModuleRegistry.shared.activate(context: ModuleContext(center: center, openTab: { vm.openModule($0) },
                                                              collapse: { vm.collapse() }, focusInput: {}))
        switch state {
        case "home": vm.expand(page: .home)
        case "dashboard": vm.selectHomeOption(.dashboard); vm.expand(page: .home)
        case "palette": vm.expand(page: .palette)
        case let s where s.hasPrefix("module:"): vm.expand(page: .module(String(s.dropFirst(7))))
        case "detail-actions":
            center.post(NotchActivity(kind: .agentApproval, priority: ActivityPriority.call, presentation: .detail, duration: 60,
                                      symbol: "terminal.fill", tint: .orange, title: "Claude Code",
                                      subtitle: "Bash: npm test", actions: [
                                        ActivityAction(id: "deny", title: T("거부", "Deny"), role: .destructive, run: {}),
                                        ActivityAction(id: "allow", title: T("허용", "Allow"), role: .primary, run: {}),
                                      ]))
        case "compact-two":
            center.setPersistent(NotchActivity(kind: .timer, priority: ActivityPriority.timer, symbol: "timer", tint: .orange,
                                               value: .text("24:12")))
            center.setPersistent(NotchActivity(kind: .stopwatch, priority: ActivityPriority.timer, symbol: "stopwatch",
                                               tint: .green, value: .text("3:05")))
        case "compact-bubble":
            center.setPersistent(NotchActivity(kind: .timer, priority: ActivityPriority.timer, symbol: "timer", tint: .orange,
                                               value: .text("24:12")))
            center.setPersistent(NotchActivity(kind: .stopwatch, priority: ActivityPriority.timer, symbol: "stopwatch",
                                               tint: .green, value: .ring(0.4)))
        default: print("unknown state: \(state)"); exit(2)
        }
        let root = ZStack(alignment: .top) {
            Color(white: 0.42)
            NotchRootView(vm: vm, timer: timer, features: features, openSettings: {})
        }
        let size = NotchGeometry.panelSize
        let host = NSHostingView(rootView: AnyView(root.frame(width: size.width, height: size.height)))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("render failed"); exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        ModuleRegistry.shared.stopAll()
        guard let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil else {
            print("write failed"); exit(1)
        }
        print("rendered notch \(state) -> \(url.path)")
    }

    /// 확장 패널과 같은 여백·배경(검은 둥근 사각형, 어두운 화면 모드)으로 그린다.
    /// - light: 노치 모양 검은 배경 대신 창처럼 밝은 배경에 그린다 (설정·권한 창 확인용)
    private static func render(_ content: AnyView, contentSize: CGSize, wait: TimeInterval, to url: URL, light: Bool = false) {
        let pad: CGFloat = light ? 0 : 30
        let size = CGSize(width: contentSize.width + 2 * pad, height: contentSize.height + 2 * pad)
        let root = content
            .frame(width: contentSize.width, height: contentSize.height)
            .padding(pad)
            .background(RoundedRectangle(cornerRadius: light ? 0 : 36, style: .continuous)
                .fill(light ? Color(nsColor: .windowBackgroundColor) : Color.black))
            .environment(\.colorScheme, light ? .light : .dark)
        let host = NSHostingView(rootView: AnyView(root))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        // onAppear·비동기 로딩이 끝나도록 잠깐 돌린다
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("render failed"); exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { print("encode failed"); exit(1) }
        do {
            try png.write(to: url)
            print("rendered \(Int(size.width))x\(Int(size.height)) -> \(url.path)")
        } catch {
            print("write failed: \(error.localizedDescription)"); exit(1)
        }
    }
}

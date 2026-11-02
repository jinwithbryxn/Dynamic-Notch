import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 런처 휠: 전역 단축키(기본 ⌃⌥L)로 노치 아래에 고정 앱·실행 중 앱·동작 고리를 원형으로 펼친다.
/// 화살표·Tab으로 이동, 숫자로 바로 이동, Return으로 실행, Space로 고리 전환, Esc나 바깥 클릭으로 닫힘.
final class LauncherWheelModule: NotchModule {
    let id = "launcherwheel"
    var title: String { T("런처 휠", "Launcher Wheel") }
    let symbol = "circle.grid.cross"
    var enabledByDefault: Bool { false }

    static let defaultShortcut = HotKeyCenter.Shortcut(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(controlKey | optionKey))
    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }
    var shortcut: HotKeyCenter.Shortcut { defaults.launchShortcut("shortcut", default: Self.defaultShortcut) }

    /// 동작 고리에 놓을 동작 (설정에서 추가)
    var ringActions: [LaunchAction] {
        guard let d = defaults.data("actions"), let list = try? JSONDecoder().decode([LaunchAction].self, from: d) else { return [] }
        return list
    }
    func setRingActions(_ list: [LaunchAction]) { defaults.set(try? JSONEncoder().encode(list), "actions") }

    fileprivate var context: ModuleContext?
    private var panel: LauncherWheelPanel?
    private(set) var hotkeyOK = true

    func start(context: ModuleContext) {
        self.context = context
        registerHotkey()
    }

    func stop() {
        HotKeyCenter.shared.unregister("launcherwheel.toggle")
        close()
        context = nil
    }

    func settingsChanged() { if context != nil { registerHotkey() } }

    private func registerHotkey() {
        hotkeyOK = HotKeyCenter.shared.register("launcherwheel.toggle", shortcut) { [weak self] in self?.toggle() }
        if !hotkeyOK {
            context?.notice(T("런처 휠 단축키를 쓸 수 없음", "Launcher Wheel shortcut unavailable"),
                            T("\(shortcut.display)을 다른 앱이 쓰는 중 · 설정에서 바꾸기", "\(shortcut.display) is taken · change it in Settings"),
                            symbol: "keyboard")
        }
    }


    func tabView() -> AnyView? { nil }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "launcherwheel.open", title: T("런처 휠 열기", "Open Launcher Wheel"), subtitle: shortcut.display,
                       symbol: symbol, keywords: ["launcher", "wheel", "런처", "휠"]) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self?.toggle() }
        }]
    }

    func settingsView() -> AnyView? { AnyView(LauncherWheelSettings(module: self)) }

    // MARK: 휠 창

    func toggle() {
        if panel != nil { close(); return }
        let model = WheelModel(pinned: LauncherStore.apps, actions: ringActions)
        let p = LauncherWheelPanel(model: model)
        model.onPerform = { [weak self] item in
            self?.close()
            item.perform(self?.context)
        }
        model.onClose = { [weak self] in self?.close() }
        panel = p
        p.present()
    }

    func close() {
        panel?.dismiss()
        panel = nil
    }

    func selfTest() -> [String] {
        var out = ["shortcut: \(shortcut.display) (registered only while the module runs)"]
        let model = WheelModel(pinned: LauncherStore.apps, actions: ringActions)
        for mode in WheelModel.Mode.allCases {
            model.mode = mode
            out.append("ring \(mode.rawValue): \(model.items.count) items \(model.items.prefix(4).map(\.label).joined(separator: ", "))")
        }
        // 원형 배치: 12시부터 시계 방향
        let pts = (0..<4).map { WheelGeometry.point(index: $0, count: 4, radius: 100) }
        out.append("geometry 4 items: " + pts.map { "(\(Int($0.x.rounded())),\(Int($0.y.rounded())))" }.joined(separator: " "))
        // 키 이동
        model.mode = .running
        if model.items.count > 2 {
            model.select(0); model.move(1); model.move(1); model.move(-1)
            out.append("key move: selected index \(model.selected) (expected 1)")
        }
        out.append("panel opened in self test: no")
        return out
    }
}

// MARK: - 모델

enum WheelGeometry {
    /// 원 중심 기준 좌표 (위가 -y). 12시 방향부터 시계 방향.
    static func point(index: Int, count: Int, radius: CGFloat) -> CGPoint {
        let a = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(max(count, 1))
        return CGPoint(x: radius * cos(a), y: radius * sin(a))
    }
}

final class WheelModel: ObservableObject {
    enum Mode: String, CaseIterable { case pinned, running, actions
        var title: String {
            switch self {
            case .pinned: return T("고정 앱", "Pinned")
            case .running: return T("실행 중", "Running")
            case .actions: return T("동작", "Actions")
            }
        }
    }

    struct Item: Identifiable {
        let id: String
        let label: String
        let icon: NSImage?
        let symbol: String
        let perform: (ModuleContext?) -> Void
    }

    @Published var mode: Mode = .pinned { didSet { selected = 0 } }
    @Published var selected = 0
    let pinned: [String]
    let actions: [LaunchAction]
    var onPerform: (Item) -> Void = { _ in }
    var onClose: () -> Void = {}

    init(pinned: [String], actions: [LaunchAction]) {
        self.pinned = pinned
        self.actions = actions
        if pinned.isEmpty { mode = !actions.isEmpty ? .actions : .running }
    }

    var items: [Item] {
        switch mode {
        case .pinned:
            return pinned.prefix(12).compactMap { k in
                guard let url = LaunchApps.resolve(k) else { return nil }
                return Item(id: k, label: LaunchApps.name(of: url), icon: NSWorkspace.shared.icon(forFile: url.path), symbol: "app") { _ in
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        case .running:
            let me = ProcessInfo.processInfo.processIdentifier
            return NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.processIdentifier != me }
                .prefix(12)
                .map { app in
                    Item(id: "pid\(app.processIdentifier)", label: app.localizedName ?? "?", icon: app.icon, symbol: "app") { _ in
                        app.unhide()
                        app.activate()
                    }
                }
        case .actions:
            return actions.prefix(12).map { a in
                Item(id: a.id, label: a.label, icon: a.kind == .app ? LaunchApps.icon(a.value) : nil, symbol: a.symbol) { ctx in
                    a.perform(context: ctx)
                }
            }
        }
    }

    func select(_ i: Int) { selected = max(0, min(i, max(0, items.count - 1))) }
    func move(_ d: Int) {
        let n = items.count
        guard n > 0 else { return }
        selected = ((selected + d) % n + n) % n
    }
    func nextMode() {
        let all = Mode.allCases
        mode = all[(all.firstIndex(of: mode)! + 1) % all.count]
    }
    func performSelected() {
        let list = items
        guard selected < list.count else { return }
        onPerform(list[selected])
    }

    /// 키 입력 처리. 처리했으면 true.
    func handleKey(_ e: NSEvent) -> Bool {
        switch Int(e.keyCode) {
        case kVK_Escape: onClose()
        case kVK_Return, kVK_ANSI_KeypadEnter: performSelected()
        case kVK_RightArrow, kVK_DownArrow: move(1)
        case kVK_LeftArrow, kVK_UpArrow: move(-1)
        case kVK_Tab: move(e.modifierFlags.contains(.shift) ? -1 : 1)
        case kVK_Space: nextMode()
        default:
            if let c = e.charactersIgnoringModifiers, let n = Int(c), n >= 1, n <= 9 { select(n - 1); return true }
            if e.charactersIgnoringModifiers == "0" { select(9); return true }
            return false
        }
        return true
    }
}

// MARK: - 창

/// 키 입력을 받는 비활성 패널 (앱을 앞으로 가져오지 않고 키보드만 받는다)
final class LauncherWheelPanel: NSPanel {
    private let model: WheelModel
    static let side: CGFloat = 340

    init(model: WheelModel) {
        self.model = model
        super.init(contentRect: CGRect(x: 0, y: 0, width: Self.side, height: Self.side),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        contentView = NSHostingView(rootView: LauncherWheelView(model: model).environment(\.colorScheme, .dark))
    }

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, model.handleKey(event) { return }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        // 바깥을 누르면 닫힌다
        DispatchQueue.main.async { [weak self] in self?.model.onClose() }
    }

    /// 노치가 있는 화면(없으면 주 화면) 위쪽 가운데, 메뉴 막대 바로 아래
    func present() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let top = screen.frame.maxY - max(screen.safeAreaInsets.top, NSStatusBar.system.thickness) - 6
        setFrameOrigin(CGPoint(x: screen.frame.midX - Self.side / 2, y: top - Self.side))
        alphaValue = 0
        orderFrontRegardless()
        makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: { self.orderOut(nil) })   // 애니메이션이 끝날 때까지 창을 붙잡아 둔다
    }
}

private struct LauncherWheelView: View {
    @ObservedObject var model: WheelModel
    @State private var appeared = false
    private let radius: CGFloat = 122
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var body: some View {
        let items = model.items
        ZStack {
            Circle().fill(Color.black.opacity(0.92))
            Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let p = WheelGeometry.point(index: i, count: items.count, radius: radius)
                Button { model.select(i); model.performSelected() } label: {
                    ZStack {
                        Circle().fill(i == model.selected ? Color.white.opacity(0.22) : Color.white.opacity(0.06))
                            .frame(width: 58, height: 58)
                        if let icon = item.icon {
                            Image(nsImage: icon).resizable().frame(width: 38, height: 38)
                        } else {
                            Image(systemName: item.symbol).font(.system(size: 20))
                        }
                        if i < 9 {
                            Text("\(i + 1)").font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(LaunchUI.secondary).offset(x: 22, y: -22)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(item.label).accessibilityLabel(item.label)
                .onHover { if $0 { model.select(i) } }
                .offset(x: p.x, y: p.y)
            }
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(WheelModel.Mode.allCases, id: \.self) { m in
                        LaunchChip(title: m.title, selected: model.mode == m) { model.mode = m }
                    }
                }
                .scaleEffect(0.82)
                Text(items.indices.contains(model.selected) ? items[model.selected].label : emptyText)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
                    .frame(width: 150)
                Text(T("←→ 이동 · ↩ 실행 · Space 전환", "←→ move · ↩ open · Space switch"))
                    .font(.system(size: 9)).foregroundStyle(LaunchUI.secondary)
            }
        }
        .foregroundStyle(.white)
        .frame(width: LauncherWheelPanel.side, height: LauncherWheelPanel.side)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.85)
        .onAppear { withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { appeared = true } }
    }

    private var emptyText: String {
        switch model.mode {
        case .pinned: return T("앱 런처 탭에서 앱을 고정하기", "Pin apps in the Launcher tab")
        case .running: return T("실행 중인 앱 없음", "No running apps")
        case .actions: return T("설정에서 동작 추가", "Add actions in Settings")
        }
    }
}

// MARK: - 설정

private struct LauncherWheelSettings: View {
    let module: LauncherWheelModule
    @State private var shortcut = LauncherWheelModule.defaultShortcut
    @State private var actions: [LaunchAction] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(T("휠 열기 단축키", "Wheel shortcut"))
                LaunchShortcutRecorder(current: shortcut) { s in
                    shortcut = s
                    ModuleDefaults(module: module.id).setLaunchShortcut(s, "shortcut")
                }
                Button(T("기본값", "Default")) {
                    shortcut = LauncherWheelModule.defaultShortcut
                    ModuleDefaults(module: module.id).setLaunchShortcut(nil, "shortcut")
                }
            }
            Text(T("고정 앱은 앱 런처 탭의 목록을 씁니다. 동작 고리에는 아래 동작이 원형으로 놓입니다 (최대 12개).",
                   "Pinned apps come from the Launcher tab. The Action Ring shows the actions below (up to 12)."))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(actions) { a in
                HStack {
                    Image(systemName: a.symbol)
                    Text(a.label)
                    Text(a.value).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button { moveAction(a, -1) } label: { Image(systemName: "chevron.up") }.help(T("위로", "Move up"))
                    Button { moveAction(a, 1) } label: { Image(systemName: "chevron.down") }.help(T("아래로", "Move down"))
                    Button(T("빼기", "Remove")) { actions.removeAll { $0.id == a.id }; module.setRingActions(actions) }
                }
            }
            LaunchActionForm { a in
                actions.append(a)
                module.setRingActions(actions)
            }
        }
        .onAppear {
            shortcut = module.shortcut
            actions = module.ringActions
        }
    }

    private func moveAction(_ a: LaunchAction, _ d: Int) {
        guard let i = actions.firstIndex(of: a) else { return }
        let j = i + d
        guard actions.indices.contains(j) else { return }
        actions.swapAt(i, j)
        module.setRingActions(actions)
    }
}

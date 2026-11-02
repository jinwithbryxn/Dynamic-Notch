import AppKit
import ApplicationServices
import SwiftUI

/// 메뉴 막대 아이콘 숨기기 (M-J-020)와 노치 뒤 아이콘 열기 (M-J-021).
/// 숨기기: 화살표와 구분자 두 상태 항목을 두고, 접으면 구분자 길이를 아주 길게 해 그 왼쪽 아이콘을 화면 밖으로 민다(공개 NSStatusItem).
/// 메뉴 막대 내용은 읽지 않는다. '모두 보이기'와 기능 끄기(stop)는 언제나 원래대로 돌린다.
/// 노치 뒤 아이콘: 손쉬운 사용으로 앱별 메뉴 막대 추가 항목(AXExtrasMenuBar)을 읽어 나열하고, 누르면 실제 항목을 누른다.
final class MenuBarIconsModule: NotchModule {
    let id = "menubar"
    var title: String { T("메뉴 막대 아이콘", "Menu Bar Icons") }
    let symbol = "menubar.arrow.up.rectangle"
    /// 메뉴 막대에 항목을 더하므로 기본 꺼짐
    var enabledByDefault: Bool { false }

    struct Extra: Identifiable {
        enum Place { case visible, behindNotch, hidden }
        let id: String
        let app: String
        let title: String
        let frame: CGRect
        let place: Place
        let element: AXUIElement
    }

    final class State: ObservableObject {
        private let d = ModuleDefaults(module: "menubar")
        @Published var collapsed = false
        @Published var autoRehide: Int { didSet { d.set(autoRehide, "autoRehide") } }
        @Published var extras: [Extra] = []
        @Published var scanning = false
        @Published var message: String?
        @Published var axGranted = CPPermission.accessibility.granted
        init() { autoRehide = d.int("autoRehide", default: 10) }
    }

    let state = State()
    private var context: ModuleContext?
    private var chevron: NSStatusItem?
    private var separator: NSStatusItem?
    private var rehideWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    var tabVisible = false

    /// 접었을 때 구분자 길이 (그 왼쪽 아이콘이 화면 밖으로 밀린다)
    private static let collapsedLength: CGFloat = 10_000
    private static let separatorLength: CGFloat = 10

    func start(context: ModuleContext) {
        self.context = context
        guard chevron == nil else { return }
        // 먼저 만든 항목이 오른쪽에 온다: 화살표 → 구분자 순서로 만들어 구분자가 화살표 왼쪽에 오게 한다
        let c = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        c.autosaveName = "dmn.menubar.chevron"
        c.button?.target = self
        c.button?.action = #selector(toggleFromMenuBar)
        c.button?.toolTip = T("메뉴 막대 아이콘 접기·펼치기", "Collapse or expand menu bar icons")
        chevron = c
        let s = NSStatusBar.system.statusItem(withLength: Self.separatorLength)
        s.autosaveName = "dmn.menubar.separator"
        s.button?.image = NSImage(systemSymbolName: "poweron", accessibilityDescription: T("숨김 구분자", "Hide separator"))
        s.button?.imagePosition = .imageOnly
        s.button?.appearsDisabled = true
        s.button?.toolTip = T("⌘를 누른 채 아이콘을 이 선 왼쪽으로 끌면 접을 때 숨겨진다", "⌘-drag icons left of this line to hide them when collapsed")
        separator = s
        state.collapsed = false
        updateChevron()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                if self?.tabVisible == true { self?.scan() }
            })
        }
    }

    func stop() {
        rehideWork?.cancel()
        // 항상 먼저 펼친 뒤 항목을 없앤다
        separator?.length = Self.separatorLength
        if let s = separator { NSStatusBar.system.removeStatusItem(s) }
        if let c = chevron { NSStatusBar.system.removeStatusItem(c) }
        separator = nil
        chevron = nil
        state.collapsed = false
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        context = nil
    }

    func tabView() -> AnyView? { AnyView(MenuBarTab(module: self, state: state)) }
    var tabContentSize: CGSize { CGSize(width: 580, height: 290) }

    func paletteActions() -> [PaletteAction] {
        [
            PaletteAction(id: "menubar.showall", title: T("메뉴 막대 아이콘 모두 보이기", "Show All Menu Bar Icons"), symbol: "eye",
                          keywords: ["menu bar", "메뉴 막대", "아이콘", "show"]) { [weak self] in self?.expand() },
            PaletteAction(id: "menubar.toggle", title: T("메뉴 막대 아이콘 접기·펼치기", "Toggle Menu Bar Icons"), symbol: symbol,
                          keywords: ["menu bar", "메뉴 막대", "hide", "숨기기"]) { [weak self] in self?.toggle() },
        ]
    }

    // MARK: 접기·펼치기

    @objc private func toggleFromMenuBar() { toggle() }

    func toggle() { state.collapsed ? expand() : collapse() }

    func collapse() {
        guard let sepWin = separator?.button?.window, let chevWin = chevron?.button?.window else {
            state.message = T("메뉴 막대 항목을 찾지 못함", "Menu bar items not found")
            return
        }
        // 구분자가 화살표 오른쪽이면 접을 때 화살표까지 사라지므로 접지 않는다
        guard sepWin.frame.minX < chevWin.frame.minX else {
            state.message = T("구분자 '|'가 화살표 오른쪽에 있음. ⌘를 누른 채 구분자를 화살표 왼쪽으로 옮겨 줘.",
                              "The '|' separator is right of the arrow. ⌘-drag it to the left of the arrow.")
            return
        }
        separator?.length = Self.collapsedLength
        state.collapsed = true
        state.message = nil
        updateChevron()
        // 화살표가 화면 밖으로 밀렸으면 바로 되돌린다 (되돌릴 수단을 잃지 않게)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, let w = self.chevron?.button?.window else { return }
            let onScreen = NSScreen.screens.contains { $0.frame.intersects(w.frame) }
            if !onScreen {
                self.expand()
                self.state.message = T("화살표가 가려져서 다시 펼침", "The arrow got hidden, so icons were expanded again")
            }
        }
    }

    func expand() {
        rehideWork?.cancel()
        separator?.length = Self.separatorLength
        state.collapsed = false
        updateChevron()
        scheduleRehide()
    }

    private func scheduleRehide() {
        rehideWork?.cancel()
        guard state.autoRehide > 0, separator != nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.collapse() }
        rehideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(state.autoRehide), execute: work)
    }

    private func updateChevron() {
        let name = state.collapsed ? "chevron.left" : "chevron.right"
        chevron?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: state.collapsed ? T("펼치기", "Expand") : T("접기", "Collapse"))
    }

    // MARK: 노치 뒤 아이콘 (손쉬운 사용)

    func scan() {
        state.axGranted = CPPermission.accessibility.granted
        guard state.axGranted else { state.extras = []; return }
        guard !state.scanning else { return }
        state.scanning = true
        let notch = Self.notchXRange()
        let screensMaxX = NSScreen.screens.map(\.frame.maxX).max() ?? 0
        let apps = NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0.localizedName ?? "?") }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let list = Self.readExtras(apps: apps, notch: notch, screensMaxX: screensMaxX)
            DispatchQueue.main.async {
                self?.state.extras = list
                self?.state.scanning = false
            }
        }
    }

    /// 노치가 있는 화면의 노치 가로 범위 (없으면 nil)
    static func notchXRange() -> ClosedRange<CGFloat>? {
        guard let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea else { return nil }
        return (s.frame.minX + l.width)...(s.frame.maxX - r.width)
    }

    static func readExtras(apps: [(pid_t, String)], notch: ClosedRange<CGFloat>?, screensMaxX: CGFloat) -> [Extra] {
        var out: [Extra] = []
        for (pid, name) in apps {
            let ax = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(ax, 0.2)
            var bar: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ax, "AXExtrasMenuBar" as CFString, &bar) == .success, let barRef = bar else { continue }
            var kids: CFTypeRef?
            guard AXUIElementCopyAttributeValue(barRef as! AXUIElement, kAXChildrenAttribute as CFString, &kids) == .success,
                  let items = kids as? [AXUIElement] else { continue }
            for (i, item) in items.enumerated() {
                let frame = Self.frame(of: item)
                var title = Self.string(item, kAXTitleAttribute) ?? ""
                if title.isEmpty { title = Self.string(item, kAXDescriptionAttribute) ?? "" }
                if title.isEmpty { title = Self.string(item, kAXHelpAttribute) ?? "" }
                let place: Extra.Place
                if frame.maxX <= 0 || frame.minX >= screensMaxX { place = .hidden }
                else if let n = notch, n.contains(frame.midX) { place = .behindNotch }
                else { place = .visible }
                out.append(Extra(id: "\(pid)-\(i)", app: name, title: title, frame: frame, place: place, element: item))
            }
        }
        return out.sorted { $0.frame.minX < $1.frame.minX }
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private static func frame(of el: AXUIElement) -> CGRect {
        var p: CFTypeRef?, s: CFTypeRef?
        var point = CGPoint.zero, size = CGSize.zero
        if AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p) == .success, let pv = p {
            AXValueGetValue(pv as! AXValue, .cgPoint, &point)
        }
        if AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s) == .success, let sv = s {
            AXValueGetValue(sv as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: point, size: size)
    }

    /// 실제 항목을 눌러 그 앱의 메뉴를 연다. 접혀 있으면 먼저 펼친다.
    func open(_ extra: Extra) {
        context?.collapse()
        let wasCollapsed = state.collapsed
        if wasCollapsed { expand() }
        DispatchQueue.main.asyncAfter(deadline: .now() + (wasCollapsed ? 0.45 : 0.25)) { [weak self] in
            let r = AXUIElementPerformAction(extra.element, kAXPressAction as CFString)
            if r != .success {
                self?.state.message = T("항목을 누르지 못함 (\(r.rawValue))", "Could not press the item (\(r.rawValue))")
            }
        }
    }

    func selfTest() -> [String] {
        var lines = [
            "accessibility (no prompt): \(CPPermission.accessibility.granted)",
            "notch x range: \(Self.notchXRange().map { "\(Int($0.lowerBound))–\(Int($0.upperBound))" } ?? "no notch")",
            "status items not created in self test",
        ]
        if CPPermission.accessibility.granted {
            let apps = NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0.localizedName ?? "?") }
            let list = Self.readExtras(apps: apps, notch: Self.notchXRange(), screensMaxX: NSScreen.screens.map(\.frame.maxX).max() ?? 0)
            lines.append("menu bar extras: \(list.count), behind notch: \(list.filter { $0.place == .behindNotch }.count)")
        } else {
            lines.append("menu bar extras: not read (Accessibility not granted)")
        }
        return lines
    }
}

private struct MenuBarTab: View {
    let module: MenuBarIconsModule
    @ObservedObject var state: MenuBarIconsModule.State

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                CPPill(symbol: state.collapsed ? "chevron.left" : "chevron.right",
                       title: state.collapsed ? T("펼치기", "Expand") : T("접기", "Collapse")) { module.toggle() }
                CPPill(symbol: "eye", title: T("모두 보이기", "Show All"), tint: .green) { module.expand() }
                Spacer()
                Text(T("자동으로 다시 접기", "Re-hide after")).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                Picker("", selection: $state.autoRehide) {
                    Text(T("끔", "Off")).tag(0)
                    Text(T("5초", "5 s")).tag(5)
                    Text(T("10초", "10 s")).tag(10)
                    Text(T("30초", "30 s")).tag(30)
                }
                .labelsHidden().frame(width: 80).controlSize(.small)
            }
            Text(T("⌘를 누른 채 아이콘을 구분자 '|' 왼쪽으로 끌면 접을 때 숨겨진다. 끄면 언제나 모두 다시 보인다.",
                   "⌘-drag icons to the left of the '|' separator to hide them when collapsed. Turning this off always shows everything."))
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
            HStack {
                Text(T("모든 메뉴 막대 항목 (노치에 가린 것 포함)", "All menu bar items (including behind the notch)")).font(.system(size: 11, weight: .semibold))
                Spacer()
                CPPill(symbol: "arrow.clockwise", title: T("새로고침", "Refresh"), disabled: !state.axGranted) { module.scan() }
            }
            if state.axGranted {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(state.extras) { e in
                            Button { module.open(e) } label: {
                                HStack(spacing: 6) {
                                    Text(e.app).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                    Text(e.title).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                                    Spacer()
                                    badge(e.place)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(T("눌러서 이 항목의 메뉴 열기", "Click to open this item's menu"))
                        }
                        if state.extras.isEmpty {
                            Text(state.scanning ? T("읽는 중…", "Reading…") : T("항목 없음", "No items"))
                                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
            } else {
                CPPermissionLine(permission: .accessibility, granted: false)
                Text(T("노치 뒤 아이콘 목록은 손쉬운 사용 권한으로 각 앱의 메뉴 막대 항목을 읽는다.",
                       "The list reads each app's menu bar items through Accessibility."))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
            if let m = state.message {
                Text(m).font(.system(size: 10.5)).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { module.tabVisible = true; module.scan() }
        .onDisappear { module.tabVisible = false }
    }

    @ViewBuilder private func badge(_ p: MenuBarIconsModule.Extra.Place) -> some View {
        switch p {
        case .behindNotch: Text(T("노치에 가림", "Behind notch")).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.yellow)
        case .hidden: Text(T("숨김", "Hidden")).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.orange)
        case .visible: Text(T("보임", "Visible")).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4))
        }
    }
}

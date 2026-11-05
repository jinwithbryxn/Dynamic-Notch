import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 창 배치 위치
enum WindowSnapPosition: String, CaseIterable, Identifiable {
    case leftHalf, rightHalf, topHalf, bottomHalf, topLeft, topRight, bottomLeft, bottomRight, full, center
    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftHalf: return T("왼쪽 절반", "Left half")
        case .rightHalf: return T("오른쪽 절반", "Right half")
        case .topHalf: return T("위쪽 절반", "Top half")
        case .bottomHalf: return T("아래쪽 절반", "Bottom half")
        case .topLeft: return T("왼쪽 위 1/4", "Top-left quarter")
        case .topRight: return T("오른쪽 위 1/4", "Top-right quarter")
        case .bottomLeft: return T("왼쪽 아래 1/4", "Bottom-left quarter")
        case .bottomRight: return T("오른쪽 아래 1/4", "Bottom-right quarter")
        case .full: return T("전체", "Full")
        case .center: return T("가운데", "Center")
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        case .topLeft: return "rectangle.inset.topleft.filled"
        case .topRight: return "rectangle.inset.topright.filled"
        case .bottomLeft: return "rectangle.inset.bottomleft.filled"
        case .bottomRight: return "rectangle.inset.bottomright.filled"
        case .full: return "rectangle.fill"
        case .center: return "rectangle.center.inset.filled"
        }
    }

    /// 화면의 보이는 영역(AppKit 좌표) 안에서 목표 사각형. center는 현재 크기를 유지한다.
    func rect(in v: CGRect, current: CGSize) -> CGRect {
        let hw = v.width / 2, hh = v.height / 2
        switch self {
        case .leftHalf: return CGRect(x: v.minX, y: v.minY, width: hw, height: v.height)
        case .rightHalf: return CGRect(x: v.minX + hw, y: v.minY, width: hw, height: v.height)
        case .topHalf: return CGRect(x: v.minX, y: v.minY + hh, width: v.width, height: hh)
        case .bottomHalf: return CGRect(x: v.minX, y: v.minY, width: v.width, height: hh)
        case .topLeft: return CGRect(x: v.minX, y: v.minY + hh, width: hw, height: hh)
        case .topRight: return CGRect(x: v.minX + hw, y: v.minY + hh, width: hw, height: hh)
        case .bottomLeft: return CGRect(x: v.minX, y: v.minY, width: hw, height: hh)
        case .bottomRight: return CGRect(x: v.minX + hw, y: v.minY, width: hw, height: hh)
        case .full: return v
        case .center:
            let w = min(current.width, v.width), h = min(current.height, v.height)
            return CGRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h)
        }
    }
}

/// 손쉬운 사용 API로 앞 앱의 창을 옮긴다.
enum WindowSnapper {
    /// 노치·팔레트가 앞에 있으면 그 전에 쓰던 앱
    static func targetApp() -> NSRunningApplication? {
        let me = ProcessInfo.processInfo.processIdentifier
        if let f = NSWorkspace.shared.frontmostApplication, f.processIdentifier != me { return f }
        return ModuleServices.previousApp
    }

    static func focusedWindow(of app: NSRunningApplication) -> AXUIElement? {
        let el = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXFocusedWindowAttribute as CFString, &ref) == .success, let ref {
            return (ref as! AXUIElement)
        }
        if AXUIElementCopyAttributeValue(el, kAXMainWindowAttribute as CFString, &ref) == .success, let ref {
            return (ref as! AXUIElement)
        }
        return nil
    }

    /// 창 위치·크기 (손쉬운 사용 좌표: 주 화면 왼쪽 위 기준, 아래로 +)
    static func frame(of w: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &s) == .success,
              let p, let s else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    static func setFrame(_ w: AXUIElement, _ r: CGRect) {
        var origin = r.origin, size = r.size
        if let pv = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv) }
        if let sv = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv) }
        // 크기 제한이 있는 앱은 크기를 바꾼 뒤 위치가 밀리므로 한 번 더
        if let pv = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv) }
    }

    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func toAX(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
    static func fromAX(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// 앞 창을 배치한다. 이미 그 자리에 있으면 다음 화면의 같은 자리로 보낸다.
    @discardableResult
    static func snapFrontmost(_ pos: WindowSnapPosition, context: ModuleContext?) -> Bool {
        guard LaunchSystem.axTrusted else {
            context?.notice(T("손쉬운 사용 권한 필요", "Accessibility permission needed"),
                            T("창을 옮기려면 시스템 설정에서 허용", "Allow it in System Settings to move windows"),
                            symbol: "hand.raised", actions: [
                                ActivityAction(id: "ax", title: T("권한 요청", "Request"), role: .primary) { LaunchSystem.requestAX() },
                            ])
            return false
        }
        guard let app = targetApp(), let w = focusedWindow(of: app), let axFrame = frame(of: w) else {
            context?.notice(T("옮길 창이 없음", "No window to move"), nil, symbol: "macwindow")
            return false
        }
        let current = fromAX(axFrame)
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return false }
        let idx = screens.firstIndex { $0.frame.contains(CGPoint(x: current.midX, y: current.midY)) } ?? 0
        var target = pos.rect(in: screens[idx].visibleFrame, current: current.size)
        if screens.count > 1, close(target, current) {
            let next = screens[(idx + 1) % screens.count]
            target = pos.rect(in: next.visibleFrame, current: current.size)
        }
        setFrame(w, toAX(target))
        return true
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 4 && abs(a.minY - b.minY) < 4 && abs(a.width - b.width) < 4 && abs(a.height - b.height) < 4
    }
}

/// 창 스냅: 팔레트·탭 버튼·전역 단축키(⌃⌥⌘←/→/↑/↓/↩)로 앞 창을 반쪽·1/4·전체로 배치한다.
/// 손쉬운 사용 권한이 필요해 기본 꺼짐. 노치로 끌어 놓는 영역은 보류.
final class WindowSnapModule: NotchModule {
    let id = "windowsnap"
    var title: String { T("창 배치", "Window Snap") }
    let symbol = "rectangle.split.2x2"
    var enabledByDefault: Bool { false }

    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }
    fileprivate var context: ModuleContext?
    var keyboardSnap: Bool { defaults.bool("keyboard", default: true) }

    static let hotkeys: [(String, UInt32, WindowSnapPosition)] = [
        ("left", UInt32(kVK_LeftArrow), .leftHalf), ("right", UInt32(kVK_RightArrow), .rightHalf),
        ("up", UInt32(kVK_UpArrow), .topHalf), ("down", UInt32(kVK_DownArrow), .bottomHalf),
        ("full", UInt32(kVK_Return), .full),
    ]
    static let hotkeyMods = UInt32(controlKey | optionKey | cmdKey)

    func start(context: ModuleContext) {
        self.context = context
        registerHotkeys()
    }

    func stop() {
        for (name, _, _) in Self.hotkeys { HotKeyCenter.shared.unregister("windowsnap.\(name)") }
        context = nil
    }

    func settingsChanged() { registerHotkeys() }

    private func registerHotkeys() {
        for (name, key, pos) in Self.hotkeys {
            let hid = "windowsnap.\(name)"
            if keyboardSnap, context != nil {
                HotKeyCenter.shared.register(hid, HotKeyCenter.Shortcut(keyCode: key, modifiers: Self.hotkeyMods)) { [weak self] in
                    WindowSnapper.snapFrontmost(pos, context: self?.context)
                }
            } else {
                HotKeyCenter.shared.unregister(hid)
            }
        }
    }

    func tabView() -> AnyView? { AnyView(WindowSnapTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 420, height: 170) }

    func paletteActions() -> [PaletteAction] {
        WindowSnapPosition.allCases.map { pos in
            PaletteAction(id: "windowsnap.\(pos.rawValue)", title: T("창: ", "Window: ") + pos.title, symbol: pos.symbol,
                          keywords: ["snap", "window", "창", "배치", "스냅"]) { [weak self] in
                // 팔레트가 닫히고 이전 앱이 앞으로 온 뒤 옮긴다
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { WindowSnapper.snapFrontmost(pos, context: self?.context) }
            }
        }
    }

    func settingsView() -> AnyView? { AnyView(WindowSnapSettings(module: self)) }

    func selfTest() -> [String] {
        var out = ["accessibility trusted: \(LaunchSystem.axTrusted)"]
        for (i, s) in NSScreen.screens.enumerated() {
            let v = s.visibleFrame
            out.append("screen \(i): visible \(Int(v.minX)),\(Int(v.minY)) \(Int(v.width))x\(Int(v.height))")
            let l = WindowSnapPosition.leftHalf.rect(in: v, current: .zero)
            let q = WindowSnapPosition.bottomRight.rect(in: v, current: .zero)
            out.append("  left half -> AX \(WindowSnapper.toAX(l).integral), bottom-right -> AX \(WindowSnapper.toAX(q).integral)")
        }
        let r = CGRect(x: 10, y: 20, width: 300, height: 200)
        out.append("AX round trip: \(WindowSnapper.fromAX(WindowSnapper.toAX(r)) == r ? "ok" : "FAIL")")
        if LaunchSystem.axTrusted, let app = WindowSnapper.targetApp(), let w = WindowSnapper.focusedWindow(of: app) {
            out.append("front window (read only): \(app.localizedName ?? "?") \(WindowSnapper.frame(of: w).map { "\($0.integral)" } ?? "no frame")")
        }
        out.append("hotkeys: ⌃⌥⌘ ← → ↑ ↓ ↩ (registered only while the module runs; not registered in self test)")
        return out
    }
}

private struct WindowSnapTab: View {
    let module: WindowSnapModule
    @State private var trusted = LaunchSystem.axTrusted
    private let grid: [[WindowSnapPosition]] = [
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf, .full],
        [.topLeft, .topRight, .bottomLeft, .bottomRight, .center],
    ]

    var body: some View {
        VStack(spacing: 8) {
            if !trusted {
                LaunchUnsupportedView(title: T("손쉬운 사용 권한 필요", "Accessibility permission needed"),
                                      reason: T("다른 앱의 창을 옮기려면 macOS 손쉬운 사용 권한이 있어야 함", "Moving other apps' windows needs macOS Accessibility access"),
                                      alternative: T("허용 뒤 이 탭을 다시 열기", "Reopen this tab after allowing it"),
                                      symbol: "hand.raised", buttonTitle: T("권한 요청", "Request access")) {
                    LaunchSystem.requestAX()
                }
            } else {
                Text(T("앞에 있던 창: ", "Target window: ") + (WindowSnapper.targetApp()?.localizedName ?? T("없음", "none")))
                    .font(.island(.footnote)).foregroundStyle(LaunchUI.secondary)
                ForEach(grid.indices, id: \.self) { r in
                    HStack(spacing: 8) {
                        ForEach(grid[r]) { pos in
                            Button { WindowSnapper.snapFrontmost(pos, context: module.context) } label: {
                                Image(systemName: pos.symbol).font(.island(.title2))
                                    .frame(width: 64, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(LaunchUI.fill))
                            }
                            .buttonStyle(.plain).help(pos.title).accessibilityLabel(pos.title)
                        }
                    }
                }
                Text(module.keyboardSnap ? T("단축키 ⌃⌥⌘ ←/→/↑/↓/↩ · 같은 자리면 다음 화면", "Shortcuts ⌃⌥⌘ ←/→/↑/↓/↩ · repeat moves to next display")
                                         : T("키보드 배치 꺼짐", "Keyboard snapping off"))
                    .font(.island(.caption)).foregroundStyle(LaunchUI.secondary)
            }
        }
        .foregroundStyle(.white)
        .onAppear { trusted = LaunchSystem.axTrusted }
    }
}

private struct WindowSnapSettings: View {
    let module: WindowSnapModule
    @State private var keyboard = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(T("키보드로 배치 (⌃⌥⌘ ←/→/↑/↓/↩)", "Snap with the keyboard (⌃⌥⌘ ←/→/↑/↓/↩)"), isOn: $keyboard)
                .onChange(of: keyboard) { _, v in ModuleDefaults(module: module.id).set(v, "keyboard") }
            Text(T("손쉬운 사용 권한이 필요합니다. 창을 노치로 끌어 놓는 배치 영역은 아직 지원하지 않습니다 (전역 드래그 감시가 필요해 보류).",
                   "Needs Accessibility access. Drag-to-notch zones are not supported yet (deferred: needs a global drag monitor)."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { keyboard = module.keyboardSnap }
    }
}

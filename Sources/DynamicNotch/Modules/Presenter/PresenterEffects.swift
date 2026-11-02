import AppKit
import Carbon.HIToolbox
import QuartzCore
import SwiftUI

// MARK: - 키 입력 듣기 (듣기 전용 이벤트 탭, 입력 모니터링 권한)

/// 키 입력을 지연시키지 않는 듣기 전용 탭. 비밀번호 칸(보안 입력) 중에는 macOS가 이벤트를 주지 않는다.
final class CPKeystrokeTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var onKey: ((CGEvent) -> Void)?

    var isRunning: Bool { tap != nil }

    /// 권한이 없거나 탭을 만들지 못하면 false
    func start() -> Bool {
        guard tap == nil else { return true }
        guard CGPreflightListenEventAccess() else { return false }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<CPKeystrokeTap>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
            } else if type == .keyDown {
                me.onKey?(event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                        eventsOfInterest: mask, callback: callback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        let src = CFMachPortCreateRunLoopSource(nil, t, 0)
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    func stop() {
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            CFMachPortInvalidate(t)
        }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
    }

    deinit { stop() }

    // MARK: 표시 글자

    static let special: [Int64: String] = [
        36: "↩", 76: "⌤", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "esc",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// 현재 ASCII 자판에서 이 글쇠의 글자 (수정키 없이)
    static func asciiCharacter(_ code: UInt16) -> String? {
        guard let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
            return status == noErr && length > 0 ? String(utf16CodeUnits: chars, count: length) : nil
        }
    }

    /// "⌃⌥⇧⌘K" 같은 표시. combosOnly면 ⌘·⌃·⌥가 없는 일반 글자는 nil (입력한 글이 보이지 않게).
    static func label(for event: CGEvent, combosOnly: Bool) -> String? {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        var mods = ""
        if flags.contains(.maskControl) { mods += "⌃" }
        if flags.contains(.maskAlternate) { mods += "⌥" }
        if flags.contains(.maskShift) { mods += "⇧" }
        if flags.contains(.maskCommand) { mods += "⌘" }
        let hasCombo = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
        let key: String
        if let s = special[code] {
            key = s
        } else {
            // 한글 자판이어도 단축키는 영문 글쇠 이름으로 (ASCII 자판 기준)
            let chars = asciiCharacter(UInt16(code)) ?? NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? ""
            guard let c = chars.first, !c.isWhitespace, c.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
            key = String(c).uppercased()
        }
        if combosOnly && !hasCombo && special[code] == nil { return nil }
        return mods + key
    }
}

/// 화면 아래 가운데 키캡 표시 (녹화에 보이도록 캡처 숨김을 쓰지 않는다)
final class CPKeystrokeHUD: ObservableObject {
    struct Entry: Identifiable, Equatable { let id = UUID(); let text: String }
    @Published var entries: [Entry] = []
    private var panel: CPOverlayPanel?

    func show(_ text: String) {
        let e = Entry(text: text)
        entries.append(e)
        if entries.count > 4 { entries.removeFirst(entries.count - 4) }
        ensurePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.entries.removeAll { $0.id == e.id } }
            if self.entries.isEmpty { self.panel?.orderOut(nil) }
        }
    }

    private func ensurePanel() {
        guard let screen = NSScreen.cpUnderMouse else { return }
        let size = CGSize(width: 640, height: 90)
        let frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 90, width: size.width, height: size.height)
        if panel == nil {
            let p = CPOverlayPanel(frame: frame, level: CPLevel.overlay, clickThrough: true, hideFromCapture: false)
            p.contentView = NSHostingView(rootView: CPKeystrokeHUDView(hud: self))
            panel = p
        }
        panel?.setFrame(frame, display: false)
        panel?.orderFrontRegardless()
    }

    func close() {
        entries.removeAll()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}

struct CPKeystrokeHUDView: View {
    @ObservedObject var hud: CPKeystrokeHUD
    var body: some View {
        HStack(spacing: 10) {
            ForEach(hud.entries) { e in
                Text(e.text)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: hud.entries)
    }
}

// MARK: - 커서 강조 (클릭 물결·후광·스포트라이트)

/// 화면마다 클릭이 통과하는 오버레이를 두고 그 위에 레이어를 그린다.
/// 클릭·이동은 권한이 필요 없는 마우스 감시로, 스포트라이트(⌃⌥ 누르는 동안)는 수정키 감시라 손쉬운 사용 권한이 필요하다.
final class CPCursorEffects {
    private(set) var ripples = false, halo = false, spotlight = false
    private var overlays: [(panel: CPOverlayPanel, view: CursorLayerView)] = []
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var spotlightWork: DispatchWorkItem?
    private var spotlightOn = false

    var isActive: Bool { ripples || halo || spotlight }

    func update(ripples: Bool, halo: Bool, spotlight: Bool) {
        let wasActive = isActive
        self.ripples = ripples
        self.halo = halo
        self.spotlight = spotlight
        if isActive && !wasActive { install() }
        if !isActive && wasActive { uninstall(); return }
        guard isActive else { return }
        reinstallMonitors()
        overlays.forEach { $0.view.setHalo(halo) }
        if !spotlight { setSpotlight(false) }
        move()
    }

    func stop() { update(ripples: false, halo: false, spotlight: false) }

    private func install() {
        buildOverlays()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.buildOverlays()
        }
        reinstallMonitors()
    }

    private func uninstall() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        if let o = screenObserver { NotificationCenter.default.removeObserver(o) }
        screenObserver = nil
        spotlightWork?.cancel()
        spotlightOn = false
        overlays.forEach { $0.panel.orderOut(nil); $0.panel.close() }
        overlays.removeAll()
    }

    private func buildOverlays() {
        overlays.forEach { $0.panel.orderOut(nil); $0.panel.close() }
        overlays = NSScreen.screens.map { screen in
            let p = CPOverlayPanel(frame: screen.frame, level: CPLevel.overlay, clickThrough: true, hideFromCapture: false)
            let v = CursorLayerView(frame: CGRect(origin: .zero, size: screen.frame.size))
            p.contentView = v
            p.orderFrontRegardless()
            v.setHalo(halo)
            return (p, v)
        }
    }

    private func reinstallMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        var mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                           .leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]
        if spotlight { mask.insert(.flagsChanged) }
        let handler: (NSEvent) -> Void = { [weak self] e in self?.handle(e) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { e in handler(e); return e }) { monitors.append(l) }
    }

    private func handle(_ e: NSEvent) {
        switch e.type {
        case .leftMouseDown, .rightMouseDown:
            if ripples { ripple(right: e.type == .rightMouseDown) }
            if halo { overlays.forEach { $0.view.pressHalo(true) } }
        case .leftMouseUp, .rightMouseUp:
            if halo { overlays.forEach { $0.view.pressHalo(false) } }
        case .flagsChanged:
            let f = e.modifierFlags.intersection([.control, .option, .command, .shift])
            spotlightWork?.cancel()
            if f == [.control, .option] {
                // 짧게 눌렀다 떼는 일반 단축키와 구분하려고 잠깐 기다린다
                let work = DispatchWorkItem { [weak self] in self?.setSpotlight(true) }
                spotlightWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            } else {
                setSpotlight(false)
            }
        default:
            break
        }
        move()
    }

    private func move() {
        let p = NSEvent.mouseLocation
        for o in overlays {
            let local = CGPoint(x: p.x - o.panel.frame.minX, y: p.y - o.panel.frame.minY)
            let inside = o.panel.frame.contains(p)
            o.view.move(to: local, visible: inside)
        }
    }

    private func ripple(right: Bool) {
        let p = NSEvent.mouseLocation
        for o in overlays where o.panel.frame.contains(p) {
            o.view.ripple(at: CGPoint(x: p.x - o.panel.frame.minX, y: p.y - o.panel.frame.minY), double: right)
        }
    }

    private func setSpotlight(_ on: Bool) {
        guard on != spotlightOn else { return }
        spotlightOn = on
        overlays.forEach { $0.view.setSpotlight(on) }
        move()
    }
}

private final class CursorLayerView: NSView {
    private let haloLayer = CAShapeLayer()
    private let spotLayer = CAShapeLayer()
    private var point = CGPoint.zero
    private var spotOn = false
    private let haloRadius: CGFloat = 26
    private let spotRadius: CGFloat = 120
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        spotLayer.fillRule = .evenOdd
        spotLayer.fillColor = NSColor.black.withAlphaComponent(0.55).cgColor
        spotLayer.isHidden = true
        layer?.addSublayer(spotLayer)
        haloLayer.path = CGPath(ellipseIn: CGRect(x: -haloRadius, y: -haloRadius, width: haloRadius * 2, height: haloRadius * 2), transform: nil)
        haloLayer.fillColor = NSColor.systemYellow.withAlphaComponent(0.25).cgColor
        haloLayer.strokeColor = NSColor.systemYellow.withAlphaComponent(0.7).cgColor
        haloLayer.lineWidth = 2
        haloLayer.isHidden = true
        layer?.addSublayer(haloLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var haloEnabled = false
    func setHalo(_ on: Bool) { haloEnabled = on; haloLayer.isHidden = !on }

    func move(to p: CGPoint, visible: Bool) {
        point = p
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        haloLayer.position = p
        haloLayer.isHidden = !(haloEnabled && visible)
        if spotOn { updateSpot() }
        CATransaction.commit()
    }

    func pressHalo(_ down: Bool) {
        haloLayer.setAffineTransform(down ? CGAffineTransform(scaleX: 0.75, y: 0.75) : .identity)
    }

    func setSpotlight(_ on: Bool) {
        spotOn = on
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spotLayer.isHidden = !on
        if on { updateSpot() }
        CATransaction.commit()
    }

    private func updateSpot() {
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addEllipse(in: CGRect(x: point.x - spotRadius, y: point.y - spotRadius, width: spotRadius * 2, height: spotRadius * 2))
        spotLayer.path = path
    }

    func ripple(at p: CGPoint, double: Bool) {
        for i in 0..<(double ? 2 : 1) {
            let ring = CAShapeLayer()
            let r: CGFloat = 24
            ring.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
            ring.fillColor = NSColor.clear.cgColor
            ring.strokeColor = (double ? NSColor.systemBlue : NSColor.systemYellow).withAlphaComponent(0.9).cgColor
            ring.lineWidth = 3
            ring.position = p
            ring.opacity = 0
            layer?.addSublayer(ring)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.9
            fade.toValue = 0
            let group = CAAnimationGroup()
            if reduceMotion {
                group.animations = [fade]
            } else {
                let grow = CABasicAnimation(keyPath: "transform.scale")
                grow.fromValue = 0.3
                grow.toValue = 1.6
                group.animations = [grow, fade]
            }
            group.duration = 0.5
            group.beginTime = CACurrentMediaTime() + Double(i) * 0.12
            group.fillMode = .backwards
            group.isRemovedOnCompletion = true
            ring.add(group, forKey: "ripple")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.12 + 0.05) { ring.removeFromSuperlayer() }
        }
    }
}

// MARK: - 멈춘 포인터 숨기기 (비공개 CGS 연결 속성)

/// 백그라운드 앱이 커서를 숨기려면 비공개 연결 속성 "SetsCursorInBackground"가 필요하다.
/// 함수가 없으면 지원 안 됨. 숨긴 채 앱이 끝나도 WindowServer가 연결을 정리하며 커서가 돌아온다.
final class CPIdleCursorHider {
    private typealias ConnFn = @convention(c) () -> Int32
    private typealias SetPropFn = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    private static let connection: ConnFn? = {
        for name in ["_CGSDefaultConnection", "CGSMainConnectionID", "SLSMainConnectionID"] {
            if let s = CPPrivate.symbol(name, in: [CPPrivate.coreGraphics, CPPrivate.skyLight]) { return unsafeBitCast(s, to: ConnFn.self) }
        }
        return nil
    }()

    private static let setProperty: SetPropFn? = {
        for name in ["CGSSetConnectionProperty", "SLSSetConnectionProperty"] {
            if let s = CPPrivate.symbol(name, in: [CPPrivate.coreGraphics, CPPrivate.skyLight]) { return unsafeBitCast(s, to: SetPropFn.self) }
        }
        return nil
    }()

    static var available: Bool { connection != nil && setProperty != nil }

    private(set) var hidden = false
    private var propertySet = false
    private var timer: Timer?
    private var monitors: [Any] = []
    var idleSeconds: Double = 3

    var isRunning: Bool { timer != nil }

    func start() -> Bool {
        guard timer == nil else { return true }
        guard let conn = Self.connection, let set = Self.setProperty else { return false }
        let c = conn()
        _ = set(c, c, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        propertySet = true
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel, .leftMouseDown, .rightMouseDown]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in self?.reveal() }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.reveal(); return e }) { monitors.append(l) }
        return true
    }

    func stop() {
        reveal()
        timer?.invalidate()
        timer = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        if propertySet, let conn = Self.connection, let set = Self.setProperty {
            let c = conn()
            _ = set(c, c, "SetsCursorInBackground" as CFString, kCFBooleanFalse)
            propertySet = false
        }
    }

    private func tick() {
        guard !hidden else { return }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .scrollWheel, .leftMouseDown]
        let idle = types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
        if idle >= idleSeconds {
            CGDisplayHideCursor(CGMainDisplayID())
            hidden = true
        }
    }

    private func reveal() {
        guard hidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        hidden = false
    }

    deinit { stop() }
}

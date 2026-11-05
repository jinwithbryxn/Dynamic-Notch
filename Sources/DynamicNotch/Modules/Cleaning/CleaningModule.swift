import AppKit
import ApplicationServices
import SwiftUI

/// 청소 모드 (M-G-015 키보드 청소 잠금, M-G-016 화면 청소, M-G-017 비상·자동 해제).
/// 키보드 잠금은 손쉬운 사용 권한의 능동 이벤트 탭으로 키를 버린다. 탭은 전용 스레드에서 돌고
/// 같은 스레드의 타이머로 자동 해제되므로 본 앱이 멈춰도 정해진 시간이 지나면 풀린다.
final class CleaningModule: NotchModule {
    let id = "cleaning"
    var title: String { T("청소 모드", "Cleaning") }
    let symbol = "sparkles"
    /// 손쉬운 사용 권한·능동 이벤트 탭·전체 화면 창을 쓰므로 기본 꺼짐
    var enabledByDefault: Bool { false }

    final class State: ObservableObject {
        @Published var lockedUntil: Date?
        @Published var screenOn = false
        @Published var axGranted = CPPermission.accessibility.granted
        @Published var message: String?
        @Published var seconds: Int { didSet { ModuleDefaults(module: "cleaning").set(seconds, "seconds") } }
        init() { seconds = ModuleDefaults(module: "cleaning").int("seconds", default: 60) }
    }

    let state = State()
    private var context: ModuleContext?
    private let keyboard = CPKeyboardLock()
    private let screen = CPCleaningScreen()
    private var tick: Timer?

    func start(context: ModuleContext) {
        self.context = context
        keyboard.onUnlock = { [weak self] reason in self?.unlocked(reason) }
        screen.onExit = { [weak self] in self?.state.screenOn = false }
    }

    func stop() {
        // 어떤 상태에서도 키보드와 화면을 돌려준다
        keyboard.unlock()
        screen.close()
        tick?.invalidate()
        tick = nil
        context?.center.removePersistent(.cleaning)
        state.lockedUntil = nil
        state.screenOn = false
        keyboard.onUnlock = nil
        screen.onExit = nil
        context = nil
    }

    func tabView() -> AnyView? { AnyView(CleaningTab(module: self, state: state)) }
    var tabContentSize: CGSize { CGSize(width: 500, height: 190) }

    func paletteActions() -> [PaletteAction] {
        [
            PaletteAction(id: "cleaning.keyboard", title: T("키보드 청소 잠금", "Lock Keyboard for Cleaning"),
                          subtitle: T("\(state.seconds)초 · ⌘Esc로 해제", "\(state.seconds) s · ⌘Esc to unlock"), symbol: "keyboard",
                          keywords: ["clean", "청소", "keyboard", "키보드", "잠금"]) { [weak self] in self?.lockKeyboard() },
            PaletteAction(id: "cleaning.screen", title: T("화면 청소 (검은 화면)", "Clean Screen (Black)"), symbol: "display",
                          keywords: ["clean", "청소", "screen", "화면"]) { [weak self] in self?.cleanScreen() },
        ]
    }

    // MARK: 키보드

    func lockKeyboard() {
        state.axGranted = CPPermission.accessibility.granted
        guard state.axGranted else {
            CPPermission.accessibility.request()
            state.message = T("손쉬운 사용 권한이 필요함. 허용한 뒤 다시 눌러 줘.", "Accessibility permission is needed. Allow it, then try again.")
            return
        }
        guard state.lockedUntil == nil else { return }
        context?.collapse()
        // 누른 클릭의 키가 아니라 이미 눌린 키의 떼기가 버려지지 않게 잠깐 뒤에 건다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let secs = TimeInterval(self.state.seconds)
            guard self.keyboard.lock(seconds: secs) else {
                self.state.message = T("이벤트 탭을 만들지 못함 (권한을 다시 확인)", "Could not create the event tap (check the permission)")
                return
            }
            self.state.message = nil
            self.state.lockedUntil = Date().addingTimeInterval(secs)
            self.startTick()
        }
    }

    func unlockKeyboard() { keyboard.unlock() }

    private func startTick() {
        tick?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.updateActivity() }
        RunLoop.main.add(t, forMode: .common)
        tick = t
        updateActivity()
    }

    private func updateActivity() {
        guard let until = state.lockedUntil else { return }
        let left = max(0, Int(until.timeIntervalSinceNow.rounded()))
        context?.center.setPersistent(NotchActivity(
            kind: .cleaning, priority: ActivityPriority.info, symbol: "keyboard", tint: .orange,
            value: .text(String(format: "%d:%02d", left / 60, left % 60)),
            title: T("키보드 청소 잠금 · ⌘Esc로 해제", "Keyboard locked · ⌘Esc to unlock"),
            wing: NotchActivity.compactWing, moduleTab: id))
    }

    private func unlocked(_ reason: CPKeyboardLock.Reason) {
        tick?.invalidate()
        tick = nil
        state.lockedUntil = nil
        context?.center.removePersistent(.cleaning)
        CPSounds.play(.cleaningDone)
        let why: String
        switch reason {
        case .timeout: why = T("시간이 지나 풀림", "Time is up")
        case .escape: why = T("⌘Esc로 풀림", "Unlocked with ⌘Esc")
        case .manual: why = T("풀림", "Unlocked")
        }
        context?.notice(T("키보드 잠금 해제", "Keyboard unlocked"), why, symbol: "keyboard", tint: .green, tab: id, duration: 2)
    }

    // MARK: 화면

    func cleanScreen() {
        context?.collapse()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.screen.show()
            self?.state.screenOn = true
        }
    }

    func selfTest() -> [String] {
        [
            "accessibility (no prompt): \(CPPermission.accessibility.granted)",
            "keyboard locked now: \(keyboard.isLocked)",
            "screens for cleaning windows: \(NSScreen.screens.count)",
            "duration: \(state.seconds) s",
            "event tap not created in self test",
        ] + (CPTestImages.renderView(CleaningScreenView(model: CPCleaningScreen(), exit: {}), size: CGSize(width: 900, height: 560),
                                     name: "cleaning-screen.png").map { ["wrote \($0)"] } ?? [])
    }
}

/// 키보드 잠금 (능동 이벤트 탭, 전용 스레드).
/// 버리는 것: 키 누름·뗌, 수정키, 상단 미디어·볼륨 키. 마우스·트랙패드는 그대로.
/// 풀리는 경우: ⌘Esc, 시간 만료(탭 스레드 타이머), unlock()/stop(). 앱이 끝나면 macOS가 탭을 함께 없앤다.
final class CPKeyboardLock {
    enum Reason { case timeout, escape, manual }

    private let guardLock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    var onUnlock: ((Reason) -> Void)?

    var isLocked: Bool { guardLock.lock(); defer { guardLock.unlock() }; return tap != nil }

    /// NX_SYSDEFINED (미디어·볼륨 키가 오는 이벤트 종류)
    private static let systemDefined: UInt32 = 14

    func lock(seconds: TimeInterval) -> Bool {
        guard AXIsProcessTrusted(), !isLocked else { return isLocked }
        var mask: CGEventMask = 0
        for t in [CGEventType.keyDown, .keyUp, .flagsChanged] { mask |= CGEventMask(1) << CGEventMask(t.rawValue) }
        mask |= CGEventMask(1) << CGEventMask(Self.systemDefined)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<CPKeyboardLock>.fromOpaque(refcon).takeUnretainedValue()
            return me.handle(type, event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: callback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guardLock.lock()
        tap = t
        guardLock.unlock()
        let ready = DispatchSemaphore(value: 0)
        let th = Thread { [weak self] in
            guard let self else { ready.signal(); return }
            let rl = CFRunLoopGetCurrent()
            let src = CFMachPortCreateRunLoopSource(nil, t, 0)
            CFRunLoopAddSource(rl, src, .commonModes)
            // 자동 해제 타이머도 같은 스레드에서: 본 앱이 멈춰도 동작한다
            let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + seconds, 0, 0, 0) { [weak self] _ in
                self?.release(.timeout)
            }
            CFRunLoopAddTimer(rl, timer, .commonModes)
            self.guardLock.lock()
            self.runLoop = rl
            self.guardLock.unlock()
            CGEvent.tapEnable(tap: t, enable: true)
            ready.signal()
            CFRunLoopRun()
            CFRunLoopTimerInvalidate(timer)
            CFRunLoopRemoveSource(rl, src, .commonModes)
        }
        th.name = "cleaning-keyboard-lock"
        th.qualityOfService = .userInteractive
        thread = th
        th.start()
        _ = ready.wait(timeout: .now() + 2)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 잠금 중이면 다시 켠다 (자동 해제 타이머는 계속 돈다)
            guardLock.lock()
            let t = tap
            guardLock.unlock()
            if let t { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventKeycode) == 53, event.flags.contains(.maskCommand) {
                release(.escape)
            }
            return nil
        case .keyUp, .flagsChanged:
            return nil
        default:
            if type.rawValue == Self.systemDefined {
                // 보조 버튼(미디어·볼륨, subtype 8)만 버린다. 다른 시스템 이벤트는 통과
                let subtype = NSEvent(cgEvent: event)?.subtype.rawValue ?? 0
                return subtype == 8 ? nil : Unmanaged.passUnretained(event)
            }
            return Unmanaged.passUnretained(event)
        }
    }

    func unlock() { release(.manual) }

    private func release(_ reason: Reason) {
        guardLock.lock()
        guard let t = tap else { guardLock.unlock(); return }
        tap = nil
        let rl = runLoop
        runLoop = nil
        guardLock.unlock()
        CGEvent.tapEnable(tap: t, enable: false)
        CFMachPortInvalidate(t)
        if let rl { CFRunLoopStop(rl) }
        DispatchQueue.main.async { [weak self] in self?.onUnlock?(reason) }
    }

    deinit {
        // 해제 중에는 약한 참조를 만들지 않고 탭만 정리한다
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            CFMachPortInvalidate(t)
        }
        if let rl = runLoop { CFRunLoopStop(rl) }
    }
}

/// 화면 청소: 모든 화면에 검은 창. 아무 곳이나 1.5초 누르거나 Esc를 1.5초 누르면 끝난다. 3분 뒤 자동으로 끝난다.
final class CPCleaningScreen: ObservableObject {
    private var windows: [CPOverlayPanel] = []
    private var keyMonitor: Any?
    private var escWork: DispatchWorkItem?
    private var autoWork: DispatchWorkItem?
    var onExit: (() -> Void)?
    @Published var holding = false

    var isShowing: Bool { !windows.isEmpty }

    func show() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let w = CPOverlayPanel(frame: screen.frame, level: CPLevel.overlay, clickThrough: false, hideFromCapture: false)
            w.allowsKey = true
            w.isOpaque = true
            w.backgroundColor = .black
            w.contentView = CPHostingView(rootView: CleaningScreenView(model: self) { [weak self] in self?.close() })
            w.orderFrontRegardless()
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 53 {
                if e.type == .keyDown, !e.isARepeat { self.beginEscHold() }
                if e.type == .keyUp { self.cancelEscHold() }
            }
            return nil   // 청소 중 키는 이 창에서 버린다 (시스템 단축키는 macOS가 처리)
        }
        let auto = DispatchWorkItem { [weak self] in self?.close() }
        autoWork = auto
        DispatchQueue.main.asyncAfter(deadline: .now() + 180, execute: auto)
    }

    private func beginEscHold() {
        holding = true
        let work = DispatchWorkItem { [weak self] in self?.close() }
        escWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func cancelEscHold() {
        holding = false
        escWork?.cancel()
    }

    func close() {
        guard !windows.isEmpty else { return }
        escWork?.cancel()
        autoWork?.cancel()
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows.removeAll()
        holding = false
        onExit?()
    }
}

private struct CleaningScreenView: View {
    @ObservedObject var model: CPCleaningScreen
    let exit: () -> Void
    @State private var pressing = false
    @State private var showHint = true

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 4)
                    Circle().trim(from: 0, to: pressing || model.holding ? 1 : 0)
                        .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(pressing || model.holding ? .linear(duration: 1.5) : .easeOut(duration: 0.2), value: pressing || model.holding)
                }
                .frame(width: 44, height: 44)
                Text(T("화면 청소 중 · 아무 곳이나 1.5초 누르거나 Esc를 길게 눌러 끝내기",
                       "Cleaning · press and hold anywhere or hold Esc for 1.5 s to exit"))
                    .font(.island(.subhead)).foregroundStyle(.white.opacity(0.45))
            }
            .opacity(showHint || pressing || model.holding ? 1 : 0.15)
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 1.5, maximumDistance: 10_000, perform: exit, onPressingChanged: { pressing = $0 })
        .onAppear {
            // 얼룩이 잘 보이게 안내 글자는 몇 초 뒤 흐리게
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation(.easeOut(duration: 0.6)) { showHint = false } }
        }
    }
}

private struct CleaningTab: View {
    let module: CleaningModule
    @ObservedObject var state: CleaningModule.State

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let until = state.lockedUntil {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let left = max(0, Int(until.timeIntervalSince(ctx.date).rounded()))
                        VStack(spacing: 4) {
                            Text(String(format: "%d:%02d", left / 60, left % 60))
                                .font(.island(.largeTitle, .semibold, design: .rounded)).monospacedDigit()
                            Text(T("키보드 잠김 · ⌘Esc로 해제", "Keyboard locked · ⌘Esc to unlock")).font(.island(.caption))
                                .foregroundStyle(.white.opacity(0.6))
                            CPPill(symbol: "lock.open.fill", title: T("지금 풀기", "Unlock Now"), tint: .green) { module.unlockKeyboard() }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                } else {
                    CPTile(symbol: "keyboard", title: T("키보드 잠그기 (\(state.seconds)초)", "Lock Keyboard (\(state.seconds) s)"), tint: .orange,
                           help: T("글자·수정키·미디어·볼륨 키를 무시한다. 마우스·트랙패드는 동작", "Ignores letters, modifiers, media and volume keys. Mouse and trackpad keep working")) {
                        module.lockKeyboard()
                    }
                }
                CPTile(symbol: "display", title: T("화면 청소", "Clean Screen"),
                       help: T("모든 화면을 검게. 길게 눌러 끝내기", "Black on all screens. Press and hold to exit"), disabled: state.screenOn) { module.cleanScreen() }
            }
            HStack(spacing: 8) {
                Text(T("잠금 시간", "Lock for")).font(.island(.footnote)).foregroundStyle(.white.opacity(0.6))
                Picker("", selection: $state.seconds) {
                    Text(T("30초", "30 s")).tag(30)
                    Text(T("60초", "60 s")).tag(60)
                    Text(T("2분", "2 min")).tag(120)
                }
                .pickerStyle(.segmented).frame(width: 180).labelsHidden()
                Spacer()
            }
            CPPermissionLine(permission: .accessibility, granted: state.axGranted)
            Text(T("⌘Esc 또는 시간이 지나면 풀린다. 잠금은 별도 스레드에서 돌아 앱이 멈춰도 시간이 되면 풀리고, 앱이 끝나면 macOS가 잠금을 함께 없앤다. 비밀번호 칸에 입력 중일 때(보안 입력)는 macOS가 키를 막지 못하게 한다.",
                   "Unlocks with ⌘Esc or when time is up. The lock runs on its own thread, so it ends on time even if the app stalls, and macOS removes it if the app quits. While a password field has focus (secure input), macOS does not let keys be blocked."))
                .font(.island(.caption)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            if let m = state.message {
                Text(m).font(.island(.caption)).foregroundStyle(.orange)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { state.axGranted = CPPermission.accessibility.granted }
    }
}

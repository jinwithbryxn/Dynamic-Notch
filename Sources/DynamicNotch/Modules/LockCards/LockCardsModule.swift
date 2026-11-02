import AppKit
import EventKit
import Intents
import SwiftUI

/// 잠금 화면 카드 창: 키 창·주 창이 되지 않고 클릭을 받지 않는다 (암호 칸 입력 방해 없음).
final class LCPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func make() -> LCPanel {
        let p = LCPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isFloatingPanel = true
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return p
    }
}

/// 잠금 화면에 시계·날씨·배터리·주변기기·타이머·다음 일정·미리 알림·집중 모드 카드를 띄운다.
/// - 잠금 화면 위에 올리는 방법은 본 앱의 SkyLight 래퍼(비공개, dlsym)를 그대로 쓴다. 없으면 표시하지 않는다.
/// - 잠금 중에만 창과 값 갱신이 있고, 풀리면 바로 창을 치우고 내용을 놓는다.
/// - 카드는 화면 왼쪽·오른쪽 가장자리에만 놓고 로그인 영역·큰 시계·메뉴 막대·음악 카드 자리는 피한다 (LCLayout).
final class LockCardsModule: NotchModule {
    let id = "lockcards"
    var title: String { T("잠금 화면 카드", "Lock Screen Cards") }
    let symbol = "lock.rectangle.stack"
    let enabledByDefault = false

    let data = LCDataModel()
    let status = LCStatus()
    private(set) var context: ModuleContext?
    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }
    private var panel: LCPanel?
    private var tokens: [NSObjectProtocol] = []
    private var refreshTimer: Timer?
    private var showWork: DispatchWorkItem?
    private var previewWork: DispatchWorkItem?
    private var locked = false
    private var started = false

    // MARK: 설정

    var onLockScreen: Bool { defaults.bool("onLockScreen", default: false) }
    var placement: LCPlacement { LCPlacement(rawValue: defaults.string("placement", default: "leftMiddle")) ?? .leftMiddle }
    var style: LCStyle { LCStyle(rawValue: defaults.string("style", default: "cards")) ?? .cards }
    var showTitles: Bool { defaults.bool("showTitles", default: false) }
    var cards: [LCCard] {
        let on = Set(defaults.strings("cards", default: LCCard.defaults.map(\.rawValue)))
        return LCCard.allCases.filter { on.contains($0.rawValue) }
    }

    // MARK: 시작·정지

    func start(context: ModuleContext) {
        self.context = context
        guard !started else { return }
        started = true
        let dnc = DistributedNotificationCenter.default()
        tokens = [
            dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.didLock() },
            dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.didUnlock() },
        ]
    }

    func stop() {
        let dnc = DistributedNotificationCenter.default()
        tokens.forEach { dnc.removeObserver($0) }
        tokens = []
        hidePanel()
        previewWork?.cancel(); previewWork = nil
        status.previewing = false
        locked = false
        started = false
    }

    func settingsChanged() {
        if locked { onLockScreen ? showOnLockScreen() : hidePanel() }
    }

    // MARK: 잠금·해제

    private func didLock() {
        locked = true
        guard onLockScreen else { return }
        // 잠금 전환 애니메이션이 끝난 뒤 올린다
        showWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.locked else { return }
            self.showOnLockScreen()
        }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func didUnlock() {
        locked = false
        showWork?.cancel()
        hidePanel()   // 풀리면 바로 치운다
    }

    private var screen: NSScreen? { NotchGeometry.targetScreen(for: AppSettings.shared.displayTarget) ?? NSScreen.main }

    private func showOnLockScreen() {
        guard SkyLight.available else {
            status.message = T("잠금 화면 표시 안 함: SkyLight를 찾지 못함", "Not shown: SkyLight not found")
            return
        }
        guard show(onLockSpace: true) else { return }
        // 잠긴 동안만 값 갱신 (타이머는 노치 상시 표시를 매초 따라감)
        refreshTimer?.invalidate()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refreshData() }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }

    /// 창을 만들어 보인다. onLockSpace면 SkyLight 잠금 Space로 옮기고, 실패하면 숨긴다.
    @discardableResult
    private func show(onLockSpace: Bool) -> Bool {
        guard let screen, let center = context?.center else { return false }
        refreshData()
        let timers = LCDataModel.timers(center)
        let available = cards.filter { LCContentBuilder.content($0, data.snapshot, timers: timers, showTitles: showTitles, now: Date()).available }
        // 값이 있는 카드 수만큼 자리를 잡고, 켜 둔 타이머 카드는 잠금 중 시작될 수 있어 한 칸을 더 둔다
        let reserveTimer = cards.contains(.timer) && !available.contains(.timer)
        let wanted = available.count + (reserveTimer ? 1 : 0)
        guard wanted > 0 else { hidePanel(); return false }
        guard let (count, rect) = LCLayout.fit(count: wanted, style: style, screen: screen.frame.size, placement: placement) else {
            status.message = T("이 화면 크기에서는 로그인 영역과 겹치지 않는 자리가 없어 표시하지 않음",
                               "Not shown: no spot that avoids the login area on this screen size")
            hidePanel()
            return false
        }
        let panel = self.panel ?? LCPanel.make()
        self.panel = panel
        let view = LCStackView(data: data, center: center, cards: cards, style: style, showTitles: showTitles,
                               maxCount: count, bottomAligned: placement == .leftBottom || placement == .rightBottom)
        panel.contentView = NSHostingView(rootView: view)
        panel.setFrame(LCLayout.appKitFrame(rect, in: screen.frame), display: true)
        panel.orderFrontRegardless()
        if onLockSpace, !SkyLight.moveToLockScreenSpace(panel) {
            status.message = T("잠금 화면 Space로 옮기지 못해 표시하지 않음", "Not shown: could not move to the lock screen space")
            hidePanel()
            return false
        }
        status.message = count < available.count
            ? T("화면이 좁아 카드 \(available.count - count)장을 뺌", "Dropped \(available.count - count) card(s) to fit the screen") : nil
        return true
    }

    private func hidePanel() {
        refreshTimer?.invalidate(); refreshTimer = nil
        guard let panel else { return }
        panel.orderOut(nil)
        panel.contentView = nil     // 내용·버퍼를 놓는다
        self.panel = nil
    }

    // MARK: 탭 동작

    func refreshData() { data.refresh(center: context?.center) }

    /// 잠그지 않고 일반 화면에 8초 동안 같은 자리·모양으로 보여 준다 (클릭은 통과).
    func previewOnDesktop() {
        guard !locked else { return }
        guard show(onLockSpace: false) else { return }
        status.previewing = true
        previewWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.locked else { return }
            self.hidePanel()
            self.status.previewing = false
        }
        previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    /// 배치·권한 상태를 글자로 복사 (제목·이름 같은 개인 내용은 넣지 않음)
    func copyDiagnostics() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(diagnostics().joined(separator: "\n"), forType: .string)
        status.message = T("진단 내용을 복사함", "Diagnostics copied")
    }

    func diagnostics() -> [String] {
        var lines = ["Lock Screen Cards diagnostics", "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
                     "SkyLight available: \(SkyLight.available)", "show on lock screen: \(onLockScreen)",
                     "placement: \(placement.rawValue), style: \(style.rawValue), cards: \(cards.map(\.rawValue).joined(separator: ","))"]
        for s in NSScreen.screens {
            let fit = LCLayout.fit(count: cards.count, style: style, screen: s.frame.size, placement: placement)
            lines.append("screen \(Int(s.frame.width))x\(Int(s.frame.height)): " + (fit.map { "fits \($0.0) at \(Int($0.1.minX)),\(Int($0.1.minY)) \(Int($0.1.width))x\(Int($0.1.height))" } ?? "no spot"))
        }
        let s = data.snapshot
        lines.append("battery: \(s.battery != nil), devices: \(s.devices.count), calendar: \(s.calendarAccess), reminders: \(s.remindersAccess), focus: \(s.focusAccess), weather hook: \(LockCardHooks.weather != nil)")
        return lines
    }

    // 탭 머리 상태
    var stateText: String {
        if !SkyLight.available { return T("지원 안 됨: SkyLight 없음", "Not supported: SkyLight missing") }
        return onLockScreen ? T("잠그면 이 카드들이 잠금 화면에 보임", "These cards appear when the screen locks")
                            : T("잠금 화면 표시 꺼짐 — 설정에서 켜기", "Lock screen display off — turn on in Settings")
    }
    var stateSymbol: String { SkyLight.available ? (onLockScreen ? "lock.fill" : "lock.slash") : "exclamationmark.triangle.fill" }
    var stateTint: Color { SkyLight.available ? (onLockScreen ? .green : .white.opacity(0.6)) : .orange }

    // MARK: 화면

    func tabView() -> AnyView? { AnyView(LCTab(module: self, data: data, status: status)) }
    var tabContentSize: CGSize { CGSize(width: 530, height: 290) }
    func settingsView() -> AnyView? { AnyView(LCSettings(module: self)) }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "lockcards.preview", title: T("잠금 화면 카드 배치 미리보기", "Preview lock screen cards"),
                       symbol: symbol, keywords: ["lock screen", "잠금 화면", "위젯", "widget"]) { [weak self] in
            self?.previewOnDesktop()
        }]
    }

    // MARK: 자체 검사 (읽기만: 창을 띄우지 않고, 권한 창을 띄우지 않고, 제목·기기 이름을 출력하지 않음)

    func selfTest() -> [String] {
        var out: [String] = []
        out.append("SkyLight symbols available: \(SkyLight.available) (no space created in self test)")
        if let b = BatteryMonitor.read() {
            out.append("mac battery: \(b.percent)% charging=\(b.isCharging) ac=\(b.onAC)")
        } else {
            out.append("mac battery: none")
        }
        let devices = LCDataModel.accessories()
        out.append("device batteries: \(devices.count) device(s) (names not printed)")
        let cal = LCDataModel.access(EKEventStore.authorizationStatus(for: .event))
        out.append("calendar access: \(cal)")
        out.append("reminders access: \(LCDataModel.remindersAccess()) usageDeclared=\(LCDataModel.remindersUsageDeclared)")
        let (focus, focusAccess) = LCDataModel.focus()
        out.append("focus access: \(focusAccess), active: \(focus != nil)")
        out.append("weather hook connected: \(LockCardHooks.weather != nil)")
        let center = ActivityCenter()
        out.append("timer source: ActivityCenter persistent \(LCDataModel.timerKinds.map(\.rawValue).joined(separator: "/")), running now in this process: \(LCDataModel.timers(center).count)")
        let snapshot = LCSnapshot(battery: BatteryMonitor.read(), devices: devices, calendarAccess: cal, focus: focus, focusAccess: focusAccess)
        let avail = LCCard.allCases.filter { LCContentBuilder.content($0, snapshot, timers: [], showTitles: false, now: Date()).available }
        out.append("cards with data now: \(avail.map(\.rawValue).joined(separator: ","))")
        // 제목 숨김 확인
        var hidden = snapshot
        hidden.calendarAccess = .granted
        hidden.event = LCEvent(title: "SECRET", start: Date().addingTimeInterval(3600), end: Date().addingTimeInterval(7200), allDay: false)
        let c = LCContentBuilder.content(.event, hidden, timers: [], showTitles: false, now: Date())
        out.append("event title hidden by default: \(!(c.value + (c.detail ?? "")).contains("SECRET") ? "ok" : "FAIL")")
        let r = LCLayout.check()
        out.append("layout: combos=\(r.combos) placed=\(r.placed) trimmed=\(r.trimmed) hidden=\(r.hidden) overlaps=\(r.violations) \(r.violations == 0 ? "ok" : "FAIL")")
        for size in [CGSize(width: 1512, height: 982), CGSize(width: 1440, height: 900)] {
            for p in LCPlacement.allCases {
                let fit = LCLayout.fit(count: 6, style: .cards, screen: size, placement: p)
                out.append("  \(Int(size.width))x\(Int(size.height)) \(p.rawValue): " + (fit.map { "\($0.0) cards at y=\(Int($0.1.minY))" } ?? "none"))
            }
        }
        _ = NSApplication.shared
        let panel = LCPanel.make()   // 화면에 올리지 않음
        let ok = !panel.canBecomeKey && !panel.canBecomeMain && panel.ignoresMouseEvents && panel.level == .screenSaver && !panel.isVisible
        out.append("panel never key, ignores clicks, not shown: \(ok ? "ok" : "FAIL")")
        return out
    }
}

import AppKit
import IOKit.pwr_mgt
import SwiftUI

/// 잠자기 방지 엔진 (공개 IOPMAssertion). 무기한·기간·종료 시각, 시각이 되면 자동 해제.
/// 상태(종료 시각)를 파일에 저장해 앱을 다시 켜도 이어 간다.
final class KeepAwakeEngine: ObservableObject {
    static let shared = KeepAwakeEngine()
    static let module = "keepawake"
    private static let stateFile = "state.json"

    struct State: Codable, Equatable {
        var started: Date
        /// nil이면 멈출 때까지
        var until: Date?
    }

    @Published private(set) var state: State?
    @Published private(set) var now = Date()
    private var assertion: IOPMAssertionID = 0
    private var holding = false
    private var center: ActivityCenter?
    private var ticker: Timer?
    private var exactTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private(set) var attached = false

    var defaults: ModuleDefaults { ModuleDefaults(module: Self.module) }
    /// 화면도 켜 둘지 (끄면 화면은 꺼져도 Mac은 깨어 있음)
    var keepDisplayOn: Bool { defaults.bool("keepDisplay", default: true) }

    var isActive: Bool { state != nil }
    var remaining: TimeInterval? { state?.until.map { max(0, $0.timeIntervalSince(now)) } }

    func attach(center: ActivityCenter) {
        self.center = center
        guard !attached else { publish(); return }
        attached = true
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.tick() }
        if let saved = TFStorage.load(State.self, Self.module, Self.stateFile) {
            if let until = saved.until, until <= Date() {
                TFStorage.removeState(Self.module, Self.stateFile)
            } else {
                state = saved
                acquire()
                notice(T("잠자기 방지를 이어서 켰어요", "Keep Awake resumed"), subtitle: statusText)
            }
        }
        refresh()
    }

    func detach() {
        attached = false
        release()
        ticker?.invalidate()
        ticker = nil
        exactTimer?.invalidate()
        exactTimer = nil
        if let o = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        wakeObserver = nil
        center?.removePersistent(.caffeinate)
        // 상태 파일은 남겨 재실행하면 이어 간다
    }

    func settingsChanged() {
        guard attached, isActive else { return }
        // 화면 켜 두기 설정이 바뀌면 단언을 다시 만든다
        release()
        acquire()
        publish()
    }

    // MARK: 명령

    func activate(for minutes: Int?) {
        activate(until: minutes.map { Date().addingTimeInterval(Double($0) * 60) })
    }

    func activate(until: Date?) {
        guard attached else { return }
        let s = State(started: Date(), until: until)
        state = s
        TFStorage.save(s, Self.module, Self.stateFile)
        if !holding { acquire() }
        refresh()
        notice(T("잠자기 방지 켜짐", "Keep Awake on"), subtitle: statusText)
    }

    func deactivate(silent: Bool = false) {
        state = nil
        TFStorage.removeState(Self.module, Self.stateFile)
        release()
        refresh()
        if !silent { notice(T("잠자기 방지 꺼짐", "Keep Awake off"), subtitle: T("평소처럼 잠들어요", "Your Mac sleeps as usual")) }
    }

    var statusText: String {
        guard let s = state else { return T("꺼짐", "Off") }
        guard let until = s.until else { return T("멈출 때까지", "Until stopped") }
        return T("\(TFFormat.time(until))까지 · \(TFFormat.duration(remaining ?? 0)) 남음", "Until \(TFFormat.time(until)) · \(TFFormat.duration(remaining ?? 0)) left")
    }

    // MARK: 내부

    private func acquire() {
        guard !holding else { return }
        let type = keepDisplayOn ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        var id: IOPMAssertionID = 0
        let r = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            "Dynamic Notch Keep Awake" as CFString, &id)
        if r == kIOReturnSuccess {
            assertion = id
            holding = true
        }
    }

    private func release() {
        guard holding else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
        holding = false
    }

    private func refresh() {
        now = Date()
        ticker?.invalidate()
        ticker = nil
        exactTimer?.invalidate()
        exactTimer = nil
        if isActive && attached {
            let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
            t.tolerance = 2
            RunLoop.main.add(t, forMode: .common)
            ticker = t
            // 종료 시각에 정확히 맞춰 한 번 더 확인
            if let until = state?.until {
                let exact = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in self?.tick() }
                RunLoop.main.add(exact, forMode: .common)
                exactTimer = exact
            }
        }
        publish()
    }

    private func tick() {
        guard attached else { return }
        now = Date()
        if let until = state?.until, until <= now {
            deactivate(silent: true)
            notice(T("잠자기 방지 끝", "Keep Awake ended"), subtitle: T("정한 시각이 되어 꺼졌어요", "Turned off at the time you set"))
            return
        }
        publish()
    }

    private func publish() {
        guard let center, attached else { return }
        guard let s = state else { center.removePersistent(.caffeinate); return }
        var a = NotchActivity(kind: .caffeinate, symbol: "cup.and.saucer.fill")
        a.priority = ActivityPriority.pinned
        a.tint = Color(red: 0.85, green: 0.62, blue: 0.38)
        if let r = remaining {
            let mins = Int((r / 60).rounded(.up))
            a.value = .text(mins >= 60 ? String(format: "%d:%02d", mins / 60, mins % 60) : T("\(mins)분", "\(mins)m"))
            a.detailValue = .ring(s.until.map { max(0, min(1, r / max(1, $0.timeIntervalSince(s.started)))) } ?? 1)
        } else {
            a.value = .text("∞")
        }
        a.title = T("잠자기 방지", "Keep Awake")
        a.subtitle = statusText
        a.wing = 64
        a.moduleTab = Self.module
        a.actions = [ActivityAction(id: "keepawake.off", title: T("끄기", "Turn Off"), role: .destructive) { [weak self] in self?.deactivate() }]
        center.setPersistent(a)
    }

    private func notice(_ title: String, subtitle: String) {
        var a = NotchActivity(kind: .notice, symbol: "cup.and.saucer.fill")
        a.duration = 2.5
        a.tint = Color(red: 0.85, green: 0.62, blue: 0.38)
        a.title = title
        a.subtitle = subtitle
        a.presentation = .detailThenCompact(1.5)
        a.moduleTab = Self.module
        center?.post(a)
    }

    // MARK: 자체 검사

    /// 단언을 만들었다가 바로 놓는다 (시스템 상태를 남기지 않음). 이 프로세스 단언 목록에 보였는지 돌려준다.
    static func probeAssertion() -> (created: Bool, listed: Bool, released: Bool) {
        var id: IOPMAssertionID = 0
        let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn), "Dynamic Notch self test" as CFString, &id)
        guard r == kIOReturnSuccess else { return (false, false, false) }
        var listed = false
        var dict: Unmanaged<CFDictionary>?
        if IOPMCopyAssertionsByProcess(&dict) == kIOReturnSuccess, let d = dict?.takeRetainedValue() as? [NSNumber: [[String: Any]]] {
            let mine = d[NSNumber(value: ProcessInfo.processInfo.processIdentifier)] ?? []
            listed = mine.contains { ($0["AssertName"] as? String) == "Dynamic Notch self test" }
        }
        let released = IOPMAssertionRelease(id) == kIOReturnSuccess
        return (true, listed, released)
    }
}

/// 잠자기 방지 탭. 덮개 닫고 깨어 있기는 관리자 권한(pmset)이 필요해 보류.
final class KeepAwakeModule: NotchModule {
    let id = KeepAwakeEngine.module
    var title: String { T("잠자기 방지", "Keep Awake") }
    let symbol = "cup.and.saucer"
    var enabledByDefault: Bool { false }

    private let engine = KeepAwakeEngine.shared
    static let durations = [15, 30, 60, 120, 240]

    func start(context: ModuleContext) {
        // 검사·그림 모드(도우미 프로세스)에서는 전원 단언을 만들지 않는다
        guard !AppSettings.isHelper else { return }
        engine.attach(center: context.center)
    }

    func stop() { engine.detach() }
    func settingsChanged() { engine.settingsChanged() }

    func tabView() -> AnyView? { AnyView(KeepAwakeTab(engine: engine)) }
    var tabContentSize: CGSize { CGSize(width: 480, height: 176) }

    func paletteActions() -> [PaletteAction] {
        let keys = ["caffeine", "caffeinate", "awake", "sleep", "잠자기", "카페인", "깨어"]
        if engine.isActive {
            return [PaletteAction(id: "keepawake.off", title: T("잠자기 방지 끄기", "Turn Off Keep Awake"), subtitle: engine.statusText,
                                  symbol: "cup.and.saucer", keywords: keys) { [weak self] in self?.engine.deactivate() }]
        }
        return [PaletteAction(id: "keepawake.on", title: T("잠자기 방지 켜기 (멈출 때까지)", "Keep Awake (until stopped)"),
                              symbol: "cup.and.saucer.fill", keywords: keys) { [weak self] in self?.engine.activate(for: nil) },
                PaletteAction(id: "keepawake.1h", title: T("잠자기 방지 1시간", "Keep Awake for 1 hour"),
                              symbol: "cup.and.saucer.fill", keywords: keys) { [weak self] in self?.engine.activate(for: 60) }]
    }

    func settingsView() -> AnyView? { AnyView(KeepAwakeSettings()) }

    func selfTest() -> [String] {
        let p = KeepAwakeEngine.probeAssertion()
        let saved = TFStorage.load(KeepAwakeEngine.State.self, KeepAwakeEngine.module, "state.json")
        return [
            "assertion create=\(p.created) listed=\(p.listed) released=\(p.released) (held only during this check)",
            "saved state: \(saved.map { $0.until.map { "until \($0)" } ?? "until stopped" } ?? "none")",
            "lid-closed awake: deferred (needs root pmset disablesleep)",
        ]
    }
}

private struct KeepAwakeTab: View {
    @ObservedObject var engine: KeepAwakeEngine
    @State private var untilTime = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: engine.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.island(.title1, .regular))
                    .foregroundStyle(engine.isActive ? Color(red: 0.85, green: 0.62, blue: 0.38) : .white.opacity(0.5))
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.isActive ? T("깨어 있는 중", "Staying awake") : T("평소처럼 잠들어요", "Sleeping as usual"))
                        .font(.island(.title3, .semibold, design: .rounded))
                    Text(engine.isActive ? engine.statusText
                                         : (engine.attached ? T("기간을 고르면 그동안 Mac이 잠들지 않아요", "Pick a duration to keep your Mac awake")
                                                            : T("기능이 켜진 본 앱에서 동작해요", "Works in the running app when the feature is on")))
                        .font(.island(.footnote)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                if engine.isActive {
                    TFPillButton(title: T("끄기", "Turn Off"), symbol: "power", tint: .red) { engine.deactivate() }
                }
            }
            HStack(spacing: 6) {
                TFPillButton(title: T("멈출 때까지", "Until Stopped"), symbol: "infinity",
                             prominent: engine.isActive && engine.state?.until == nil, help: T("멈출 때까지 깨어 있기", "Stay awake until stopped")) { engine.activate(for: nil) }
                ForEach(KeepAwakeModule.durations, id: \.self) { m in
                    TFPillButton(title: m >= 60 ? T("\(m / 60)시간", "\(m / 60)h") : T("\(m)분", "\(m)m")) { engine.activate(for: m) }
                }
            }
            HStack(spacing: 8) {
                Text(T("종료 시각", "Until")).font(.island(.footnote)).foregroundStyle(.white.opacity(0.6))
                DatePicker("", selection: $untilTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                    .frame(width: 110)
                TFPillButton(title: T("이 시각까지", "Until This Time")) {
                    var target = untilTime
                    // 이미 지난 시각이면 내일 같은 시각
                    if target <= Date() { target = Calendar.current.date(byAdding: .day, value: 1, to: target) ?? target }
                    engine.activate(until: target)
                }
                Spacer()
            }
            Text(T("덮개를 닫아도 깨어 있기는 관리자 권한(pmset)이 필요해 지원하지 않아요. 대안: 전원·외부 화면을 연결한 클램쉘 모드.",
                   "Staying awake with the lid closed needs admin rights (pmset) and isn't supported. Alternative: clamshell mode with power and an external display."))
                .font(.island(.caption)).foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
    }
}

private struct KeepAwakeSettings: View {
    @StateObject private var prefs = TFPrefs(module: KeepAwakeEngine.module)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(T("화면도 켜 두기", "Keep the display on too"), isOn: prefs.bool("keepDisplay", true))
            TFSettingsNote(text: T("끄면 화면은 꺼져도 Mac은 잠들지 않아요 (다운로드·빌드용).", "When off, the display may sleep but the Mac stays awake (for downloads or builds)."))
            Divider()
            Text(T("덮개 닫고 깨어 있기", "Stay Awake with the Lid Closed")).font(.headline)
            TFSettingsNote(text: T("지원 안 됨: 시스템 전원 설정(pmset disablesleep)을 바꾸려면 관리자 권한 도우미가 필요해요. 이 앱은 관리자 권한을 쓰지 않아요. 대안: 전원 어댑터와 외부 디스플레이·키보드를 연결하면 macOS 클램쉘 모드로 덮개를 닫아도 깨어 있어요.",
                                   "Not supported: changing the system power setting (pmset disablesleep) needs an admin helper, which this app doesn't use. Alternative: with a power adapter and an external display and keyboard, macOS clamshell mode keeps the Mac awake with the lid closed."))
        }
    }
}

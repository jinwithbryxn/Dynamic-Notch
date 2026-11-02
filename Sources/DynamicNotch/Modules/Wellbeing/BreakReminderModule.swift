import AppKit
import SwiftUI

/// 휴식 알림: 눈 휴식(기본 20분)·일어서기(기본 1시간)·물 마시기(기본 꺼짐).
/// 실제로 입력하는 동안만 시간이 쌓이고, 오래 자리를 비우면 다시 시작한다.
/// 잠금·화면 보호기·Focus·통화(마이크 사용)·전체 화면 중에 도래한 알림은 쌓아 두지 않고 버린다. 화면을 가리지 않는다.
final class BreakReminderModule: NotchModule, ObservableObject {
    let id = "breaks"
    var title: String { T("휴식 알림", "Break Reminders") }
    let symbol = "eye"
    var enabledByDefault: Bool { false }

    enum Kind: String, CaseIterable, Identifiable {
        case eye, stand, water
        var id: String { rawValue }
        var label: String {
            switch self {
            case .eye: return T("눈 휴식", "Look Away")
            case .stand: return T("일어서기", "Stand Up")
            case .water: return T("물 마시기", "Drink Water")
            }
        }
        var symbol: String {
            switch self {
            case .eye: return "eye"
            case .stand: return "figure.stand"
            case .water: return "drop.fill"
            }
        }
        var tint: Color {
            switch self {
            case .eye: return .cyan
            case .stand: return .orange
            case .water: return .blue
            }
        }
        var defaultOn: Bool { self != .water }
        var defaultMinutes: Int {
            switch self {
            case .eye: return 20
            case .stand: return 60
            case .water: return 45
            }
        }
        var message: String {
            switch self {
            case .eye: return T("20초 동안 6m 넘게 먼 곳을 보세요", "Look at something 20 feet away for 20 seconds")
            case .stand: return T("잠깐 일어나서 몸을 풀어 보세요", "Stand up and stretch for a moment")
            case .water: return T("물 한 잔 마실 시간이에요", "Time for a glass of water")
            }
        }
    }

    /// 쌓인 활동 시간(초)
    @Published private(set) var elapsed: [Kind: Double] = [:]
    @Published private(set) var dropped = 0
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var running = false

    private var context: ModuleContext?
    private var timer: Timer?
    private var last = Date()
    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }

    func isOn(_ k: Kind) -> Bool { defaults.bool("\(k.rawValue).on", default: k.defaultOn) }
    func minutes(_ k: Kind) -> Int { max(1, defaults.int("\(k.rawValue).minutes", default: k.defaultMinutes)) }

    func start(context: ModuleContext) {
        self.context = context
        guard timer == nil, !AppSettings.isHelper else { return }
        last = Date()
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        running = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        running = false
        elapsed = [:]
        context = nil
    }

    // MARK: 동작

    func snooze(_ k: Kind) { elapsed[k] = max(0, Double(minutes(k) * 60) - 300) }
    func skip(_ k: Kind) { elapsed[k] = 0 }
    func pause(hours: Double) { pausedUntil = Date().addingTimeInterval(hours * 3600) }
    func unpause() { pausedUntil = nil; last = Date() }

    /// 지금 알림을 띄우면 안 되는 이유 (없으면 nil)
    func suppressReason() -> String? {
        if TFSystem.isScreenLocked || TFSystem.isScreenSaverRunning { return "locked" }
        if defaults.bool("skipFocus", default: true), TFSystem.focusState == true { return "focus" }
        if defaults.bool("skipCalls", default: true), TFSystem.isMicrophoneInUse { return "call" }
        if defaults.bool("skipFullScreen", default: true), TFSystem.isFrontAppFullScreen { return "fullscreen" }
        if let s = PomodoroEngine.shared.state, s.phase.isBreak, PomodoroEngine.shared.isRunning { return "pomodoro break" }
        return nil
    }

    private func tick() {
        let now = Date()
        let dt = min(30, now.timeIntervalSince(last))
        last = now
        if let p = pausedUntil {
            if p > now { return }
            pausedUntil = nil
        }
        let idle = TFSystem.idleSeconds
        let away = TFSystem.isScreenLocked || TFSystem.isScreenSaverRunning
        for k in Kind.allCases where isOn(k) {
            let interval = Double(minutes(k) * 60)
            // 간격(최대 5분)보다 오래 자리를 비웠으면 이미 쉰 것으로 보고 다시 시작
            if idle >= min(interval, 300) { elapsed[k] = 0; continue }
            // 자리에서 입력하는 동안만 쌓는다
            guard idle < 60, !away else { continue }
            elapsed[k, default: 0] += dt
            if elapsed[k, default: 0] >= interval {
                elapsed[k] = 0
                if suppressReason() != nil { dropped += 1 } else { remind(k) }
            }
        }
    }

    private func remind(_ k: Kind) {
        var a = NotchActivity(kind: .notice, symbol: k.symbol)
        a.priority = ActivityPriority.info
        a.presentation = .detail
        a.duration = 10
        a.tint = k.tint
        a.title = k.label
        a.subtitle = k.message
        a.moduleTab = id
        a.actions = [
            ActivityAction(id: "breaks.snooze.\(k.rawValue)", title: T("5분 뒤", "In 5 min")) { [weak self] in
                self?.snooze(k)
                self?.context?.center.dismissTransient(kind: .notice)
            },
            ActivityAction(id: "breaks.skip.\(k.rawValue)", title: T("건너뛰기", "Skip")) { [weak self] in
                self?.skip(k)
                self?.context?.center.dismissTransient(kind: .notice)
            },
        ]
        context?.center.post(a)
    }

    func tabView() -> AnyView? { AnyView(BreakReminderTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 480, height: 168) }

    func paletteActions() -> [PaletteAction] {
        let keys = ["break", "휴식", "eye", "눈", "stand", "일어"]
        if pausedUntil != nil {
            return [PaletteAction(id: "breaks.resume", title: T("휴식 알림 다시 켜기", "Resume Break Reminders"), symbol: "eye", keywords: keys) { [weak self] in self?.unpause() }]
        }
        return [PaletteAction(id: "breaks.pause", title: T("휴식 알림 1시간 멈춤", "Pause Break Reminders for 1 Hour"), symbol: "eye.slash", keywords: keys) { [weak self] in self?.pause(hours: 1) }]
    }

    func settingsView() -> AnyView? { AnyView(BreakReminderSettings()) }

    func selfTest() -> [String] {
        let focus = TFSystem.focusState.map { $0 ? "on" : "off" } ?? "unknown (no Focus Status permission)"
        return Kind.allCases.map { "\($0.rawValue): \(isOn($0) ? "on" : "off") every \(minutes($0)) min" } + [
            "idle \(Int(TFSystem.idleSeconds))s, locked \(TFSystem.isScreenLocked), screensaver \(TFSystem.isScreenSaverRunning)",
            "mic in use (call) \(TFSystem.isMicrophoneInUse), front app full screen \(TFSystem.isFrontAppFullScreen), focus \(focus)",
            "would suppress now: \(suppressReason() ?? "no")",
            "screen sharing/recording detection: unsupported (no public API)",
        ]
    }
}

private struct BreakReminderTab: View {
    @ObservedObject var module: BreakReminderModule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(BreakReminderModule.Kind.allCases) { k in row(k) }
            HStack(spacing: 8) {
                if let p = module.pausedUntil {
                    Text(T("\(TFFormat.time(p))까지 멈춤", "Paused until \(TFFormat.time(p))")).font(.system(size: 10.5)).foregroundStyle(.yellow)
                    TFPillButton(title: T("다시 켜기", "Resume")) { module.unpause() }
                } else {
                    TFPillButton(title: T("1시간 멈춤", "Pause 1 h"), symbol: "pause.fill") { module.pause(hours: 1) }
                }
                Spacer()
                Text(module.running
                     ? T("입력하는 동안만 시간이 쌓여요" + (module.dropped > 0 ? " · 잠금·Focus·통화 중 \(module.dropped)개 버림" : ""),
                         "Counts only while you're active" + (module.dropped > 0 ? " · \(module.dropped) skipped (lock/Focus/call)" : ""))
                     : T("기능이 켜진 본 앱에서 동작해요", "Runs in the app when the feature is on"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
        }
        .foregroundStyle(.white)
    }

    private func row(_ k: BreakReminderModule.Kind) -> some View {
        let on = module.isOn(k)
        let interval = Double(module.minutes(k) * 60)
        let e = module.elapsed[k] ?? 0
        return HStack(spacing: 10) {
            Image(systemName: k.symbol).font(.system(size: 14)).foregroundStyle(on ? k.tint : .white.opacity(0.3)).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(k.label).font(.system(size: 12.5, weight: .semibold))
                    Text(T("\(module.minutes(k))분마다", "every \(module.minutes(k)) min")).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text(on ? T("약 \(Int(((interval - e) / 60).rounded(.up)))분 뒤", "in ~\(Int(((interval - e) / 60).rounded(.up))) min") : T("꺼짐", "Off"))
                        .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
                }
                BarGauge(value: on ? e / interval : 0, tint: k.tint)
            }
            if on {
                TFPillButton(title: "", symbol: "arrow.counterclockwise", help: T("다시 시작", "Restart")) { module.skip(k) }
            }
        }
        .opacity(on ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }
}

private struct BreakReminderSettings: View {
    @StateObject private var prefs = TFPrefs(module: "breaks")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(BreakReminderModule.Kind.allCases) { k in
                HStack {
                    Toggle(k.label, isOn: prefs.bool("\(k.rawValue).on", k.defaultOn))
                    Spacer()
                    Stepper(T("\(prefs.int("\(k.rawValue).minutes", k.defaultMinutes).wrappedValue)분마다", "Every \(prefs.int("\(k.rawValue).minutes", k.defaultMinutes).wrappedValue) min"),
                            value: prefs.int("\(k.rawValue).minutes", k.defaultMinutes), in: 5...240, step: 5)
                }
            }
            TFSettingsNote(text: T("입력하는 동안만 시간이 쌓이고, 5분 넘게(간격이 더 짧으면 간격만큼) 자리를 비우면 다시 시작해요.",
                                   "Time builds only while you're active, and restarts after you've been away 5 minutes (or the interval, if shorter)."))
            Divider()
            Text(T("이럴 때는 알림을 버려요", "Skip reminders that come due")).font(.headline)
            Toggle(T("Focus(집중 모드) 중", "During a Focus"), isOn: prefs.bool("skipFocus", true))
            Toggle(T("통화·회의 중 (마이크 사용 중)", "During calls (microphone in use)"), isOn: prefs.bool("skipCalls", true))
            Toggle(T("전체 화면 앱 사용 중", "While an app is full screen"), isOn: prefs.bool("skipFullScreen", true))
            TFSettingsNote(text: T("화면 잠금·화면 보호기·포모도로 휴식 중에도 버려요. Focus는 이 앱이 집중 모드 상태 권한을 받은 경우에만 알 수 있어요. 화면 공유·녹화 감지는 공개 API가 없어 지원하지 않아요(대안: 발표 전 팔레트에서 '휴식 알림 1시간 멈춤').",
                                   "Also skipped while locked, on the screen saver or in a Pomodoro break. Focus is known only if the app already has Focus Status access. Screen sharing/recording detection has no public API and isn't supported (alternative: 'Pause Break Reminders for 1 Hour' in the palette)."))
        }
    }
}

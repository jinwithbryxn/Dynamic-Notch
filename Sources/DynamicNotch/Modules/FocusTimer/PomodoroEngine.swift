import AppKit
import SwiftUI

/// 포모도로·반복 타이머 엔진.
/// 종료 시각(벽시계)을 파일에 저장해 잠자기·복귀·앱 재실행 뒤에도 정확히 이어 간다.
final class PomodoroEngine: ObservableObject {
    static let shared = PomodoroEngine()
    static let module = "pomodoro"
    private static let stateFile = "state.json"
    /// 앱이 꺼져 있거나 잠든 동안 이보다 오래전에 끝난 단계는 소리·알림 없이 넘긴다
    private static let silentAfter: TimeInterval = 600

    enum Mode: String, Codable { case pomodoro, repeating }

    enum Phase: String, Codable {
        case focus, shortBreak, longBreak, repeating

        var isBreak: Bool { self == .shortBreak || self == .longBreak }
        var title: String {
            switch self {
            case .focus: return T("집중", "Focus")
            case .shortBreak: return T("짧은 휴식", "Short Break")
            case .longBreak: return T("긴 휴식", "Long Break")
            case .repeating: return T("반복 타이머", "Repeat Timer")
            }
        }
        var symbol: String {
            switch self {
            case .focus: return "brain.head.profile"
            case .shortBreak: return "cup.and.saucer.fill"
            case .longBreak: return "sofa.fill"
            case .repeating: return "repeat"
            }
        }
        var tint: Color {
            switch self {
            case .focus: return Color(red: 1.0, green: 0.42, blue: 0.32)
            case .shortBreak: return .green
            case .longBreak: return .mint
            case .repeating: return .cyan
            }
        }
    }

    struct State: Codable, Equatable {
        var mode: Mode
        var phase: Phase
        /// 이번 단계 전체 길이(초)
        var length: Double
        /// 진행 중이면 종료 시각
        var endDate: Date?
        /// 일시정지·대기 중이면 남은 초
        var pausedRemaining: Double?
        /// 이번 단계를 시작한 시각 (집중 기록용)
        var phaseStart: Date
        /// 긴 휴식 뒤 끝낸 집중 수
        var cycleCount = 0
        /// 5분 연장 단계
        var isExtension = false
        /// 반복 타이머가 다시 시작한 횟수
        var repeatCount = 0
        /// 단계가 끝나 다음 단계를 누르길 기다리는 중 (자동 시작 꺼짐)
        var waiting = false
    }

    /// 마스코트 (SF Symbol, 자체 그림)
    static let mascots: [(id: String, symbol: String, label: String)] = [
        ("none", "", T("없음", "None")),
        ("cat", "cat.fill", T("고양이", "Cat")),
        ("dog", "dog.fill", T("강아지", "Dog")),
        ("hare", "hare.fill", T("토끼", "Hare")),
        ("tortoise", "tortoise.fill", T("거북이", "Tortoise")),
        ("bird", "bird.fill", T("새", "Bird")),
        ("fish", "fish.fill", T("물고기", "Fish")),
        ("ladybug", "ladybug.fill", T("무당벌레", "Ladybug")),
    ]

    @Published private(set) var state: State?
    @Published private(set) var now = Date()

    private var center: ActivityCenter?
    private var ticker: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?
    private var hiddenThisPhase: Set<String> = []
    private(set) var attached = false

    // MARK: 자체 검사용 (파일·알림·소리·타이머 없이 상태 전이만 확인)
    private(set) var testMode = false
    private(set) var testLog: [FocusSession] = []

    static func makeForTest() -> PomodoroEngine {
        let e = PomodoroEngine()
        e.testMode = true
        e.attached = true
        return e
    }

    /// 지금 단계를 끝난 것으로 처리 (조용히)
    func testFinishNow() { finishPhase(silent: true) }

    // MARK: 설정 (ModuleDefaults "module.pomodoro.*")

    var defaults: ModuleDefaults { ModuleDefaults(module: Self.module) }
    var focusMinutes: Int { max(1, defaults.int("focusMinutes", default: 25)) }
    var shortBreakMinutes: Int { max(1, defaults.int("shortBreakMinutes", default: 5)) }
    var longBreakMinutes: Int { max(1, defaults.int("longBreakMinutes", default: 15)) }
    var cyclesBeforeLong: Int { max(1, defaults.int("cycles", default: 4)) }
    var autoStartBreaks: Bool { defaults.bool("autoBreaks", default: false) }
    var autoStartFocus: Bool { defaults.bool("autoFocus", default: false) }
    var endSound: String { defaults.string("sound", default: "Glass") }
    var alarmRepeat: TFAlarm.Repeat { TFAlarm.Repeat(rawValue: defaults.string("alarmRepeat", default: "once")) ?? .once }
    var repeatSeconds: Int { max(5, defaults.int("repeatSeconds", default: 20 * 60)) }
    var repeatStopAfter: Int { max(0, defaults.int("repeatStopAfter", default: 0)) }
    var repeatStopWhenAway: Bool { defaults.bool("repeatStopAway", default: true) }
    var blockApps: Bool { defaults.bool("blockApps", default: false) }
    var blockedApps: [String] { defaults.strings("blockedApps", default: []) }
    var mascot: String { defaults.string("mascot", default: "none") }
    var mascotSymbol: String? {
        Self.mascots.first { $0.id == mascot }.flatMap { $0.symbol.isEmpty ? nil : $0.symbol }
    }

    func length(of phase: Phase) -> Double {
        switch phase {
        case .focus: return Double(focusMinutes * 60)
        case .shortBreak: return Double(shortBreakMinutes * 60)
        case .longBreak: return Double(longBreakMinutes * 60)
        case .repeating: return Double(repeatSeconds)
        }
    }

    // MARK: 상태

    var isRunning: Bool { state?.endDate != nil }
    var isPaused: Bool { state != nil && state?.endDate == nil }

    var remaining: Double { state.map(remaining(of:)) ?? 0 }

    private func remaining(of s: State) -> Double {
        if let p = s.pausedRemaining { return p }
        guard let end = s.endDate else { return 0 }
        return max(0, end.timeIntervalSince(now))
    }

    /// 남은 비율 (1 → 0)
    var progressRemaining: Double {
        guard let s = state, s.length > 0 else { return 0 }
        return max(0, min(1, remaining / s.length))
    }

    // MARK: 본 앱 연결

    func attach(center: ActivityCenter) {
        self.center = center
        guard !attached else { publish(); return }
        attached = true
        FocusLog.shared.load()
        state = TFStorage.load(State.self, Self.module, Self.stateFile)
        now = Date()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.tick() }
        if let s = state, let end = s.endDate, end <= Date() {
            // 앱이 꺼져 있던 동안 끝났다
            finishPhase(silent: Date().timeIntervalSince(end) > Self.silentAfter)
        }
        changed(save: false)
    }

    func detach() {
        attached = false
        ticker?.invalidate()
        ticker = nil
        if let o = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        wakeObserver = nil
        stopBlocking()
        TFAlarm.shared.stop()
        center?.removePersistent(.pomodoro)
        center?.dismissTransient(kind: .pomodoro)
        // 상태 파일은 남겨 다시 켜거나 재실행하면 이어 간다
    }

    /// 설정이 바뀜 (도우미 프로세스)
    func settingsChanged() {
        guard attached else { return }
        updateBlocking()
        publish()
    }

    // MARK: 명령

    func startFocus() {
        userAction()
        let cycle = (state?.mode == .pomodoro && state?.phase != .longBreak) ? (state?.cycleCount ?? 0) : 0
        begin(.focus, cycle: cycle)
    }

    func startRepeat(seconds: Int? = nil) {
        userAction()
        // 진행 중이던 집중은 중간 기록으로 남긴다
        if let s = state, s.phase == .focus, !s.waiting { logFocus(s, completed: false) }
        if let seconds { defaults.set(max(5, seconds), "repeatSeconds") }
        begin(.repeating, cycle: 0, length: Double(seconds ?? repeatSeconds))
    }

    func pause() {
        guard var s = state, let end = s.endDate else { return }
        userAction()
        s.pausedRemaining = max(0, end.timeIntervalSinceNow)
        s.endDate = nil
        state = s
        changed()
    }

    func resume() {
        guard var s = state, let p = s.pausedRemaining else { return }
        userAction()
        if s.waiting {
            s.waiting = false
            s.phaseStart = Date()
        }
        s.endDate = Date().addingTimeInterval(p)
        s.pausedRemaining = nil
        state = s
        changed()
    }

    /// 시작·일시정지·이어서 (단축키·팔레트)
    func toggle() {
        if state == nil { startFocus() } else if isRunning { pause() } else { resume() }
    }

    func stop() {
        userAction()
        if let s = state, s.phase == .focus, !s.waiting { logFocus(s, completed: false) }
        state = nil
        changed()
    }

    func skip() {
        guard let s = state else { return }
        userAction()
        switch s.phase {
        case .focus:
            if !s.waiting { logFocus(s, completed: false) }
            begin(nextBreak(after: s.cycleCount), cycle: s.cycleCount)
        case .shortBreak:
            begin(.focus, cycle: s.cycleCount)
        case .longBreak:
            begin(.focus, cycle: 0)
        case .repeating:
            begin(.repeating, cycle: 0, length: s.length, repeatCount: s.repeatCount + 1)
        }
    }

    /// 5분 연장: 집중 중이면 그대로 늘리고, 집중이 끝난 뒤(휴식 대기·휴식 중)면 집중을 5분 더 한다.
    func extend(minutes: Int = 5) {
        guard var s = state else { return }
        userAction()
        let add = Double(minutes * 60)
        if s.phase == .focus && !s.waiting || s.phase == .repeating {
            s.length += add
            if let end = s.endDate { s.endDate = end.addingTimeInterval(add) }
            if let p = s.pausedRemaining { s.pausedRemaining = p + add }
            state = s
            changed()
        } else {
            begin(.focus, cycle: s.cycleCount, length: add, isExtension: true)
        }
    }

    // MARK: 내부

    private func userAction() {
        guard !testMode else { return }
        TFAlarm.shared.stop()
        center?.dismissTransient(kind: .pomodoro)
    }

    private func nextBreak(after cycle: Int) -> Phase {
        cycle >= cyclesBeforeLong ? .longBreak : .shortBreak
    }

    private func begin(_ phase: Phase, cycle: Int, length: Double? = nil, isExtension: Bool = false,
                       repeatCount: Int = 0, waiting: Bool = false) {
        let len = length ?? self.length(of: phase)
        let n = Date()
        state = State(mode: phase == .repeating ? .repeating : .pomodoro, phase: phase, length: len,
                      endDate: waiting ? nil : n.addingTimeInterval(len), pausedRemaining: waiting ? len : nil,
                      phaseStart: n, cycleCount: cycle, isExtension: isExtension, repeatCount: repeatCount,
                      waiting: waiting)
        hiddenThisPhase = []
        changed()
    }

    private func changed(save: Bool = true) {
        now = Date()
        if testMode { return }
        if save {
            if let state { TFStorage.save(state, Self.module, Self.stateFile) } else { TFStorage.removeState(Self.module, Self.stateFile) }
        }
        refreshTicker()
        updateBlocking()
        publish()
        var info: [String: Any] = ["running": isRunning]
        if let s = state { info["phase"] = s.phase.rawValue; info["waiting"] = s.waiting }
        NotificationCenter.default.post(name: TFEvents.pomodoroChanged, object: nil, userInfo: info)
    }

    private func refreshTicker() {
        if isRunning && attached {
            guard ticker == nil else { return }
            let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
            t.tolerance = 0.1
            RunLoop.main.add(t, forMode: .common)
            ticker = t
        } else {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func tick() {
        now = Date()
        guard let s = state, let end = s.endDate else { return }
        if end <= now {
            finishPhase(silent: now.timeIntervalSince(end) > Self.silentAfter)
        } else {
            publish()
        }
    }

    private func logFocus(_ s: State, completed: Bool, end: Date = Date()) {
        let focused = completed ? s.length : s.length - remaining(of: s)
        guard completed || focused >= 60 else { return }
        // 5분 연장은 시간만 더하고 세션 수에는 넣지 않는다
        let session = FocusSession(start: s.phaseStart, end: end, seconds: focused, completed: completed && !s.isExtension)
        if testMode { testLog.append(session) } else { FocusLog.shared.add(session) }
    }

    private func finishPhase(silent: Bool) {
        guard let s = state else { return }
        let endedAt = min(s.endDate ?? Date(), Date())
        switch s.phase {
        case .focus:
            logFocus(s, completed: true, end: endedAt)
            let cycle = s.isExtension ? s.cycleCount : s.cycleCount + 1
            let next = nextBreak(after: cycle)
            begin(next, cycle: cycle, waiting: !autoStartBreaks)
            if !silent { announce(ended: .focus, next: next, auto: autoStartBreaks) }
        case .shortBreak, .longBreak:
            begin(.focus, cycle: s.phase == .longBreak ? 0 : s.cycleCount, waiting: !autoStartFocus)
            if !silent { announce(ended: s.phase, next: .focus, auto: autoStartFocus) }
        case .repeating:
            let count = s.repeatCount + 1
            let away = repeatStopWhenAway && TFSystem.idleSeconds >= 300
            let limit = repeatStopAfter > 0 && count >= repeatStopAfter
            if silent || away || limit {
                state = nil
                changed()
                if !silent { announceRepeatEnd(away: away, count: count) }
            } else {
                begin(.repeating, cycle: 0, length: s.length, repeatCount: count)
                announceRepeat(count: count, length: s.length)
            }
        }
    }

    private func announce(ended: Phase, next: Phase, auto: Bool) {
        TFAlarm.shared.ring(endSound, repeat: alarmRepeat)
        var actions: [ActivityAction] = []
        if ended == .focus {
            if !auto {
                actions.append(ActivityAction(id: "pomodoro.startBreak", title: T("휴식 시작", "Start Break"), role: .primary) { [weak self] in self?.resume() })
            }
            actions.append(ActivityAction(id: "pomodoro.extend", title: T("5분 연장", "+5 min")) { [weak self] in self?.extend() })
            actions.append(ActivityAction(id: "pomodoro.skip", title: T("휴식 건너뛰기", "Skip Break")) { [weak self] in self?.skip() })
        } else {
            if !auto {
                actions.append(ActivityAction(id: "pomodoro.startFocus", title: T("집중 시작", "Start Focus"), role: .primary) { [weak self] in self?.resume() })
            }
            actions.append(ActivityAction(id: "pomodoro.stop", title: T("그만하기", "Stop"), role: .destructive) { [weak self] in self?.stop() })
        }
        let minutes = Int(length(of: next) / 60)
        var a = NotchActivity(kind: .pomodoro, symbol: ended == .focus ? "checkmark.circle.fill" : "bell.fill")
        a.priority = ActivityPriority.batteryLow
        a.presentation = .detail
        a.duration = 12
        a.tint = next.tint
        a.value = .check
        a.title = ended == .focus ? T("집중 끝!", "Focus done!") : T("휴식 끝", "Break over")
        a.subtitle = auto ? T("\(next.title) \(minutes)분 시작", "\(next.title) · \(minutes) min started")
                          : T("\(next.title) \(minutes)분 준비됨", "\(next.title) · \(minutes) min ready")
        a.moduleTab = Self.module
        a.actions = actions
        center?.post(a)
    }

    private func announceRepeat(count: Int, length: Double) {
        TFAlarm.shared.ring(endSound, repeat: alarmRepeat)
        var a = NotchActivity(kind: .pomodoro, symbol: "repeat")
        a.priority = ActivityPriority.batteryLow
        a.presentation = .detail
        a.duration = 8
        a.tint = Phase.repeating.tint
        a.value = .text("\(count)")
        a.title = T("반복 타이머 \(count)회", "Repeat timer · \(count)")
        a.subtitle = T("\(TFFormat.clock(length)) 다시 시작", "Restarted \(TFFormat.clock(length))")
        a.moduleTab = Self.module
        a.actions = [
            ActivityAction(id: "pomodoro.silence", title: T("알람 끄기", "Silence")) { TFAlarm.shared.stop() },
            ActivityAction(id: "pomodoro.stopRepeat", title: T("반복 멈추기", "Stop Repeating"), role: .destructive) { [weak self] in self?.stop() },
        ]
        center?.post(a)
    }

    private func announceRepeatEnd(away: Bool, count: Int) {
        TFAlarm.shared.ring(endSound, repeat: .once)
        var a = NotchActivity(kind: .pomodoro, symbol: "repeat")
        a.priority = ActivityPriority.info
        a.presentation = .detail
        a.duration = 8
        a.tint = Phase.repeating.tint
        a.value = .check
        a.title = T("반복 타이머 끝", "Repeat timer ended")
        a.subtitle = away ? T("자리를 비워 \(count)회에서 멈췄어요", "Stopped after \(count) because you were away")
                          : T("\(count)회 반복을 마쳤어요", "Finished \(count) repeats")
        a.moduleTab = Self.module
        center?.post(a)
    }

    private func publish() {
        guard let center, attached else { return }
        guard let s = state else { center.removePersistent(.pomodoro); return }
        var a = NotchActivity(kind: .pomodoro, symbol: isPaused && !s.waiting ? "pause.fill" : (mascotSymbol ?? s.phase.symbol))
        a.priority = ActivityPriority.timer
        a.tint = s.phase.tint
        a.value = .text(TFFormat.clock(remaining))
        a.title = s.waiting ? T("\(s.phase.title) 준비", "\(s.phase.title) ready") : s.phase.title
        a.subtitle = subtitle(s)
        a.detailValue = .ring(progressRemaining)
        a.wing = 64
        a.moduleTab = Self.module
        if isRunning {
            a.actions = [
                ActivityAction(id: "pomodoro.pause", title: T("일시정지", "Pause")) { [weak self] in self?.pause() },
                ActivityAction(id: "pomodoro.skip", title: T("건너뛰기", "Skip")) { [weak self] in self?.skip() },
                ActivityAction(id: "pomodoro.stop", title: T("정지", "Stop"), role: .destructive) { [weak self] in self?.stop() },
            ]
        } else {
            a.actions = [
                ActivityAction(id: "pomodoro.resume", title: s.waiting ? T("시작", "Start") : T("계속", "Resume"), role: .primary) { [weak self] in self?.resume() },
                ActivityAction(id: "pomodoro.stop", title: T("정지", "Stop"), role: .destructive) { [weak self] in self?.stop() },
            ]
        }
        center.setPersistent(a)
    }

    func subtitle(_ s: State) -> String {
        switch s.phase {
        case .focus:
            let n = min(s.cycleCount + 1, cyclesBeforeLong)
            return s.isExtension ? T("5분 연장", "+5 min extension") : T("세션 \(n)/\(cyclesBeforeLong)", "Session \(n)/\(cyclesBeforeLong)")
        case .shortBreak, .longBreak:
            return T("다음: 집중 \(focusMinutes)분", "Next: \(focusMinutes) min focus")
        case .repeating:
            return T("\(s.repeatCount + 1)회째 · \(TFFormat.clock(s.length))", "Round \(s.repeatCount + 1) · \(TFFormat.clock(s.length))")
        }
    }

    // MARK: 방해 앱 숨기기 (집중 단계에서만, 앱을 종료하지 않음)

    private func updateBlocking() {
        let should = attached && blockApps && !blockedApps.isEmpty && state?.phase == .focus && isRunning
        guard should else { stopBlocking(); return }
        if activateObserver == nil {
            activateObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.hideIfBlocked(app)
            }
        }
        if let front = NSWorkspace.shared.frontmostApplication { hideIfBlocked(front) }
    }

    private func stopBlocking() {
        if let o = activateObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        activateObserver = nil
    }

    private func hideIfBlocked(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier, blockedApps.contains(id),
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        app.hide()
        guard !hiddenThisPhase.contains(id) else { return }
        hiddenThisPhase.insert(id)
        var a = NotchActivity(kind: .notice, symbol: "eye.slash")
        a.duration = 2.5
        a.tint = Phase.focus.tint
        a.title = T("집중 중이라 \(TFApps.name(id)) 숨김", "Hid \(TFApps.name(id)) while focusing")
        a.moduleTab = Self.module
        center?.post(a)
    }
}

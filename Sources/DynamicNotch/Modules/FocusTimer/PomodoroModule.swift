import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 포모도로 + 반복 타이머 + 집중 기록 탭.
/// 타이머 자체는 권한·감시가 없어 기본으로 켠다. 방해 앱 숨기기는 설정에서 따로 켠다(기본 꺼짐).
final class PomodoroModule: NotchModule {
    let id = PomodoroEngine.module
    var title: String { T("포모도로", "Pomodoro") }
    let symbol = "timer.circle"
    var enabledByDefault: Bool { true }

    private let engine = PomodoroEngine.shared
    private var context: ModuleContext?

    /// 빠른 시작 단축키 (Carbon 전역 단축키, 권한 불필요)
    static let hotkeys: [(id: String, label: String, shortcut: HotKeyCenter.Shortcut?)] = [
        ("none", T("없음", "None"), nil),
        ("ctrlOptP", "⌃⌥P", .init(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | optionKey))),
        ("ctrlOptCmdP", "⌃⌥⌘P", .init(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | optionKey | cmdKey))),
        ("ctrlShiftP", "⌃⇧P", .init(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | shiftKey))),
    ]

    func start(context: ModuleContext) {
        self.context = context
        engine.attach(center: context.center)
        registerHotkey()
    }

    func stop() {
        HotKeyCenter.shared.unregister("pomodoro.start")
        engine.detach()
        context = nil
    }

    func settingsChanged() {
        // 도우미에서 기록을 지웠으면 다시 읽는다 (지운 기록을 다시 쓰지 않게)
        FocusLog.shared.load(force: true)
        registerHotkey()
        engine.settingsChanged()
    }

    private func registerHotkey() {
        let choice = engine.defaults.string("hotkey", default: "none")
        guard context != nil, let sc = Self.hotkeys.first(where: { $0.id == choice })?.shortcut else {
            HotKeyCenter.shared.unregister("pomodoro.start")
            return
        }
        HotKeyCenter.shared.register("pomodoro.start", sc) { [weak self] in self?.engine.toggle() }
    }

    func tabView() -> AnyView? { AnyView(PomodoroTab(engine: engine, log: FocusLog.shared)) }
    var tabContentSize: CGSize { CGSize(width: 560, height: 214) }

    func paletteActions() -> [PaletteAction] {
        var list: [PaletteAction] = []
        let keys = ["pomodoro", "포모도로", "focus", "집중", "timer", "타이머"]
        if engine.state == nil {
            list.append(PaletteAction(id: "pomodoro.start", title: T("포모도로 시작", "Start Pomodoro"),
                                      subtitle: T("집중 \(engine.focusMinutes)분", "\(engine.focusMinutes) min focus"),
                                      symbol: "play.circle", keywords: keys) { [weak self] in self?.engine.startFocus() })
            list.append(PaletteAction(id: "pomodoro.repeat", title: T("반복 타이머 시작", "Start Repeat Timer"),
                                      subtitle: TFFormat.clock(Double(engine.repeatSeconds)),
                                      symbol: "repeat", keywords: ["repeat", "반복"] + keys) { [weak self] in self?.engine.startRepeat() })
        } else {
            if engine.isRunning {
                list.append(PaletteAction(id: "pomodoro.pause", title: T("포모도로 일시정지", "Pause Pomodoro"),
                                          symbol: "pause.circle", keywords: keys) { [weak self] in self?.engine.pause() })
            } else {
                list.append(PaletteAction(id: "pomodoro.resume", title: T("포모도로 계속", "Resume Pomodoro"),
                                          symbol: "play.circle", keywords: keys) { [weak self] in self?.engine.resume() })
            }
            list.append(PaletteAction(id: "pomodoro.stop", title: T("포모도로 정지", "Stop Pomodoro"),
                                      symbol: "stop.circle", keywords: keys) { [weak self] in self?.engine.stop() })
        }
        return list
    }

    /// "반복 10" / "repeat 10" → 10분 반복 타이머
    func paletteResults(for query: String) -> [PaletteAction] {
        let parts = query.lowercased().split(separator: " ")
        guard parts.count == 2, ["반복", "repeat"].contains(String(parts[0])), let m = Int(parts[1]), (1...600).contains(m) else { return [] }
        return [PaletteAction(id: "pomodoro.repeat.\(m)", title: T("\(m)분 반복 타이머", "\(m) min repeat timer"),
                              symbol: "repeat") { [weak self] in self?.engine.startRepeat(seconds: m * 60) }]
    }

    func settingsView() -> AnyView? { AnyView(PomodoroSettings()) }

    func selfTest() -> [String] {
        var lines: [String] = []
        // 저장 파일 왕복 (임시 폴더, 사용자 기록은 건드리지 않음)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tf-selftest-\(UUID().uuidString).json")
        let s = PomodoroEngine.State(mode: .pomodoro, phase: .focus, length: 1500, endDate: Date().addingTimeInterval(1500),
                                     pausedRemaining: nil, phaseStart: Date(), cycleCount: 2)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        if let data = try? enc.encode(s), (try? data.write(to: tmp)) != nil,
           let back = try? dec.decode(PomodoroEngine.State.self, from: Data(contentsOf: tmp)) {
            lines.append("state round trip: \(back.phase.rawValue) cycle \(back.cycleCount) remaining ~\(Int(back.endDate!.timeIntervalSinceNow))s")
        } else {
            lines.append("state round trip: FAILED")
        }
        try? FileManager.default.removeItem(at: tmp)
        lines.append("settings: focus \(engine.focusMinutes)m short \(engine.shortBreakMinutes)m long \(engine.longBreakMinutes)m cycles \(engine.cyclesBeforeLong)")
        lines.append("storage folder: \(TFStorage.root.path)")
        let saved = TFStorage.load(PomodoroEngine.State.self, PomodoroEngine.module, "state.json")
        lines.append("saved running state: \(saved.map { "\($0.phase.rawValue) waiting=\($0.waiting)" } ?? "none")")
        FocusLog.shared.load(force: true)
        let log = FocusLog.shared
        lines.append("focus log: \(log.sessions.count) sessions, today \(Int(log.todaySeconds / 60))m, streak \(log.streakDays)d, total \(Int(log.totalSeconds / 60))m")
        lines.append("sounds: \(TFAlarm.systemSounds.count) system sounds, end sound '\(engine.endSound)' found=\(NSSound(named: engine.endSound) != nil)")
        lines.append("mascot symbols valid: \(PomodoroEngine.mascots.filter { !$0.symbol.isEmpty }.allSatisfy { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) != nil })")
        lines.append("idle seconds now: \(Int(TFSystem.idleSeconds))")
        lines.append(contentsOf: Self.stateMachineTest())
        return lines
    }

    /// 상태 전이 검사 (별도 엔진, 파일·알림·소리 없음)
    static func stateMachineTest() -> [String] {
        let e = PomodoroEngine.makeForTest()
        var trace: [String] = []
        func mark() {
            guard let s = e.state else { trace.append("idle"); return }
            trace.append("\(s.phase.rawValue)\(s.waiting ? "(wait)" : (e.isPaused ? "(pause)" : ""))#\(s.cycleCount)")
        }
        e.startFocus(); mark()
        e.pause(); let pausedLeft = Int(e.remaining); mark()
        e.resume(); mark()
        for _ in 0..<e.cyclesBeforeLong {
            if e.state?.waiting == true { e.resume() }
            e.testFinishNow(); mark()          // 집중 끝 → 휴식
            if e.state?.phase.isBreak == true && e.state?.phase != .longBreak {
                if e.state?.waiting == true { e.resume() }
                e.testFinishNow(); mark()      // 휴식 끝 → 집중
            }
        }
        e.extend(); mark()                      // 긴 휴식 대신 5분 더 집중
        e.testFinishNow(); mark()
        e.skip(); mark()                        // 긴 휴식 건너뛰기 → 집중 #0
        e.stop(); mark()
        e.startRepeat(seconds: 60); mark()
        e.testFinishNow(); mark()               // 반복: 다시 시작 또는 자리 비움으로 멈춤
        e.stop()
        let completed = e.testLog.filter(\.completed).count
        return ["state machine: " + trace.joined(separator: " → "),
                "paused remaining \(pausedLeft)s, logged \(e.testLog.count) sessions (\(completed) completed, extension not counted)"]
    }
}

// MARK: - 탭

private enum PomodoroPage: String, Hashable { case pomodoro, repeating, stats }

/// 탭 안에서 마지막으로 본 구역 (알림 없이 바로 저장)
private let pomodoroPageKey = "module.pomodoro.page"

private struct PomodoroTab: View {
    @ObservedObject var engine: PomodoroEngine
    @ObservedObject var log: FocusLog
    @State private var page: PomodoroPage = .pomodoro

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TFSegment(items: [(.pomodoro, T("포모도로", "Pomodoro")), (.repeating, T("반복 타이머", "Repeat")),
                                  (.stats, T("기록", "Stats"))], selection: Binding(get: { page }, set: {
                                    page = $0
                                    UserDefaults.standard.set($0.rawValue, forKey: pomodoroPageKey)
                                  }))
                Spacer()
                if ModuleRegistry.shared.running.contains("focussounds") { FocusSoundQuickMenu(player: FocusSoundPlayer.shared) }
            }
            switch page {
            case .pomodoro: PomodoroPageView(engine: engine, log: log)
            case .repeating: RepeatPageView(engine: engine)
            case .stats: FocusStatsView(log: log)
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            log.load()
            page = PomodoroPage(rawValue: UserDefaults.standard.string(forKey: pomodoroPageKey) ?? "") ?? .pomodoro
            if engine.state?.mode == .repeating { page = .repeating } else if engine.state != nil && page == .repeating { page = .pomodoro }
        }
    }
}

/// 남은 시간 원 + 가운데 시간 + 마스코트
private struct CountdownRing: View {
    @ObservedObject var engine: PomodoroEngine
    var tint: Color
    var size: CGFloat = 132

    var body: some View {
        ZStack {
            RingGauge(value: engine.state == nil ? 1 : engine.progressRemaining, tint: tint, lineWidth: 7)
            VStack(spacing: 0) {
                Text(TFFormat.clock(engine.state == nil ? engine.length(of: .focus) : engine.remaining))
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text(engine.state.map { $0.waiting ? T("준비", "Ready") : (engine.isPaused ? T("일시정지", "Paused") : $0.phase.title) } ?? T("대기", "Idle"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if let symbol = engine.mascotSymbol {
                MascotView(symbol: symbol, running: engine.isRunning, resting: engine.state?.phase.isBreak == true, tint: tint)
                    .offset(x: 10, y: 4)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 타이머 마스코트: 집중 중에는 통통 뛰고, 휴식 중에는 졸고, 멈추면 가만히 있는다.
private struct MascotView: View {
    var symbol: String
    var running: Bool
    var resting: Bool
    var tint: Color
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var body: some View {
        if running && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                figure
                    .offset(y: resting ? 0 : -abs(sin(t * .pi / 0.6)) * 5)
                    .rotationEffect(.degrees(resting ? sin(t * .pi / 2) * 6 : 0))
            }
        } else {
            figure
        }
    }

    private var figure: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black))
            if resting {
                Text("z").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                    .offset(x: 4, y: -4)
            }
        }
        .accessibilityLabel(T("마스코트", "Mascot"))
    }
}

private struct PomodoroPageView: View {
    @ObservedObject var engine: PomodoroEngine
    @ObservedObject var log: FocusLog

    var body: some View {
        let s = engine.state?.mode == .pomodoro ? engine.state : nil
        let phase = s?.phase ?? .focus
        HStack(alignment: .center, spacing: 22) {
            CountdownRing(engine: engine, tint: phase.tint)
                .opacity(engine.state?.mode == .repeating ? 0.35 : 1)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.map { $0.waiting ? T("\($0.phase.title) 준비됨", "\($0.phase.title) ready") : $0.phase.title } ?? T("집중을 시작해 볼까요", "Ready to focus"))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(s.map { engine.subtitle($0) } ?? T("집중 \(engine.focusMinutes)분 · 휴식 \(engine.shortBreakMinutes)분 · \(engine.cyclesBeforeLong)세션마다 긴 휴식 \(engine.longBreakMinutes)분",
                                                         "\(engine.focusMinutes)m focus · \(engine.shortBreakMinutes)m break · long \(engine.longBreakMinutes)m every \(engine.cyclesBeforeLong)"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }
                controls(s)
                HStack(spacing: 14) {
                    stat(T("오늘", "Today"), TFFormat.duration(log.todaySeconds), "\(log.todayCount)" + T("세션", " sessions"))
                    stat(T("연속", "Streak"), T("\(log.streakDays)일", "\(log.streakDays)d"), nil)
                }
                if engine.state?.mode == .repeating {
                    Text(T("반복 타이머가 도는 중이에요", "The repeat timer is running"))
                        .font(.system(size: 10.5)).foregroundStyle(.cyan)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func controls(_ s: PomodoroEngine.State?) -> some View {
        HStack(spacing: 8) {
            if s == nil {
                TFPillButton(title: T("집중 시작", "Start Focus"), symbol: "play.fill", tint: PomodoroEngine.Phase.focus.tint, prominent: true) { engine.startFocus() }
            } else if engine.isRunning {
                TFRoundButton(symbol: "pause.fill", tint: s!.phase.tint, help: T("일시정지", "Pause")) { engine.pause() }
                TFRoundButton(symbol: "forward.end.fill", help: T("건너뛰기", "Skip")) { engine.skip() }
                TFRoundButton(symbol: "stop.fill", tint: .red, help: T("정지", "Stop")) { engine.stop() }
                TFPillButton(title: T("+5분", "+5 min"), help: T("5분 연장", "Extend 5 minutes")) { engine.extend() }
            } else {
                TFRoundButton(symbol: "play.fill", tint: s!.phase.tint, help: s!.waiting ? T("시작", "Start") : T("계속", "Resume")) { engine.resume() }
                if s!.waiting && s!.phase.isBreak {
                    TFPillButton(title: T("5분 연장", "+5 min")) { engine.extend() }
                    TFPillButton(title: T("휴식 건너뛰기", "Skip Break")) { engine.skip() }
                } else {
                    TFRoundButton(symbol: "forward.end.fill", help: T("건너뛰기", "Skip")) { engine.skip() }
                }
                TFRoundButton(symbol: "stop.fill", tint: .red, help: T("정지", "Stop")) { engine.stop() }
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ extra: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                if let extra { Text(extra).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55)) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RepeatPageView: View {
    @ObservedObject var engine: PomodoroEngine
    @State private var minutes: Int = 20
    private let presets = [1, 5, 10, 20, 30, 60]

    var body: some View {
        let s = engine.state?.mode == .repeating ? engine.state : nil
        HStack(alignment: .center, spacing: 22) {
            ZStack {
                RingGauge(value: s == nil ? 1 : engine.progressRemaining, tint: .cyan, lineWidth: 7)
                VStack(spacing: 0) {
                    Text(TFFormat.clock(s == nil ? Double(minutes * 60) : engine.remaining))
                        .font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(s.map { T("\($0.repeatCount + 1)회째", "Round \($0.repeatCount + 1)") } ?? T("반복", "Repeat"))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 132, height: 132)
            .opacity(engine.state?.mode == .pomodoro ? 0.35 : 1)

            VStack(alignment: .leading, spacing: 9) {
                Text(T("끝나면 같은 길이로 다시 시작", "Restarts with the same length when it ends"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                HStack(spacing: 5) {
                    ForEach(presets, id: \.self) { m in
                        TFPillButton(title: m >= 60 ? T("\(m / 60)시간", "\(m / 60)h") : T("\(m)분", "\(m)m"),
                                     tint: m == minutes ? .cyan : .white, prominent: m == minutes) {
                            minutes = m
                            if s != nil { engine.startRepeat(seconds: m * 60) } else { engine.defaults.set(m * 60, "repeatSeconds") }
                        }
                    }
                    Stepper("", value: Binding(get: { minutes }, set: { minutes = max(1, min(600, $0)); engine.defaults.set(minutes * 60, "repeatSeconds") }), in: 1...600)
                        .labelsHidden()
                        .help(T("1분씩 조절", "Adjust by 1 minute"))
                }
                HStack(spacing: 8) {
                    if s == nil {
                        TFPillButton(title: T("반복 시작", "Start"), symbol: "play.fill", tint: .cyan, prominent: true) { engine.startRepeat(seconds: minutes * 60) }
                    } else if engine.isRunning {
                        TFRoundButton(symbol: "pause.fill", tint: .cyan, help: T("일시정지", "Pause")) { engine.pause() }
                        TFRoundButton(symbol: "arrow.counterclockwise", help: T("처음부터 다시", "Restart")) { engine.skip() }
                        TFRoundButton(symbol: "stop.fill", tint: .red, help: T("정지", "Stop")) { engine.stop() }
                    } else {
                        TFRoundButton(symbol: "play.fill", tint: .cyan, help: T("계속", "Resume")) { engine.resume() }
                        TFRoundButton(symbol: "stop.fill", tint: .red, help: T("정지", "Stop")) { engine.stop() }
                    }
                }
                Text(stopRule)
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .onAppear { minutes = max(1, engine.repeatSeconds / 60) }
    }

    private var stopRule: String {
        var parts: [String] = []
        if engine.repeatStopWhenAway { parts.append(T("5분 넘게 자리를 비우면 멈춤", "Stops if you're away 5+ min")) }
        parts.append(engine.repeatStopAfter > 0 ? T("\(engine.repeatStopAfter)회 뒤 멈춤", "Stops after \(engine.repeatStopAfter) rounds")
                                                : T("횟수 제한 없음", "No round limit"))
        parts.append(T("알람: \(engine.alarmRepeat.label)", "Alarm: \(engine.alarmRepeat.label)"))
        return parts.joined(separator: " · ")
    }
}

/// 집중 기록: 오늘·연속·누적 + 7일 차트 + 최근 세션
struct FocusStatsView: View {
    @ObservedObject var log: FocusLog

    var body: some View {
        let days = log.lastDays(7)
        let maxSec = max(days.map(\.seconds).max() ?? 0, 1800)
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    tile(T("오늘", "Today"), TFFormat.duration(log.todaySeconds), T("\(log.todayCount)세션", "\(log.todayCount) sessions"))
                    tile(T("연속 기록", "Streak"), T("\(log.streakDays)일", "\(log.streakDays) days"), T("하루 1세션 이상", "1+ session a day"))
                    tile(T("누적", "Total"), TFFormat.duration(log.totalSeconds), T("\(log.totalCount)세션", "\(log.totalCount) sessions"))
                }
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(days, id: \.key) { d in
                        VStack(spacing: 3) {
                            Text(d.seconds > 0 ? TFFormat.short(d.seconds) : "")
                                .font(.system(size: 8.5, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(d.key == TFDay.key() ? PomodoroEngine.Phase.focus.tint : Color.white.opacity(0.35))
                                .frame(width: 22, height: max(3, 62 * CGFloat(d.seconds / maxSec)))
                            Text(TFDay.weekdayShort(d.key)).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.55))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(d.key) \(TFFormat.duration(d.seconds))")
                    }
                }
                .frame(height: 92, alignment: .bottom)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(T("최근 세션", "Recent sessions")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                if log.sessions.isEmpty {
                    Text(T("아직 기록이 없어요. 포모도로를 마치면 여기에 쌓여요.", "No sessions yet. Finished pomodoros show up here."))
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(log.recent.prefix(6)) { s in
                        HStack(spacing: 6) {
                            Image(systemName: s.completed ? "checkmark.circle.fill" : "circle.dashed")
                                .font(.system(size: 10)).foregroundStyle(s.completed ? .green : .white.opacity(0.4))
                            Text(sessionDate(s.start)).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.65))
                            Spacer(minLength: 4)
                            Text(TFFormat.duration(s.seconds)).font(.system(size: 10.5, weight: .medium)).monospacedDigit()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 170)
        }
    }

    private func sessionDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate(Calendar.current.isDateInToday(d) ? "jmm" : "MMMd jmm")
        return f.string(from: d)
    }

    private func tile(_ label: String, _ value: String, _ extra: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(extra).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 설정 (도우미 프로세스)

private struct PomodoroSettings: View {
    @StateObject private var prefs = TFPrefs(module: PomodoroEngine.module)
    @State private var cleared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("포모도로", "Pomodoro")).font(.headline)
            Stepper(T("집중 \(prefs.int("focusMinutes", 25).wrappedValue)분", "Focus \(prefs.int("focusMinutes", 25).wrappedValue) min"),
                    value: prefs.int("focusMinutes", 25), in: 1...180)
            Stepper(T("짧은 휴식 \(prefs.int("shortBreakMinutes", 5).wrappedValue)분", "Short break \(prefs.int("shortBreakMinutes", 5).wrappedValue) min"),
                    value: prefs.int("shortBreakMinutes", 5), in: 1...60)
            Stepper(T("긴 휴식 \(prefs.int("longBreakMinutes", 15).wrappedValue)분", "Long break \(prefs.int("longBreakMinutes", 15).wrappedValue) min"),
                    value: prefs.int("longBreakMinutes", 15), in: 1...90)
            Stepper(T("\(prefs.int("cycles", 4).wrappedValue)세션마다 긴 휴식", "Long break every \(prefs.int("cycles", 4).wrappedValue) sessions"),
                    value: prefs.int("cycles", 4), in: 1...12)
            TFSettingsNote(text: T("진행 중인 세션은 원래 길이를 유지해요.", "A session in progress keeps its original length."))
            Toggle(T("집중이 끝나면 휴식 자동 시작", "Start breaks automatically"), isOn: prefs.bool("autoBreaks", false))
            Toggle(T("휴식이 끝나면 다음 집중 자동 시작", "Start the next focus automatically"), isOn: prefs.bool("autoFocus", false))

            Divider()
            Text(T("끝날 때 소리", "End Sound")).font(.headline)
            HStack {
                Picker(T("소리", "Sound"), selection: prefs.string("sound", "Glass")) {
                    Text(T("없음", "None")).tag("none")
                    ForEach(TFAlarm.systemSounds, id: \.self) { Text($0).tag($0) }
                }
                Button(T("미리 듣기", "Preview")) { NSSound(named: prefs.string("sound", "Glass").wrappedValue)?.play() }
            }
            Picker(T("알람 반복", "Repeat Alarm"), selection: prefs.string("alarmRepeat", "once")) {
                ForEach(TFAlarm.Repeat.allCases) { Text($0.label).tag($0.rawValue) }
            }

            Divider()
            Text(T("반복 타이머", "Repeat Timer")).font(.headline)
            Stepper(T("길이 \(prefs.int("repeatSeconds", 1200).wrappedValue / 60)분", "Length \(prefs.int("repeatSeconds", 1200).wrappedValue / 60) min"),
                    value: Binding(get: { prefs.int("repeatSeconds", 1200).wrappedValue / 60 },
                                   set: { prefs.int("repeatSeconds", 1200).wrappedValue = max(1, $0) * 60 }), in: 1...600)
            Stepper(prefs.int("repeatStopAfter", 0).wrappedValue == 0 ? T("횟수 제한 없음", "No round limit")
                        : T("\(prefs.int("repeatStopAfter", 0).wrappedValue)회 뒤 멈춤", "Stop after \(prefs.int("repeatStopAfter", 0).wrappedValue) rounds"),
                    value: prefs.int("repeatStopAfter", 0), in: 0...100)
            Toggle(T("5분 넘게 자리를 비우면 반복 멈춤", "Stop repeating when away for 5+ minutes"), isOn: prefs.bool("repeatStopAway", true))

            Divider()
            Text(T("화면", "Display")).font(.headline)
            Picker(T("마스코트", "Mascot"), selection: prefs.string("mascot", "none")) {
                ForEach(PomodoroEngine.mascots, id: \.id) { m in
                    if m.symbol.isEmpty { Text(m.label).tag(m.id) } else { Label(m.label, systemImage: m.symbol).tag(m.id) }
                }
            }
            TFSettingsNote(text: T("카운트다운 옆과 접힌 노치 아이콘에 보여요. 동작 줄이기를 켜면 움직이지 않아요.",
                                   "Shown next to the countdown and as the collapsed notch icon. It stays still with Reduce Motion."))
            Picker(T("시작·일시정지 단축키", "Start/Pause Shortcut"), selection: prefs.string("hotkey", "none")) {
                ForEach(PomodoroModule.hotkeys, id: \.id) { Text($0.label).tag($0.id) }
            }

            Divider()
            Text(T("집중 중 방해 앱 숨기기", "Block Apps While Focusing")).font(.headline)
            Toggle(T("집중 단계에서 목록의 앱이 앞으로 나오면 숨기기", "Hide listed apps when they come forward during focus"), isOn: prefs.bool("blockApps", false))
            TFSettingsNote(text: T("앱을 종료하지 않고 숨기기만 해요. 휴식 중에는 막지 않아요.", "Apps are hidden, never quit. Breaks are not blocked."))
            TFAppListEditor(prefs: prefs, key: "blockedApps", emptyText: T("아직 숨길 앱이 없어요.", "No apps blocked yet."))

            Divider()
            Text(T("집중 기록", "Focus History")).font(.headline)
            TFSettingsNote(text: T("기록은 이 Mac에만 저장되고 업로드하지 않아요.", "History stays on this Mac and is never uploaded."))
            Button(cleared ? T("휴지통으로 옮겼어요", "Moved to the Trash") : T("집중 기록 지우기 (휴지통으로)", "Clear Focus History (to Trash)")) {
                if FocusLog.shared.clear() {
                    cleared = true
                    prefs.defaults.set(Date().timeIntervalSince1970, "logClearedAt")
                }
            }
            .disabled(cleared)
        }
    }
}

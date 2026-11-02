import AppKit
import SwiftUI

/// 스톱워치 엔진. 시작 시각과 쌓인 시간만 저장해 드리프트가 없고, 잠자기·재실행 뒤에도 이어 간다.
final class StopwatchEngine: ObservableObject {
    static let shared = StopwatchEngine()
    static let module = "stopwatch"
    private static let stateFile = "state.json"
    static let maxLaps = 99

    struct State: Codable, Equatable {
        /// 진행 중이면 이번 구간을 시작한 시각
        var startDate: Date?
        /// 앞선 구간까지 쌓인 초
        var accumulated: Double = 0
        /// 랩을 누른 순간의 전체 경과 초
        var laps: [Double] = []
    }

    @Published private(set) var state = State()
    private var center: ActivityCenter?
    private(set) var attached = false

    var isRunning: Bool { state.startDate != nil }
    var isIdle: Bool { state.startDate == nil && state.accumulated == 0 }

    func elapsed(at date: Date = Date()) -> Double {
        state.accumulated + (state.startDate.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    func attach(center: ActivityCenter) {
        self.center = center
        if !attached {
            attached = true
            state = TFStorage.load(State.self, Self.module, Self.stateFile) ?? State()
        }
        publish()
    }

    func detach() {
        attached = false
        center?.removePersistent(.stopwatch)
    }

    func start() {
        guard state.startDate == nil else { return }
        state.startDate = Date()
        changed()
    }

    func pause() {
        guard let s = state.startDate else { return }
        state.accumulated += max(0, Date().timeIntervalSince(s))
        state.startDate = nil
        changed()
    }

    func toggle() { isRunning ? pause() : start() }

    func lap() {
        guard isRunning, state.laps.count < Self.maxLaps else { return }
        state.laps.append(elapsed())
        changed()
    }

    func reset() {
        state = State()
        changed()
    }

    private func changed() {
        if isIdle { TFStorage.removeState(Self.module, Self.stateFile) } else { TFStorage.save(state, Self.module, Self.stateFile) }
        publish()
    }

    private func publish() {
        guard let center, attached else { return }
        guard !isIdle else { center.removePersistent(.stopwatch); return }
        var a = NotchActivity(kind: .stopwatch, symbol: isRunning ? "stopwatch" : "pause.fill")
        a.priority = ActivityPriority.timer
        a.tint = .yellow
        if let start = state.startDate {
            // 경과 시간 표시는 노치가 스스로 1초마다 그린다 (게시를 반복하지 않음)
            a.value = .elapsed(start.addingTimeInterval(-state.accumulated))
        } else {
            a.value = .text(StopwatchEngine.format(elapsed(), hundredths: false))
        }
        a.title = T("스톱워치", "Stopwatch")
        a.subtitle = state.laps.isEmpty ? nil : T("랩 \(state.laps.count)개", "\(state.laps.count) laps")
        a.wing = 64
        a.moduleTab = Self.module
        a.actions = isRunning
            ? [ActivityAction(id: "stopwatch.pause", title: T("일시정지", "Pause")) { [weak self] in self?.pause() },
               ActivityAction(id: "stopwatch.lap", title: T("랩", "Lap")) { [weak self] in self?.lap() }]
            : [ActivityAction(id: "stopwatch.resume", title: T("계속", "Resume"), role: .primary) { [weak self] in self?.start() },
               ActivityAction(id: "stopwatch.reset", title: T("초기화", "Reset"), role: .destructive) { [weak self] in self?.reset() }]
        center.setPersistent(a)
    }

    /// "1:02:03.45" / "02:03.45"
    static func format(_ t: Double, hundredths: Bool = true) -> String {
        let total = max(0, t)
        let s = Int(total)
        let cs = Int((total - Double(s)) * 100)
        let base = s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
        return hundredths ? base + String(format: ".%02d", cs) : base
    }
}

/// 스톱워치 탭: 시작·일시정지·랩·초기화
final class StopwatchModule: NotchModule {
    let id = StopwatchEngine.module
    var title: String { T("스톱워치", "Stopwatch") }
    let symbol = "stopwatch"
    var enabledByDefault: Bool { true }

    private let engine = StopwatchEngine.shared

    func start(context: ModuleContext) { engine.attach(center: context.center) }
    func stop() { engine.detach() }

    func tabView() -> AnyView? { AnyView(StopwatchTab(engine: engine)) }
    var tabContentSize: CGSize { CGSize(width: 500, height: 190) }

    func paletteActions() -> [PaletteAction] {
        let keys = ["stopwatch", "스톱워치", "lap", "랩"]
        var list = [PaletteAction(id: "stopwatch.toggle",
                                  title: engine.isRunning ? T("스톱워치 일시정지", "Pause Stopwatch") : T("스톱워치 시작", "Start Stopwatch"),
                                  symbol: engine.isRunning ? "pause.circle" : "stopwatch", keywords: keys) { [weak self] in self?.engine.toggle() }]
        if !engine.isIdle {
            list.append(PaletteAction(id: "stopwatch.reset", title: T("스톱워치 초기화", "Reset Stopwatch"),
                                      symbol: "arrow.counterclockwise", keywords: keys) { [weak self] in self?.engine.reset() })
        }
        return list
    }

    func selfTest() -> [String] {
        // 드리프트 검사: 시작 시각 기준 계산이 실제 흐른 시간과 맞는지 (상태 파일은 건드리지 않음)
        var s = StopwatchEngine.State()
        let t0 = Date()
        s.startDate = t0.addingTimeInterval(-90.5)
        s.accumulated = 30
        s.laps = [40, 100]
        let elapsed = s.accumulated + Date().timeIntervalSince(s.startDate!)
        let saved = TFStorage.load(StopwatchEngine.State.self, StopwatchEngine.module, "state.json")
        return [
            "elapsed calc: \(String(format: "%.2f", elapsed))s (expected ~120.50)",
            "format: \(StopwatchEngine.format(3723.456)) / \(StopwatchEngine.format(65.4))",
            "lap splits: \(zip(s.laps, [0] + s.laps).map { StopwatchEngine.format($0 - $1) })",
            "saved state: \(saved.map { "running=\($0.startDate != nil) acc=\(Int($0.accumulated))s laps=\($0.laps.count)" } ?? "none")",
        ]
    }
}

private struct StopwatchTab: View {
    @ObservedObject var engine: StopwatchEngine

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Group {
                    if engine.isRunning {
                        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in timeText(engine.elapsed(at: ctx.date)) }
                    } else {
                        timeText(engine.elapsed())
                    }
                }
                .frame(height: 64, alignment: .leading)
                HStack(spacing: 10) {
                    TFRoundButton(symbol: engine.isRunning ? "pause.fill" : "play.fill", tint: .yellow, size: 40,
                                  help: engine.isRunning ? T("일시정지", "Pause") : T("시작", "Start")) { engine.toggle() }
                    TFRoundButton(symbol: "flag.fill", size: 40, help: T("랩", "Lap")) { engine.lap() }
                        .opacity(engine.isRunning ? 1 : 0.35)
                        .disabled(!engine.isRunning)
                    TFRoundButton(symbol: "arrow.counterclockwise", size: 40, help: T("초기화", "Reset")) { engine.reset() }
                        .opacity(engine.isIdle ? 0.35 : 1)
                        .disabled(engine.isIdle)
                }
                Text(T("시작 시각 기준으로 계산해 잠자기·재실행 뒤에도 정확해요", "Counted from the start time, so it stays exact across sleep and relaunch"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 250, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(T("랩", "Laps")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                if engine.state.laps.isEmpty {
                    Text(T("실행 중에 깃발을 누르면 랩이 기록돼요", "Press the flag while running to record a lap"))
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 3) {
                            let laps = engine.state.laps
                            let splits = zip(laps, [0] + laps).map { $0 - $1 }
                            let best = splits.count > 1 ? splits.min() : nil
                            let worst = splits.count > 1 ? splits.max() : nil
                            ForEach(Array(laps.indices.reversed()), id: \.self) { i in
                                HStack {
                                    Text(T("랩 \(i + 1)", "Lap \(i + 1)")).foregroundStyle(.white.opacity(0.6))
                                    Spacer()
                                    Text(StopwatchEngine.format(splits[i]))
                                        .foregroundStyle(splits[i] == best ? .green : (splits[i] == worst ? .red : .white))
                                    Text(StopwatchEngine.format(laps[i])).foregroundStyle(.white.opacity(0.45)).frame(width: 70, alignment: .trailing)
                                }
                                .font(.system(size: 11, design: .rounded)).monospacedDigit()
                                .padding(.vertical, 2)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
    }

    private func timeText(_ t: Double) -> some View {
        Text(StopwatchEngine.format(t))
            .font(.system(size: 44, weight: .light, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(T("경과 시간", "Elapsed") + " " + StopwatchEngine.format(t, hundredths: false))
    }
}

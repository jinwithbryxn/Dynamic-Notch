import Foundation

/// 집중 세션 한 건 (포모도로 집중 단계)
struct FocusSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Date
    var end: Date
    /// 실제로 집중한 초 (일시정지 제외)
    var seconds: Double
    /// 끝까지 마쳤는지 (중간에 멈추거나 건너뛰면 false)
    var completed: Bool
}

/// 집중 기록: 오늘·연속 기록·누적·7일 차트·세션 목록. 로컬 JSON에만 저장한다.
final class FocusLog: ObservableObject {
    static let shared = FocusLog()
    static let module = "pomodoro"
    static let file = "focus-log.json"
    /// 기록을 너무 오래 쌓지 않게 (약 10년치 하루 3세션)
    static let maxSessions = 12000

    @Published private(set) var sessions: [FocusSession] = [] {
        didSet { rebuildIndex() }
    }
    /// 날짜별 합계 (화면이 0.5초마다 다시 그려도 전체를 훑지 않게)
    private var byDay: [String: (seconds: Double, completed: Int, all: Int)] = [:]
    private var loaded = false

    private func rebuildIndex() {
        var m: [String: (seconds: Double, completed: Int, all: Int)] = [:]
        for s in sessions {
            let k = TFDay.key(s.start)
            var v = m[k] ?? (0, 0, 0)
            v.seconds += s.seconds
            v.all += 1
            if s.completed { v.completed += 1 }
            m[k] = v
        }
        byDay = m
    }

    func load(force: Bool = false) {
        guard force || !loaded else { return }
        sessions = TFStorage.load([FocusSession].self, Self.module, Self.file) ?? []
        loaded = true
    }

    func add(_ s: FocusSession) {
        load()
        guard s.seconds >= 1 else { return }
        sessions.append(s)
        if sessions.count > Self.maxSessions { sessions.removeFirst(sessions.count - Self.maxSessions) }
        TFStorage.save(sessions, Self.module, Self.file)
    }

    /// 기록 지우기 (휴지통으로)
    @discardableResult
    func clear() -> Bool {
        let ok = TFStorage.trash(Self.module, Self.file)
        if ok { sessions = [] }
        return ok
    }

    // MARK: 집계

    func seconds(day key: String) -> Double { byDay[key]?.seconds ?? 0 }

    func count(day key: String, completedOnly: Bool = true) -> Int {
        completedOnly ? (byDay[key]?.completed ?? 0) : (byDay[key]?.all ?? 0)
    }

    var todaySeconds: Double { seconds(day: TFDay.key()) }
    var todayCount: Int { count(day: TFDay.key()) }
    var totalSeconds: Double { sessions.reduce(0) { $0 + $1.seconds } }
    var totalCount: Int { sessions.filter(\.completed).count }

    /// 끝낸 집중이 하루 이상 있는 날이 오늘(또는 어제)까지 이어진 날 수
    var streakDays: Int {
        let days = Set(byDay.filter { $0.value.completed > 0 }.keys)
        guard !days.isEmpty else { return 0 }
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        if !days.contains(TFDay.key(day)) {
            guard let y = cal.date(byAdding: .day, value: -1, to: day), days.contains(TFDay.key(y)) else { return 0 }
            day = y
        }
        var n = 0
        while days.contains(TFDay.key(day)) {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }

    /// 최근 n일 (오래된 날 → 오늘) 집중 초
    func lastDays(_ n: Int) -> [(key: String, seconds: Double)] {
        TFDay.lastDays(n).map { ($0, byDay[$0]?.seconds ?? 0) }
    }

    func seconds(year: Int, month: Int? = nil) -> Double {
        byDay.filter { TFDay.isIn($0.key, year: year, month: month) }.values.reduce(0) { $0 + $1.seconds }
    }

    func count(year: Int, month: Int? = nil) -> Int {
        byDay.filter { TFDay.isIn($0.key, year: year, month: month) }.values.reduce(0) { $0 + $1.completed }
    }

    var recent: [FocusSession] { Array(sessions.suffix(20).reversed()) }
}

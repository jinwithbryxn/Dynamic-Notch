import AppKit
import SwiftUI

/// 데이터 사용 기록: 물리 인터페이스(Wi-Fi·이더넷)의 송수신 바이트를 1분마다 읽어 일별 합계를 이 Mac에만 저장한다.
/// 잠든 시간과 측정 사이 빈 시간은 추정하지 않고, 실제로 관측한 시간만 더한다. 최대 1년 보관.
final class NetworkUsageModule: NotchModule {
    let id = "netusage"
    var title: String { T("데이터 사용량", "Data Usage") }
    let symbol = "chart.bar.xaxis"
    var enabledByDefault: Bool { false }

    static let interval: TimeInterval = 60
    let store = NetUsageStore()
    private var timer: Timer?
    private var last: (SysNetCounters, Date)?
    private var observers: [NSObjectProtocol] = []
    private var lastSave = Date.distantPast
    private var context: ModuleContext?
    var isActive: Bool { timer != nil }

    func start(context: ModuleContext) {
        self.context = context
        guard timer == nil else { return }
        store.load()
        last = (SysNetCounters.readPhysical(), Date())
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.sample() }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let nc = NSWorkspace.shared.notificationCenter
        // 잠들기 직전까지는 더하고, 깨면 기준을 새로 잡는다 (잠든 시간은 세지 않음)
        observers.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sample(); self?.last = nil; self?.store.save()
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.last = (SysNetCounters.readPhysical(), Date())
        })
    }

    func stop() {
        if timer != nil { sample() }
        timer?.invalidate(); timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        last = nil
        store.save()
        context = nil
    }

    /// 지난 측정 이후 늘어난 바이트를 오늘에 더한다.
    func sample() {
        let now = Date()
        let current = SysNetCounters.readPhysical()
        defer { last = (current, now) }
        guard let (old, at) = last else { return }
        let dt = now.timeIntervalSince(at)
        guard dt > 0 else { return }
        var rx: UInt64 = 0, tx: UInt64 = 0
        for (name, b) in current.byInterface {
            // 새로 생긴 인터페이스나 카운터가 줄어든(재설정된) 인터페이스는 이번엔 기준만 잡는다
            guard let o = old.byInterface[name], b.rx >= o.rx, b.tx >= o.tx else { continue }
            rx += b.rx - o.rx
            tx += b.tx - o.tx
        }
        // 타이머가 밀린 빈 시간은 관측 시간에 넣지 않는다
        let observed = dt <= Self.interval * 2.5 ? dt : 0
        store.add(rx: rx, tx: tx, seconds: observed, at: now)
        if now.timeIntervalSince(lastSave) > 300 { store.save(); lastSave = now }
    }

    func tabView() -> AnyView? { AnyView(NetUsageTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 480, height: 252) }

    func paletteActions() -> [PaletteAction] {
        let today = store.total(.today)
        return [PaletteAction(id: "netusage.today",
                              title: T("오늘 데이터 사용량", "Data used today"),
                              subtitle: "↓ \(SysFmt.bytes(Int64(today.rx)))  ↑ \(SysFmt.bytes(Int64(today.tx)))",
                              symbol: symbol, keywords: ["data", "usage", "network", "데이터", "사용량", "트래픽"]) { [weak self] in
            guard let self else { return }
            self.context?.openTab(self.id)
        }]
    }

    func settingsView() -> AnyView? { AnyView(NetUsageSettings(module: self)) }

    func selfTest() -> [String] {
        let a = SysNetCounters.readPhysical()
        Thread.sleep(forTimeInterval: 1)
        let b = SysNetCounters.readPhysical()
        var lines = ["physical interfaces: " + a.interfaces.sorted().joined(separator: ", ")]
        for name in b.byInterface.keys.sorted() {
            guard let x = b.byInterface[name], x.rx > 0 || x.tx > 0 else { continue }
            let o = a.byInterface[name] ?? x
            lines.append("  \(name): rx \(SysFmt.bytes(Int64(x.rx))) tx \(SysFmt.bytes(Int64(x.tx))) · 1 s delta rx \(x.rx &- o.rx) B tx \(x.tx &- o.tx) B")
        }
        let s = NetUsageStore()
        s.load()
        lines.append("store file: \(NetUsageStore.fileURL.path) days stored \(s.days.count)")
        let t = s.total(.today)
        lines.append("today stored rx \(SysFmt.bytes(Int64(t.rx))) tx \(SysFmt.bytes(Int64(t.tx))) observed \(SysFmt.seconds(t.seconds))")
        // 합계 규칙 점검 (메모리 안의 임시 저장소, 파일에 쓰지 않음)
        let probe = NetUsageStore()
        let now = Date()
        if let old = Calendar.current.date(byAdding: .day, value: -400, to: now) { probe.add(rx: 999, tx: 999, seconds: 60, at: old) }
        probe.add(rx: 10, tx: 1, seconds: 60, at: now)
        probe.add(rx: 5, tx: 2, seconds: 60, at: now)
        probe.add(rx: 1, tx: 1, seconds: 0, at: now.addingTimeInterval(1))
        let today = probe.total(.today, now: now.addingTimeInterval(1))
        lines.append("store rule check: \(today.rx == 16 && today.tx == 4 && today.seconds == 120 && probe.days.count == 1 ? "pass" : "FAIL") (old days pruned, same-day merge)")
        return lines
    }
}

/// 일별 합계 저장소 (JSON 파일, 이 Mac에만)
final class NetUsageStore: ObservableObject {
    struct Day: Codable, Equatable {
        var day: String      // yyyy-MM-dd (현지 날짜)
        var rx: UInt64
        var tx: UInt64
        var seconds: Double
    }

    enum Period: CaseIterable { case today, week, month, year }

    @Published private(set) var days: [Day] = []

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.dynamicnotch.app", isDirectory: true)
            .appendingPathComponent("netusage.json")
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ date: Date) -> String { dayFormatter.string(from: date) }
    static func date(_ key: String) -> Date? { dayFormatter.date(from: key) }

    func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let list = try? JSONDecoder().decode([Day].self, from: data) else { return }
        days = list
    }

    func save() {
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(days) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func add(rx: UInt64, tx: UInt64, seconds: Double, at date: Date) {
        let k = Self.key(date)
        if let i = days.lastIndex(where: { $0.day == k }) {
            days[i].rx += rx; days[i].tx += tx; days[i].seconds += seconds
        } else {
            days.append(Day(day: k, rx: rx, tx: tx, seconds: seconds))
            // 1년(366일)보다 오래된 날은 버린다
            if let cutoff = Calendar.current.date(byAdding: .day, value: -366, to: date) {
                let ck = Self.key(cutoff)
                days.removeAll { $0.day < ck }
            }
        }
    }

    func total(_ period: Period, now: Date = Date()) -> (rx: UInt64, tx: UInt64, seconds: Double) {
        let cal = Calendar.current
        let start: Date
        switch period {
        case .today: start = cal.startOfDay(for: now)
        case .week: start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .month: start = cal.dateInterval(of: .month, for: now)?.start ?? now
        case .year: start = cal.dateInterval(of: .year, for: now)?.start ?? now
        }
        let sk = Self.key(start)
        return days.filter { $0.day >= sk }.reduce((0, 0, 0)) { ($0.0 + $1.rx, $0.1 + $1.tx, $0.2 + $1.seconds) }
    }

    var firstDay: Date? { days.first.flatMap { Self.date($0.day) } }

    /// 기록 지우기: 파일은 휴지통으로 보낸다 (영구 삭제하지 않음)
    func clear() {
        days.removeAll()
        let url = Self.fileURL
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }
}

// MARK: - 탭

private struct NetUsageTab: View {
    let module: NetworkUsageModule
    @ObservedObject var store: NetUsageStore
    @State private var confirmClear = false

    init(module: NetworkUsageModule) {
        self.module = module
        _store = ObservedObject(wrappedValue: module.store)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(T("데이터 사용량", "Data usage")).font(.system(size: 14, weight: .semibold))
                    Text(sinceText).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                if confirmClear {
                    Text(T("기록을 지울까요?", "Clear history?")).font(.system(size: 11))
                    SysPillButton(title: T("지우기", "Clear"), tint: .red, prominent: true) { store.clear(); confirmClear = false }
                    SysPillButton(title: T("취소", "Cancel")) { confirmClear = false }
                } else {
                    SysPillButton(title: T("기록 지우기", "Clear history"), symbol: "trash",
                                  help: T("기록 파일을 휴지통으로 보냅니다", "Moves the history file to the Trash")) { confirmClear = true }
                }
            }
            HStack(spacing: 6) {
                ForEach(NetUsageStore.Period.allCases, id: \.self) { p in periodCard(p) }
            }
            .frame(height: 78)
            SysCard {
                VStack(alignment: .leading, spacing: 4) {
                    SysHeader(text: T("최근 14일", "Last 14 days"))
                    chart
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear { if module.isActive { module.sample() } }
    }

    private var sinceText: String {
        guard let first = store.firstDay else {
            return T("아직 기록 없음 · 켜 둔 동안 1분마다 기록", "No history yet · recorded every minute while enabled")
        }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        let total = store.days.reduce(0) { $0 + $1.seconds }
        return T("\(f.string(from: first))부터 · 실제 관측 \(SysFmt.seconds(total)) (잠든 시간 제외)",
                 "Since \(f.string(from: first)) · observed \(SysFmt.seconds(total)) (sleep excluded)")
    }

    private func name(_ p: NetUsageStore.Period) -> String {
        switch p {
        case .today: return T("오늘", "Today")
        case .week: return T("이번 주", "This week")
        case .month: return T("이번 달", "This month")
        case .year: return T("올해", "This year")
        }
    }

    private func periodCard(_ p: NetUsageStore.Period) -> some View {
        let t = store.total(p)
        return SysCard {
            VStack(alignment: .leading, spacing: 3) {
                Text(name(p)).font(.system(size: 11, weight: .semibold))
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.cyan)
                    Text(SysFmt.bytes(Int64(t.rx))).font(.system(size: 11, design: .rounded)).monospacedDigit()
                }
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up").font(.system(size: 8, weight: .bold)).foregroundStyle(.pink)
                    Text(SysFmt.bytes(Int64(t.tx))).font(.system(size: 11, design: .rounded)).monospacedDigit()
                }
                Text(SysFmt.seconds(t.seconds)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let keys: [String] = (0..<14).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.map(NetUsageStore.key)
        let map = Dictionary(store.days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let values = keys.map { (map[$0]?.rx ?? 0, map[$0]?.tx ?? 0) }
        let peak = max(1, values.map { $0.0 + $0.1 }.max() ?? 1)
        return GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    let h = geo.size.height - 12
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle().fill(Color.pink.opacity(0.8)).frame(height: h * CGFloat(Double(v.1) / Double(peak)))
                        Rectangle().fill(Color.cyan.opacity(0.85)).frame(height: h * CGFloat(Double(v.0) / Double(peak)))
                        Text(String(keys[i].suffix(2))).font(.system(size: 7.5)).foregroundStyle(.white.opacity(0.4)).frame(height: 12)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(keys[i]) ↓ \(SysFmt.bytes(Int64(v.0))) ↑ \(SysFmt.bytes(Int64(v.1)))")
                }
            }
        }
    }
}

private struct NetUsageSettings: View {
    let module: NetworkUsageModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(T("Wi-Fi와 이더넷(en*)의 바이트 수만 1분마다 읽어 일별 합계를 이 Mac에 저장합니다(최대 1년). 앱별·사이트별 집계와 한도 경고는 없습니다.",
                   "Reads only Wi-Fi and Ethernet (en*) byte counters every minute and keeps daily totals on this Mac (up to one year). No per-app or per-site totals and no data cap alerts."))
            Text(T("저장 위치: ", "Stored at: ") + NetUsageStore.fileURL.path).font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

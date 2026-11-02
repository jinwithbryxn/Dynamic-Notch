import AppKit
import SwiftUI

/// 앱 사용 시간 저장소: 날짜별 [번들 ID: 초]. 이 Mac에만 저장한다.
final class ScreenTimeStore: ObservableObject {
    static let shared = ScreenTimeStore()
    static let module = "screentime"
    static let file = "usage.json"

    private struct FileData: Codable {
        var days: [String: [String: Double]]
        var names: [String: String]
    }

    @Published private(set) var days: [String: [String: Double]] = [:]
    private(set) var names: [String: String] = [:]
    private var loaded = false
    private var dirty = false

    func load(force: Bool = false) {
        guard force || !loaded else { return }
        let f = TFStorage.load(FileData.self, Self.module, Self.file)
        days = f?.days ?? [:]
        names = f?.names ?? [:]
        loaded = true
        dirty = false
    }

    func add(_ bundleID: String, name: String, seconds: Double) {
        load()
        guard seconds > 0 else { return }
        days[TFDay.key(), default: [:]][bundleID, default: 0] += seconds
        names[bundleID] = name
        dirty = true
    }

    func saveIfNeeded() {
        guard dirty else { return }
        dirty = false
        // 3년보다 오래된 날은 정리
        let cutoff = TFDay.key(Calendar.current.date(byAdding: .day, value: -1100, to: Date()) ?? Date())
        days = days.filter { $0.key >= cutoff }
        TFStorage.save(FileData(days: days, names: names), Self.module, Self.file)
    }

    @discardableResult
    func clear() -> Bool {
        let ok = TFStorage.trash(Self.module, Self.file)
        if ok { days = [:]; names = [:]; dirty = false }
        return ok
    }

    func name(_ id: String) -> String { names[id] ?? TFApps.name(id) }

    // MARK: 집계

    func total(_ keys: [String]) -> Double {
        keys.reduce(0) { $0 + (days[$1]?.values.reduce(0, +) ?? 0) }
    }

    func apps(_ keys: [String]) -> [(id: String, seconds: Double)] {
        var sum: [String: Double] = [:]
        for k in keys { for (id, s) in days[k] ?? [:] { sum[id, default: 0] += s } }
        return sum.map { ($0.key, $0.value) }.sorted { $0.seconds > $1.seconds }
    }

    /// 사용한 날 기준 하루 평균
    func dailyAverage(_ keys: [String]) -> Double {
        let used = keys.filter { (days[$0]?.values.reduce(0, +) ?? 0) > 0 }
        return used.isEmpty ? 0 : total(used) / Double(used.count)
    }

    var allKeys: [String] { days.keys.sorted() }

    /// 이번 주(달력 기준) 날짜 키
    var weekKeys: [String] {
        let cal = Calendar.current
        guard let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return [TFDay.key()] }
        let n = (cal.dateComponents([.day], from: start, to: cal.startOfDay(for: Date())).day ?? 0) + 1
        return (0..<n).compactMap { cal.date(byAdding: .day, value: $0, to: start) }.map { TFDay.key($0) }
    }

    func keys(year: Int, month: Int? = nil) -> [String] {
        days.keys.filter { TFDay.isIn($0, year: year, month: month) }
    }
}

/// Screen Time: 앞에 있는 앱의 사용 시간을 센다. 5분 넘게 입력이 없거나 잠금·화면 보호기·이 앱 자신은 빼고 센다.
/// 백그라운드 감시라 기본은 꺼짐.
final class ScreenTimeModule: NotchModule {
    let id = ScreenTimeStore.module
    var title: String { T("Screen Time", "Screen Time") }
    let symbol = "hourglass"
    var enabledByDefault: Bool { false }

    static let idleCutoff: TimeInterval = 300
    private static let excluded: Set<String> = ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine",
                                                "com.apple.ScreenSaver.legacyScreenSaver"]

    private let store = ScreenTimeStore.shared
    private var current: (id: String, name: String)?
    private var lastTick = Date()
    private var paused = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastSave = Date()
    private var seenClearedAt: Double = 0

    func start(context: ModuleContext) {
        store.load()
        seenClearedAt = ModuleDefaults(module: id).double("clearedAt", default: 0)
        guard timer == nil, !AppSettings.isHelper else { return }
        lastTick = Date()
        setCurrent(NSWorkspace.shared.frontmostApplication)
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            self?.credit()
            self?.setCurrent(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.credit()
                self?.paused = true
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.lastTick = Date()
                self?.paused = false
            })
        }
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.credit() }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        credit()
        timer?.invalidate()
        timer = nil
        for o in observers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        observers = []
        store.saveIfNeeded()
        current = nil
    }

    func settingsChanged() {
        let cleared = ModuleDefaults(module: id).double("clearedAt", default: 0)
        if cleared > seenClearedAt {
            seenClearedAt = cleared
            store.load(force: true)
        }
    }

    private func setCurrent(_ app: NSRunningApplication?) {
        guard let app, let bid = app.bundleIdentifier,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !Self.excluded.contains(bid) else { current = nil; return }
        current = (bid, app.localizedName ?? bid)
    }

    /// 마지막 확인 뒤 흐른 시간을 앞 앱에 준다
    private func credit() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        guard timer != nil, !paused, dt > 0, dt < 60, let cur = current else { return }
        guard !TFSystem.isScreenLocked, !TFSystem.isScreenSaverRunning else { return }
        let idle = TFSystem.idleSeconds
        let counted = idle < Self.idleCutoff ? dt : max(0, dt - (idle - Self.idleCutoff))
        store.add(cur.id, name: cur.name, seconds: counted)
        if now.timeIntervalSince(lastSave) >= 60 {
            lastSave = now
            store.saveIfNeeded()
        }
    }

    func tabView() -> AnyView? { AnyView(ScreenTimeTab(store: store)) }
    var tabContentSize: CGSize { CGSize(width: 600, height: 240) }

    func settingsView() -> AnyView? { AnyView(ScreenTimeSettings()) }

    func selfTest() -> [String] {
        store.load(force: true)
        let front = NSWorkspace.shared.frontmostApplication
        return [
            "frontmost: \(front?.bundleIdentifier ?? "-") (\(front?.localizedName ?? "-"))",
            "idle \(Int(TFSystem.idleSeconds))s (cutoff \(Int(Self.idleCutoff))s), locked \(TFSystem.isScreenLocked), screensaver \(TFSystem.isScreenSaverRunning)",
            "stored days \(store.days.count), today \(TFFormat.duration(store.total([TFDay.key()]))), week \(TFFormat.duration(store.total(store.weekKeys)))",
            "week keys: \(store.weekKeys.first ?? "-") … \(store.weekKeys.last ?? "-")",
        ]
    }
}

// MARK: - 요약 (M-C-010): 지난달 영수증·올해 요약, 텍스트로 복사 (게시하지 않음)

enum UsageSummary {
    struct Card {
        var title: String
        var lines: [(String, String)]
        var hasData: Bool
    }

    static func lastMonth() -> Card {
        let cal = Calendar.current
        let d = cal.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let y = cal.component(.year, from: d), m = cal.component(.month, from: d)
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("yMMMM")
        return card(title: T("\(f.string(from: d)) 영수증", "\(f.string(from: d)) Receipt"), year: y, month: m)
    }

    static func thisYear() -> Card {
        let y = Calendar.current.component(.year, from: Date())
        return card(title: T("\(y)년 요약", "\(y) Wrapped"), year: y, month: nil)
    }

    private static func card(title: String, year: Int, month: Int?) -> Card {
        let focus = FocusLog.shared, screen = ScreenTimeStore.shared, activity = ActivityStore.shared
        focus.load(); screen.load(); activity.load()
        let fs = focus.seconds(year: year, month: month), fc = focus.count(year: year, month: month)
        let keys = screen.keys(year: year, month: month)
        let st = screen.total(keys)
        let top = screen.apps(keys).prefix(3)
        let act = activity.total(year: year, month: month)
        var lines: [(String, String)] = []
        lines.append((T("집중", "Focus"), fc > 0 || fs > 0 ? T("\(TFFormat.duration(fs)) · \(fc)세션", "\(TFFormat.duration(fs)) · \(fc) sessions") : "—"))
        lines.append((T("화면 사용", "Screen time"), st > 0 ? TFFormat.duration(st) : "—"))
        for (i, a) in top.enumerated() { lines.append(("  \(i + 1). \(screen.name(a.id))", TFFormat.duration(a.seconds))) }
        lines.append((T("입력 시간", "Active input"), act.activeSeconds > 0 ? TFFormat.duration(act.activeSeconds) : "—"))
        lines.append((T("키 입력", "Keystrokes"), act.keys > 0 ? TFFormat.number(act.keys) : "—"))
        lines.append((T("커서 이동", "Cursor distance"), act.distanceMM > 0 ? ActivityRingModule.km(act.distanceMM / 1000) : "—"))
        return Card(title: title, lines: lines, hasData: fs > 0 || st > 0 || act.activeSeconds > 0)
    }

    static func text(_ c: Card) -> String {
        ([c.title, String(repeating: "-", count: 24)] + c.lines.map { "\($0.0)  \($0.1)" } + ["", "Dynamic Notch"]).joined(separator: "\n")
    }
}

// MARK: - 화면

private enum ScreenTimeRange: String, Hashable { case today, week, all, summary }
private let screenTimeRangeKey = "module.screentime.range"

private struct ScreenTimeTab: View {
    @ObservedObject var store: ScreenTimeStore
    @State private var range: ScreenTimeRange = .today

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TFSegment(items: [(.today, T("오늘", "Today")), (.week, T("이번 주", "This Week")), (.all, T("전체", "All Time")),
                              (.summary, T("요약", "Summary"))], selection: Binding(get: { range }, set: {
                                range = $0
                                UserDefaults.standard.set($0.rawValue, forKey: screenTimeRangeKey)
                              }))
            if range == .summary {
                SummaryView()
            } else if store.days.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(T("아직 기록이 없어요", "No usage recorded yet")).font(.system(size: 15, weight: .semibold))
                    Text(T("기능을 켜 두면 앞에 있는 앱의 사용 시간을 이 Mac에만 기록해요. 5분 넘게 입력이 없거나 잠금·화면 보호기 중에는 세지 않아요.",
                           "While on, the time of the app in front is recorded on this Mac only. Idle (5+ min), lock and screen saver time isn't counted."))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .top, spacing: 18) {
                    usageList.frame(width: 300)
                    WeekBars(store: store)
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            store.load()
            range = ScreenTimeRange(rawValue: UserDefaults.standard.string(forKey: screenTimeRangeKey) ?? "") ?? .today
        }
    }

    private var keys: [String] {
        switch range {
        case .today: return [TFDay.key()]
        case .week: return store.weekKeys
        default: return store.allKeys
        }
    }

    private var usageList: some View {
        let k = keys
        let total = store.total(k)
        let apps = Array(store.apps(k).prefix(5))
        let maxSec = apps.first?.seconds ?? 1
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(TFFormat.duration(total)).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                if range != .today {
                    Text(T("하루 평균 \(TFFormat.duration(store.dailyAverage(k)))", "\(TFFormat.duration(store.dailyAverage(k))) daily avg"))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                }
            }
            if apps.isEmpty {
                Text(T("이 기간에는 기록이 없어요", "Nothing recorded in this range")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(apps, id: \.id) { a in
                HStack(spacing: 7) {
                    if let icon = TFApps.icon(a.id) { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                    else { Image(systemName: "app").frame(width: 18, height: 18) }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(store.name(a.id)).font(.system(size: 11.5)).lineLimit(1)
                            Spacer()
                            Text(TFFormat.duration(a.seconds)).font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.8))
                        }
                        GeometryReader { g in
                            Capsule().fill(Color.white.opacity(0.55)).frame(width: max(2, g.size.width * CGFloat(a.seconds / maxSec)), height: 3)
                        }
                        .frame(height: 3)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// 최근 7일 막대 (상위 3개 앱 색 + 기타)
private struct WeekBars: View {
    @ObservedObject var store: ScreenTimeStore
    static let colors: [Color] = [Color(red: 0.35, green: 0.6, blue: 1.0), Color(red: 1.0, green: 0.6, blue: 0.25), Color(red: 0.55, green: 0.9, blue: 0.45)]

    var body: some View {
        let days = TFDay.lastDays(7)
        let top = Array(store.apps(days).prefix(3).map(\.id))
        let totals = days.map { store.total([$0]) }
        let maxSec = max(totals.max() ?? 0, 3600)
        VStack(alignment: .leading, spacing: 6) {
            Text(T("최근 7일", "Last 7 days")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            HStack(alignment: .bottom, spacing: 9) {
                ForEach(days.indices, id: \.self) { i in
                    let k = days[i]
                    let byApp = store.days[k] ?? [:]
                    let parts = top.map { byApp[$0] ?? 0 }
                    let other = max(0, totals[i] - parts.reduce(0, +))
                    VStack(spacing: 3) {
                        VStack(spacing: 1) {
                            Rectangle().fill(Color.white.opacity(0.3)).frame(height: h(other, maxSec))
                            ForEach(Array(parts.indices.reversed()), id: \.self) { j in
                                Rectangle().fill(Self.colors[j]).frame(height: h(parts[j], maxSec))
                            }
                        }
                        .frame(width: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        Text(TFDay.weekdayShort(k)).font(.system(size: 9.5)).foregroundStyle(k == TFDay.key() ? .white : .white.opacity(0.55))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(k) \(TFFormat.duration(totals[i]))")
                }
            }
            .frame(height: 100, alignment: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(top.indices, id: \.self) { j in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(Self.colors[j]).frame(width: 8, height: 8)
                        Text(store.name(top[j])).font(.system(size: 10)).lineLimit(1)
                    }
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.3)).frame(width: 8, height: 8)
                    Text(T("기타", "Other")).font(.system(size: 10))
                }
            }
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func h(_ s: Double, _ maxSec: Double) -> CGFloat { s <= 0 ? 0 : max(1.5, 76 * CGFloat(s / maxSec)) }
}

private struct SummaryView: View {
    @State private var copied: String?

    var body: some View {
        let cards = [UsageSummary.lastMonth(), UsageSummary.thisYear()]
        HStack(alignment: .top, spacing: 12) {
            ForEach(cards.indices, id: \.self) { i in
                let c = cards[i]
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(c.title).font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        TFPillButton(title: copied == c.title ? T("복사됨", "Copied") : T("복사", "Copy"), symbol: "doc.on.doc",
                                     help: T("요약을 텍스트로 복사 (게시하지 않음)", "Copy the summary as text (nothing is posted)")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(UsageSummary.text(c), forType: .string)
                            copied = c.title
                        }
                        .disabled(!c.hasData)
                    }
                    if c.hasData {
                        ForEach(c.lines.indices, id: \.self) { j in
                            HStack {
                                Text(c.lines[j].0).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                                Spacer()
                                Text(c.lines[j].1).monospacedDigit()
                            }
                            .font(.system(size: 10.5, design: .monospaced))
                        }
                    } else {
                        Text(T("이 기간의 기록이 아직 없어요. 포모도로·Screen Time·활동 링 기록이 쌓이면 보여요.",
                               "No records for this period yet. It fills in from Pomodoro, Screen Time and Activity data."))
                            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
            }
        }
    }
}

private struct ScreenTimeSettings: View {
    @StateObject private var prefs = TFPrefs(module: ScreenTimeStore.module)
    @State private var cleared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TFSettingsNote(text: T("앞에 있는 앱에 시간을 줘요(웹사이트별 집계 없음). 5분 넘게 입력이 없으면 멈추고, 화면 잠금·화면 보호기·이 앱 자신은 세지 않아요. 기록은 이 Mac에만 저장하고 업로드하지 않아요.",
                                   "Time goes to the app in front (no per-website tracking). Counting pauses after 5 minutes without input and skips the lock screen, screen saver and this app. Data stays on this Mac."))
            Button(cleared ? T("휴지통으로 옮겼어요", "Moved to the Trash") : T("Screen Time 기록 지우기 (휴지통으로)", "Clear Screen Time History (to Trash)")) {
                if ScreenTimeStore.shared.clear() {
                    cleared = true
                    prefs.defaults.set(Date().timeIntervalSince1970, "clearedAt")
                }
            }
            .disabled(cleared)
        }
    }
}

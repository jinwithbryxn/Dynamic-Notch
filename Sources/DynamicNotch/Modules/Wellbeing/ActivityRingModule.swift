import AppKit
import SwiftUI

/// 하루 활동 합계 (키 내용은 저장하지 않고 횟수만)
struct ActivityDay: Codable, Equatable {
    var distanceMM: Double = 0
    var keys: Int = 0
    var clicks: Int = 0
    var activeSeconds: Double = 0
}

/// 활동 기록 저장소: 날짜별 합계와 이미 알린 이정표. 이 Mac에만 저장한다.
final class ActivityStore: ObservableObject {
    static let shared = ActivityStore()
    static let module = "activity"
    static let file = "activity.json"

    private struct FileData: Codable {
        var days: [String: ActivityDay]
        var milestones: [String]
    }

    @Published private(set) var days: [String: ActivityDay] = [:]
    private(set) var milestones: Set<String> = []
    private var loaded = false
    private var dirty = false

    func load(force: Bool = false) {
        guard force || !loaded else { return }
        let f = TFStorage.load(FileData.self, Self.module, Self.file)
        days = f?.days ?? [:]
        milestones = Set(f?.milestones ?? [])
        loaded = true
        dirty = false
    }

    func saveIfNeeded() {
        guard dirty else { return }
        dirty = false
        // 2년보다 오래된 날은 정리
        let cutoff = TFDay.key(Calendar.current.date(byAdding: .day, value: -730, to: Date()) ?? Date())
        days = days.filter { $0.key >= cutoff }
        TFStorage.save(FileData(days: days, milestones: Array(milestones)), Self.module, Self.file)
    }

    func mutateToday(_ f: (inout ActivityDay) -> Void) {
        load()
        let key = TFDay.key()
        var d = days[key] ?? ActivityDay()
        f(&d)
        days[key] = d
        dirty = true
    }

    func markMilestone(_ id: String) -> Bool {
        guard !milestones.contains(id) else { return false }
        milestones.insert(id)
        dirty = true
        return true
    }

    @discardableResult
    func clear() -> Bool {
        let ok = TFStorage.trash(Self.module, Self.file)
        if ok { days = [:]; milestones = []; dirty = false }
        return ok
    }

    var today: ActivityDay { days[TFDay.key()] ?? ActivityDay() }

    var totals: ActivityDay {
        days.values.reduce(into: ActivityDay()) {
            $0.distanceMM += $1.distanceMM; $0.keys += $1.keys; $0.clicks += $1.clicks; $0.activeSeconds += $1.activeSeconds
        }
    }

    func total(year: Int, month: Int? = nil) -> ActivityDay {
        days.filter { TFDay.isIn($0.key, year: year, month: month) }.values.reduce(into: ActivityDay()) {
            $0.distanceMM += $1.distanceMM; $0.keys += $1.keys; $0.clicks += $1.clicks; $0.activeSeconds += $1.activeSeconds
        }
    }

    // MARK: 목표

    struct Goals {
        var meters: Double
        var keys: Int
        var activeMinutes: Int
    }

    static var goals: Goals {
        let d = ModuleDefaults(module: module)
        return Goals(meters: Double(max(10, d.int("goalMeters", default: 300))),
                     keys: max(100, d.int("goalKeys", default: 5000)),
                     activeMinutes: max(10, d.int("goalMinutes", default: 240)))
    }

    /// 링 세 개의 채움 (이동·타이핑·입력 시간)
    static func progress(_ d: ActivityDay, keysAvailable: Bool = true) -> (move: Double, type: Double, focus: Double) {
        let g = goals
        return (d.distanceMM / 1000 / g.meters, keysAvailable ? Double(d.keys) / Double(g.keys) : 0, d.activeSeconds / 60 / Double(g.activeMinutes))
    }

    func goalsMet(_ d: ActivityDay) -> Bool {
        let p = Self.progress(d)
        return p.move >= 1 && p.type >= 1 && p.focus >= 1
    }

    /// 세 목표를 모두 채운 날이 오늘(또는 어제)까지 이어진 날 수
    var streakDays: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        if !(days[TFDay.key(day)].map(goalsMet) ?? false) {
            guard let y = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = y
        }
        var n = 0
        while let d = days[TFDay.key(day)], goalsMet(d) {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }
}

/// 활동 링: 커서 이동 거리(권한 불필요, 0.5초마다 위치 확인) · 키 입력 수(입력 모니터링 권한) · 실제 입력 시간(유휴 시간).
/// 백그라운드 감시와 권한이 필요해 기본은 꺼짐.
final class ActivityRingModule: NotchModule {
    let id = ActivityStore.module
    var title: String { T("활동 링", "Activity Rings") }
    let symbol = "circle.circle"
    var enabledByDefault: Bool { false }

    private let store = ActivityStore.shared
    private var context: ModuleContext?
    private var sampler: Timer?
    private var slowTimer: Timer?
    private var lastPoint: NSPoint?
    private var clickMonitor: Any?
    private var keySubscribed = false
    private var mmPerPoint: [CGDirectDisplayID: Double] = [:]
    private var lastActiveCheck = Date()
    private var lastSave = Date()
    private var seenClearedAt: Double = 0

    static let milestoneMeters: [Double] = [1_000, 5_000, 10_000, 42_195, 100_000, 500_000, 1_000_000]
    static let milestoneKeys: [Int] = [10_000, 100_000, 500_000, 1_000_000, 5_000_000]
    static let milestoneHours: [Double] = [10, 50, 100, 500, 1000]

    func start(context: ModuleContext) {
        self.context = context
        store.load()
        seenClearedAt = ModuleDefaults(module: id).double("clearedAt", default: 0)
        guard sampler == nil, !AppSettings.isHelper else { return }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.sampleMouse() }
        t.tolerance = 0.15
        RunLoop.main.add(t, forMode: .common)
        sampler = t
        let slow = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.slowTick() }
        slow.tolerance = 1
        RunLoop.main.add(slow, forMode: .common)
        slowTimer = slow
        lastActiveCheck = Date()
        // 클릭 수는 전역 마우스 감시로 센다 (권한 불필요)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.store.mutateToday { $0.clicks += 1 }
        }
        subscribeKeys()
    }

    func stop() {
        sampler?.invalidate(); sampler = nil
        slowTimer?.invalidate(); slowTimer = nil
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
        TFKeyTap.shared.remove("activity")
        keySubscribed = false
        lastPoint = nil
        store.saveIfNeeded()
        context = nil
    }

    func settingsChanged() {
        // 도우미에서 기록을 지웠으면 다시 읽는다
        let cleared = ModuleDefaults(module: id).double("clearedAt", default: 0)
        if cleared > seenClearedAt {
            seenClearedAt = cleared
            store.load(force: true)
        }
    }

    private func subscribeKeys() {
        guard !keySubscribed else { return }
        keySubscribed = TFKeyTap.shared.add("activity") { [weak self] _ in self?.store.mutateToday { $0.keys += 1 } }
    }

    private func sampleMouse() {
        let p = NSEvent.mouseLocation
        defer { lastPoint = p }
        guard let last = lastPoint, p != last else { return }
        let d = hypot(p.x - last.x, p.y - last.y)
        // 화면 사이 순간 이동은 빼고 센다
        guard d < 2500 else { return }
        store.mutateToday { $0.distanceMM += d * mm(at: p) }
    }

    /// 커서가 있는 화면의 1pt 실제 길이(mm)
    private func mm(at p: NSPoint) -> Double {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) ?? NSScreen.main,
              let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return 0.25 }
        let id = CGDirectDisplayID(num.uint32Value)
        if let v = mmPerPoint[id] { return v }
        let size = CGDisplayScreenSize(id)
        let v = size.width > 0 ? Double(size.width) / Double(screen.frame.width) : 0.25
        mmPerPoint[id] = v
        return v
    }

    private func slowTick() {
        let now = Date()
        let dt = min(10, now.timeIntervalSince(lastActiveCheck))
        lastActiveCheck = now
        // 최근 몇 초 안에 입력이 있었으면 그만큼 입력 시간으로 센다
        if TFSystem.idleSeconds < dt + 0.5, !TFSystem.isScreenLocked {
            store.mutateToday { $0.activeSeconds += dt }
        }
        if !keySubscribed { subscribeKeys() }
        if now.timeIntervalSince(lastSave) >= 60 {
            lastSave = now
            checkMilestones()
            store.saveIfNeeded()
        }
    }

    private func checkMilestones() {
        let t = store.totals
        for m in Self.milestoneMeters where t.distanceMM / 1000 >= m && store.markMilestone("m\(Int(m))") {
            announce(T("커서가 누적 \(Self.km(m))를 움직였어요", "Your cursor has traveled \(Self.km(m))"), symbol: "cursorarrow.motionlines")
        }
        for k in Self.milestoneKeys where t.keys >= k && store.markMilestone("k\(k)") {
            announce(T("누적 \(TFFormat.number(k))번 입력했어요", "\(TFFormat.number(k)) keystrokes in total"), symbol: "keyboard")
        }
        for h in Self.milestoneHours where t.activeSeconds / 3600 >= h && store.markMilestone("h\(Int(h))") {
            announce(T("누적 입력 시간 \(Int(h))시간", "\(Int(h)) hours of active input"), symbol: "clock.badge.checkmark")
        }
    }

    private func announce(_ title: String, symbol: String) {
        context?.notice(title, T("활동 이정표", "Activity milestone"), symbol: symbol, tint: .green, tab: id, duration: 4)
    }

    static func km(_ meters: Double) -> String {
        meters >= 1000 ? String(format: meters.truncatingRemainder(dividingBy: 1000) == 0 ? "%.0f km" : "%.1f km", meters / 1000)
                       : String(format: "%.0f m", meters)
    }

    func tabView() -> AnyView? { AnyView(ActivityRingTab(store: store)) }
    var tabContentSize: CGSize { CGSize(width: 500, height: 196) }

    func settingsView() -> AnyView? { AnyView(ActivityRingSettings()) }

    func selfTest() -> [String] {
        store.load(force: true)
        let p = NSEvent.mouseLocation
        let screens = NSScreen.screens.compactMap { s -> String? in
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let mm = CGDisplayScreenSize(CGDirectDisplayID(n.uint32Value))
            return String(format: "%.0fx%.0fpt %.0fmm wide (%.3f mm/pt)", s.frame.width, s.frame.height, mm.width, mm.width / s.frame.width)
        }
        let today = store.today
        return [
            "cursor at \(Int(p.x)),\(Int(p.y)); screens: \(screens.joined(separator: "; "))",
            "idle seconds: \(Int(TFSystem.idleSeconds)), screen locked: \(TFSystem.isScreenLocked)",
            "input monitoring (key count): \(TFKeyTap.hasPermission ? "granted" : "not granted -> key ring unsupported")",
            String(format: "today: %.1f m, %d keys, %d clicks, %.0f min active; days stored %d", today.distanceMM / 1000, today.keys, today.clicks, today.activeSeconds / 60, store.days.count),
        ]
    }
}

// MARK: - 화면

/// 세 겹 링 (바깥: 이동, 가운데: 타이핑, 안: 입력 시간)
struct ActivityRingsGlyph: View {
    var move: Double
    var type: Double
    var focus: Double
    var size: CGFloat = 120
    var typeAvailable = true

    static let moveTint = Color(red: 1.0, green: 0.27, blue: 0.4)
    static let typeTint = Color(red: 0.6, green: 1.0, blue: 0.2)
    static let focusTint = Color(red: 0.2, green: 0.85, blue: 1.0)

    var body: some View {
        let w = size * 0.11
        ZStack {
            ring(move, Self.moveTint, size, w)
            ring(typeAvailable ? type : 0, typeAvailable ? Self.typeTint : .gray, size - 2.4 * w, w)
            ring(focus, Self.focusTint, size - 4.8 * w, w)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(T("활동 링", "Activity rings"))
    }

    private func ring(_ v: Double, _ tint: Color, _ d: CGFloat, _ w: CGFloat) -> some View {
        ZStack {
            Circle().stroke(tint.opacity(0.2), lineWidth: w)
            Circle().trim(from: 0, to: max(0.001, min(1, v)))
                .stroke(tint, style: StrokeStyle(lineWidth: w, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if v > 1 {
                // 목표를 넘으면 한 바퀴 더
                Circle().trim(from: 0, to: min(1, v - 1))
                    .stroke(tint.opacity(0.7), style: StrokeStyle(lineWidth: w * 0.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: d, height: d)
    }
}

private struct ActivityRingTab: View {
    @ObservedObject var store: ActivityStore
    @State private var hasKeys = TFKeyTap.hasPermission

    var body: some View {
        content
        .foregroundStyle(.white)
        .onAppear { store.load(); hasKeys = TFKeyTap.hasPermission }
    }

    private var content: some View {
        let d = store.today
        let g = ActivityStore.goals
        let p = ActivityStore.progress(d, keysAvailable: hasKeys)
        return HStack(alignment: .center, spacing: 22) {
            ActivityRingsGlyph(move: p.move, type: p.type, focus: p.focus, size: 132, typeAvailable: hasKeys)
            VStack(alignment: .leading, spacing: 8) {
                row(T("이동", "Move"), ActivityRingsGlyph.moveTint,
                    ActivityRingModule.km(d.distanceMM / 1000), "/ " + ActivityRingModule.km(g.meters))
                if hasKeys {
                    row(T("타이핑", "Type"), ActivityRingsGlyph.typeTint, TFFormat.number(d.keys), "/ " + TFFormat.number(g.keys) + T("회", ""))
                } else {
                    TFUnsupportedBox(title: T("키 입력 수: 권한 필요", "Keystrokes: permission needed"),
                                     reason: T("키 입력 횟수를 세려면 입력 모니터링 권한이 있어야 해요. 키 내용은 저장하지 않아요.",
                                               "Counting keystrokes needs Input Monitoring. Key contents are never stored."),
                                     alternative: T("이동·입력 시간 링은 권한 없이 동작해요.", "Move and Focus rings work without it."),
                                     buttonTitle: T("허용", "Allow")) {
                        TFKeyTap.requestPermission()
                        TFKeyTap.openPrivacySettings()
                    }
                }
                row(T("입력 시간", "Focus"), ActivityRingsGlyph.focusTint, TFFormat.duration(d.activeSeconds), "/ " + TFFormat.duration(Double(g.activeMinutes * 60)))
                HStack(spacing: 12) {
                    Label(T("클릭 \(TFFormat.number(d.clicks))", "\(TFFormat.number(d.clicks)) clicks"), systemImage: "cursorarrow.click")
                    Label(T("연속 \(store.streakDays)일", "\(store.streakDays)-day streak"), systemImage: "flame.fill")
                }
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
    }

    private func row(_ label: String, _ tint: Color, _ value: String, _ goal: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.7)).frame(width: 54, alignment: .leading)
            Text(value).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tint)
            Text(goal).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ActivityRingSettings: View {
    @StateObject private var prefs = TFPrefs(module: ActivityStore.module)
    @State private var hasKeys = TFKeyTap.hasPermission
    @State private var cleared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("하루 목표", "Daily Goals")).font(.headline)
            Stepper(T("이동 \(prefs.int("goalMeters", 300).wrappedValue) m", "Move \(prefs.int("goalMeters", 300).wrappedValue) m"),
                    value: prefs.int("goalMeters", 300), in: 50...10000, step: 50)
            Stepper(T("타이핑 \(prefs.int("goalKeys", 5000).wrappedValue)회", "Type \(prefs.int("goalKeys", 5000).wrappedValue) keys"),
                    value: prefs.int("goalKeys", 5000), in: 500...100000, step: 500)
            Stepper(T("입력 시간 \(prefs.int("goalMinutes", 240).wrappedValue)분", "Focus \(prefs.int("goalMinutes", 240).wrappedValue) min"),
                    value: prefs.int("goalMinutes", 240), in: 30...960, step: 30)
            TFSettingsNote(text: T("세 목표를 모두 채운 날이 이어지면 연속 기록이 쌓여요. 누적 이정표를 넘으면 한 번만 알려 줘요.",
                                   "Days that fill all three rings build a streak. Lifetime milestones are announced once."))
            Divider()
            Text(T("권한", "Permission")).font(.headline)
            HStack {
                Image(systemName: hasKeys ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(hasKeys ? .green : .yellow)
                Text(hasKeys ? T("입력 모니터링 허용됨", "Input Monitoring allowed") : T("입력 모니터링 없음: 타이핑 링을 셀 수 없어요", "No Input Monitoring: the Type ring can't count"))
                Spacer()
                if !hasKeys {
                    Button(T("권한 요청", "Request")) { TFKeyTap.requestPermission(); hasKeys = TFKeyTap.hasPermission }
                    Button(T("설정 열기", "Open Settings")) { TFKeyTap.openPrivacySettings() }
                }
            }
            TFSettingsNote(text: T("키는 횟수만 세고 내용은 읽거나 저장하지 않아요. 커서 거리는 0.5초마다 위치를 확인해 계산하고, 화면 크기(mm)로 실제 길이로 바꿔요. 기록은 이 Mac에만 저장해요.",
                                   "Only keystroke counts are kept, never contents. Cursor distance samples the position every 0.5 s and converts using the display's physical size. Data stays on this Mac."))
            Button(cleared ? T("휴지통으로 옮겼어요", "Moved to the Trash") : T("활동 기록 지우기 (휴지통으로)", "Clear Activity History (to Trash)")) {
                if ActivityStore.shared.clear() {
                    cleared = true
                    prefs.defaults.set(Date().timeIntervalSince1970, "clearedAt")
                }
            }
            .disabled(cleared)
        }
    }
}

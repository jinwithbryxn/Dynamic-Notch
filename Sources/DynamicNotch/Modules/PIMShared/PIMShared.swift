import AppKit
import Carbon.HIToolbox
import EventKit
import SwiftUI

// 일정·할 일·메모·날씨 기능이 함께 쓰는 도우미.
// 다른 기능과 이름이 겹치지 않게 모두 PIM 접두어를 붙인다.

// MARK: - 권한

/// 일정·미리 알림 권한 상태 (요청하지 않고 읽기만 한다)
enum PIMAccess: Equatable {
    case granted, notDetermined, denied, writeOnly
    /// Info.plist에 사용 목적 문구가 없어 이 빌드는 권한을 요청할 수 없다
    case missingUsageKey

    static func of(_ type: EKEntityType) -> PIMAccess {
        let key = type == .event ? "NSCalendarsFullAccessUsageDescription" : "NSRemindersFullAccessUsageDescription"
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: return .granted
        case .writeOnly: return .writeOnly
        case .notDetermined: return PIMPrivacy.hasUsageKey(key) ? .notDetermined : .missingUsageKey
        case .denied, .restricted: return .denied
        default: return .granted   // 예전 '허용됨'
        }
    }

    var label: String {
        switch self {
        case .granted: return T("허용됨", "Allowed")
        case .notDetermined: return T("아직 묻지 않음", "Not requested")
        case .denied: return T("거부됨", "Denied")
        case .writeOnly: return T("쓰기만 허용 (읽기 불가)", "Write-only (cannot read)")
        case .missingUsageKey: return T("지원 안 됨 (Info.plist 문구 없음)", "Unsupported (Info.plist string missing)")
        }
    }

    var debugName: String {
        switch self {
        case .granted: return "fullAccess"
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .writeOnly: return "writeOnly"
        case .missingUsageKey: return "missingUsageKey"
        }
    }
}

enum PIMPrivacy {
    static func hasUsageKey(_ key: String) -> Bool {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.isEmpty == false
    }

    /// 시스템 설정의 개인정보 보호 항목을 연다 (Privacy_Calendars, Privacy_Reminders, Privacy_LocationServices, Privacy_Automation)
    static func open(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 시스템 설정 → 인터넷 계정
    static func openInternetAccounts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 사용자가 누른 동작에서만 부른다. 거부된 상태면 시스템 설정을 연다.
    static func request(_ type: EKEntityType, store: EKEventStore, done: @escaping (Bool) -> Void) {
        switch PIMAccess.of(type) {
        case .granted: done(true)
        case .missingUsageKey: done(false)
        case .denied, .writeOnly:
            open(type == .event ? "Privacy_Calendars" : "Privacy_Reminders")
            done(false)
        case .notDetermined:
            let handler: EKEventStoreRequestAccessCompletionHandler = { ok, _ in DispatchQueue.main.async { done(ok) } }
            if type == .event { store.requestFullAccessToEvents(completion: handler) }
            else { store.requestFullAccessToReminders(completion: handler) }
        }
    }
}

/// 일정·미리 알림 기능이 함께 쓰는 EventKit 저장소. 처음 쓸 때 만든다 (만들기만으로는 권한을 묻지 않는다).
enum PIMEventStore {
    private static var store: EKEventStore?

    static var shared: EKEventStore {
        if let store { return store }
        let s = EKEventStore()
        store = s
        return s
    }

    /// 다른 프로세스(설정 창)에서 권한을 받은 뒤 캘린더 목록이 비어 있으면 새로 읽는다.
    static func refreshIfEmpty(_ type: EKEntityType) {
        guard PIMAccess.of(type) == .granted, let s = store else { return }
        if s.calendars(for: type).isEmpty { s.reset() }
    }
}

// MARK: - 자연어 날짜

/// 입력에서 찾은 날짜와 나머지 제목
struct PIMParsedDate: Equatable {
    var title: String
    var date: Date
    var hasTime: Bool
    var duration: TimeInterval?
    /// 날짜로 읽힌 원문 부분
    var matched: String
}

/// "내일 오후 3시 회의", "lunch with Alex tomorrow at 1pm" 같은 입력에서 날짜를 찾는다.
/// 한글이 있으면 자체 규칙을 먼저 쓰고, 아니면 NSDataDetector를 쓴다.
enum PIMDateParser {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    static func parse(_ text: String, now: Date = Date()) -> PIMParsedDate? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.range(of: "\\p{Hangul}", options: .regularExpression) != nil, let k = parseKorean(trimmed, now: now) {
            return k
        }
        return parseDetector(trimmed)
    }

    // NSDataDetector (영어 등)
    private static func parseDetector(_ text: String) -> PIMParsedDate? {
        guard let detector else { return nil }
        let ns = text as NSString
        guard let m = detector.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)),
              let date = m.date else { return nil }
        let matched = ns.substring(with: m.range)
        let timeHint = "(\\d{1,2}(:\\d{2})?\\s*(am|pm|a\\.m\\.|p\\.m\\.))|(\\d{1,2}:\\d{2})|\\bnoon\\b|\\bmidnight\\b|\\bat\\s+\\d|o'clock|\\btonight\\b|\\bmorning\\b|\\bevening\\b|\\bafternoon\\b"
        let hasTime = matched.range(of: timeHint, options: [.regularExpression, .caseInsensitive]) != nil
        var title = ns.replacingCharacters(in: m.range, with: " ")
        title = cleanTitle(title, english: true)
        let day = hasTime ? date : Calendar.current.startOfDay(for: date)
        return PIMParsedDate(title: title, date: day, hasTime: hasTime,
                             duration: m.duration > 0 ? m.duration : nil, matched: matched)
    }

    // 한국어 규칙: 오늘·내일·모레·글피, (이번|다음) 주 X요일, N월 N일, N일, 오전·오후 N시 (N분|반), HH:MM
    private static func parseKorean(_ text: String, now: Date) -> PIMParsedDate? {
        let cal = Calendar.current
        var working = text as NSString
        var matchedParts: [String] = []
        var day: Date?
        var hour: Int?
        var minute = 0

        func take(_ pattern: String) -> NSTextCheckingResult? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: working as String, range: NSRange(location: 0, length: working.length)) else { return nil }
            return m
        }
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : working.substring(with: r)
        }
        func remove(_ m: NSTextCheckingResult) {
            matchedParts.append(working.substring(with: m.range))
            working = working.replacingCharacters(in: m.range, with: " ") as NSString
        }

        let today = cal.startOfDay(for: now)
        if let m = take("(오늘|내일|모레|글피)(까지|에)?") {
            let offset = ["오늘": 0, "내일": 1, "모레": 2, "글피": 3][group(m, 1) ?? ""] ?? 0
            day = cal.date(byAdding: .day, value: offset, to: today)
            remove(m)
        } else if let m = take("(다음\\s?주|담주|이번\\s?주)?\\s*(월|화|수|목|금|토|일)요일(까지|에)?") {
            let names = ["일": 1, "월": 2, "화": 3, "수": 4, "목": 5, "금": 6, "토": 7]
            let wd = names[group(m, 2) ?? ""] ?? 2
            let which = group(m, 1)?.replacingOccurrences(of: " ", with: "")
            // 이번 주는 월요일 시작으로 본다
            let weekdayToday = cal.component(.weekday, from: today)
            let mondayOffset = (weekdayToday + 5) % 7
            let monday = cal.date(byAdding: .day, value: -mondayOffset, to: today) ?? today
            let idx = (wd + 5) % 7   // 월=0 … 일=6
            if which == "이번주" {
                day = cal.date(byAdding: .day, value: idx, to: monday)
            } else if which == "다음주" || which == "담주" {
                day = cal.date(byAdding: .day, value: idx + 7, to: monday)
            } else {
                // 다음에 오는 그 요일 (오늘이면 다음 주)
                var d = cal.date(byAdding: .day, value: 1, to: today) ?? today
                while cal.component(.weekday, from: d) != wd { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
                day = d
            }
            remove(m)
        } else if let m = take("(\\d{1,2})\\s*월\\s*(\\d{1,2})\\s*일(까지|에)?") {
            let mo = Int(group(m, 1) ?? "") ?? 1, d = Int(group(m, 2) ?? "") ?? 1
            var comps = cal.dateComponents([.year], from: today)
            comps.month = mo; comps.day = d
            if var date = cal.date(from: comps) {
                if date < today { date = cal.date(byAdding: .year, value: 1, to: date) ?? date }
                day = date
            }
            remove(m)
        }

        if let m = take("(오전|오후|아침|낮|저녁|밤|새벽)?\\s*(\\d{1,2})\\s*시(\\s*(\\d{1,2})\\s*분|\\s*반)?(까지|에)?") {
            var h = Int(group(m, 2) ?? "") ?? 9
            let part = group(m, 1)
            if let mm = group(m, 4) { minute = Int(mm) ?? 0 } else if group(m, 3)?.contains("반") == true { minute = 30 }
            switch part {
            case "오후", "저녁", "밤": if h < 12 { h += 12 }
            case "낮": if h < 12 && h <= 6 { h += 12 }
            case "오전", "아침", "새벽": if h == 12 { h = 0 }
            default: if (1...6).contains(h) { h += 12 }   // "3시 회의"는 보통 오후
            }
            hour = min(23, h)
            remove(m)
        } else if let m = take("(\\d{1,2}):(\\d{2})(까지|에)?") {
            hour = min(23, Int(group(m, 1) ?? "") ?? 9)
            minute = min(59, Int(group(m, 2) ?? "") ?? 0)
            remove(m)
        }

        guard day != nil || hour != nil else { return nil }
        var base = day ?? today
        var date = base
        if let hour {
            date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
            // 날짜 없이 지난 시각이면 내일
            if day == nil, date <= now {
                base = cal.date(byAdding: .day, value: 1, to: base) ?? base
                date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
            }
        }
        let title = cleanTitle(working as String, english: false)
        return PIMParsedDate(title: title, date: date, hasTime: hour != nil, duration: nil,
                             matched: matchedParts.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " "))
    }

    private static func cleanTitle(_ s: String, english: Bool) -> String {
        var t = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.-·")))
        if english {
            for word in [" at", " on", " by", " from"] where t.lowercased().hasSuffix(word) { t = String(t.dropLast(word.count)) }
            for word in ["on ", "at ", "by "] where t.lowercased().hasPrefix(word) { t = String(t.dropFirst(word.count)) }
        }
        return t.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - 표시 도우미

enum PIMFormat {
    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = L10n.isEnglish ? Locale(identifier: "en_US") : Locale(identifier: "ko_KR")
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: date)
    }

    static func shortDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = L10n.isEnglish ? Locale(identifier: "en_US") : Locale(identifier: "ko_KR")
        f.setLocalizedDateFormatFromTemplate("MMMdEEE")
        return f.string(from: date)
    }

    /// "오늘", "내일", "11월 4일 (수)"
    static func dayTitle(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return T("오늘", "Today") }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: t) { return T("내일", "Tomorrow") }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: y) { return T("어제", "Yesterday") }
        return shortDay(date)
    }

    /// 날짜 미리보기: "내일 · 오후 3:00" / "11월 4일 (수) · 하루 종일"
    static func preview(_ p: PIMParsedDate, now: Date = Date()) -> String {
        let day = dayTitle(p.date, now: now)
        let full = shortDay(p.date)
        let head = day == full ? full : "\(day) · \(full)"
        return p.hasTime ? "\(head) · \(time(p.date))" : "\(head) · \(T("하루 종일", "All day"))"
    }

    /// 남은 시간: "12분", "1시간 5분" / "12m", "1h 5m"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int((seconds / 60).rounded(.up)))
        let h = total / 60, m = total % 60
        if h == 0 { return T("\(m)분", "\(m)m") }
        if m == 0 { return T("\(h)시간", "\(h)h") }
        return T("\(h)시간 \(m)분", "\(h)h \(m)m")
    }
}

// MARK: - 회의 링크

enum PIMMeetingLink {
    /// 화상 회의로 보는 주소
    static let hosts = ["zoom.us", "zoom.com", "zoomgov.com", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                        "webex.com", "whereby.com", "around.co", "meet.jit.si", "chime.aws", "bluejeans.com",
                        "gotomeeting.com", "meet.goto.com", "app.slack.com", "facetime.apple.com", "discord.gg",
                        "discord.com", "livestorm.co", "skype.com", "meet.lync.com", "gather.town", "pop.com", "tuple.app"]
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "app.slack.com" { return url.path.contains("huddle") }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// 일정 주소·장소·메모에서 첫 회의 링크를 찾는다.
    static func find(url: URL?, texts: [String?]) -> URL? {
        if let url, isMeeting(url) { return url }
        guard let detector else { return nil }
        for case let text? in texts where !text.isEmpty {
            let ns = text as NSString
            for m in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if let u = m.url, u.scheme?.hasPrefix("http") == true, isMeeting(u) { return u }
            }
        }
        return nil
    }
}

// MARK: - 자체 검사 도우미

enum PIMWait {
    /// 메인 런루프를 돌리며 기다린다 (자체 검사에서 메인 큐로 돌아오는 응답을 받기 위해)
    static func until(timeout: TimeInterval, _ done: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !done() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}

// MARK: - 파일 저장

/// 기능 데이터(할 일·링크 등)를 Application Support/<번들 ID>/Modules/에 JSON으로 저장한다.
enum PIMFiles {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "DynamicNotch", isDirectory: true)
            .appendingPathComponent("Modules", isDirectory: true)
    }

    static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, _ name: String) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(value) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }
}

// MARK: - 색

enum PIMColor {
    static let palette = ["#FF453A", "#FF9F0A", "#FFD60A", "#32D74B", "#64D2FF", "#0A84FF", "#BF5AF2", "#FF375F", "#AC8E68"]

    static func color(hex: String) -> Color { Color(nsColor: nsColor(hex: hex)) }

    static func nsColor(hex: String) -> NSColor {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count >= 6, let v = UInt64(s.prefix(6), radix: 16) else { return .systemBlue }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - 화면 조각

/// 작고 둥근 캡슐 버튼
struct PIMPillStyle: ButtonStyle {
    var prominent = false
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.island(.footnote, .semibold))
            .foregroundStyle(prominent ? Color.black : tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(prominent ? tint.opacity(configuration.isPressed ? 0.7 : 0.92)
                                                 : Color.white.opacity(configuration.isPressed ? 0.2 : 0.12)))
            .contentShape(Capsule())
    }
}

/// 빈 상태·권한 안내
struct PIMEmptyState: View {
    var symbol: String
    var title: String
    var detail: String? = nil
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.island(.title2)).foregroundStyle(.white.opacity(0.75))
            Text(title).font(.island(.subhead, .semibold)).foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(.island(.caption)).foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if let buttonTitle, let action {
                Button(buttonTitle, action: action).buttonStyle(PIMPillStyle(prominent: true))
                    .accessibilityLabel(buttonTitle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }
}

/// 원형 체크 버튼
struct PIMCheckCircle: View {
    var checked: Bool
    var tint: Color = .white

    var body: some View {
        ZStack {
            Circle().strokeBorder(tint.opacity(checked ? 0.9 : 0.55), lineWidth: 1.4)
            if checked {
                Circle().fill(tint.opacity(0.9)).padding(3)
            }
        }
        .frame(width: 15, height: 15)
    }
}

// MARK: - 단축키 기록 (설정 창)

/// 설정 창에서 전역 단축키를 하나 기록한다. 값은 ModuleDefaults에 JSON으로 저장된다.
struct PIMShortcutRecorder: View {
    let defaults: ModuleDefaults
    let key: String
    @State private var shortcut: HotKeyCenter.Shortcut?
    @State private var recording = false
    @State private var monitor: Any?

    static func load(_ defaults: ModuleDefaults, _ key: String) -> HotKeyCenter.Shortcut? {
        defaults.data(key).flatMap { try? JSONDecoder().decode(HotKeyCenter.Shortcut.self, from: $0) }
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(recording ? T("키를 누르세요… (Esc 취소)", "Press keys… (Esc cancels)") : (shortcut?.display ?? T("기록", "Record"))) {
                recording ? stop() : start()
            }
            if shortcut != nil {
                Button(T("지우기", "Clear")) {
                    shortcut = nil
                    defaults.set(nil, key)
                }
            }
        }
        .onAppear { shortcut = Self.load(defaults, key) }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            var mods: UInt32 = 0
            let f = event.modifierFlags
            if f.contains(.command) { mods |= UInt32(cmdKey) }
            if f.contains(.option) { mods |= UInt32(optionKey) }
            if f.contains(.control) { mods |= UInt32(controlKey) }
            if f.contains(.shift) { mods |= UInt32(shiftKey) }
            // ⌘·⌥·⌃ 중 하나는 있어야 전역 단축키로 쓴다
            guard mods & UInt32(cmdKey | optionKey | controlKey) != 0,
                  HotKeyCenter.Shortcut.keyNames[UInt32(event.keyCode)] != nil else { return nil }
            let s = HotKeyCenter.Shortcut(keyCode: UInt32(event.keyCode), modifiers: mods)
            shortcut = s
            defaults.set(try? JSONEncoder().encode(s), key)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

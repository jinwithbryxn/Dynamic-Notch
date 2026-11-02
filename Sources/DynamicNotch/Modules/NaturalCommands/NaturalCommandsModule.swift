import AppKit
import EventKit
import SwiftUI

/// 자연어 명령 해석 결과
struct NLCommand: Equatable {
    enum Kind: Equatable {
        case timer(seconds: Int)
        case event(title: String, date: Date, allDay: Bool)
        case reminder(title: String, date: Date?)
    }
    let kind: Kind
}

/// "10분 타이머", "timer 10m", "내일 9시 회의", "remind me to call mom at 5pm" 같은 문장을 해석한다.
/// 한국어 날짜·시각은 직접 해석하고, 영어는 NSDataDetector를 쓴다.
enum NLCommandParser {
    static func parse(_ raw: String, now: Date = Date(), calendar cal: Calendar = .current) -> NLCommand? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard text.count >= 3, text.count <= 160 else { return nil }
        let lower = text.lowercased()

        // 1) 타이머
        if lower.contains("타이머") || lower.range(of: #"\btimer\b"#, options: .regularExpression) != nil {
            if let s = durationSeconds(lower), s > 0, s <= 24 * 3600 { return NLCommand(kind: .timer(seconds: s)) }
            return nil
        }

        // 2) 미리 알림 / 일정
        let reminderWords = ["remind me to ", "remind me ", "reminder ", "리마인드", "알려줘", "알려 줘", "미리 알림", "미리알림", "할 일", "todo ", "to-do "]
        let isReminder = reminderWords.contains { lower.contains($0) }
        var rest = text
        for w in reminderWords + ["add ", "create ", "schedule ", "new event ", "일정 추가", "일정"] {
            if let r = rest.range(of: w, options: .caseInsensitive) { rest.removeSubrange(r) }
        }
        let found = findDate(rest, now: now, calendar: cal)
        if let f = found { rest = f.remaining }
        let title = cleanTitle(rest)

        if isReminder {
            guard !title.isEmpty else { return nil }
            // 날짜만 있으면 그날 오전 9시에 알림
            var date = found?.date
            if let f = found, !f.hasTime { date = cal.date(bySettingHour: 9, minute: 0, second: 0, of: f.date) }
            return NLCommand(kind: .reminder(title: title, date: date))
        }
        guard let f = found, !title.isEmpty, f.hasTime || f.hasDay else { return nil }
        return NLCommand(kind: .event(title: title, date: f.date, allDay: !f.hasTime))
    }

    // MARK: 길이

    static func durationSeconds(_ s: String) -> Int? {
        let re = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*(시간|분|초|hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)(?![a-z])"#)
        let ns = s as NSString
        var total = 0.0
        var any = false
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            guard let v = Double(ns.substring(with: m.range(at: 1))) else { continue }
            let u = ns.substring(with: m.range(at: 2))
            any = true
            switch u {
            case "시간", "h", "hr", "hrs", "hour", "hours": total += v * 3600
            case "초", "s", "sec", "secs", "second", "seconds": total += v
            default: total += v * 60
            }
        }
        if s.contains("시간 반") || s.contains("시간반") { total += 1800 }
        if s.contains("half an hour") { total += 1800; any = true }
        return any ? Int(total.rounded()) : nil
    }

    // MARK: 날짜

    struct Found { var date: Date; var hasDay: Bool; var hasTime: Bool; var remaining: String }

    static func findDate(_ text: String, now: Date, calendar cal: Calendar) -> Found? {
        var rest = text
        var dayOffset: Int?
        var explicitDay: DateComponents?
        var hour: Int?, minute = 0
        var relative: TimeInterval?

        func take(_ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)) else { return nil }
            let groups = (0..<m.numberOfRanges).map { i -> String in
                guard let r = Range(m.range(at: i), in: rest) else { return "" }
                return String(rest[r])
            }
            if let r = Range(m.range, in: rest) { rest.replaceSubrange(r, with: " ") }
            return groups
        }

        // 상대 시간: 10분 후, 2시간 뒤
        if let g = take(#"(\d+)\s*(분|시간)\s*(후|뒤)(에)?"#), let n = Double(g[1]) {
            relative = n * (g[2] == "분" ? 60 : 3600)
        }
        // 날짜
        if let g = take(#"(오늘|내일|모레|글피)(은|에)?"#) {
            dayOffset = ["오늘": 0, "내일": 1, "모레": 2, "글피": 3][g[1]]
        } else if let g = take(#"(\d+)\s*일\s*(후|뒤)(에)?"#), let n = Int(g[1]) {
            dayOffset = n
        } else if let g = take(#"(\d{1,2})\s*월\s*(\d{1,2})\s*일(에)?"#), let mo = Int(g[1]), let d = Int(g[2]) {
            explicitDay = DateComponents(month: mo, day: d)
        } else if let g = take(#"(다음\s*주|담주|이번\s*주)?\s*(월|화|수|목|금|토|일)요일(에)?"#) {
            let target = ["일": 1, "월": 2, "화": 3, "수": 4, "목": 5, "금": 6, "토": 7][g[2]]!
            let today = cal.component(.weekday, from: now)
            var delta = (target - today + 7) % 7
            if g[1].replacingOccurrences(of: " ", with: "").hasPrefix("다음") || g[1] == "담주" {
                // 다음 주: 월요일 시작 주 기준으로 다음 주의 그 요일
                let mondayIndex = (today + 5) % 7          // 월=0 … 일=6
                let targetIndex = (target + 5) % 7
                delta = 7 - mondayIndex + targetIndex
            }
            dayOffset = delta
        }
        // 시각
        if let g = take(#"(오전|오후|아침|낮|저녁|밤|새벽)?\s*(\d{1,2})\s*시\s*(?:(\d{1,2})\s*분|(반))?(에|까지|부터)?"#), let h = Int(g[2]), h <= 24 {
            hour = koreanHour(h, marker: g[1])
            if let m = Int(g[3]) { minute = min(59, m) } else if g[4] == "반" { minute = 30 }
        } else if let g = take(#"(오전|오후)?\s*(\d{1,2}):(\d{2})(에)?"#), let h = Int(g[2]), let m = Int(g[3]), h < 24, m < 60 {
            hour = g[1] == "오후" && h < 12 ? h + 12 : h
            minute = m
        }

        let usedKorean = relative != nil || dayOffset != nil || explicitDay != nil || hour != nil
        if usedKorean {
            if let relative {
                return Found(date: now.addingTimeInterval(relative), hasDay: true, hasTime: true, remaining: rest)
            }
            var base = cal.startOfDay(for: now)
            if let dayOffset { base = cal.date(byAdding: .day, value: dayOffset, to: base) ?? base }
            if let e = explicitDay {
                var c = cal.dateComponents([.year], from: now)
                c.month = e.month; c.day = e.day
                if let d = cal.date(from: c) {
                    base = d < cal.startOfDay(for: now) ? (cal.date(byAdding: .year, value: 1, to: d) ?? d) : d
                }
            }
            var date = base
            if let hour {
                date = cal.date(bySettingHour: hour % 24, minute: minute, second: 0, of: base) ?? base
                // 날짜 없이 지난 시각이면 내일
                if dayOffset == nil, explicitDay == nil, date <= now { date = cal.date(byAdding: .day, value: 1, to: date) ?? date }
            }
            return Found(date: date, hasDay: dayOffset != nil || explicitDay != nil, hasTime: hour != nil, remaining: rest)
        }

        // 영어 등: NSDataDetector
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let m = det.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let d = m.date,
              let r = Range(m.range, in: text) else { return nil }
        let matched = text[r].lowercased()
        let hasTime = matched.range(of: #"\d|noon|midnight|morning|evening|night|minute|hour"#, options: .regularExpression) != nil
        var remaining = text
        remaining.replaceSubrange(r, with: " ")
        var date = d
        if !hasTime, m.timeZone == nil { date = cal.startOfDay(for: d) }
        return Found(date: date, hasDay: true, hasTime: hasTime, remaining: remaining)
    }

    /// 한국어 시각: 오후·저녁·밤은 +12, 표시 없이 1–6시는 오후로 본다 ("3시 회의" = 15시)
    static func koreanHour(_ h: Int, marker: String) -> Int {
        switch marker {
        case "오후", "저녁", "밤": return h < 12 ? h + 12 : (h == 12 && marker == "밤" ? 0 : h)
        case "낮": return h < 7 ? h + 12 : h
        case "오전", "아침", "새벽": return h == 12 ? 0 : h
        default: return (1...6).contains(h) ? h + 12 : h
        }
    }

    static func cleanTitle(_ s: String) -> String {
        var words = s.split(separator: " ").map(String.init)
        let drop: Set<String> = ["at", "on", "for", "to", "in", "by", "the", "에", "에서", "까지", "부터", "을", "를", "은", "는", "-", "·", ",", "me", "please"]
        while let f = words.first, drop.contains(f.lowercased()) { words.removeFirst() }
        while let l = words.last, drop.contains(l.lowercased()) { words.removeLast() }
        var t = words.joined(separator: " ")
        for suffix in ["을", "를"] where t.hasSuffix(suffix) && t.count > 2 { t.removeLast() }
        return t.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}

/// 자연어 명령: 팔레트에 "10분 타이머", "내일 9시 회의", "remind me to call mom at 5pm"처럼 입력하면
/// 타이머를 시작하거나, 확인을 받은 뒤 캘린더 일정·미리 알림을 만든다. 권한은 추가를 누를 때만 요청한다.
final class NaturalCommandsModule: NotchModule {
    let id = "nlcommands"
    var title: String { T("자연어 명령", "Natural Language Commands") }
    let symbol = "text.bubble"
    var enabledByDefault: Bool { false }

    /// 본 앱의 노치 타이머로 시작하는 연결점 (통합 담당이 AppDelegate에서 `timer.start(seconds:)`로 채운다).
    /// 비어 있으면 이 기능의 간단한 타이머(끝날 때 소리와 알림)를 쓴다.
    static var startTimerHook: ((Int) -> Void)?

    fileprivate var context: ModuleContext?
    private var timers: [(id: UUID, end: Date, seconds: Int, work: DispatchWorkItem)] = []
    private lazy var store = EKEventStore()

    func start(context: ModuleContext) { self.context = context }
    func stop() {
        timers.forEach { $0.work.cancel() }
        timers = []
        context = nil
    }

    func paletteResults(for query: String) -> [PaletteAction] {
        guard let cmd = NLCommandParser.parse(query) else { return [] }
        switch cmd.kind {
        case .timer(let s):
            return [PaletteAction(id: "nl.timer", title: T("타이머 시작: ", "Start timer: ") + Self.durationText(s),
                                  subtitle: T("Return: 시작", "Return: start"), symbol: "timer") { [weak self] in self?.startTimer(s) }]
        case let .event(title, date, allDay):
            return [PaletteAction(id: "nl.event", title: T("일정 추가: ", "Add event: ") + title,
                                  subtitle: Self.dateText(date, allDay: allDay) + T(" · 확인 후 캘린더에 추가", " · confirm before adding"),
                                  symbol: "calendar.badge.plus") { [weak self] in self?.confirmEvent(title, date, allDay) }]
        case let .reminder(title, date):
            return [PaletteAction(id: "nl.reminder", title: T("미리 알림: ", "Reminder: ") + title,
                                  subtitle: (date.map { Self.dateText($0, allDay: false) } ?? T("날짜 없음", "No date")) + T(" · 확인 후 추가", " · confirm before adding"),
                                  symbol: "checklist") { [weak self] in self?.confirmReminder(title, date) }]
        }
    }

    func paletteActions() -> [PaletteAction] {
        timers.map { t in
            let left = max(0, Int(t.end.timeIntervalSinceNow))
            return PaletteAction(id: "nl.timer.cancel.\(t.id)", title: T("타이머 취소: ", "Cancel timer: ") + Self.durationText(t.seconds),
                                 subtitle: T("\(Self.durationText(left)) 남음", "\(Self.durationText(left)) left"), symbol: "timer",
                                 keywords: ["timer", "타이머", "cancel", "취소"]) { [weak self] in self?.cancelTimer(t.id) }
        }
    }

    // MARK: 타이머

    func startTimer(_ seconds: Int) {
        if let hook = Self.startTimerHook { hook(seconds); return }
        let id = UUID()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.timers.removeAll { $0.id == id }
            NSSound(named: "Glass")?.play()
            self.context?.notice(T("타이머 끝", "Timer done"), Self.durationText(seconds), symbol: "timer", tint: .orange, duration: 8)
        }
        timers.append((id, Date().addingTimeInterval(TimeInterval(seconds)), seconds, work))
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: work)
        let end = DateFormatter.localizedString(from: Date().addingTimeInterval(TimeInterval(seconds)), dateStyle: .none, timeStyle: .short)
        context?.notice(T("타이머 시작: ", "Timer started: ") + Self.durationText(seconds), T("\(end)에 끝남 · 팔레트에서 취소", "Ends at \(end) · cancel from the palette"),
                        symbol: "timer", actions: [ActivityAction(id: "cancel", title: T("취소", "Cancel"), role: .destructive) { [weak self] in self?.cancelTimer(id) }])
    }

    func cancelTimer(_ id: UUID) {
        timers.first { $0.id == id }?.work.cancel()
        timers.removeAll { $0.id == id }
    }

    // MARK: 일정·미리 알림 (확인 후)

    private func confirmEvent(_ title: String, _ date: Date, _ allDay: Bool) {
        context?.notice(T("일정을 추가할까?", "Add this event?"), "\(title) · \(Self.dateText(date, allDay: allDay))",
                        symbol: "calendar.badge.plus", duration: 15, actions: [
                            ActivityAction(id: "add", title: T("추가", "Add"), role: .primary) { [weak self] in self?.addEvent(title, date, allDay) },
                            ActivityAction(id: "no", title: T("취소", "Cancel")) { [weak self] in self?.context?.center.dismissTransient(kind: .notice) },
                        ])
    }

    private func confirmReminder(_ title: String, _ date: Date?) {
        guard LaunchSystem.hasUsageKey("NSRemindersFullAccessUsageDescription") else {
            context?.notice(T("미리 알림 지원 안 됨", "Reminders unavailable"),
                            T("앱 정보에 미리 알림 권한 문구가 없어 요청할 수 없음 · 대신 일정으로 추가 가능", "The app lacks the Reminders usage text · add it as an event instead"),
                            symbol: "checklist", duration: 15, actions: date.map { d in
                                [ActivityAction(id: "asEvent", title: T("일정으로 추가", "Add as event"), role: .primary) { [weak self] in self?.addEvent(title, d, false) }]
                            } ?? [])
            return
        }
        context?.notice(T("미리 알림을 추가할까?", "Add this reminder?"), title + (date.map { " · " + Self.dateText($0, allDay: false) } ?? ""),
                        symbol: "checklist", duration: 15, actions: [
                            ActivityAction(id: "add", title: T("추가", "Add"), role: .primary) { [weak self] in self?.addReminder(title, date) },
                            ActivityAction(id: "no", title: T("취소", "Cancel")) { [weak self] in self?.context?.center.dismissTransient(kind: .notice) },
                        ])
    }

    private func addEvent(_ title: String, _ date: Date, _ allDay: Bool) {
        access(.event) { [weak self] ok in
            guard let self else { return }
            guard ok else { self.denied(T("캘린더", "Calendar"), anchor: "Privacy_Calendars"); return }
            let ev = EKEvent(eventStore: self.store)
            ev.title = title
            ev.startDate = date
            ev.endDate = allDay ? date : date.addingTimeInterval(3600)
            ev.isAllDay = allDay
            guard let cal = self.store.defaultCalendarForNewEvents else {
                self.context?.notice(T("기본 캘린더가 없음", "No default calendar"), nil, symbol: "calendar.badge.exclamationmark")
                return
            }
            ev.calendar = cal
            do {
                try self.store.save(ev, span: .thisEvent)
                self.context?.notice(T("일정 추가함", "Event added"), "\(title) · \(Self.dateText(date, allDay: allDay)) · \(cal.title)", symbol: "calendar")
            } catch {
                self.context?.notice(T("일정 추가 실패", "Could not add event"), error.localizedDescription, symbol: "calendar.badge.exclamationmark", tint: .red)
            }
        }
    }

    private func addReminder(_ title: String, _ date: Date?) {
        access(.reminder) { [weak self] ok in
            guard let self else { return }
            guard ok else { self.denied(T("미리 알림", "Reminders"), anchor: "Privacy_Reminders"); return }
            let r = EKReminder(eventStore: self.store)
            r.title = title
            r.calendar = self.store.defaultCalendarForNewReminders()
            if let date {
                r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                r.addAlarm(EKAlarm(absoluteDate: date))
            }
            do {
                try self.store.save(r, commit: true)
                self.context?.notice(T("미리 알림 추가함", "Reminder added"), title, symbol: "checklist")
            } catch {
                self.context?.notice(T("미리 알림 추가 실패", "Could not add reminder"), error.localizedDescription, symbol: "checklist", tint: .red)
            }
        }
    }

    /// 권한 확인. 정해지지 않았을 때만 요청 창을 띄운다 (사용자가 추가를 누른 뒤).
    private func access(_ type: EKEntityType, _ done: @escaping (Bool) -> Void) {
        let status = EKEventStore.authorizationStatus(for: type)
        switch status {
        case .fullAccess: done(true)
        case .writeOnly: done(type == .event)
        case .notDetermined:
            let finish: (Bool, Error?) -> Void = { ok, _ in DispatchQueue.main.async { done(ok) } }
            if type == .event { store.requestFullAccessToEvents(completion: finish) } else { store.requestFullAccessToReminders(completion: finish) }
        default: done(false)
        }
    }

    private func denied(_ what: String, anchor: String) {
        context?.notice(T("\(what) 권한 없음", "No \(what) access"), T("시스템 설정 > 개인정보 보호에서 허용", "Allow it in System Settings > Privacy"),
                        symbol: "lock", actions: [ActivityAction(id: "open", title: T("설정 열기", "Open Settings")) { LaunchSystem.openPrivacyPane(anchor) }])
    }

    // MARK: 표시

    static func durationText(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        var parts: [String] = []
        if h > 0 { parts.append(T("\(h)시간", "\(h)h")) }
        if m > 0 { parts.append(T("\(m)분", "\(m)m")) }
        if sec > 0 || parts.isEmpty { parts.append(T("\(sec)초", "\(sec)s")) }
        return parts.joined(separator: " ")
    }

    static func dateText(_ d: Date, allDay: Bool) -> String {
        let f = DateFormatter()
        f.locale = L10n.isEnglish ? Locale(identifier: "en_US") : Locale(identifier: "ko_KR")
        f.setLocalizedDateFormatFromTemplate(allDay ? "MMMdEEE" : "MMMdEEEjmm")
        return f.string(from: d) + (allDay ? T(" (하루 종일)", " (all day)") : "")
    }

    func selfTest() -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10, minute: 0))!   // 월요일 10:00
        var out = ["now = \(Self.dateText(now, allDay: false)) (fixed for the test)"]
        let samples = [
            "10분 타이머", "타이머 1시간 30분", "timer 10m", "set a timer for 90 seconds", "25 min timer",
            "내일 9시 회의", "내일 오전 9시에 팀 회의", "금요일 저녁 7시 저녁 약속", "다음 주 월요일 3시 치과", "11월 20일 생일 파티",
            "3시 반 디자인 리뷰", "30분 후 회의 준비 알려줘", "remind me to call mom at 5pm", "lunch with Sam tomorrow at noon",
            "dentist friday 3pm", "remind me to buy milk", "미리 알림 우유 사기 내일", "hello world", "9:30", "1+2",
        ]
        for s in samples {
            guard let c = NLCommandParser.parse(s, now: now, calendar: cal) else { out.append("\(s) -> (none)"); continue }
            switch c.kind {
            case .timer(let sec): out.append("\(s) -> timer \(Self.durationText(sec))")
            case let .event(t, d, allDay): out.append("\(s) -> event \"\(t)\" \(Self.dateText(d, allDay: allDay))")
            case let .reminder(t, d): out.append("\(s) -> reminder \"\(t)\" \(d.map { Self.dateText($0, allDay: false) } ?? "no date")")
            }
        }
        out.append("calendar access: \(Self.statusName(EKEventStore.authorizationStatus(for: .event))) · reminders: \(Self.statusName(EKEventStore.authorizationStatus(for: .reminder)))")
        out.append("Info.plist reminders usage text: \(LaunchSystem.hasUsageKey("NSRemindersFullAccessUsageDescription") ? "present" : "missing -> reminders show unsupported")")
        for q in ["10분 타이머", "내일 9시 회의"] {
            out.append("palette \"\(q)\": " + (paletteResults(for: q).first.map { "\($0.title) — \($0.subtitle ?? "")" } ?? "(none)"))
        }
        out.append("timer hook: \(Self.startTimerHook == nil ? "not wired -> module timer" : "wired")")
        out.append("permission requested in self test: no")
        return out
    }

    static func statusName(_ s: EKAuthorizationStatus) -> String {
        switch s {
        case .fullAccess: return "full"
        case .writeOnly: return "write-only"
        case .notDetermined: return "not determined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        @unknown default: return "other"
        }
    }
}

import Foundation

/// .ics(iCalendar) 읽기 전용 해석기. VEVENT와 간단한 RRULE(DAILY·WEEKLY·MONTHLY·YEARLY,
/// INTERVAL·COUNT·UNTIL·BYDAY·BYMONTHDAY·BYMONTH), EXDATE, RECURRENCE-ID(한 회만 바뀐 일정)를 다룬다.
/// BYSETPOS·BYWEEKNO·BYYEARDAY·RDATE는 지원하지 않는다.
enum CalICS {
    struct Event {
        var uid: String
        var summary: String
        var start: Date
        var end: Date
        var allDay: Bool
        var timeZone: TimeZone
        var location: String?
        var description: String?
        var url: URL?
        var rrule: [String: String]?
        var exdates: [Date] = []
        var recurrenceID: Date?
        var cancelled = false
        /// Google·Teams가 넣는 회의 주소
        var conferenceURL: URL?
    }

    struct Occurrence {
        var event: Event
        var start: Date
        var end: Date
    }

    struct Feed {
        var name: String?
        var events: [Event]
    }

    // MARK: 해석

    static func parse(_ text: String) -> Feed {
        var name: String?
        var events: [Event] = []
        var current: [Prop]?
        var depth = 0   // VEVENT 안의 VALARM 등은 건너뛴다
        var defaultTZ = TimeZone.current
        for line in unfold(text) {
            guard let p = prop(line) else { continue }
            switch (p.name, p.value.uppercased()) {
            case ("BEGIN", "VEVENT"):
                current = []
                depth = 0
            case ("BEGIN", _):
                if current != nil { depth += 1 }
            case ("END", "VEVENT"):
                if let props = current, let e = makeEvent(props, defaultTZ: defaultTZ) { events.append(e) }
                current = nil
            case ("END", _):
                if current != nil { depth = max(0, depth - 1) }
            default:
                if current != nil {
                    if depth == 0 { current?.append(p) }
                } else if p.name == "X-WR-CALNAME" {
                    name = unescape(p.value)
                } else if p.name == "X-WR-TIMEZONE", let tz = zone(p.value) {
                    defaultTZ = tz
                }
            }
        }
        return Feed(name: name, events: events)
    }

    struct Prop {
        var name: String
        var params: [String: String]
        var value: String
    }

    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for raw in normalized.components(separatedBy: "\n") {
            if let f = raw.first, f == " " || f == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                lines.append(raw)
            }
        }
        return lines
    }

    static func prop(_ line: String) -> Prop? {
        var inQuote = false
        var colon: String.Index?
        var cuts: [String.Index] = []
        for i in line.indices {
            let c = line[i]
            if c == "\"" { inQuote.toggle() }
            else if !inQuote, c == ";" { cuts.append(i) }
            else if !inQuote, c == ":" { colon = i; break }
        }
        guard let colon else { return nil }
        let head = line[..<colon]
        var parts: [Substring] = []
        var startIdx = head.startIndex
        for cut in cuts where cut < colon {
            parts.append(head[startIdx..<cut])
            startIdx = head.index(after: cut)
        }
        parts.append(head[startIdx...])
        var params: [String: String] = [:]
        for p in parts.dropFirst() {
            let kv = p.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            params[kv[0].uppercased()] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return Prop(name: parts[0].uppercased(), params: params, value: String(line[line.index(after: colon)...]))
    }

    static func unescape(_ s: String) -> String {
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            if c == "\\", let n = it.next() {
                switch n {
                case "n", "N": out.append("\n")
                default: out.append(n)
                }
            } else {
                out.append(c)
            }
        }
        return out
    }

    private static func makeEvent(_ props: [Prop], defaultTZ: TimeZone) -> Event? {
        func first(_ name: String) -> Prop? { props.first { $0.name == name } }
        guard let dtstart = first("DTSTART"), let s = date(dtstart.value, params: dtstart.params, defaultTZ: defaultTZ) else { return nil }
        var end: Date
        if let dtend = first("DTEND"), let e = date(dtend.value, params: dtend.params, defaultTZ: defaultTZ) {
            end = e.date
        } else if let dur = first("DURATION").flatMap({ duration($0.value) }) {
            end = s.date.addingTimeInterval(dur)
        } else {
            end = s.allDay ? (Foundation.Calendar.current.date(byAdding: .day, value: 1, to: s.date) ?? s.date) : s.date
        }
        if end < s.date { end = s.date }
        var rrule: [String: String]?
        if let r = first("RRULE") {
            var dict: [String: String] = [:]
            for part in r.value.split(separator: ";") {
                let kv = part.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { dict[kv[0].uppercased()] = String(kv[1]) }
            }
            rrule = dict
        }
        var exdates: [Date] = []
        for ex in props where ex.name == "EXDATE" {
            for v in ex.value.split(separator: ",") {
                if let d = date(String(v), params: ex.params, defaultTZ: s.timeZone) { exdates.append(d.date) }
            }
        }
        let rid = first("RECURRENCE-ID").flatMap { date($0.value, params: $0.params, defaultTZ: s.timeZone)?.date }
        let conference = ["X-GOOGLE-CONFERENCE", "X-MICROSOFT-SKYPETEAMSMEETINGURL", "X-MICROSOFT-ONLINEMEETINGCONFLINK"]
            .compactMap { first($0).flatMap { URL(string: $0.value.trimmingCharacters(in: .whitespaces)) } }.first
        return Event(uid: first("UID")?.value ?? UUID().uuidString,
                     summary: first("SUMMARY").map { unescape($0.value) } ?? T("(제목 없음)", "(No Title)"),
                     start: s.date, end: end, allDay: s.allDay, timeZone: s.timeZone,
                     location: first("LOCATION").map { unescape($0.value) }.flatMap { $0.isEmpty ? nil : $0 },
                     description: first("DESCRIPTION").map { unescape($0.value) },
                     url: first("URL").flatMap { URL(string: $0.value.trimmingCharacters(in: .whitespaces)) },
                     rrule: rrule, exdates: exdates, recurrenceID: rid,
                     cancelled: first("STATUS")?.value.uppercased() == "CANCELLED",
                     conferenceURL: conference)
    }

    // MARK: 날짜

    static func date(_ value: String, params: [String: String], defaultTZ: TimeZone) -> (date: Date, allDay: Bool, timeZone: TimeZone)? {
        let v = value.trimmingCharacters(in: .whitespaces)
        let digits = v.filter { $0.isNumber }
        if params["VALUE"]?.uppercased() == "DATE" || (!v.contains("T") && digits.count == 8) {
            guard digits.count >= 8, let y = Int(digits.prefix(4)), let m = Int(digits.dropFirst(4).prefix(2)),
                  let d = Int(digits.dropFirst(6).prefix(2)) else { return nil }
            // 종일 일정은 이 Mac 시간대의 그날 0시
            guard let date = Foundation.Calendar.current.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
            return (date, true, .current)
        }
        let utc = v.hasSuffix("Z")
        let tz: TimeZone = utc ? TimeZone(identifier: "UTC")! : (params["TZID"].flatMap(zone) ?? defaultTZ)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        let core = String(v.prefix(15))
        guard let date = f.date(from: core) else { return nil }
        return (date, false, utc ? defaultTZ : tz)
    }

    /// P1D, PT1H30M, P1W, -PT15M
    static func duration(_ value: String) -> TimeInterval? {
        var s = value.uppercased()
        var sign = 1.0
        if s.hasPrefix("-") { sign = -1; s.removeFirst() } else if s.hasPrefix("+") { s.removeFirst() }
        guard s.hasPrefix("P") else { return nil }
        s.removeFirst()
        var total = 0.0, number = "", inTime = false
        for c in s {
            if c == "T" { inTime = true; continue }
            if c.isNumber { number.append(c); continue }
            let n = Double(number) ?? 0
            number = ""
            switch c {
            case "W": total += n * 7 * 86_400
            case "D": total += n * 86_400
            case "H": total += n * 3_600
            case "M": total += inTime ? n * 60 : n * 30 * 86_400
            case "S": total += n
            default: break
            }
        }
        return sign * total
    }

    /// TZID → 시간대. IANA 이름, "/mozilla.org/…/Europe/Berlin" 형태, 흔한 Windows 이름을 받는다.
    static func zone(_ raw: String) -> TimeZone? {
        let id = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        if let tz = TimeZone(identifier: id) { return tz }
        let parts = id.split(separator: "/")
        if parts.count >= 2, let tz = TimeZone(identifier: parts.suffix(2).joined(separator: "/")) { return tz }
        let windows: [String: String] = [
            "Korea Standard Time": "Asia/Seoul", "Tokyo Standard Time": "Asia/Tokyo", "China Standard Time": "Asia/Shanghai",
            "Taipei Standard Time": "Asia/Taipei", "Singapore Standard Time": "Asia/Singapore", "India Standard Time": "Asia/Kolkata",
            "Pacific Standard Time": "America/Los_Angeles", "Mountain Standard Time": "America/Denver",
            "Central Standard Time": "America/Chicago", "Eastern Standard Time": "America/New_York",
            "GMT Standard Time": "Europe/London", "W. Europe Standard Time": "Europe/Berlin", "Romance Standard Time": "Europe/Paris",
            "Central Europe Standard Time": "Europe/Budapest", "Central European Standard Time": "Europe/Warsaw",
            "AUS Eastern Standard Time": "Australia/Sydney", "UTC": "UTC", "Coordinated Universal Time": "UTC",
        ]
        return windows[id].flatMap(TimeZone.init(identifier:))
    }

    // MARK: 반복 펼치기

    /// 창(from…to)과 겹치는 회차. 바뀐 회차(RECURRENCE-ID)는 원래 회차 대신 들어간다.
    static func expand(_ events: [Event], from: Date, to: Date) -> [Occurrence] {
        var overrides: [String: [TimeInterval: Event]] = [:]
        for e in events where e.recurrenceID != nil {
            overrides[e.uid, default: [:]][e.recurrenceID!.timeIntervalSince1970] = e
        }
        var out: [Occurrence] = []
        for e in events {
            if let _ = e.recurrenceID {
                if !e.cancelled, e.end > from, e.start < to { out.append(Occurrence(event: e, start: e.start, end: e.end)) }
                continue
            }
            guard !e.cancelled else { continue }
            let length = e.end.timeIntervalSince(e.start)
            let replaced = overrides[e.uid] ?? [:]
            for s in starts(of: e, from: from.addingTimeInterval(-length), to: to) where replaced[s.timeIntervalSince1970] == nil {
                let end = s.addingTimeInterval(length)
                if end > from || (length == 0 && s >= from) { out.append(Occurrence(event: e, start: s, end: end)) }
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    /// 한 일정의 회차 시작 시각들 (from 이후, to 이전). 반복이 없으면 시작 하나.
    static func starts(of e: Event, from: Date, to: Date) -> [Date] {
        guard let rule = e.rrule, let freq = rule["FREQ"]?.uppercased() else {
            return e.start <= to && e.start >= from ? [e.start] : (e.start < from && e.end > from ? [e.start] : [])
        }
        var cal = Foundation.Calendar(identifier: .gregorian)
        cal.timeZone = e.timeZone
        cal.firstWeekday = rule["WKST"]?.uppercased() == "SU" ? 1 : 2
        let interval = max(1, Int(rule["INTERVAL"] ?? "1") ?? 1)
        let count = rule["COUNT"].flatMap { Int($0) }
        var until: Date?
        if let u = rule["UNTIL"], let d = date(u, params: [:], defaultTZ: e.timeZone) {
            // 날짜만 있으면 그날 끝까지
            until = d.allDay ? cal.date(byAdding: .day, value: 1, to: d.date)?.addingTimeInterval(-1) : d.date
        }
        let weekdayCodes = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        let byDay: [(ordinal: Int?, weekday: Int)] = (rule["BYDAY"] ?? "").split(separator: ",").compactMap { raw in
            let s = String(raw).uppercased()
            guard s.count >= 2, let wd = weekdayCodes[String(s.suffix(2))] else { return nil }
            let num = String(s.dropLast(2))
            return (num.isEmpty ? nil : Int(num), wd)
        }
        let byMonthDay = (rule["BYMONTHDAY"] ?? "").split(separator: ",").compactMap { Int($0) }
        let byMonth = (rule["BYMONTH"] ?? "").split(separator: ",").compactMap { Int($0) }
        let time = cal.dateComponents([.hour, .minute, .second], from: e.start)
        let excluded = Set(e.exdates.map { Int($0.timeIntervalSince1970) })

        var results: [Date] = []
        var produced = 0
        var iterations = 0
        var stop = false

        func at(_ day: Date) -> Date? {
            cal.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day)
        }
        /// 회차 하나를 낸다. 더 볼 필요가 없으면 stop.
        func emit(_ d: Date) {
            if d < e.start { return }
            if let until, d > until { stop = true; return }
            produced += 1
            if let count, produced > count { stop = true; return }
            if d > to { stop = true; return }
            if d >= from, !excluded.contains(Int(d.timeIntervalSince1970)) { results.append(d) }
        }
        func daysInMonth(_ monthStart: Date) -> [Date] {
            guard let r = cal.range(of: .day, in: .month, for: monthStart) else { return [] }
            return r.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: monthStart) }
        }
        func byDayMatches(in days: [Date]) -> [Date] {
            var out: [Date] = []
            for (ord, wd) in byDay {
                let same = days.filter { cal.component(.weekday, from: $0) == wd }
                if let ord {
                    let idx = ord > 0 ? ord - 1 : same.count + ord
                    if same.indices.contains(idx) { out.append(same[idx]) }
                } else {
                    out.append(contentsOf: same)
                }
            }
            return out
        }

        switch freq {
        case "DAILY":
            var day = cal.startOfDay(for: e.start)
            let allowed = Set(byDay.map(\.weekday))
            while !stop, iterations < 60_000 {
                iterations += 1
                if (allowed.isEmpty || allowed.contains(cal.component(.weekday, from: day))),
                   byMonth.isEmpty || byMonth.contains(cal.component(.month, from: day)), let d = at(day) { emit(d) }
                guard let next = cal.date(byAdding: .day, value: interval, to: day) else { break }
                day = next
            }
        case "WEEKLY":
            let days = byDay.isEmpty ? [cal.component(.weekday, from: e.start)] : byDay.map(\.weekday)
            let ordered = days.sorted { ($0 - cal.firstWeekday + 7) % 7 < ($1 - cal.firstWeekday + 7) % 7 }
            guard var weekStart = cal.dateInterval(of: .weekOfYear, for: e.start)?.start else { break }
            while !stop, iterations < 20_000 {
                iterations += 1
                for wd in ordered where !stop {
                    let offset = (wd - cal.firstWeekday + 7) % 7
                    if let day = cal.date(byAdding: .day, value: offset, to: weekStart), let d = at(day) { emit(d) }
                }
                guard let next = cal.date(byAdding: .weekOfYear, value: interval, to: weekStart) else { break }
                weekStart = next
            }
        case "MONTHLY":
            guard var monthStart = cal.date(from: cal.dateComponents([.year, .month], from: e.start)) else { break }
            let startDay = cal.component(.day, from: e.start)
            while !stop, iterations < 5_000 {
                iterations += 1
                let days = daysInMonth(monthStart)
                var cands: [Date] = []
                if !byMonthDay.isEmpty {
                    for md in byMonthDay {
                        let idx = md > 0 ? md - 1 : days.count + md
                        if days.indices.contains(idx) { cands.append(days[idx]) }
                    }
                } else if !byDay.isEmpty {
                    cands = byDayMatches(in: days)
                } else if days.indices.contains(startDay - 1) {
                    cands = [days[startDay - 1]]
                }
                for day in Set(cands).sorted() where !stop { if let d = at(day) { emit(d) } }
                guard let next = cal.date(byAdding: .month, value: interval, to: monthStart) else { break }
                monthStart = next
            }
        case "YEARLY":
            let comps = cal.dateComponents([.year, .month, .day], from: e.start)
            var year = comps.year ?? 2000
            let months = byMonth.isEmpty ? [comps.month ?? 1] : byMonth
            while !stop, iterations < 1_000 {
                iterations += 1
                for m in months.sorted() where !stop {
                    guard let monthStart = cal.date(from: DateComponents(year: year, month: m, day: 1)) else { continue }
                    let days = daysInMonth(monthStart)
                    var cands: [Date] = []
                    if !byMonthDay.isEmpty {
                        for md in byMonthDay {
                            let idx = md > 0 ? md - 1 : days.count + md
                            if days.indices.contains(idx) { cands.append(days[idx]) }
                        }
                    } else if !byDay.isEmpty {
                        cands = byDayMatches(in: days)
                    } else if let d = comps.day, days.indices.contains(d - 1) {
                        cands = [days[d - 1]]
                    }
                    for day in Set(cands).sorted() where !stop { if let d = at(day) { emit(d) } }
                }
                year += interval
            }
        default:
            return e.start >= from && e.start <= to ? [e.start] : []
        }
        return results
    }
}

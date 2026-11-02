import AppKit
import EventKit
import SwiftUI

/// 탭·노치·메뉴 막대에 보이는 일정 한 회차
struct CalItem: Identifiable, Equatable {
    enum Origin: Equatable { case system, subscription(String) }
    var id: String
    /// EKEvent.eventIdentifier (편집·삭제용)
    var eventID: String?
    /// EKEvent.calendarItemIdentifier (캘린더 앱에서 열기)
    var itemID: String?
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var color: Color
    var calendarName: String
    var location: String?
    var meetingURL: URL?
    var origin: Origin
    /// 본인의 단일 일정이고 쓰기 가능한 캘린더에 있다
    var editable: Bool
    var recurring: Bool
    var hasAttendees: Bool

    func overlaps(day: Date) -> Bool {
        let cal = Calendar.current
        let s = cal.startOfDay(for: day)
        guard let e = cal.date(byAdding: .day, value: 1, to: s) else { return false }
        return start < e && (end > s || (end == start && start >= s))
    }

    var timeText: String {
        if allDay { return T("하루 종일", "All day") }
        return "\(PIMFormat.time(start)) – \(PIMFormat.time(end))"
    }
}

/// 마감이 있는 미리 알림 (그날 일정 옆에 표시, M-D-010)
struct CalTask: Identifiable, Equatable {
    var id: String
    var title: String
    var due: Date
    var hasTime: Bool
    var color: Color
    var list: String
}

/// 지운 일정 되돌리기용 사본
struct CalUndo: Equatable {
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var calendarID: String
    var location: String?
    var notes: String?
    var url: URL?
}

/// 일정 데이터: EventKit + 구독. 탭·모듈이 함께 쓴다.
final class CalendarModel: ObservableObject {
    @Published private(set) var access: PIMAccess = .notDetermined
    @Published private(set) var reminderAccess: PIMAccess = .notDetermined
    /// 달력에 보이는 달의 1일
    @Published var month: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @Published var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @Published private(set) var items: [CalItem] = []
    @Published private(set) var tasks: [CalTask] = []
    /// 날짜(0시) → 그날 일정 색 (달력 점)
    @Published private(set) var dayColors: [Date: [Color]] = [:]
    /// 지금부터 이틀 안 일정 (카운트다운·메뉴 막대·알림)
    @Published private(set) var upcoming: [CalItem] = []
    @Published private(set) var feedErrors: [String: String] = [:]
    @Published private(set) var feedCounts: [String: Int] = [:]
    @Published var undo: CalUndo?
    @Published var message: String?
    /// 새 일정 입력 칸에 포커스 요청 (늘어날 때마다)
    @Published var focusRequest = 0
    /// 마지막으로 탭이 보인 날 (날이 바뀌면 오늘로 돌아간다)
    var lastShownDay = Calendar.current.startOfDay(for: Date())

    let defaults = ModuleDefaults(module: "calendar")
    private var feeds: [String: CalICS.Feed] = [:]
    private var loaders: [String: CalFeedLoader] = [:]
    private(set) var feedFetchedAt: [String: Date] = [:]
    private var undoWork: DispatchWorkItem?
    private var messageWork: DispatchWorkItem?

    var store: EKEventStore { PIMEventStore.shared }

    // MARK: 설정

    var useMacCalendars: Bool { defaults.bool("useMacCalendars", default: true) || subscriptions.isEmpty }
    var hiddenCalendars: Set<String> { Set(defaults.strings("hiddenCalendars", default: [])) }
    var manageEvents: Bool { defaults.bool("manageEvents", default: true) }
    var showDueTasks: Bool { defaults.bool("dueTasks", default: false) }
    var subscriptions: [CalSubscription] {
        var list = CalSubscription.load(defaults)
        if devFeedURL != nil {
            list.append(CalSubscription(id: "dev", name: T("검사용 피드", "Test feed"), kind: .ics, colorHex: "#FF9F0A", username: nil))
        }
        return list
    }
    /// 개발용: 화면 그리기 모드에서 DMN_CAL_TEST_ICS로 준 .ics (저장하지 않음)
    var devFeedURL: URL?

    // MARK: 읽기

    func refreshAccess() {
        access = PIMAccess.of(.event)
        reminderAccess = PIMAccess.of(.reminder)
        if access == .granted { PIMEventStore.refreshIfEmpty(.event) }
    }

    /// 달력 범위(6주)와 선택한 날부터 7일을 함께 읽는다.
    var visibleRange: (Date, Date) {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: month)
        let lead = (weekday - cal.firstWeekday + 7) % 7
        let gridStart = cal.date(byAdding: .day, value: -lead, to: month) ?? month
        let gridEnd = cal.date(byAdding: .day, value: 42, to: gridStart) ?? month
        let agendaEnd = cal.date(byAdding: .day, value: 7, to: selectedDay) ?? selectedDay
        return (min(gridStart, selectedDay), max(gridEnd, agendaEnd))
    }

    func reloadVisible() {
        refreshAccess()
        let (from, to) = visibleRange
        let list = (eventKitItems(from: from, to: to) + subscriptionItems(from: from, to: to))
            .sorted { ($0.start, $0.allDay ? 0 : 1, $0.title) < ($1.start, $1.allDay ? 0 : 1, $1.title) }
        items = list
        var colors: [Date: [Color]] = [:]
        let cal = Calendar.current
        for item in list {
            var day = cal.startOfDay(for: item.start)
            let lastDay = cal.startOfDay(for: item.allDay ? item.end.addingTimeInterval(-1) : item.end)
            var guardCount = 0
            while day <= max(lastDay, day), guardCount < 42 {
                if day >= from, day < to, (colors[day]?.count ?? 0) < 3 { colors[day, default: []].append(item.color) }
                guard let next = cal.date(byAdding: .day, value: 1, to: day), next <= lastDay else { break }
                day = next
                guardCount += 1
            }
        }
        dayColors = colors
        loadTasks(from: from, to: to)
    }

    func reloadUpcoming() {
        refreshAccess()
        let now = Date()
        let from = now.addingTimeInterval(-12 * 3600)
        let to = now.addingTimeInterval(48 * 3600)
        upcoming = (eventKitItems(from: from, to: to) + subscriptionItems(from: from, to: to))
            .filter { !$0.allDay && $0.end > now }
            .sorted { $0.start < $1.start }
    }

    private func eventKitItems(from: Date, to: Date) -> [CalItem] {
        guard access == .granted, useMacCalendars else { return [] }
        let hidden = hiddenCalendars
        let calendars = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
        return store.events(matching: predicate).compactMap { e in
            if e.status == .canceled { return nil }
            if e.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined { return nil }
            let attendees = !(e.attendees?.isEmpty ?? true)
            return CalItem(id: "ek:\(e.calendarItemIdentifier):\(Int(e.startDate.timeIntervalSince1970))",
                           eventID: e.eventIdentifier, itemID: e.calendarItemIdentifier,
                           title: (e.title?.isEmpty == false ? e.title! : T("(제목 없음)", "(No Title)")),
                           start: e.startDate, end: e.endDate, allDay: e.isAllDay,
                           color: Color(nsColor: e.calendar.color ?? .systemBlue), calendarName: e.calendar.title,
                           location: e.location, meetingURL: PIMMeetingLink.find(url: e.url, texts: [e.location, e.notes]),
                           origin: .system,
                           editable: e.calendar.allowsContentModifications && !e.hasRecurrenceRules && !attendees,
                           recurring: e.hasRecurrenceRules, hasAttendees: attendees)
        }
    }

    private func subscriptionItems(from: Date, to: Date) -> [CalItem] {
        var out: [CalItem] = []
        for sub in subscriptions {
            guard let feed = feeds[sub.id] else { continue }
            let color = PIMColor.color(hex: sub.colorHex)
            for occ in CalICS.expand(feed.events, from: from, to: to) {
                let e = occ.event
                out.append(CalItem(id: "sub:\(sub.id):\(e.uid):\(Int(occ.start.timeIntervalSince1970))",
                                   eventID: nil, itemID: nil, title: e.summary, start: occ.start, end: occ.end,
                                   allDay: e.allDay, color: color, calendarName: sub.name, location: e.location,
                                   meetingURL: PIMMeetingLink.find(url: e.conferenceURL ?? e.url, texts: [e.location, e.description]),
                                   origin: .subscription(sub.id), editable: false, recurring: e.rrule != nil, hasAttendees: false))
            }
        }
        return out
    }

    private func loadTasks(from: Date, to: Date) {
        guard showDueTasks, reminderAccess == .granted else { tasks = []; return }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: from, ending: to, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let list: [CalTask] = (reminders ?? []).compactMap { r in
                guard let comps = r.dueDateComponents, let due = Calendar.current.date(from: comps) else { return nil }
                return CalTask(id: r.calendarItemIdentifier, title: r.title ?? "", due: due, hasTime: comps.hour != nil,
                               color: Color(nsColor: r.calendar.color ?? .systemOrange), list: r.calendar.title)
            }.sorted { $0.due < $1.due }
            DispatchQueue.main.async { self?.tasks = list }
        }
    }

    func items(on day: Date) -> [CalItem] { items.filter { $0.overlaps(day: day) } }

    func tasks(on day: Date) -> [CalTask] { tasks.filter { Calendar.current.isDate($0.due, inSameDayAs: day) } }

    // MARK: 구독

    /// 구독을 읽는다. force가 아니면 30분 안에 읽은 것은 건너뛴다.
    func refreshFeeds(force: Bool = false, done: (() -> Void)? = nil) {
        let subs = subscriptions
        let ids = Set(subs.map(\.id))
        for (id, loader) in loaders where !ids.contains(id) { loader.cancel(); loaders[id] = nil }
        feeds = feeds.filter { ids.contains($0.key) }
        feedErrors = feedErrors.filter { ids.contains($0.key) }
        feedCounts = feedCounts.filter { ids.contains($0.key) }
        let now = Date()
        let pending = subs.filter { force || (feedFetchedAt[$0.id].map { now.timeIntervalSince($0) > 30 * 60 } ?? true) }
        guard !pending.isEmpty else { done?(); return }
        var remaining = pending.count
        let from = now.addingTimeInterval(-35 * 86_400)
        let to = now.addingTimeInterval(90 * 86_400)
        for sub in pending {
            let loader = loaders[sub.id] ?? CalFeedLoader()
            loader.cancel()
            loaders[sub.id] = loader
            loader.load(sub, directURL: sub.id == "dev" ? devFeedURL : nil, from: from, to: to) { [weak self] result in
                guard let self else { return }
                self.feedFetchedAt[sub.id] = Date()
                switch result {
                case .success(let feed):
                    self.feeds[sub.id] = feed
                    self.feedErrors[sub.id] = nil
                    self.feedCounts[sub.id] = CalICS.expand(feed.events, from: now, to: to).count
                case .failure(let e):
                    self.feedErrors[sub.id] = e.localizedDescription
                }
                remaining -= 1
                if remaining == 0 { done?() }
            }
        }
    }

    func cancelFeeds() {
        for loader in loaders.values { loader.cancel() }
        loaders.removeAll()
    }

    // MARK: 쓰기 (사용자가 누른 동작에서만)

    func requestAccess(then: @escaping () -> Void = {}) {
        PIMPrivacy.request(.event, store: store) { [weak self] _ in
            self?.reloadVisible()
            then()
        }
    }

    func requestReminderAccess() {
        PIMPrivacy.request(.reminder, store: store) { [weak self] _ in self?.reloadVisible() }
    }

    /// 새 일정이 들어갈 캘린더 (설정에서 고른 것, 없으면 기본 캘린더)
    var targetCalendar: EKCalendar? {
        guard access == .granted else { return nil }
        let id = defaults.string("newEventCalendar", default: "")
        if !id.isEmpty, let c = store.calendar(withIdentifier: id), c.allowsContentModifications { return c }
        if let d = store.defaultCalendarForNewEvents, d.allowsContentModifications { return d }
        return store.calendars(for: .event).first { $0.allowsContentModifications }
    }

    /// 입력 한 줄로 일정을 만든다. 성공하면 nil, 실패하면 이유.
    @discardableResult
    func create(from text: String) -> String? {
        guard manageEvents else { return T("설정에서 '일정 관리'가 꺼져 있음", "Manage Events is off in Settings") }
        guard access == .granted else { return T("캘린더 권한이 필요함", "Calendar access is required") }
        guard let calendar = targetCalendar else { return T("쓸 수 있는 캘린더가 없음", "No writable calendar") }
        let parsed = PIMDateParser.parse(text)
        let title = (parsed?.title.isEmpty == false ? parsed!.title : text).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return T("제목을 입력하세요", "Enter a title") }
        let e = EKEvent(eventStore: store)
        e.calendar = calendar
        e.title = title
        if let p = parsed {
            e.isAllDay = !p.hasTime
            e.startDate = p.date
            e.endDate = p.hasTime ? p.date.addingTimeInterval(p.duration ?? 3600) : p.date.addingTimeInterval(86_400 - 1)
        } else {
            // 날짜가 없으면 선택한 날 하루 종일
            e.isAllDay = true
            e.startDate = selectedDay
            e.endDate = selectedDay.addingTimeInterval(86_400 - 1)
        }
        do {
            try store.save(e, span: .thisEvent, commit: true)
            selectedDay = Calendar.current.startOfDay(for: e.startDate)
            showMonth(of: selectedDay)
            flash(T("'\(title)' 추가함 · \(calendar.title)", "Added '\(title)' · \(calendar.title)"))
            reloadVisible()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func event(for item: CalItem) -> EKEvent? {
        guard let id = item.eventID else { return nil }
        return store.event(withIdentifier: id)
    }

    @discardableResult
    func update(_ item: CalItem, title: String, start: Date, end: Date, allDay: Bool) -> String? {
        guard manageEvents, item.editable, let e = event(for: item) else { return T("이 일정은 여기서 바꿀 수 없음", "This event can't be edited here") }
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return T("제목을 입력하세요", "Enter a title") }
        guard end >= start else { return T("끝 시각이 시작보다 빠름", "End is before start") }
        e.title = t
        e.isAllDay = allDay
        e.startDate = allDay ? Calendar.current.startOfDay(for: start) : start
        e.endDate = allDay ? Calendar.current.startOfDay(for: end).addingTimeInterval(86_400 - 1) : end
        do {
            try store.save(e, span: .thisEvent, commit: true)
            flash(T("저장함", "Saved"))
            reloadVisible()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 확인을 받은 뒤에만 부른다. 지운 내용은 10초 동안 되돌릴 수 있다.
    @discardableResult
    func delete(_ item: CalItem) -> String? {
        guard manageEvents, item.editable, let e = event(for: item) else { return T("이 일정은 여기서 지울 수 없음", "This event can't be deleted here") }
        let snapshot = CalUndo(title: e.title ?? "", start: e.startDate, end: e.endDate, allDay: e.isAllDay,
                               calendarID: e.calendar.calendarIdentifier, location: e.location, notes: e.notes, url: e.url)
        do {
            try store.remove(e, span: .thisEvent, commit: true)
            undo = snapshot
            undoWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.undo = nil }
            undoWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
            reloadVisible()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func undoDelete() {
        guard let u = undo, let calendar = store.calendar(withIdentifier: u.calendarID) else { undo = nil; return }
        let e = EKEvent(eventStore: store)
        e.calendar = calendar
        e.title = u.title
        e.startDate = u.start
        e.endDate = u.end
        e.isAllDay = u.allDay
        e.location = u.location
        e.notes = u.notes
        e.url = u.url
        do {
            try store.save(e, span: .thisEvent, commit: true)
            flash(T("되돌림", "Restored"))
        } catch {
            flash(error.localizedDescription)
        }
        undo = nil
        reloadVisible()
    }

    func open(_ item: CalItem) {
        if let id = item.itemID, let url = URL(string: "ical://ekevent/\(id)?method=show&options=more"), NSWorkspace.shared.open(url) { return }
        Self.openCalendarApp(on: item.start)
    }

    static func openCalendarApp(on date: Date? = nil) {
        if let date, let url = URL(string: "ical://date/\(Int(date.timeIntervalSinceReferenceDate))"), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    // MARK: 달 이동

    func showMonth(of day: Date) {
        let cal = Calendar.current
        if let m = cal.date(from: cal.dateComponents([.year, .month], from: day)), m != month { month = m }
    }

    func moveMonth(_ delta: Int) {
        guard let m = Calendar.current.date(byAdding: .month, value: delta, to: month) else { return }
        month = m
        if !Calendar.current.isDate(selectedDay, equalTo: m, toGranularity: .month) { selectedDay = m }
        reloadVisible()
    }

    func goToday() {
        selectedDay = Calendar.current.startOfDay(for: Date())
        showMonth(of: selectedDay)
        reloadVisible()
    }

    func select(_ day: Date) {
        selectedDay = Calendar.current.startOfDay(for: day)
        showMonth(of: selectedDay)
        reloadVisible()
    }

    func flash(_ text: String) {
        message = text
        messageWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.message = nil }
        messageWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}

import AppKit
import EventKit
import SwiftUI

/// 캘린더: 한 달 달력과 한 주 일정 탭, 다음 일정 카운트다운(노치), 메뉴 막대 다음 회의,
/// 전체 화면 회의 알림, .ics·CalDAV 읽기 전용 구독, 빠른 일정 추가·편집·삭제, 마감 미리 알림 함께 보기.
/// 캘린더 권한과 네트워크(구독)를 쓰므로 처음에는 꺼져 있다.
final class CalendarModule: NotchModule {
    let id = "calendar"
    var title: String { T("캘린더", "Calendar") }
    let symbol = "calendar"
    let enabledByDefault = false

    let model = CalendarModel()
    private var context: ModuleContext?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var tickTimer: Timer?
    private var lastUpcomingLoad = Date.distantPast
    private var statusItem: CalStatusItem?
    private let alerts = CalAlertWindows()
    /// 카운트다운에서 참가·닫기를 누른 일정
    private var countdownClosed = Set<String>()
    /// 카운트다운을 처음 띄울 때 한 번 펼쳐 보인 일정
    private var countdownAnnounced = Set<String>()
    /// 전체 화면 알림을 이미 띄운 일정
    private var alerted = Set<String>()
    private var snoozed: (item: CalItem, until: Date)?
    private var lastPreviewRequest: Double = 0
    private var subscriptionSignature = ""

    private var defaults: ModuleDefaults { model.defaults }
    private var countdownOn: Bool { defaults.bool("countdown", default: true) }
    private var leadMinutes: Int { max(1, defaults.int("leadMinutes", default: 10)) }
    private var keepUntilJoined: Bool { defaults.bool("keepUntilJoined", default: false) }
    private var menuBarOn: Bool { defaults.bool("menuBar", default: false) }
    private var alertOn: Bool { defaults.bool("fullScreenAlert", default: false) }
    private var alertMinutes: Int { max(0, defaults.int("alertMinutes", default: 1)) }
    private var alertOnlyWithLink: Bool { defaults.bool("alertOnlyWithLink", default: false) }

    // MARK: 시작·정지

    func start(context: ModuleContext) {
        guard self.context == nil else { return }
        self.context = context
        lastPreviewRequest = defaults.double("previewAlert", default: 0)
        subscriptionSignature = signature()
        model.reloadVisible()
        model.reloadUpcoming()
        lastUpcomingLoad = Date()
        // 화면 그리기·설정 창 같은 보조 프로세스에서는 감시·메뉴 막대·알림 창을 만들지 않는다
        guard !AppSettings.isHelper else {
            if let raw = ProcessInfo.processInfo.environment["DMN_CAL_TEST_ICS"] { model.devFeedURL = CalSubscription.normalize(raw) }
            model.refreshFeeds { [weak self] in self?.model.reloadVisible() }
            return
        }
        let nc = NotificationCenter.default
        let ws = NSWorkspace.shared.notificationCenter
        observers = [
            (nc, nc.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in self?.reloadAll() }),
            (nc, nc.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in self?.reloadAll() }),
            (ws, ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.reloadAll()
                self?.model.refreshFeeds { self?.reloadAll() }
            }),
        ]
        model.refreshFeeds { [weak self] in self?.reloadAll() }
        applySettings()
        tick()
    }

    func stop() {
        for (nc, token) in observers { nc.removeObserver(token) }
        observers.removeAll()
        tickTimer?.invalidate()
        tickTimer = nil
        model.cancelFeeds()
        statusItem?.remove()
        statusItem = nil
        alerts.close()
        snoozed = nil
        HotKeyCenter.shared.unregister("calendar.open")
        HotKeyCenter.shared.unregister("calendar.join")
        context?.center.removePersistent(.calendar)
        context = nil
    }

    func settingsChanged() {
        guard context != nil else { return }
        let sig = signature()
        if sig != subscriptionSignature {
            subscriptionSignature = sig
            model.refreshFeeds(force: true) { [weak self] in self?.reloadAll() }
        }
        reloadAll()
        guard !AppSettings.isHelper else { return }
        applySettings()
        let preview = defaults.double("previewAlert", default: 0)
        if preview > lastPreviewRequest {
            lastPreviewRequest = preview
            if Date().timeIntervalSince1970 - preview < 10 { showPreviewAlert() }
        }
        tick()
    }

    private func signature() -> String {
        model.subscriptions.map { "\($0.id)|\($0.kind.rawValue)|\($0.username ?? "")" }.joined(separator: ",")
    }

    private func reloadAll() {
        model.reloadUpcoming()
        pruneMarks()
        model.reloadVisible()
        lastUpcomingLoad = Date()
        tick()
    }

    /// 끝난 일정의 표시 기록을 버린다
    private func pruneMarks() {
        let ids = Set(model.upcoming.map(\.id))
        countdownClosed.formIntersection(ids)
        countdownAnnounced.formIntersection(ids)
        alerted.formIntersection(ids)
    }

    private func applySettings() {
        if menuBarOn {
            if statusItem == nil {
                statusItem = CalStatusItem(menu: { [weak self] in self?.buildMenu() ?? NSMenu() })
            }
        } else {
            statusItem?.remove()
            statusItem = nil
        }
        if let s = PIMShortcutRecorder.load(defaults, "shortcutOpen") {
            HotKeyCenter.shared.register("calendar.open", s) { [weak self] in self?.context?.openTab("calendar") }
        } else {
            HotKeyCenter.shared.unregister("calendar.open")
        }
        if let s = PIMShortcutRecorder.load(defaults, "shortcutJoin") {
            HotKeyCenter.shared.register("calendar.join", s) { [weak self] in self?.joinNext() }
        } else {
            HotKeyCenter.shared.unregister("calendar.join")
        }
    }

    // MARK: 주기 확인

    /// 카운트다운·메뉴 막대·알림을 맞추고 다음 확인 시각을 정한다.
    /// 곧 할 일이 있으면 분마다, 없으면 다음 일정 직전이나 10분 뒤에 한 번만 깨어난다.
    private func tick() {
        guard context != nil, !AppSettings.isHelper else { return }
        let now = Date()
        if now.timeIntervalSince(lastUpcomingLoad) > 10 * 60 {
            model.reloadUpcoming()
            pruneMarks()
            lastUpcomingLoad = now
            model.refreshFeeds { [weak self] in self?.model.reloadUpcoming() }
        }
        updateCountdown(now)
        updateStatusItem(now)
        checkAlerts(now)
        scheduleTick(now)
    }

    private func scheduleTick(_ now: Date) {
        tickTimer?.invalidate()
        let maxLead = TimeInterval(max(countdownOn ? leadMinutes : 0, alertOn ? alertMinutes : 0) * 60)
        let soon = model.upcoming.contains { $0.start.timeIntervalSince(now) <= maxLead + 120 && $0.end > now }
        var next: Date
        if menuBarOn || soon || snoozed != nil {
            // 다음 분 경계 (+1초)
            let sec = Calendar.current.component(.second, from: now)
            next = now.addingTimeInterval(TimeInterval(61 - sec))
        } else {
            next = now.addingTimeInterval(10 * 60)
            if let first = model.upcoming.first(where: { $0.start > now }) {
                next = min(next, first.start.addingTimeInterval(-maxLead - 60))
            }
            next = max(next, now.addingTimeInterval(30))
        }
        let t = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in self?.tick() }
        t.tolerance = 3
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    // MARK: 카운트다운 (M-D-002)

    /// 지금 카운트다운할 일정: 시작 N분 전부터, '참가·닫기 전까지 남기기'면 시작 후 끝날 때(최대 15분)까지
    func countdownCandidate(_ now: Date) -> CalItem? {
        let lead = TimeInterval(leadMinutes * 60)
        return model.upcoming.first { e in
            guard !countdownClosed.contains(e.id) else { return false }
            let until = e.start.timeIntervalSince(now)
            if until > 0 { return until <= lead }
            return keepUntilJoined && e.end > now && -until < 15 * 60
        }
    }

    private func updateCountdown(_ now: Date) {
        guard let center = context?.center else { return }
        guard countdownOn, let e = countdownCandidate(now) else {
            center.removePersistent(.calendar)
            return
        }
        let secs = e.start.timeIntervalSince(now)
        let value = secs > 0 ? PIMFormat.duration(secs) : T("지금", "Now")
        var actions: [ActivityAction] = []
        if let url = e.meetingURL {
            actions.append(ActivityAction(id: "calendar.join", title: T("참가", "Join"), role: .primary) { [weak self] in
                NSWorkspace.shared.open(url)
                self?.closeCountdown(e.id)
            })
        }
        actions.append(ActivityAction(id: "calendar.dismiss", title: T("닫기", "Dismiss")) { [weak self] in
            self?.closeCountdown(e.id)
        })
        let subtitle = secs > 0 ? "\(e.timeText) · \(T("\(value) 후", "in \(value)"))"
                                : "\(e.timeText) · \(T("시작함", "Started"))"
        let activity = NotchActivity(kind: .calendar, priority: ActivityPriority.info, presentation: .compact,
                                     symbol: e.meetingURL != nil ? "video.fill" : "calendar", tint: e.color,
                                     value: .text(value), title: e.title, subtitle: subtitle,
                                     moduleTab: id, actions: actions)
        center.setPersistent(activity)
        if !countdownAnnounced.contains(e.id) {
            countdownAnnounced.insert(e.id)
            var card = activity
            card.presentation = .detail
            card.duration = keepUntilJoined ? 12 : 6
            center.post(card)
        }
    }

    private func closeCountdown(_ id: String) {
        countdownClosed.insert(id)
        context?.center.removePersistent(.calendar)
        context?.center.dismissTransient(kind: .calendar)
        tick()
    }

    // MARK: 메뉴 막대 (M-D-003)

    /// "Standup · 12분 후" / "12분 남음"
    func menuBarTitle(_ now: Date) -> String? {
        let showTitle = defaults.bool("menuBarTitle", default: true)
        let cal = Calendar.current
        if let current = model.upcoming.first(where: { $0.start <= now && $0.end > now }),
           !(model.upcoming.contains { $0.start > now && $0.start.timeIntervalSince(now) <= 10 * 60 }) {
            let left = T("\(PIMFormat.duration(current.end.timeIntervalSince(now))) 남음", "\(PIMFormat.duration(current.end.timeIntervalSince(now))) left")
            return showTitle ? "\(Self.short(current.title)) · \(left)" : left
        }
        guard let next = model.upcoming.first(where: { $0.start > now }), cal.isDate(next.start, inSameDayAs: now)
                || next.start.timeIntervalSince(now) < 6 * 3600 else { return nil }
        let inText = T("\(PIMFormat.duration(next.start.timeIntervalSince(now))) 후", "in \(PIMFormat.duration(next.start.timeIntervalSince(now)))")
        return showTitle ? "\(Self.short(next.title)) · \(inText)" : inText
    }

    private static func short(_ s: String) -> String { s.count > 22 ? String(s.prefix(21)) + "…" : s }

    private func updateStatusItem(_ now: Date) {
        statusItem?.update(title: menuBarTitle(now), dateIcon: defaults.bool("menuBarDateIcon", default: false))
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let now = Date()
        let today = model.upcoming.filter { Calendar.current.isDate($0.start, inSameDayAs: now) || ($0.start <= now && $0.end > now) }
        if today.isEmpty {
            let empty = NSMenuItem(title: T("오늘 남은 일정 없음", "No more events today"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for e in today.prefix(8) {
            let item = CalMenuAction(title: "\(PIMFormat.time(e.start))  \(e.title)") { [weak self] in
                self?.context?.openTab("calendar")
            }
            menu.addItem(item.menuItem)
            if let url = e.meetingURL {
                let join = CalMenuAction(title: "    " + T("참가", "Join"), symbol: "video.fill") { NSWorkspace.shared.open(url) }
                menu.addItem(join.menuItem)
            }
        }
        menu.addItem(.separator())
        menu.addItem(CalMenuAction(title: T("캘린더 탭 열기", "Open Calendar Tab"), symbol: "calendar") { [weak self] in
            self?.context?.openTab("calendar")
        }.menuItem)
        if model.manageEvents {
            menu.addItem(CalMenuAction(title: T("새 일정…", "New Event…"), symbol: "plus") { [weak self] in
                self?.newEvent()
            }.menuItem)
        }
        menu.addItem(CalMenuAction(title: T("캘린더 앱 열기", "Open Calendar App"), symbol: "arrow.up.forward.app") {
            CalendarModel.openCalendarApp()
        }.menuItem)
        return menu
    }

    // MARK: 전체 화면 알림 (M-D-004)

    private func checkAlerts(_ now: Date) {
        if let s = snoozed, now >= s.until, !alerts.isShowing {
            snoozed = nil
            if s.item.end > now { present(s.item, preview: false) }
            return
        }
        guard alertOn, !alerts.isShowing else { return }
        let lead = TimeInterval(alertMinutes * 60)
        for e in model.upcoming where !alerted.contains(e.id) {
            if alertOnlyWithLink, e.meetingURL == nil { continue }
            let fire = e.start.addingTimeInterval(-lead)
            // 잠자기 등으로 놓쳤으면 시작 후 5분까지는 띄운다
            guard now >= fire, now <= e.start.addingTimeInterval(5 * 60) else { continue }
            alerted.insert(e.id)
            present(e, preview: false)
            break
        }
    }

    private func present(_ e: CalItem, preview: Bool) {
        alerts.show(e, preview: preview,
                    onJoin: e.meetingURL.map { url in { [weak self] in
                        NSWorkspace.shared.open(url)
                        self?.countdownClosed.insert(e.id)
                        self?.tick()
                    } },
                    onSnooze: preview ? nil : { [weak self] in
                        self?.snoozed = (e, Date().addingTimeInterval(60))
                        self?.tick()
                    },
                    onDismiss: {})
    }

    /// 설정의 '미리 보기': 실제 일정이 아님을 밝힌 예시 알림
    func showPreviewAlert() {
        let now = Date()
        let start = Calendar.current.date(bySetting: .second, value: 0, of: now.addingTimeInterval(120)) ?? now
        let sample = CalItem(id: "preview", eventID: nil, itemID: nil, title: T("미리 보기 회의", "Preview Meeting"),
                             start: start, end: start.addingTimeInterval(1800), allDay: false, color: .blue,
                             calendarName: T("미리 보기 (실제 일정 아님)", "Preview (not a real event)"),
                             location: nil, meetingURL: nil, origin: .system, editable: false, recurring: false, hasAttendees: false)
        present(sample, preview: true)
    }

    // MARK: 동작

    /// 지금 진행 중이거나 15분 안에 시작하는 회의 링크를 연다.
    func joinNext() {
        let now = Date()
        let cands = model.upcoming.filter { $0.meetingURL != nil && $0.end > now && $0.start.timeIntervalSince(now) <= 15 * 60 }
            .sorted { abs($0.start.timeIntervalSince(now)) < abs($1.start.timeIntervalSince(now)) }
        if let e = cands.first, let url = e.meetingURL {
            NSWorkspace.shared.open(url)
            countdownClosed.insert(e.id)
            tick()
        } else {
            context?.notice(T("곧 참가할 회의가 없음", "No meeting to join soon"),
                            T("15분 안에 시작하는 회의 링크가 없음", "No meeting link starting within 15 minutes"),
                            symbol: "video.slash", tab: id)
        }
    }

    func newEvent() {
        context?.openTab(id)
        context?.focusInput()
        model.focusRequest += 1
    }

    // MARK: 탭·팔레트·설정

    func tabView() -> AnyView? { AnyView(CalendarTab(model: model, focusInput: { [weak self] in self?.context?.focusInput() })) }
    var tabContentSize: CGSize { CGSize(width: 620, height: 280) }

    func paletteActions() -> [PaletteAction] {
        var out: [PaletteAction] = []
        let now = Date()
        if let next = model.upcoming.first(where: { $0.end > now }) {
            let when = next.start > now ? T("\(PIMFormat.duration(next.start.timeIntervalSince(now))) 후", "in \(PIMFormat.duration(next.start.timeIntervalSince(now)))")
                                        : T("진행 중", "In progress")
            out.append(PaletteAction(id: "calendar.next", title: T("다음 일정: \(next.title)", "Next: \(next.title)"),
                                     subtitle: "\(PIMFormat.dayTitle(next.start)) \(next.timeText) · \(when)", symbol: "calendar",
                                     keywords: ["next meeting", "next event", "다음 회의", "다음 일정", "calendar", "캘린더"]) { [weak self] in
                self?.context?.openTab("calendar")
            })
        }
        if model.upcoming.contains(where: { $0.meetingURL != nil && $0.end > now && $0.start.timeIntervalSince(now) <= 15 * 60 }) {
            out.append(PaletteAction(id: "calendar.join", title: T("회의 참가", "Join Meeting"), symbol: "video.fill",
                                     keywords: ["join", "zoom", "meet", "teams", "참가", "회의"]) { [weak self] in self?.joinNext() })
        }
        out.append(PaletteAction(id: "calendar.open", title: T("캘린더 열기", "Open Calendar"), symbol: "calendar",
                                 keywords: ["calendar", "캘린더", "달력", "일정", "agenda"]) { [weak self] in
            self?.context?.openTab("calendar")
        })
        if model.manageEvents {
            out.append(PaletteAction(id: "calendar.new", title: T("새 일정…", "New Event…"), symbol: "calendar.badge.plus",
                                     keywords: ["new event", "add event", "새 일정", "일정 추가"]) { [weak self] in self?.newEvent() })
        }
        return out
    }

    /// "일정 내일 3시 회의", "event lunch tomorrow 1pm" → 바로 추가
    func paletteResults(for query: String) -> [PaletteAction] {
        guard model.manageEvents, model.access == .granted else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces)
        let prefixes = ["일정 ", "새 일정 ", "event ", "new event ", "add event "]
        guard let p = prefixes.first(where: { q.lowercased().hasPrefix($0) }) else { return [] }
        let text = String(q.dropFirst(p.count))
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let parsed = PIMDateParser.parse(text)
        let title = parsed?.title.isEmpty == false ? parsed!.title : text
        let when = parsed.map { PIMFormat.preview($0) } ?? "\(PIMFormat.dayTitle(model.selectedDay)) · \(T("하루 종일", "All day"))"
        return [PaletteAction(id: "calendar.add", title: T("일정 추가: \(title)", "Add Event: \(title)"),
                              subtitle: "\(when) · \(model.targetCalendar?.title ?? "")", symbol: "calendar.badge.plus") { [weak self] in
            guard let self else { return }
            if let err = self.model.create(from: text) {
                self.context?.notice(T("일정을 추가하지 못함", "Couldn't add event"), err, symbol: "exclamationmark.triangle")
            } else {
                self.context?.notice(T("일정 추가함", "Event added"), "\(title) · \(when)", symbol: "calendar.badge.checkmark", tab: "calendar")
            }
        }]
    }

    func settingsView() -> AnyView? { AnyView(CalendarSettings()) }

    // MARK: 자체 검사 (읽기만)

    func selfTest() -> [String] {
        var lines: [String] = []
        let ev = PIMAccess.of(.event), rem = PIMAccess.of(.reminder)
        lines.append("calendar access: \(ev.debugName)")
        lines.append("reminders access: \(rem.debugName)")
        lines.append("Info.plist NSCalendarsFullAccessUsageDescription: \(PIMPrivacy.hasUsageKey("NSCalendarsFullAccessUsageDescription"))")
        lines.append("Info.plist NSRemindersFullAccessUsageDescription: \(PIMPrivacy.hasUsageKey("NSRemindersFullAccessUsageDescription"))")
        if ev == .granted {
            let store = PIMEventStore.shared
            let cals = store.calendars(for: .event)
            let sources = Set(cals.map { $0.source.title })
            lines.append("event calendars: \(cals.count) in \(sources.count) accounts, writable \(cals.filter(\.allowsContentModifications).count)")
            model.reloadUpcoming()
            let withLink = model.upcoming.filter { $0.meetingURL != nil }.count
            lines.append("upcoming 48h (timed): \(model.upcoming.count), with meeting link: \(withLink)")
            if let next = model.upcoming.first(where: { $0.start > Date() }) {
                lines.append("next event starts in \(PIMFormat.duration(next.start.timeIntervalSinceNow))")
            }
        } else {
            lines.append("event read skipped (no full access)")
        }
        let subs = model.subscriptions
        lines.append("subscriptions configured: \(subs.count)")
        // 해석기 검사 (내장 예제 문자열, 화면에 보이지 않음)
        lines.append(contentsOf: Self.parserChecks())
        // 개발용: DMN_CAL_TEST_ICS=<주소>를 주면 그 .ics를 실제로 받아 해석한다
        if let raw = ProcessInfo.processInfo.environment["DMN_CAL_TEST_ICS"], let url = CalSubscription.normalize(raw) {
            let sem = DispatchSemaphore(value: 0)
            var line = "test ics: no response"
            URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 20)) { data, resp, err in
                defer { sem.signal() }
                if let err { line = "test ics: error \(err.localizedDescription)"; return }
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let feed = CalICS.parse(text)
                let now = Date()
                let occ = CalICS.expand(feed.events, from: now, to: now.addingTimeInterval(90 * 86_400))
                line = "test ics: http \((resp as? HTTPURLResponse)?.statusCode ?? 0), VEVENT \(feed.events.count), recurring \(feed.events.filter { $0.rrule != nil }.count), next 90d occurrences \(occ.count), name \(feed.name ?? "-")"
            }.resume()
            _ = sem.wait(timeout: .now() + 25)
            lines.append(line)
        }
        return lines
    }

    static func parserChecks() -> [String] {
        var out: [String] = []
        let sample = """
        BEGIN:VCALENDAR\r
        X-WR-CALNAME:Test\r
        BEGIN:VEVENT\r
        UID:a\r
        SUMMARY:Weekly sync\\, team\r
        DTSTART;TZID=Asia/Seoul:20261005T100000\r
        DTEND;TZID=Asia/Seoul:20261005T103000\r
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6\r
        EXDATE;TZID=Asia/Seoul:20261007T100000\r
        LOCATION:https://meet.google.com/abc-defg-hij\r
        BEGIN:VALARM\r
        TRIGGER:-PT10M\r
        END:VALARM\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:a\r
        RECURRENCE-ID;TZID=Asia/Seoul:20261012T100000\r
        SUMMARY:Weekly sync (moved)\r
        DTSTART;TZID=Asia/Seoul:20261012T150000\r
        DTEND;TZID=Asia/Seoul:20261012T153000\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:b\r
        SUMMARY:Holiday\r
        DTSTART;VALUE=DATE:20261009\r
        DTEND;VALUE=DATE:20261010\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:c\r
        SUMMARY:Monthly review\r
        DTSTART:20261030T010000Z\r
        DURATION:PT1H\r
        RRULE:FREQ=MONTHLY;BYDAY=-1FR;UNTIL=20270301T000000Z\r
        END:VEVENT\r
        END:VCALENDAR\r
        """
        let feed = CalICS.parse(sample)
        let from = CalICS.date("20261001T000000Z", params: [:], defaultTZ: .current)!.date
        let to = CalICS.date("20270401T000000Z", params: [:], defaultTZ: .current)!.date
        let occ = CalICS.expand(feed.events, from: from, to: to)
        let weekly = occ.filter { $0.event.uid == "a" }
        let monthly = occ.filter { $0.event.uid == "c" }
        let link = PIMMeetingLink.find(url: nil, texts: [feed.events.first?.location])
        // 기대: 주간 6회 중 EXDATE 1회 제외 = 5회 (그중 1회는 15시로 옮김), 종일 1개, 월간 마지막 금요일 5회(10~2월)
        let movedOK = weekly.contains { $0.event.summary.contains("moved") }
        out.append("ics parser: name \(feed.name ?? "-"), VEVENT \(feed.events.count), weekly \(weekly.count)/5 moved \(movedOK), monthly-last-friday \(monthly.count)/5, all-day \(occ.filter { $0.event.allDay }.count)/1, escaped title '\(feed.events.first?.summary ?? "")', meet link \(link?.host ?? "none")")
        let now = Date()
        let samples = ["내일 오후 3시 회의", "다음 주 금요일 10시 반 치과", "11월 20일 보고서 마감", "lunch with Alex tomorrow at 1pm", "dentist on Friday"]
        for s in samples {
            if let p = PIMDateParser.parse(s, now: now) {
                out.append("date parser: '\(s)' → '\(p.title)' · \(PIMFormat.preview(p, now: now))")
            } else {
                out.append("date parser: '\(s)' → no date")
            }
        }
        return out
    }
}

/// 메뉴 항목에 클로저를 붙인다
final class CalMenuAction: NSObject {
    let menuItem: NSMenuItem
    private let run: () -> Void

    init(title: String, symbol: String? = nil, run: @escaping () -> Void) {
        self.run = run
        menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        super.init()
        menuItem.target = self
        menuItem.action = #selector(fire)
        menuItem.representedObject = self   // 메뉴가 사는 동안 붙잡아 둔다
        if let symbol { menuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    @objc private func fire() { run() }
}

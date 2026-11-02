import AppKit
import SwiftUI

/// 캘린더 탭: 왼쪽 한 달 달력, 오른쪽 선택한 날부터 한 주 일정·마감 미리 알림과 빠른 추가.
struct CalendarTab: View {
    @ObservedObject var model: CalendarModel
    let focusInput: () -> Void
    @State private var selected: CalItem?
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CalMonthGrid(model: model)
                .frame(width: 222)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
            Group {
                if let item = selected {
                    CalEventDetail(model: model, item: item, close: { selected = nil })
                } else {
                    agenda
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(.white)
        .onAppear {
            let today = Calendar.current.startOfDay(for: Date())
            if model.lastShownDay != today {
                model.lastShownDay = today
                model.goToday()
            } else {
                model.reloadVisible()
            }
            if model.manageEvents, model.access == .granted { focusInput() }
        }
        .onChange(of: model.focusRequest) { _, _ in
            selected = nil
            focusInput()
            DispatchQueue.main.async { inputFocused = true }
        }
    }

    // MARK: 오른쪽: 한 주 일정

    @ViewBuilder private var agenda: some View {
        let hasFeeds = !model.subscriptions.isEmpty
        if model.access != .granted && !hasFeeds {
            accessState
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if model.manageEvents && model.access == .granted { quickAdd }
                if let undo = model.undo {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 10))
                        Text(T("'\(undo.title)' 지움", "Deleted '\(undo.title)'")).font(.system(size: 11)).lineLimit(1)
                        Spacer(minLength: 0)
                        Button(T("되돌리기", "Undo")) { model.undoDelete() }.buttonStyle(PIMPillStyle())
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                } else if let msg = model.message {
                    Text(msg).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                if model.access != .granted {
                    Text(T("캘린더 권한이 없어 구독 일정만 보임", "No calendar access — showing subscriptions only"))
                        .font(.system(size: 10)).foregroundStyle(.orange.opacity(0.9))
                }
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(agendaDays, id: \.self) { day in
                            daySection(day)
                        }
                    }
                }
            }
        }
    }

    private var agendaDays: [Date] {
        let cal = Calendar.current
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: model.selectedDay) }
            .filter { $0 == model.selectedDay || !model.items(on: $0).isEmpty || !model.tasks(on: $0).isEmpty }
    }

    @ViewBuilder private func daySection(_ day: Date) -> some View {
        let events = model.items(on: day)
        let tasks = model.tasks(on: day)
        Text(PIMFormat.dayTitle(day) == PIMFormat.shortDay(day) ? PIMFormat.shortDay(day) : "\(PIMFormat.dayTitle(day)) · \(PIMFormat.shortDay(day))")
            .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
            .padding(.top, day == model.selectedDay ? 0 : 4)
        if events.isEmpty && tasks.isEmpty {
            Text(T("일정 없음", "No events")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).padding(.leading, 2)
        }
        ForEach(events) { e in
            CalEventRow(item: e, day: day) { selected = e }
        }
        ForEach(tasks) { t in
            HStack(spacing: 7) {
                Image(systemName: "circle").font(.system(size: 10)).foregroundStyle(t.color)
                Text(t.title).font(.system(size: 11.5)).lineLimit(1)
                Spacer(minLength: 4)
                Text(t.hasTime ? PIMFormat.time(t.due) : t.list).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.vertical, 2)
            .foregroundStyle(t.due < Date() ? Color.red.opacity(0.95) : .white)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(T("미리 알림 \(t.title)", "Reminder \(t.title)"))
        }
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                TextField(T("새 일정: 내일 오후 3시 회의", "New event: lunch tomorrow at 1pm"), text: $draft)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .focused($inputFocused)
                    .onSubmit(add)
                    .accessibilityLabel(T("새 일정 입력", "New event"))
                if !draft.isEmpty {
                    Button(T("추가", "Add"), action: add).buttonStyle(PIMPillStyle(prominent: true))
                        .help(T("일정 추가 (Return)", "Add event (Return)"))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
            if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(previewText).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
        }
    }

    private var previewText: String {
        let target = model.targetCalendar?.title ?? T("캘린더 없음", "No calendar")
        if let p = PIMDateParser.parse(draft) {
            let title = p.title.isEmpty ? draft : p.title
            return "\(PIMFormat.preview(p)) · '\(title)' → \(target)"
        }
        return "\(PIMFormat.dayTitle(model.selectedDay)) · \(T("하루 종일", "All day")) · '\(draft)' → \(target)"
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if let err = model.create(from: text) { model.flash(err) } else { draft = "" }
    }

    @ViewBuilder private var accessState: some View {
        switch model.access {
        case .notDetermined:
            PIMEmptyState(symbol: "calendar", title: T("캘린더 접근을 허용하세요", "Allow calendar access"),
                          detail: T("macOS 캘린더의 iCloud·Google·Exchange 일정을 읽음", "Reads iCloud, Google and Exchange events from macOS Calendar"),
                          buttonTitle: T("캘린더 허용", "Allow Calendar")) { model.requestAccess() }
        case .missingUsageKey:
            PIMEmptyState(symbol: "exclamationmark.triangle", title: T("지원 안 됨", "Unsupported"),
                          detail: T("이 빌드의 Info.plist에 캘린더 사용 목적 문구가 없음. 대안: .ics 링크 구독", "This build's Info.plist lacks the calendar usage string. Alternative: subscribe to an .ics link"))
        case .writeOnly:
            PIMEmptyState(symbol: "calendar.badge.exclamationmark", title: T("쓰기만 허용됨", "Write-only access"),
                          detail: T("일정을 보려면 시스템 설정에서 '전체 접근'으로 바꾸세요", "Switch to Full Access in System Settings to see events"),
                          buttonTitle: T("시스템 설정 열기", "Open System Settings")) { PIMPrivacy.open("Privacy_Calendars") }
        default:
            PIMEmptyState(symbol: "calendar.badge.exclamationmark", title: T("캘린더 접근이 거부됨", "Calendar access denied"),
                          detail: T("시스템 설정 → 개인정보 보호 → 캘린더에서 켜세요", "Turn it on in System Settings → Privacy → Calendars"),
                          buttonTitle: T("시스템 설정 열기", "Open System Settings")) { PIMPrivacy.open("Privacy_Calendars") }
        }
    }
}

// MARK: - 일정 한 줄

private struct CalEventRow: View {
    let item: CalItem
    let day: Date
    let open: () -> Void

    var body: some View {
        let now = Date()
        let live = !item.allDay && item.start <= now && item.end > now
        HStack(spacing: 7) {
            Capsule().fill(item.color).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    if live { Text(T("진행 중", "Now")).font(.system(size: 9, weight: .bold)).foregroundStyle(item.color) }
                    Text(item.timeText).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).monospacedDigit()
                    Text("· \(item.calendarName)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let url = item.meetingURL, item.end > now {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(T("참가", "Join"), systemImage: "video.fill").labelStyle(.titleAndIcon)
                }
                .buttonStyle(PIMPillStyle(prominent: live || item.start.timeIntervalSince(now) < 15 * 60, tint: item.color))
                .help(url.host ?? "")
                .accessibilityLabel(T("\(item.title) 회의 참가", "Join \(item.title)"))
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(live ? item.color.opacity(0.16) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - 한 달 달력

private struct CalMonthGrid: View {
    @ObservedObject var model: CalendarModel

    private var cal: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(monthTitle).font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                Button { model.moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(PIMPillStyle()).help(T("이전 달", "Previous month")).accessibilityLabel(T("이전 달", "Previous month"))
                Button(T("오늘", "Today")) { model.goToday() }.buttonStyle(PIMPillStyle())
                Button { model.moveMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(PIMPillStyle()).help(T("다음 달", "Next month")).accessibilityLabel(T("다음 달", "Next month"))
            }
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.white.opacity(0.45)).frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 1) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { col in
                            dayCell(days[row * 7 + col])
                        }
                    }
                }
            }
        }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = L10n.isEnglish ? Locale(identifier: "en_US") : Locale(identifier: "ko_KR")
        f.setLocalizedDateFormatFromTemplate("yMMMM")
        return f.string(from: model.month)
    }

    private var weekdaySymbols: [String] {
        var c = cal
        c.locale = L10n.isEnglish ? Locale(identifier: "en_US") : Locale(identifier: "ko_KR")
        let symbols = c.veryShortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var days: [Date] {
        let weekday = cal.component(.weekday, from: model.month)
        let lead = (weekday - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -lead, to: model.month) ?? model.month
        return (0..<42).map { cal.date(byAdding: .day, value: $0, to: start) ?? start }
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = cal.isDate(day, equalTo: model.month, toGranularity: .month)
        let isToday = cal.isDateInToday(day)
        let isSelected = cal.isDate(day, inSameDayAs: model.selectedDay)
        let colors = model.dayColors[cal.startOfDay(for: day)] ?? []
        return Button { model.select(day) } label: {
            VStack(spacing: 1) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 11, weight: isToday || isSelected ? .bold : .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.black : (isToday ? Color.red : Color.white.opacity(inMonth ? 0.92 : 0.3)))
                    .frame(width: 22, height: 19)
                    .background(Circle().fill(isSelected ? Color.white : (isToday ? Color.red.opacity(0.18) : Color.clear)))
                HStack(spacing: 2) {
                    ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { _, c in
                        Circle().fill(c.opacity(inMonth ? 1 : 0.4)).frame(width: 3.5, height: 3.5)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(PIMFormat.shortDay(day))\(colors.isEmpty ? "" : T(", 일정 있음", ", has events"))")
    }
}

// MARK: - 일정 상세·편집

private struct CalEventDetail: View {
    @ObservedObject var model: CalendarModel
    let item: CalItem
    let close: () -> Void
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var allDay = false
    @State private var error: String?

    private var canManage: Bool { model.manageEvents && item.editable && model.access == .granted }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Button { close() } label: { Label(T("일정", "Events"), systemImage: "chevron.left") }
                    .buttonStyle(PIMPillStyle()).accessibilityLabel(T("목록으로", "Back to list"))
                Spacer()
                if let url = item.meetingURL, item.end > Date() {
                    Button { NSWorkspace.shared.open(url) } label: { Label(T("참가", "Join"), systemImage: "video.fill") }
                        .buttonStyle(PIMPillStyle(prominent: true, tint: item.color)).help(url.absoluteString)
                }
            }
            if editing { editor } else { details }
            if let error { Text(error).font(.system(size: 10.5)).foregroundStyle(.orange) }
            Spacer(minLength: 0)
        }
        .onAppear(perform: resetFields)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 7) {
                Capsule().fill(item.color).frame(width: 4, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                    Text("\(PIMFormat.dayTitle(item.start)) · \(item.timeText)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                }
            }
            Label(item.calendarName, systemImage: "calendar").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
            if let loc = item.location, !loc.isEmpty {
                Label(loc, systemImage: "mappin.and.ellipse").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
            }
            if !item.editable {
                Text(reason).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
            }
            if confirmDelete {
                HStack(spacing: 6) {
                    Text(T("이 일정을 지울까요?", "Delete this event?")).font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button(T("취소", "Cancel")) { confirmDelete = false }.buttonStyle(PIMPillStyle())
                    Button(T("삭제", "Delete")) {
                        if let err = model.delete(item) { error = err } else { close() }
                    }
                    .buttonStyle(PIMPillStyle(prominent: true, tint: .red))
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.15)))
            } else {
                HStack(spacing: 6) {
                    if item.origin == .system {
                        Button(T("캘린더 앱에서 열기", "Open in Calendar")) { model.open(item) }.buttonStyle(PIMPillStyle())
                    }
                    if canManage {
                        Button(T("편집", "Edit")) { resetFields(); editing = true }.buttonStyle(PIMPillStyle())
                        Button(T("삭제", "Delete")) { confirmDelete = true }.buttonStyle(PIMPillStyle(tint: .red))
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private var reason: String {
        if case .subscription = item.origin { return T("구독 캘린더는 읽기 전용", "Subscribed calendars are read-only") }
        if item.recurring { return T("반복 일정은 캘린더 앱에서 바꾸세요", "Edit repeating events in the Calendar app") }
        if item.hasAttendees { return T("참석자가 있는 일정은 캘린더 앱에서 바꾸세요", "Edit events with attendees in the Calendar app") }
        return T("읽기 전용 캘린더", "Read-only calendar")
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(T("제목", "Title"), text: $title)
                .textFieldStyle(.plain).font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
            Toggle(T("하루 종일", "All day"), isOn: $allDay).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
            HStack {
                Text(T("시작", "Start")).font(.system(size: 11)).frame(width: 34, alignment: .leading)
                DatePicker("", selection: $start, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field).controlSize(.small)
            }
            HStack {
                Text(T("끝", "End")).font(.system(size: 11)).frame(width: 34, alignment: .leading)
                DatePicker("", selection: $end, in: start..., displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field).controlSize(.small)
            }
            HStack(spacing: 6) {
                Spacer()
                Button(T("취소", "Cancel")) { editing = false; error = nil }.buttonStyle(PIMPillStyle())
                Button(T("저장", "Save")) {
                    if let err = model.update(item, title: title, start: start, end: end, allDay: allDay) { error = err } else { close() }
                }
                .buttonStyle(PIMPillStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .onChange(of: start) { old, new in
            // 시작을 옮기면 길이를 유지한 채 끝도 옮긴다
            end = end.addingTimeInterval(new.timeIntervalSince(old))
        }
    }

    private func resetFields() {
        title = item.title
        start = item.start
        end = item.allDay ? max(item.start, item.end.addingTimeInterval(-1)) : item.end
        allDay = item.allDay
        error = nil
    }
}

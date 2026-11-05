import AppKit
import EventKit
import SwiftUI

/// Apple 미리 알림(EventKit)과 선택적 Todoist 작업.
/// 한 줄 입력 후 Return으로 추가, 미완료 목록, 기한 지남·임박 강조, 완료·완료 취소.
/// 미리 알림 권한(또는 Todoist 토큰과 네트워크)이 필요해 처음에는 꺼져 있다.
final class RemindersModule: NotchModule {
    let id = "reminders"
    var title: String { T("미리 알림", "Reminders") }
    let symbol = "checklist"
    let enabledByDefault = false

    let model = RemindersModel()
    private var context: ModuleContext?
    private var observer: NSObjectProtocol?

    func start(context: ModuleContext) {
        guard self.context == nil else { return }
        self.context = context
        model.reload()
        guard !AppSettings.isHelper else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            self?.model.reload()
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        model.stop()
        context = nil
    }

    func settingsChanged() { model.reload() }

    func tabView() -> AnyView? { AnyView(RemindersTab(model: model, focusInput: { [weak self] in self?.context?.focusInput() })) }
    var tabContentSize: CGSize { CGSize(width: 460, height: 260) }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "reminders.open", title: T("미리 알림 열기", "Open Reminders"),
                       subtitle: model.items.isEmpty ? nil : T("미완료 \(model.items.count)개", "\(model.items.count) open"),
                       symbol: symbol, keywords: ["reminders", "미리 알림", "할 일", "tasks", "todoist"]) { [weak self] in
            self?.context?.openTab("reminders")
        }]
    }

    /// "미리 알림 내일 9시 전화", "remind me call Alex tomorrow at 9", "add reminder …"
    func paletteResults(for query: String) -> [PaletteAction] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let prefixes = ["미리 알림 ", "알림 추가 ", "remind me to ", "remind me ", "add reminder ", "reminder "]
        guard let p = prefixes.first(where: { q.lowercased().hasPrefix($0) }) else { return [] }
        let text = String(q.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, model.canAdd else { return [] }
        let parsed = PIMDateParser.parse(text)
        let title = parsed?.title.isEmpty == false ? parsed!.title : text
        return [PaletteAction(id: "reminders.add", title: T("미리 알림 추가: \(title)", "Add Reminder: \(title)"),
                              subtitle: [parsed.map { PIMFormat.preview($0) }, model.destinationName].compactMap { $0 }.joined(separator: " · "),
                              symbol: "plus.circle") { [weak self] in
            self?.model.add(text, useDate: true) { err in
                if let err { self?.context?.notice(T("추가하지 못함", "Couldn't add"), err, symbol: "exclamationmark.triangle") }
                else { self?.context?.notice(T("미리 알림 추가함", "Reminder added"), title, symbol: "checklist", tab: "reminders") }
            }
        }]
    }

    func settingsView() -> AnyView? { AnyView(RemindersSettings()) }

    func selfTest() -> [String] {
        var lines = ["reminders access: \(PIMAccess.of(.reminder).debugName)",
                     "Info.plist NSRemindersFullAccessUsageDescription: \(PIMPrivacy.hasUsageKey("NSRemindersFullAccessUsageDescription"))",
                     "todoist token in keychain: \(TodoistClient.hasToken)",
                     "todoist enabled: \(model.todoistOn)"]
        if PIMAccess.of(.reminder) == .granted {
            let lists = PIMEventStore.shared.calendars(for: .reminder)
            lines.append("reminder lists: \(lists.count)")
        }
        let p = PIMDateParser.parse("tomorrow at 9 call Alex")
        lines.append("quick add parse: 'tomorrow at 9 call Alex' → '\(p?.title ?? "-")' · \(p.map { PIMFormat.preview($0) } ?? "no date")")
        return lines
    }
}

/// 미리 알림 한 줄 (Apple 또는 Todoist)
struct RemItem: Identifiable, Equatable {
    enum Source: Equatable { case apple, todoist }
    var id: String
    var title: String
    var due: Date?
    var hasTime: Bool
    var color: Color
    var list: String
    var source: Source
}

final class RemindersModel: ObservableObject {
    @Published private(set) var access: PIMAccess = .notDetermined
    @Published private(set) var items: [RemItem] = []
    @Published private(set) var todoistError: String?
    /// 방금 완료한 항목 (잠깐 줄을 긋고 되돌릴 수 있게 남긴다)
    @Published private(set) var completing: Set<String> = []
    @Published var message: String?
    @Published var draft = ""
    @Published var dropDate = false

    let defaults = ModuleDefaults(module: "reminders")
    private let todoist = TodoistClient()
    private var appleItems: [RemItem] = []
    private var todoistItems: [RemItem] = []
    private var removeWork: [String: DispatchWorkItem] = [:]
    private var messageWork: DispatchWorkItem?

    var store: EKEventStore { PIMEventStore.shared }
    var todoistOn: Bool { defaults.bool("todoist", default: false) && TodoistClient.hasToken }
    var useApple: Bool { defaults.bool("useApple", default: true) || !todoistOn }
    var destination: String { todoistOn ? defaults.string("quickAdd", default: "reminders") : "reminders" }
    var destinationName: String {
        if destination == "todoist" { return "Todoist" }
        return targetList?.title ?? T("미리 알림", "Reminders")
    }
    var canAdd: Bool { destination == "todoist" || access == .granted }

    var targetList: EKCalendar? {
        guard access == .granted else { return nil }
        let id = defaults.string("list", default: "")
        if !id.isEmpty, let c = store.calendar(withIdentifier: id) { return c }
        return store.defaultCalendarForNewReminders()
    }

    func stop() {
        todoist.cancel()
        removeWork.values.forEach { $0.cancel() }
        removeWork.removeAll()
        completing.removeAll()
    }

    func reload() {
        access = PIMAccess.of(.reminder)
        if access == .granted, useApple {
            PIMEventStore.refreshIfEmpty(.reminder)
            let id = defaults.string("list", default: "")
            let lists = id.isEmpty ? nil : store.calendar(withIdentifier: id).map { [$0] }
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
            store.fetchReminders(matching: predicate) { [weak self] reminders in
                let mapped: [RemItem] = (reminders ?? []).map { r in
                    let comps = r.dueDateComponents
                    return RemItem(id: r.calendarItemIdentifier, title: r.title ?? "", due: comps.flatMap { Calendar.current.date(from: $0) },
                                   hasTime: comps?.hour != nil, color: Color(nsColor: r.calendar.color ?? .systemOrange),
                                   list: r.calendar.title, source: .apple)
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.appleItems = mapped
                    self.merge()
                }
            }
        } else {
            appleItems = []
            merge()
        }
    }

    /// Todoist는 탭이 보일 때만 읽는다 (네트워크).
    func reloadTodoist() {
        guard todoistOn else { todoistItems = []; todoistError = nil; merge(); return }
        todoist.list { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let tasks):
                self.todoistError = nil
                self.todoistItems = tasks.map { t in
                    let due = t.dueDate
                    return RemItem(id: "todoist:\(t.id)", title: t.content, due: due?.date, hasTime: due?.hasTime ?? false,
                                   color: Color(red: 0.89, green: 0.27, blue: 0.2), list: "Todoist", source: .todoist)
                }
            case .failure(let e):
                self.todoistError = e.localizedDescription
            }
            self.merge()
        }
    }

    private func merge() {
        // 기한 지남 → 기한 있음(빠른 순) → 기한 없음
        let all = appleItems + todoistItems
        let kept = items.filter { completing.contains($0.id) && !all.contains($0) }
        items = (all + kept).sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        }
    }

    // MARK: 쓰기 (사용자가 누른 동작에서만)

    func requestAccess() {
        PIMPrivacy.request(.reminder, store: store) { [weak self] _ in self?.reload() }
    }

    func add(_ text: String, useDate: Bool, done: @escaping (String?) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { done(nil); return }
        let parsed = useDate ? PIMDateParser.parse(trimmed) : nil
        let title = parsed?.title.isEmpty == false ? parsed!.title : trimmed
        if destination == "todoist" {
            todoist.add(title, due: parsed) { [weak self] r in
                switch r {
                case .success: self?.reloadTodoist(); done(nil)
                case .failure(let e): done(e.localizedDescription)
                }
            }
            return
        }
        guard access == .granted, let list = targetList else { done(T("미리 알림 권한이 필요함", "Reminders access is required")); return }
        let r = EKReminder(eventStore: store)
        r.calendar = list
        r.title = title
        if let p = parsed {
            let parts: Set<Calendar.Component> = p.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            r.dueDateComponents = Calendar.current.dateComponents(parts, from: p.date)
            if p.hasTime { r.addAlarm(EKAlarm(absoluteDate: p.date)) }
        }
        do {
            try store.save(r, commit: true)
            reload()
            done(nil)
        } catch {
            done(error.localizedDescription)
        }
    }

    func complete(_ item: RemItem) {
        if completing.contains(item.id) { undo(item); return }
        completing.insert(item.id)
        setCompleted(item, true) { [weak self] err in
            guard let self else { return }
            if let err {
                self.completing.remove(item.id)
                self.flash(err)
                return
            }
            let work = DispatchWorkItem { [weak self] in
                self?.completing.remove(item.id)
                self?.removeWork[item.id] = nil
                self?.reload()
                self?.merge()
            }
            self.removeWork[item.id]?.cancel()
            self.removeWork[item.id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        }
    }

    private func undo(_ item: RemItem) {
        removeWork[item.id]?.cancel()
        removeWork[item.id] = nil
        setCompleted(item, false) { [weak self] err in
            self?.completing.remove(item.id)
            if let err { self?.flash(err) }
            self?.reload()
            if item.source == .todoist { self?.reloadTodoist() }
        }
    }

    private func setCompleted(_ item: RemItem, _ done: Bool, completion: @escaping (String?) -> Void) {
        switch item.source {
        case .todoist:
            let id = String(item.id.dropFirst("todoist:".count))
            let handler: (Result<Void, Error>) -> Void = { r in
                if case .failure(let e) = r { completion(e.localizedDescription) } else { completion(nil) }
            }
            done ? todoist.close(id, completion: handler) : todoist.reopen(id, completion: handler)
        case .apple:
            guard let r = store.calendarItem(withIdentifier: item.id) as? EKReminder else {
                completion(T("미리 알림을 찾지 못함", "Reminder not found")); return
            }
            r.isCompleted = done
            do {
                try store.save(r, commit: true)
                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
    }

    func flash(_ text: String) {
        message = text
        messageWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.message = nil }
        messageWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}

// MARK: - 탭

private struct RemindersTab: View {
    @ObservedObject var model: RemindersModel
    let focusInput: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.access == .granted || model.todoistOn {
                input
                list
            } else {
                accessState
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            model.reload()
            model.reloadTodoist()
            if model.canAdd {
                focusInput()
                DispatchQueue.main.async { focused = true }
            }
        }
    }

    private var parsed: PIMParsedDate? { model.dropDate ? nil : PIMDateParser.parse(model.draft) }

    private var input: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").font(.island(.subhead)).foregroundStyle(.white.opacity(0.6))
                TextField(T("새 미리 알림 (예: 내일 9시 알렉스에게 전화)", "New reminder (e.g. tomorrow at 9 call Alex)"), text: $model.draft)
                    .textFieldStyle(.plain).font(.island(.subhead))
                    .focused($focused)
                    .onSubmit(add)
                    .onChange(of: model.draft) { _, _ in if model.draft.isEmpty { model.dropDate = false } }
                    .accessibilityLabel(T("새 미리 알림", "New reminder"))
                Text(model.destinationName).font(.island(.caption)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
            if let p = PIMDateParser.parse(model.draft) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.island(.caption2))
                    Text(model.dropDate ? T("날짜 없이 추가", "Add without a date") : "\(PIMFormat.preview(p)) · '\(p.title.isEmpty ? model.draft : p.title)'")
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button(model.dropDate ? T("날짜 쓰기", "Use date") : T("날짜 빼기", "No date")) { model.dropDate.toggle() }
                        .buttonStyle(PIMPillStyle())
                }
                .font(.island(.caption)).foregroundStyle(.white.opacity(0.65))
            } else if let msg = model.message {
                Text(msg).font(.island(.caption)).foregroundStyle(.orange)
            }
        }
    }

    private func add() {
        let text = model.draft
        model.add(text, useDate: !model.dropDate) { err in
            if let err { model.flash(err) } else { model.draft = ""; model.dropDate = false }
        }
    }

    @ViewBuilder private var list: some View {
        if let err = model.todoistError {
            Text("Todoist: \(err)").font(.island(.caption)).foregroundStyle(.orange).lineLimit(1)
        }
        if model.items.isEmpty {
            PIMEmptyState(symbol: "checkmark.circle", title: T("미완료 미리 알림 없음", "No open reminders"))
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.items) { item in row(item) }
                }
            }
        }
    }

    private func row(_ item: RemItem) -> some View {
        let done = model.completing.contains(item.id)
        let now = Date()
        let overdue = item.due.map { item.hasTime ? $0 < now : $0 < Calendar.current.startOfDay(for: now) } ?? false
        let soon = item.due.map { !overdue && $0.timeIntervalSince(now) < 24 * 3600 } ?? false
        return HStack(spacing: 8) {
            Button { model.complete(item) } label: { PIMCheckCircle(checked: done, tint: item.color) }
                .buttonStyle(.plain)
                .help(done ? T("완료 취소", "Mark incomplete") : T("완료", "Complete"))
                .accessibilityLabel(done ? T("\(item.title) 완료 취소", "Mark \(item.title) incomplete") : T("\(item.title) 완료", "Complete \(item.title)"))
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(.island(.subhead)).lineLimit(1).strikethrough(done)
                    .foregroundStyle(done ? Color.white.opacity(0.4) : .white)
                if let due = item.due {
                    Text(dueText(due, hasTime: item.hasTime, overdue: overdue))
                        .font(.island(.caption)).foregroundStyle(overdue ? Color.red : (soon ? Color.orange : Color.white.opacity(0.5)))
                }
            }
            Spacer(minLength: 4)
            if done {
                Button(T("되돌리기", "Undo")) { model.complete(item) }.buttonStyle(PIMPillStyle())
            } else {
                Text(item.list).font(.island(.caption2)).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private func dueText(_ due: Date, hasTime: Bool, overdue: Bool) -> String {
        let day = PIMFormat.dayTitle(due)
        let text = hasTime ? "\(day) \(PIMFormat.time(due))" : day
        return overdue ? T("기한 지남 · ", "Overdue · ") + text : text
    }

    @ViewBuilder private var accessState: some View {
        switch model.access {
        case .missingUsageKey:
            PIMEmptyState(symbol: "exclamationmark.triangle", title: T("지원 안 됨", "Unsupported"),
                          detail: T("이 빌드의 Info.plist에 미리 알림 사용 목적 문구가 없어 권한을 요청할 수 없음. 대안: 설정에서 Todoist를 연결하거나 '할 일' 탭 사용",
                                    "This build's Info.plist lacks the Reminders usage string, so access can't be requested. Alternative: connect Todoist in Settings or use the To-Do tab"))
        case .notDetermined:
            PIMEmptyState(symbol: "checklist", title: T("미리 알림 접근을 허용하세요", "Allow Reminders access"),
                          detail: T("Apple 미리 알림을 읽고 추가·완료함 (iCloud로 다른 기기와 동기화)", "Reads, adds and completes Apple Reminders (syncs via iCloud)"),
                          buttonTitle: T("미리 알림 허용", "Allow Reminders")) { model.requestAccess() }
        default:
            PIMEmptyState(symbol: "checklist", title: T("미리 알림 접근이 거부됨", "Reminders access denied"),
                          detail: T("시스템 설정 → 개인정보 보호 → 미리 알림에서 켜세요", "Turn it on in System Settings → Privacy → Reminders"),
                          buttonTitle: T("시스템 설정 열기", "Open System Settings")) { PIMPrivacy.open("Privacy_Reminders") }
        }
    }
}

// MARK: - 설정

private struct RemindersSettings: View {
    private let d = ModuleDefaults(module: "reminders")
    private struct ListRow: Identifiable { var id: String; var title: String; var source: String }

    @State private var access = PIMAccess.of(.reminder)
    @State private var lists: [ListRow] = []
    @State private var list = ""
    @State private var useApple = true
    @State private var todoist = false
    @State private var quickAdd = "reminders"
    @State private var hasToken = TodoistClient.hasToken
    @State private var token = ""
    @State private var status: String?
    @State private var loaded = false
    private let client = TodoistClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PIMSettingsGroup(title: T("Apple 미리 알림", "Apple Reminders")) {
                HStack {
                    Text(T("상태: ", "Status: ") + access.label)
                    Spacer()
                    if access == .notDetermined {
                        Button(T("허용 요청", "Request Access")) {
                            PIMPrivacy.request(.reminder, store: PIMEventStore.shared) { _ in load() }
                        }
                    } else if access == .denied {
                        Button(T("시스템 설정 열기", "Open System Settings")) { PIMPrivacy.open("Privacy_Reminders") }
                    }
                }
                if access == .missingUsageKey {
                    Text(T("지원 안 됨: 이 빌드의 Info.plist에 NSRemindersFullAccessUsageDescription 문구가 없어 권한을 요청할 수 없습니다. 대안: Todoist 연결 또는 '할 일' 기능.",
                           "Unsupported: this build's Info.plist lacks NSRemindersFullAccessUsageDescription, so access can't be requested. Alternative: connect Todoist or use To-Do."))
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if loaded {
                    Toggle(T("Apple 미리 알림 사용", "Use Apple Reminders"), isOn: $useApple)
                        .disabled(useApple && !(todoist && hasToken))
                        .onChange(of: useApple) { _, v in d.set(v, "useApple") }
                    if access == .granted {
                        Picker(T("표시할 목록", "Show List"), selection: $list) {
                            Text(T("모든 목록 (새 항목은 기본 목록)", "All lists (new items go to the default list)")).tag("")
                            ForEach(lists) { l in Text("\(l.title) (\(l.source))").tag(l.id) }
                        }
                        .onChange(of: list) { _, v in d.set(v, "list") }
                    }
                }
            }
            if loaded {
                PIMSettingsGroup(title: "Todoist") {
                    Toggle(T("Todoist 작업 함께 보기", "Show Todoist Tasks"), isOn: $todoist)
                        .onChange(of: todoist) { _, v in d.set(v, "todoist") }
                    Text(T("Todoist 설정 → 연동 → 개발자에서 개인 API 토큰을 복사해 넣으세요. 토큰은 키체인에만 저장하고, 탭을 열 때만 api.todoist.com에 요청합니다.",
                           "Copy your personal API token from Todoist Settings → Integrations → Developer. It's stored only in the Keychain; api.todoist.com is contacted only while the tab is open."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        SecureField(hasToken ? T("저장됨 (바꾸려면 새로 입력)", "Saved (type to replace)") : T("API 토큰", "API token"), text: $token)
                            .textFieldStyle(.roundedBorder)
                        Button(T("저장하고 확인", "Save and Check")) { saveToken() }.disabled(token.isEmpty)
                        if hasToken {
                            Button(T("연결 해제", "Disconnect")) {
                                KeychainStore.set(nil, for: TodoistClient.tokenAccount)
                                hasToken = false
                                status = T("연결 해제함", "Disconnected")
                                if !useApple { useApple = true; d.set(true, "useApple") }
                                d.set(false, "todoist")
                                todoist = false
                            }
                        }
                    }
                    Text(T("연결 상태: ", "Connection: ") + (hasToken ? T("토큰 있음", "Token saved") : T("연결 안 됨", "Not connected")) + (status.map { " · " + $0 } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                    if todoist && hasToken {
                        Picker(T("빠른 추가 저장 위치", "Quick Add Destination"), selection: $quickAdd) {
                            Text(T("Apple 미리 알림", "Apple Reminders")).tag("reminders")
                            Text("Todoist").tag("todoist")
                        }
                        .onChange(of: quickAdd) { _, v in d.set(v, "quickAdd") }
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func saveToken() {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        status = T("확인 중…", "Checking…")
        client.list(token: t) { result in
            switch result {
            case .success(let tasks):
                KeychainStore.set(t, for: TodoistClient.tokenAccount)
                hasToken = true
                token = ""
                status = T("연결됨 · 작업 \(tasks.count)개", "Connected · \(tasks.count) tasks")
                d.set(Date().timeIntervalSince1970, "tokenChanged")
            case .failure(let e):
                status = e.localizedDescription
            }
        }
    }

    private func load() {
        access = PIMAccess.of(.reminder)
        if access == .granted {
            PIMEventStore.refreshIfEmpty(.reminder)
            lists = PIMEventStore.shared.calendars(for: .reminder).map { ListRow(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title) }
                .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
        }
        list = d.string("list", default: "")
        useApple = d.bool("useApple", default: true)
        todoist = d.bool("todoist", default: false)
        quickAdd = d.string("quickAdd", default: "reminders")
        hasToken = TodoistClient.hasToken
        loaded = true
    }
}

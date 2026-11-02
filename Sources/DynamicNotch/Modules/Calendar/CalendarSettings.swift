import EventKit
import SwiftUI

/// 설정 창 묶음 제목 (일정·할 일·메모·날씨 설정이 함께 쓴다)
struct PIMSettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }
}

/// 캘린더 설정 (설정 도우미 프로세스에서 그려진다)
struct CalendarSettings: View {
    private let d = ModuleDefaults(module: "calendar")

    private struct CalRow: Identifiable {
        var id: String
        var title: String
        var color: Color
        var source: String
        var writable: Bool
    }

    @State private var access = PIMAccess.of(.event)
    @State private var reminderAccess = PIMAccess.of(.reminder)
    @State private var calendars: [CalRow] = []
    @State private var loaded = false
    @State private var useMac = true
    @State private var hidden: Set<String> = []
    @State private var manage = true
    @State private var newCal = ""
    @State private var dueTasks = false
    @State private var countdown = true
    @State private var lead = 10
    @State private var keep = false
    @State private var menuBar = false
    @State private var menuTitle = true
    @State private var dateIcon = false
    @State private var alert = false
    @State private var alertMin = 1
    @State private var onlyLink = false
    @State private var subs: [CalSubscription] = []
    @State private var addKind = CalSubscription.Kind.ics
    @State private var addName = ""
    @State private var addURL = ""
    @State private var addUser = ""
    @State private var addPassword = ""
    @State private var addColor = PIMColor.palette[5]
    @State private var addStatus: String?
    @State private var testing = false
    @State private var loader = CalFeedLoader()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            accessGroup
            if loaded { optionGroups }
        }
        .onAppear(perform: load)
    }

    // MARK: 권한·출처

    private var accessGroup: some View {
        PIMSettingsGroup(title: T("캘린더 접근", "Calendar Access")) {
            HStack {
                Text(T("상태: ", "Status: ") + access.label)
                Spacer()
                switch access {
                case .notDetermined:
                    Button(T("허용 요청", "Request Access")) {
                        PIMPrivacy.request(.event, store: PIMEventStore.shared) { _ in load() }
                    }
                case .denied, .writeOnly:
                    Button(T("시스템 설정 열기", "Open System Settings")) { PIMPrivacy.open("Privacy_Calendars") }
                default: EmptyView()
                }
            }
            HStack {
                Text(T("Google·Microsoft 365·Exchange 계정은 시스템 설정 → 인터넷 계정에서 추가하면 여기에 자동으로 나옵니다. 이 앱은 해당 서비스에 직접 로그인하지 않습니다.",
                       "Add Google, Microsoft 365 or Exchange in System Settings → Internet Accounts and they appear here automatically. This app never signs in to those services directly."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(T("인터넷 계정 열기", "Open Internet Accounts")) { PIMPrivacy.openInternetAccounts() }
            }
        }
    }

    @ViewBuilder private var optionGroups: some View {
        PIMSettingsGroup(title: T("캘린더 출처", "Calendar Sources")) {
            Toggle(T("macOS 캘린더 사용", "Use macOS Calendars"), isOn: $useMac)
                .disabled(useMac && subs.isEmpty)
                .onChange(of: useMac) { _, v in d.set(v, "useMacCalendars") }
            if useMac && subs.isEmpty {
                Text(T("끄려면 먼저 .ics 링크나 CalDAV 계정을 추가하세요.", "Add an .ics link or CalDAV account before turning this off."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if access == .granted && useMac {
                let groups = Dictionary(grouping: calendars, by: \.source)
                ForEach(groups.keys.sorted(), id: \.self) { source in
                    Text(source).font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                    ForEach(groups[source] ?? []) { c in
                        Toggle(isOn: Binding(get: { !hidden.contains(c.id) }, set: { on in
                            if on { hidden.remove(c.id) } else { hidden.insert(c.id) }
                            d.set(Array(hidden), "hiddenCalendars")
                        })) {
                            HStack(spacing: 6) {
                                Circle().fill(c.color).frame(width: 9, height: 9)
                                Text(c.title)
                            }
                        }
                    }
                }
            }
        }

        PIMSettingsGroup(title: T("일정과 할 일", "Events & Tasks")) {
            Toggle(T("일정 관리 (빠른 추가·편집·삭제)", "Manage Calendar Events (quick add, edit, delete)"), isOn: $manage)
                .onChange(of: manage) { _, v in d.set(v, "manageEvents") }
            Text(T("입력한 날짜를 미리 보여 주고 쓰기 가능한 Apple 캘린더에 저장합니다. 반복·참석자 있는 일정은 캘린더 앱에서 바꿉니다.",
                   "Shows a date preview and saves to a writable Apple calendar. Repeating events and events with attendees open in Calendar."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if manage && access == .granted {
                Picker(T("새 일정 캘린더", "New Event Calendar"), selection: $newCal) {
                    Text(T("기본 캘린더", "Default Calendar")).tag("")
                    ForEach(calendars.filter(\.writable)) { c in Text("\(c.title) (\(c.source))").tag(c.id) }
                }
                .onChange(of: newCal) { _, v in d.set(v, "newEventCalendar") }
            }
            Toggle(T("마감 미리 알림을 일정과 함께 보기", "Calendar with Due Tasks"), isOn: $dueTasks)
                .onChange(of: dueTasks) { _, v in d.set(v, "dueTasks") }
            if dueTasks {
                HStack {
                    Text(T("미리 알림 권한: ", "Reminders access: ") + reminderAccess.label).font(.caption)
                    Spacer()
                    if reminderAccess == .notDetermined {
                        Button(T("허용 요청", "Request Access")) {
                            PIMPrivacy.request(.reminder, store: PIMEventStore.shared) { _ in reminderAccess = PIMAccess.of(.reminder) }
                        }
                    } else if reminderAccess == .denied {
                        Button(T("시스템 설정 열기", "Open System Settings")) { PIMPrivacy.open("Privacy_Reminders") }
                    }
                }
                if reminderAccess == .missingUsageKey {
                    Text(T("이 빌드는 Info.plist에 미리 알림 사용 목적 문구가 없어 권한을 요청할 수 없습니다.",
                           "This build can't request Reminders access because Info.plist lacks the usage string."))
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }

        PIMSettingsGroup(title: T("라이브 활동", "Live Activity")) {
            Toggle(T("다음 일정 카운트다운", "Upcoming Event Island"), isOn: $countdown)
                .onChange(of: countdown) { _, v in d.set(v, "countdown") }
            Picker(T("몇 분 전부터", "Lead Time"), selection: $lead) {
                ForEach([1, 2, 5, 10, 15, 30, 60], id: \.self) { m in Text(T("\(m)분", "\(m) min")).tag(m) }
            }
            .disabled(!countdown)
            .onChange(of: lead) { _, v in d.set(v, "leadMinutes") }
            Toggle(T("참가하거나 닫을 때까지 남기기", "Keep Until Joined or Dismissed"), isOn: $keep)
                .disabled(!countdown)
                .onChange(of: keep) { _, v in d.set(v, "keepUntilJoined") }
        }

        PIMSettingsGroup(title: T("메뉴 막대", "Menu Bar")) {
            Toggle(T("메뉴 막대에 다음 회의", "Next Meeting in Menu Bar"), isOn: $menuBar)
                .onChange(of: menuBar) { _, v in d.set(v, "menuBar") }
            Toggle(T("일정 제목 보이기", "Show Event Title"), isOn: $menuTitle)
                .disabled(!menuBar)
                .onChange(of: menuTitle) { _, v in d.set(v, "menuBarTitle") }
            Toggle(T("아이콘에 날짜", "Show Date in Icon"), isOn: $dateIcon)
                .disabled(!menuBar)
                .onChange(of: dateIcon) { _, v in d.set(v, "menuBarDateIcon") }
        }

        PIMSettingsGroup(title: T("단축키", "Keyboard Shortcuts")) {
            HStack { Text(T("캘린더 열기", "Open Calendar")); Spacer(); PIMShortcutRecorder(defaults: d, key: "shortcutOpen") }
            HStack { Text(T("회의 참가", "Join Meeting")); Spacer(); PIMShortcutRecorder(defaults: d, key: "shortcutJoin") }
        }

        PIMSettingsGroup(title: T("전체 화면 회의 알림", "Full-Screen Meeting Alert")) {
            Toggle(T("전체 화면 알림", "Full-Screen Alert"), isOn: $alert)
                .onChange(of: alert) { _, v in d.set(v, "fullScreenAlert") }
            Picker(T("알림 시점", "Alert Timing"), selection: $alertMin) {
                Text(T("시작할 때", "At start")).tag(0)
                ForEach([1, 2, 5, 10], id: \.self) { m in Text(T("\(m)분 전", "\(m) min before")).tag(m) }
            }
            .disabled(!alert)
            .onChange(of: alertMin) { _, v in d.set(v, "alertMinutes") }
            Toggle(T("회의 링크가 있는 일정만", "Only Meetings with a Join Link"), isOn: $onlyLink)
                .disabled(!alert)
                .onChange(of: onlyLink) { _, v in d.set(v, "alertOnlyWithLink") }
            HStack {
                Button(T("알림 미리 보기", "Preview Alert")) { d.set(Date().timeIntervalSince1970, "previewAlert") }
                Text(T("기능이 켜져 있을 때 모든 화면에 예시 알림을 띄웁니다. Esc로 닫습니다.", "Shows a sample alert on all displays while the feature is on. Press Esc to close."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        subscriptionsGroup
    }

    // MARK: 구독

    private var subscriptionsGroup: some View {
        PIMSettingsGroup(title: T("다른 캘린더 연결 (읽기 전용)", "Connect Another Calendar (read-only)")) {
            ForEach(subs) { s in
                HStack {
                    Circle().fill(PIMColor.color(hex: s.colorHex)).frame(width: 9, height: 9)
                    Text(s.name)
                    Text(s.kind == .ics ? ".ics" : "CalDAV").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(T("빼기", "Remove")) { remove(s) }
                }
            }
            Picker(T("연결 방식", "Connection Type"), selection: $addKind) {
                Text(T(".ics 링크", ".ics Link")).tag(CalSubscription.Kind.ics)
                Text("CalDAV").tag(CalSubscription.Kind.caldav)
            }
            .pickerStyle(.segmented)
            Text(addKind == .ics
                 ? T("캘린더 공유 설정의 비공개 .ics 주소(webcal:// 또는 https://)를 붙여 넣으세요. 주소는 키체인에만 저장하고 30분마다 다시 읽습니다. 반복 일정은 앞으로 90일까지 펼칩니다.",
                     "Paste the private .ics address (webcal:// or https://) from the calendar's sharing settings. It's stored only in the Keychain and re-read every 30 minutes. Repeating events expand 90 days ahead.")
                 : T("CalDAV 서버나 캘린더 주소(https), 사용자 이름, 앱 전용 비밀번호를 넣으세요. 비밀번호는 키체인에만 저장합니다.",
                     "Enter the CalDAV server or calendar address (https), username and an app-specific password. The password is stored only in the Keychain."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField(T("이름 (예: 회사 일정)", "Name (e.g. Work)"), text: $addName)
            TextField(addKind == .ics ? "webcal://… / https://….ics" : "https://caldav.example.com/", text: $addURL)
            if addKind == .caldav {
                TextField(T("사용자 이름", "Username"), text: $addUser)
                SecureField(T("비밀번호 (앱 전용 비밀번호 권장)", "Password (app-specific recommended)"), text: $addPassword)
            }
            HStack(spacing: 6) {
                ForEach(PIMColor.palette, id: \.self) { hex in
                    Circle().fill(PIMColor.color(hex: hex)).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.primary, lineWidth: addColor == hex ? 2 : 0))
                        .onTapGesture { addColor = hex }
                        .accessibilityLabel(hex)
                }
                Spacer()
                Button(T("추가하고 확인", "Add and Check")) { add() }
                    .disabled(testing || addURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let addStatus { Text(addStatus).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func add() {
        guard let url = CalSubscription.normalize(addURL) else { addStatus = CalFeedError.badURL.localizedDescription; return }
        if addKind == .caldav {
            guard url.scheme?.lowercased() == "https" else { addStatus = CalFeedError.insecure.localizedDescription; return }
            guard !addUser.isEmpty, !addPassword.isEmpty else { addStatus = T("사용자 이름과 비밀번호가 필요함", "Username and password are required"); return }
        }
        let name = addName.trimmingCharacters(in: .whitespaces).isEmpty ? (url.host ?? "Calendar") : addName
        let sub = CalSubscription(id: UUID().uuidString, name: name, kind: addKind, colorHex: addColor,
                                  username: addKind == .caldav ? addUser : nil)
        KeychainStore.set(url.absoluteString, for: sub.urlAccount)
        if addKind == .caldav { KeychainStore.set(addPassword, for: sub.passwordAccount) }
        testing = true
        addStatus = T("확인 중…", "Checking…")
        let now = Date()
        loader.load(sub, from: now, to: now.addingTimeInterval(90 * 86_400)) { result in
            testing = false
            switch result {
            case .success(let feed):
                let count = CalICS.expand(feed.events, from: now, to: now.addingTimeInterval(90 * 86_400)).count
                subs.append(sub)
                CalSubscription.save(subs, d)
                addStatus = T("추가함 · 앞으로 90일 일정 \(count)개", "Added · \(count) events in the next 90 days")
                addName = ""; addURL = ""; addUser = ""; addPassword = ""
            case .failure(let e):
                KeychainStore.set(nil, for: sub.urlAccount)
                KeychainStore.set(nil, for: sub.passwordAccount)
                addStatus = T("추가하지 못함: ", "Couldn't add: ") + e.localizedDescription
            }
        }
    }

    private func remove(_ s: CalSubscription) {
        KeychainStore.set(nil, for: s.urlAccount)
        KeychainStore.set(nil, for: s.passwordAccount)
        subs.removeAll { $0.id == s.id }
        CalSubscription.save(subs, d)
        if subs.isEmpty && !useMac { useMac = true; d.set(true, "useMacCalendars") }
    }

    private func load() {
        access = PIMAccess.of(.event)
        reminderAccess = PIMAccess.of(.reminder)
        if access == .granted {
            PIMEventStore.refreshIfEmpty(.event)
            calendars = PIMEventStore.shared.calendars(for: .event).map {
                CalRow(id: $0.calendarIdentifier, title: $0.title, color: Color(nsColor: $0.color ?? .systemBlue),
                       source: $0.source.title, writable: $0.allowsContentModifications)
            }.sorted { ($0.source, $0.title) < ($1.source, $1.title) }
        }
        useMac = d.bool("useMacCalendars", default: true)
        hidden = Set(d.strings("hiddenCalendars", default: []))
        manage = d.bool("manageEvents", default: true)
        newCal = d.string("newEventCalendar", default: "")
        dueTasks = d.bool("dueTasks", default: false)
        countdown = d.bool("countdown", default: true)
        lead = d.int("leadMinutes", default: 10)
        keep = d.bool("keepUntilJoined", default: false)
        menuBar = d.bool("menuBar", default: false)
        menuTitle = d.bool("menuBarTitle", default: true)
        dateIcon = d.bool("menuBarDateIcon", default: false)
        alert = d.bool("fullScreenAlert", default: false)
        alertMin = d.int("alertMinutes", default: 1)
        onlyLink = d.bool("alertOnlyWithLink", default: false)
        subs = CalSubscription.load(d)
        loaded = true
    }
}

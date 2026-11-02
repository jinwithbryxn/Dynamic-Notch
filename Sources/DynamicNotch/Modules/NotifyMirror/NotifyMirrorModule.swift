import AppKit
import ApplicationServices
import CryptoKit
import SwiftUI

/// 탭 화면이 보는 상태
final class NMState: ObservableObject {
    @Published var items: [NMItem] = []
    @Published var unread = 0
    @Published var trusted = AXIsProcessTrusted()
    /// 답장할 수 있는(배너가 아직 살아 있는) 알림
    @Published var replyable: Set<UUID> = []
    @Published var replyStatus: [UUID: String] = [:]
    @Published var dbStatus: NMDatabase.Status = .notFound
    @Published var dbRecords: [NMDatabase.Record] = []
    @Published var dbBadges: [(String, Int)] = []
    @Published var dbMessage: String?
    @Published var dbLoading = false
}

/// 다른 앱의 macOS 알림 배너를 손쉬운 사용으로 읽어 노치에 띄우고, 암호화한 사본을 기록 탭에 모은다.
/// - 필요 권한: 손쉬운 사용(배너 읽기·닫기·답장). 알림 센터 기록 탭은 전체 디스크 접근.
/// - 평소에는 NotificationCenter 프로세스의 창이 생길 때만 깨어난다 (AXObserver). 권한이 없을 때만 5초마다 권한을 확인한다.
/// - 잠금 화면에서는 노치에 띄우지 않고 기록만 남긴다.
final class NotifyMirrorModule: NotchModule {
    let id = "notifymirror"
    var title: String { T("알림 미러링", "Notification Mirror") }
    let symbol = "bell.badge"
    let enabledByDefault = false

    let state = NMState()
    private let store = NMStore()
    private(set) var context: ModuleContext?
    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }

    // 감시
    private var axObserver: AXObserver?
    private var observedPID: pid_t = 0
    private var trustTimer: Timer?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var lockTokens: [NSObjectProtocol] = []
    private var scanPending = false
    private var scanGeneration = 0
    private var saveWork: DispatchWorkItem?
    private var started = false
    private var locked = false
    private var primed = false
    private var badgePosted = false
    private var lastClearRequest: Double = 0

    /// 이미 본 알림 (내용 해시 → 처음 본 시각)
    private var seen: [String: Date] = [:]
    /// 아직 화면에 있는 배너 (알림 id → 요소·동작)
    private struct Live { var root: AXUIElement; var banner: NMBanner; var itemID: UUID }
    private var live: [UUID: Live] = [:]

    // MARK: 설정

    var privacy: NMPrivacy { NMPrivacy(rawValue: defaults.int("privacy", default: 1)) ?? .sender }
    var notchOnly: Bool { defaults.string("delivery", default: "alongside") == "notchOnly" }
    var compactStyle: Bool { defaults.string("style", default: "card") == "compact" }
    var saveHistory: Bool { defaults.bool("saveHistory", default: true) }
    var retentionDays: Int { defaults.int("retentionDays", default: 7) }
    var unreadBadge: Bool { defaults.bool("unreadBadge", default: false) }
    var muted: [String] { defaults.strings("muted", default: []) }

    private var lastOpenedKey: String { "module.\(id).lastOpened" }
    private var lastOpened: Date {
        get { Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: lastOpenedKey)) }
        set { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: lastOpenedKey) }
    }

    // MARK: 시작·정지

    func start(context: ModuleContext) {
        self.context = context
        guard !started else { return }
        started = true
        lastClearRequest = defaults.double("clearRequest", default: 0)
        state.items = store.load(retentionDays: retentionDays)
        recountUnread()
        state.dbStatus = NMDatabase.status()

        let dnc = DistributedNotificationCenter.default()
        lockTokens = [
            dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.locked = true },
            dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                self?.locked = false
                self?.recountUnread()   // 잠금 중 쌓인 읽지 않은 개수를 다시 보인다
            },
        ]
        let ws = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
                guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == NMBannerReader.bundleID else { return }
                self?.attach()   // 알림 센터 프로세스가 다시 뜨면 다시 붙는다
            },
        ]
        attach()
    }

    func stop() {
        detach()
        trustTimer?.invalidate(); trustTimer = nil
        let dnc = DistributedNotificationCenter.default()
        lockTokens.forEach { dnc.removeObserver($0) }
        lockTokens = []
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens = []
        scanGeneration &+= 1
        scanPending = false
        if badgePosted { context?.center.removePersistent(.notice); badgePosted = false }
        saveWork?.cancel()
        // 사용자가 기능을 끈 경우(앱 종료가 아님): 사본은 휴지통으로, 키는 지운다
        let userDisabled = !defaults.bool("enabled", default: enabledByDefault)
        if userDisabled, !AppSettings.isHelper {
            store.eraseKeyAndTrash()
            state.items = []
        } else if saveHistory, !state.items.isEmpty, !AppSettings.isHelper {
            store.save(state.items)
        }
        live = [:]
        seen = [:]
        primed = false
        started = false
    }

    func settingsChanged() {
        let clear = defaults.double("clearRequest", default: 0)
        if clear > lastClearRequest {
            lastClearRequest = clear
            store.trash()
            state.items = []
        }
        if !saveHistory { store.trash() }
        state.items = store.prune(state.items, retentionDays: retentionDays)
        recountUnread()
    }

    // MARK: 손쉬운 사용 감시

    private func attach() {
        state.trusted = AXIsProcessTrusted()
        guard state.trusted else {
            // 권한이 생기면 바로 붙도록 가볍게 확인한다 (권한 창은 띄우지 않음)
            if trustTimer == nil {
                let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
                    guard let self, AXIsProcessTrusted() else { return }
                    self.trustTimer?.invalidate(); self.trustTimer = nil
                    self.attach()
                }
                t.tolerance = 1
                RunLoop.main.add(t, forMode: .common)
                trustTimer = t
            }
            return
        }
        guard let pid = NMBannerReader.notificationCenterPID() else { return }
        if axObserver != nil, observedPID == pid { return }
        detach()
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<NotifyMirrorModule>.fromOpaque(refcon).takeUnretainedValue().scheduleScan()
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for note in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXUIElementDestroyedNotification] {
            AXObserverAddNotification(observer, app, note as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = observer
        observedPID = pid
        primed = false
        scheduleScan()   // 지금 떠 있는 배너는 '이미 본 것'으로만 기록한다
    }

    private func detach() {
        if let o = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        }
        axObserver = nil
        observedPID = 0
    }

    /// 알림이 연달아 와도 한 묶음만: 0.15초 뒤 읽고, 글자가 늦게 채워지는 경우를 위해 0.6초·1.3초에 한 번씩 더 읽는다.
    func scheduleScan() {
        guard !scanPending else { return }
        scanPending = true
        scanGeneration &+= 1
        let gen = scanGeneration
        for (i, delay) in [0.15, 0.6, 1.3].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.scanGeneration == gen else { return }
                if i == 2 { self.scanPending = false }
                self.scan()
            }
        }
    }

    private func scan() {
        guard started, observedPID != 0 else { return }
        let result = NMBannerReader.parse(NMBannerReader.snapshot(pid: observedPID))
        pruneLive()
        let now = Date()
        if !primed || result.panelOpen {
            // 처음 붙었을 때와 알림 센터 목록이 열렸을 때는 다시 띄우지 않는다
            for b in result.banners { seen[b.signature] = now }
            primed = true
            return
        }
        for b in result.banners where !b.isCall {
            // 같은 배너 요소면 글자가 늘어난 경우만 갱신
            if let el = b.element, let match = live.first(where: { CFEqual($0.value.root, el) }) {
                let key = match.key, entry = match.value
                if b.signature != entry.banner.signature, contentLength(b) > contentLength(entry.banner) {
                    seen[b.signature] = now
                    live[key]?.banner = b
                    update(itemID: entry.itemID, with: b)
                }
                continue
            }
            guard seen[b.signature] == nil else { continue }
            seen[b.signature] = now
            // '5분 전'처럼 지금이 아닌 시각이 붙은 것은 알림 센터 목록의 예전 알림이다
            if b.isFresh == false { continue }
            if isOwnApp(b.appName) { continue }
            handleNew(b, at: now)
        }
        // 같은 내용이 다시 오면(예: 같은 사람의 "ok") 30분 뒤부터는 새 알림으로 본다
        seen = seen.filter { now.timeIntervalSince($0.value) < 30 * 60 }
    }

    private func contentLength(_ b: NMBanner) -> Int { b.title.count + b.subtitle.count + b.body.count }

    private func isOwnApp(_ name: String) -> Bool {
        let own = [Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "Dynamic Notch"].compactMap { $0 }
        return own.contains { !name.isEmpty && name.hasPrefix($0) }
    }

    private func pruneLive() {
        live = live.filter { NMBannerReader.isAlive($0.value.root) }
        let ids = Set(live.values.filter { $0.banner.canReply }.map(\.itemID))
        if ids != state.replyable { state.replyable = ids }
    }

    // MARK: 새 알림

    private func handleNew(_ b: NMBanner, at date: Date) {
        let item = NMItem.make(app: b.appName, title: b.title, subtitle: b.subtitle, body: b.body, date: date, privacy: privacy)
        state.items.insert(item, at: 0)
        if state.items.count > NMStore.maxItems { state.items.removeLast(state.items.count - NMStore.maxItems) }
        if let el = b.element { live[item.id] = Live(root: el, banner: b, itemID: item.id) }
        pruneLive()
        scheduleSave()
        recountUnread()
        let isMuted = muted.contains { $0.caseInsensitiveCompare(b.appName) == .orderedSame }
        // 잠금 중에는 노치에 내용을 띄우지 않는다 (잠금 화면 미리보기 차단)
        guard !locked, !isMuted else { return }
        let presented = present(item, banner: b)
        // '노치에만' 방식: 노치에 띄운 경우에만 macOS 배너를 닫는다 (실패하면 배너를 그대로 둔다)
        // 답장할 수 있는 배너는 닫으면 답장이 불가능해지므로 그대로 둔다
        if presented, notchOnly, !b.canReply { closeBanner(item.id, attempt: 0) }
    }

    private func update(itemID: UUID, with b: NMBanner) {
        guard let i = state.items.firstIndex(where: { $0.id == itemID }) else { return }
        var fresh = NMItem.make(app: b.appName, title: b.title, subtitle: b.subtitle, body: b.body, date: state.items[i].date, privacy: privacy)
        fresh.id = itemID
        state.items[i] = fresh
        scheduleSave()
        if !locked { context?.center.update(.notice) { a in
            guard a.moduleTab == self.id else { return }
            let lines = fresh.lines(self.privacy)
            a.title = lines.0
            a.subtitle = lines.1
        } }
    }

    @discardableResult
    private func present(_ item: NMItem, banner b: NMBanner) -> Bool {
        guard let ctx = context else { return false }
        let lines = item.lines(privacy)
        var actions = [ActivityAction(id: "open", title: T("열기", "Open"), role: .primary) { [weak self] in self?.open(item.id) }]
        if b.canReply {
            actions.append(ActivityAction(id: "reply", title: T("답장", "Reply")) { [weak self] in
                guard let self else { return }
                self.context?.openTab(self.id)
            })
        }
        if b.close != nil {
            actions.append(ActivityAction(id: "dismiss", title: T("닫기", "Dismiss")) { [weak self] in self?.closeBanner(item.id, attempt: 0) })
        }
        ctx.center.post(NotchActivity(
            kind: .notice, priority: ActivityPriority.info, presentation: compactStyle ? .compact : .detail,
            symbol: "bell.badge.fill", tint: .white, value: compactStyle ? .text(item.app) : .none,
            title: lines.0, subtitle: lines.1, wing: NotchActivity.compactWing,
            artwork: NMAppIcons.icon(for: item.app), moduleTab: id, actions: actions))
        return true
    }

    // MARK: 동작

    /// 배너가 아직 있으면 배너를 눌러 해당 메시지로, 없으면 앱을 연다.
    func open(_ itemID: UUID) {
        if let entry = live[itemID], NMBannerReader.isAlive(entry.root), entry.banner.open?.perform() == true { return }
        guard let item = state.items.first(where: { $0.id == itemID }), let url = NMAppIcons.appURL(for: item.app) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// 배너 닫기: ① 배너의 닫기 동작 → 남아 있으면 ② 닫기 버튼, 최대 4번 다시 확인
    func closeBanner(_ itemID: UUID, attempt: Int) {
        guard let entry = live[itemID], NMBannerReader.isAlive(entry.root) else { return }
        if attempt == 0 {
            entry.banner.close?.perform()
        } else {
            let fresh = NMBannerReader.banner(from: NMBannerReader.snapshot(element: entry.root))
            fresh.close?.perform()
        }
        guard attempt < 4 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.closeBanner(itemID, attempt: attempt + 1) }
    }

    func canReply(_ itemID: UUID) -> Bool { state.replyable.contains(itemID) }

    func reply(_ itemID: UUID, text: String) {
        guard let entry = live[itemID], let action = entry.banner.reply else {
            state.replyStatus[itemID] = T("보내지 못함: 배너가 사라짐 — 앱에서 답장하세요", "Not sent: banner is gone — reply in the app")
            return
        }
        state.replyStatus[itemID] = T("보내는 중…", "Sending…")
        NMReplier.send(text, root: entry.root, reply: action, pid: observedPID) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .sent: self.state.replyStatus[itemID] = T("보냄", "Sent")
            case .notSent(let why): self.state.replyStatus[itemID] = T("보내지 못함: ", "Not sent: ") + why
            }
            self.pruneLive()
        }
    }

    /// 탭을 열면 읽음 처리
    func markRead() {
        lastOpened = Date()
        recountUnread()
    }

    private func recountUnread() {
        let since = lastOpened
        state.unread = state.items.filter { $0.date > since && !$0.fromDatabase }.count
        guard let ctx = context else { return }
        if unreadBadge, state.unread > 0, !locked {
            ctx.center.setPersistent(NotchActivity(
                kind: .notice, priority: ActivityPriority.pinned, symbol: "bell.badge.fill", tint: .white,
                value: .text("\(state.unread)"), title: T("읽지 않은 알림", "Unread notifications"),
                wing: NotchActivity.compactWing, moduleTab: id))
            badgePosted = true
        } else if badgePosted {
            ctx.center.removePersistent(.notice)
            badgePosted = false
        }
    }

    private func scheduleSave() {
        guard saveHistory else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.store.save(self.store.prune(self.state.items, retentionDays: self.retentionDays))
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// 알림 센터 기록 불러오기 (사용자가 누를 때만, 전체 디스크 접근)
    func loadDatabase() {
        state.dbStatus = NMDatabase.status()
        state.dbLoading = true
        state.dbMessage = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = NMDatabase.read()
            DispatchQueue.main.async {
                guard let self else { return }
                self.state.dbLoading = false
                switch result {
                case .success(let r):
                    self.state.dbRecords = r.records
                    self.state.dbBadges = r.badges
                    self.state.dbMessage = r.records.isEmpty ? T("기록이 비어 있음", "No records") : nil
                case .failure(let e):
                    self.state.dbRecords = []
                    self.state.dbBadges = []
                    self.state.dbMessage = e.message
                }
            }
        }
    }

    // MARK: 화면

    func tabView() -> AnyView? { AnyView(NMTab(module: self, state: state)) }
    var tabContentSize: CGSize { CGSize(width: 500, height: 290) }
    func settingsView() -> AnyView? { AnyView(NMSettings(module: self)) }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "notifymirror.open", title: T("알림 기록 열기", "Open notification history"),
                       subtitle: state.unread > 0 ? T("읽지 않음 \(state.unread)", "\(state.unread) unread") : nil,
                       symbol: "bell.badge", keywords: ["notification", "알림", "기록", "history"]) { [weak self] in
            guard let self else { return }
            self.context?.openTab(self.id)
        }]
    }

    // MARK: 자체 검사 (읽기만, 권한 창을 띄우지 않음, 알림 내용을 출력하지 않음)

    func selfTest() -> [String] {
        var out: [String] = []
        out.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        out.append("accessibility trusted: \(AXIsProcessTrusted())")
        out.append("NotificationCenter pid: \(NMBannerReader.notificationCenterPID().map(String.init) ?? "not running")")
        if AXIsProcessTrusted(), let pid = NMBannerReader.notificationCenterPID() {
            let scan = NMBannerReader.parse(NMBannerReader.snapshot(pid: pid))
            out.append("live scan: banners=\(scan.banners.count) panelOpen=\(scan.panelOpen) (contents not printed)")
        } else {
            out.append("live scan: skipped (needs Accessibility)")
        }
        switch NMDatabase.status() {
        case .available: out.append("notification DB: readable (not read in self test)")
        case .noFullDiskAccess: out.append("notification DB: blocked (needs Full Disk Access)")
        case .notFound: out.append("notification DB: not found at \(NMDatabase.candidatePaths().count) known paths")
        }
        out.append(contentsOf: NMSelfTest.parserChecks())
        out.append(contentsOf: NMSelfTest.cryptoChecks())
        out.append(contentsOf: NMSelfTest.privacyChecks())
        out.append("history file present: \(store.fileExists) (key not read in self test)")
        return out
    }
}

/// 앱 이름 → 앱 위치·아이콘 (배너는 번들 ID를 주지 않으므로 이름으로 찾는다)
enum NMAppIcons {
    private static var urlCache: [String: URL?] = [:]
    private static var iconCache: [String: NSImage] = [:]

    static func appURL(for name: String) -> URL? {
        guard !name.isEmpty else { return nil }
        if let cached = urlCache[name] { return cached }
        var found: URL? = NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.bundleURL
        if found == nil {
            let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                        "/Applications/Utilities", NSHomeDirectory() + "/Applications"]
            found = dirs.map { URL(fileURLWithPath: "\($0)/\(name).app") }.first { FileManager.default.fileExists(atPath: $0.path) }
        }
        urlCache[name] = found
        return found
    }

    static func icon(for name: String) -> NSImage? {
        if let i = iconCache[name] { return i }
        guard let url = appURL(for: name) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        iconCache[name] = icon
        return icon
    }
}

/// 자체 검사: 실제 배너 대신 macOS 버전별 구조를 본뜬 트리로 파서를 확인한다 (화면에 쓰지 않는 검사 자료).
enum NMSelfTest {
    private static func text(_ v: String, id: String = "") -> NMNode {
        NMNode(role: kAXStaticTextRole as String, identifier: id, value: v)
    }

    static func parserChecks() -> [String] {
        var out: [String] = []
        func check(_ name: String, _ ok: Bool) { out.append("parser \(name): \(ok ? "ok" : "FAIL")") }

        // ① 식별자형 (macOS 14–15 계열): subrole + title/body 식별자 + 닫기 동작
        let a = NMNode(role: "AXGroup", subrole: "AXNotificationCenterBanner", desc: "Messages, Kim, Lunch?",
                       actions: ["AXPress", "Name:Close\nTarget:0x0\nSelector:(null)", "Name:Reply\nTarget:0x0\nSelector:(null)"],
                       children: [NMNode(role: "AXImage", desc: "Messages"), text("Kim", id: "title"), text("now", id: "date"),
                                  text("Lunch?", id: "body")])
        let sa = NMBannerReader.parse([NMNode(role: "AXWindow", children: [NMNode(role: "AXGroup", children: [a])])])
        check("identifier layout", sa.banners.count == 1 && sa.banners[0].title == "Kim" && sa.banners[0].body == "Lunch?"
              && sa.banners[0].appName == "Messages" && sa.banners[0].replySeen && !sa.panelOpen)

        // ② 순서형 (식별자 없음): 제목·부제·본문 순, 시각 글자 제외, 닫기 버튼
        let b = NMNode(role: "AXGroup", children: [
            text("Slack"), text("#general"), text("오후 3:12"), text("Deploy finished"),
            NMNode(role: "AXButton", title: "닫기"),
        ])
        var bb = b
        bb.actions = ["Name:닫기"]
        let sb = NMBannerReader.parse([NMNode(role: "AXWindow", children: [bb])])
        check("ordered layout", sb.banners.count == 1 && sb.banners[0].title == "Slack" && sb.banners[0].subtitle == "#general"
              && sb.banners[0].body == "Deploy finished")

        // ③ 설명만 있는 구조: "앱, 제목, 본문"
        let c = NMNode(role: "AXGroup", subrole: "AXNotificationCenterAlert", desc: "Mail, Invoice, Your invoice is ready")
        let sc = NMBannerReader.parse([NMNode(role: "AXWindow", children: [c])])
        check("description layout", sc.banners.first.map { $0.appName == "Mail" && $0.title == "Invoice" && $0.body == "Your invoice is ready" } ?? false)

        // ④ 통화 배너는 건너뛴다
        let d = NMNode(role: "AXGroup", subrole: "AXNotificationCenterBanner", children: [
            text("FaceTime"), text("Incoming call"), NMNode(role: "AXButton", title: "Accept"), NMNode(role: "AXButton", title: "Decline"),
        ])
        let sd = NMBannerReader.parse([NMNode(role: "AXWindow", children: [d])])
        check("call banner flagged", sd.banners.first?.isCall == true)

        // ⑤ 알림 센터 목록(위젯 포함)이 열리면 미러링하지 않는다
        let widget = NMNode(role: "AXGroup", identifier: "widget-calendar")
        let se = NMBannerReader.parse([NMNode(role: "AXWindow", children: [widget, a])])
        check("panel open detected", se.panelOpen)

        // ⑥ 시각 글자 판별
        check("timestamps", ["now", "5분 전", "3m ago", "오후 3:12", "9:41 AM"].allSatisfy { NMBannerReader.isTimestamp(text($0)) }
              && !NMBannerReader.isTimestamp(text("Lunch at 12?")))
        // ⑥-2 '5분 전'이 붙은 알림은 새 알림이 아님
        let old = NMNode(role: "AXGroup", subrole: "AXNotificationCenterBanner", children: [text("Kim", id: "title"), text("5분 전"), text("hi", id: "body")])
        check("old timestamp not fresh", NMBannerReader.parse([NMNode(role: "AXWindow", children: [old])]).banners.first?.isFresh == false
              && sa.banners[0].isFresh == true)
        // ⑦ 동작 이름
        check("action label", NMBannerReader.actionLabel("Name:Close\nTarget:0x0\nSelector:(null)") == "close")
        // ⑧ 같은 내용 = 같은 해시
        check("signature stable", sa.banners[0].signature == NMBannerReader.parse([NMNode(role: "AXWindow", children: [a])]).banners[0].signature)
        return out
    }

    static func cryptoChecks() -> [String] {
        let key = SymmetricKey(size: .bits256)   // 검사용 임시 키 (키체인에 저장하지 않음)
        let items = [NMItem(date: Date(), app: "A", title: "t", subtitle: "", body: "b")]
        guard let sealed = try? NMStore.seal(items, key: key) else { return ["crypto seal: FAIL"] }
        let roundTrip = (try? NMStore.open(sealed, key: key)) == items
        let wrongKey = (try? NMStore.open(sealed, key: SymmetricKey(size: .bits256))) == nil
        let plaintextHidden = !String(decoding: sealed, as: UTF8.self).contains("\"title\"")
        return ["crypto round trip: \(roundTrip ? "ok" : "FAIL")",
                "crypto wrong key rejected: \(wrongKey ? "ok" : "FAIL")",
                "crypto no plaintext: \(plaintextHidden ? "ok" : "FAIL")"]
    }

    static func privacyChecks() -> [String] {
        let d = Date()
        let appOnly = NMItem.make(app: "A", title: "T", subtitle: "S", body: "B", date: d, privacy: .appOnly)
        let sender = NMItem.make(app: "A", title: "T", subtitle: "S", body: "B", date: d, privacy: .sender)
        let full = NMItem.make(app: "A", title: "T", subtitle: "S", body: "B", date: d, privacy: .full)
        let ok = appOnly.title.isEmpty && appOnly.body.isEmpty && sender.title == "T" && sender.body.isEmpty && full.body == "B"
        return ["privacy levels store only allowed fields: \(ok ? "ok" : "FAIL")"]
    }
}

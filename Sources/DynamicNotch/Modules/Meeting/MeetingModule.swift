import AppKit
import ApplicationServices
import SwiftUI

/// 회의 앱 통화 상태·제어 (M-J-011, M-J-012).
/// 통화 판단: 회의 앱(또는 Meet을 연 브라우저)이 마이크를 쓰고 있으면 통화. macOS 14.2 이상은 프로세스별 입력 사용으로 앱을 특정하고,
/// 그보다 낮으면 '마이크 사용 + 회의 앱 실행'으로 추정한다. 소리를 녹음하거나 읽지 않는다.
/// 제어: 앱 메뉴 항목 누르기(손쉬운 사용) 또는 앱을 앞으로 가져와 그 앱의 단축키 보내기. 앱이 바뀌면 동작이 멈출 수 있다.
final class MeetingModule: NotchModule {
    let id = "meeting"
    var title: String { T("회의 통화", "Meeting Calls") }
    let symbol = "video.bubble"
    /// 백그라운드 감시·손쉬운 사용 권한이 필요해 기본 꺼짐
    var enabledByDefault: Bool { false }

    enum Control: String, CaseIterable { case mute, camera, leave }

    enum Method {
        case menu([String], fallback: Shortcut?)
        case shortcut(Shortcut)
        case unsupported(String)
    }

    struct Shortcut {
        let key: CGKeyCode
        let flags: CGEventFlags
        let label: String
    }

    struct App {
        let name: String
        let bundleIDs: [String]
        var browser = false
        let controls: [Control: Method]

        func method(_ c: Control) -> Method { controls[c] ?? .unsupported(T("이 앱은 지원 안 됨", "Not supported for this app")) }
    }

    static let cmdShift: CGEventFlags = [.maskCommand, .maskShift]
    static let apps: [App] = [
        App(name: "Zoom", bundleIDs: ["us.zoom.xos"], controls: [
            .mute: .menu(["Mute Audio", "Unmute Audio", "오디오 음소거", "오디오 음소거 해제"], fallback: Shortcut(key: 0, flags: cmdShift, label: "⇧⌘A")),
            .camera: .menu(["Start Video", "Stop Video", "비디오 시작", "비디오 중지"], fallback: Shortcut(key: 9, flags: cmdShift, label: "⇧⌘V")),
            .leave: .shortcut(Shortcut(key: 13, flags: .maskCommand, label: "⌘W")),
        ]),
        App(name: "Microsoft Teams", bundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"], controls: [
            .mute: .shortcut(Shortcut(key: 46, flags: cmdShift, label: "⇧⌘M")),
            .camera: .shortcut(Shortcut(key: 31, flags: cmdShift, label: "⇧⌘O")),
            .leave: .shortcut(Shortcut(key: 4, flags: cmdShift, label: "⇧⌘H")),
        ]),
        App(name: "Slack", bundleIDs: ["com.tinyspeck.slackmacgap"], controls: [
            .mute: .shortcut(Shortcut(key: 49, flags: cmdShift, label: "⇧⌘Space")),
            .camera: .shortcut(Shortcut(key: 9, flags: cmdShift, label: "⇧⌘V")),
            .leave: .shortcut(Shortcut(key: 4, flags: cmdShift, label: "⇧⌘H")),
        ]),
        App(name: "Discord", bundleIDs: ["com.hnc.Discord"], controls: [
            .mute: .shortcut(Shortcut(key: 46, flags: cmdShift, label: "⇧⌘M")),
            .camera: .unsupported(T("Discord에 기본 단축키가 없음", "Discord has no default shortcut")),
            .leave: .unsupported(T("Discord에 기본 단축키가 없음", "Discord has no default shortcut")),
        ]),
        App(name: "Webex", bundleIDs: ["Cisco-Systems.Spark", "com.webex.meetingmanager", "com.cisco.webexmeetingsapp"], controls: [
            .mute: .shortcut(Shortcut(key: 46, flags: cmdShift, label: "⇧⌘M")),
            .camera: .shortcut(Shortcut(key: 9, flags: cmdShift, label: "⇧⌘V")),
            .leave: .unsupported(T("Webex 나가기는 확인 창이 달라 지원 안 됨", "Webex leave uses its own dialog; not supported")),
        ]),
        App(name: "WhatsApp", bundleIDs: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"], controls: [
            .mute: .unsupported(T("상태 표시만 지원", "Status only")),
            .camera: .unsupported(T("상태 표시만 지원", "Status only")),
            .leave: .unsupported(T("상태 표시만 지원", "Status only")),
        ]),
        App(name: "Google Meet", bundleIDs: ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser",
                                              "com.microsoft.edgemac", "com.brave.Browser", "org.mozilla.firefox"], browser: true, controls: [
            .mute: .shortcut(Shortcut(key: 2, flags: .maskCommand, label: "⌘D")),
            .camera: .shortcut(Shortcut(key: 14, flags: .maskCommand, label: "⌘E")),
            .leave: .unsupported(T("탭을 닫으면 다른 탭도 닫힐 수 있어 지원 안 됨", "Not supported (closing the tab is risky)")),
        ]),
    ]

    static func app(for bundleID: String?) -> App? {
        guard let bundleID else { return nil }
        return apps.first { $0.bundleIDs.contains(bundleID) }
    }

    final class State: ObservableObject {
        @Published var call: (app: App, running: NSRunningApplication, since: Date, guessed: Bool)?
        @Published var muted: Bool?
        @Published var message: String?
        @Published var axGranted = CPPermission.accessibility.granted
        var callID: String? { call.map { "\($0.app.name)-\($0.running.processIdentifier)" } }
    }

    let state = State()
    private var context: ModuleContext?
    private let monitor = CPDeviceUseMonitor()
    private var recheck: Timer?
    private var pending: (key: String?, since: Date)?
    private var pendingWork: DispatchWorkItem?
    private var workspaceObservers: [NSObjectProtocol] = []

    func start(context: ModuleContext) {
        self.context = context
        monitor.onChange = { [weak self] _ in self?.evaluate() }
        monitor.start()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.evaluate() })
        }
        evaluate()
    }

    func stop() {
        monitor.stop()
        monitor.onChange = nil
        recheck?.invalidate()
        recheck = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        state.call = nil
        pending = nil
        pendingWork?.cancel()
        pendingWork = nil
        context = nil
    }

    func tabView() -> AnyView? { AnyView(MeetingTab(module: self, state: state)) }
    var tabContentSize: CGSize { CGSize(width: 560, height: 240) }

    // MARK: 통화 판단

    /// 지금 통화 중인 회의 앱 (가장 그럴듯한 하나)
    private func detect() -> (App, NSRunningApplication, Bool)? {
        let snap = CPDeviceUseMonitor.current()
        guard snap.micOn else { return nil }
        let pids = CPDeviceUseMonitor.audioInputPIDs()
        if !pids.isEmpty {
            for pid in pids {
                guard let owner = CPDeviceUseMonitor.owningApp(pid), let app = Self.app(for: owner.bundleIdentifier) else { continue }
                if app.browser && !Self.browserShowsMeet(owner) { continue }
                return (app, owner, false)
            }
            return nil
        }
        // 14.2 미만 또는 목록이 비면: 마이크 사용 + 회의 앱 실행으로 추정 (브라우저 제외)
        for running in NSWorkspace.shared.runningApplications {
            if let app = Self.app(for: running.bundleIdentifier), !app.browser { return (app, running, true) }
        }
        return nil
    }

    /// 브라우저 창 제목에 Meet이 있는지 (손쉬운 사용 권한이 있을 때만 확인, 없으면 통화로 보지 않음)
    static func browserShowsMeet(_ app: NSRunningApplication) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.3)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return false }
        return windows.contains { w in
            var t: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
            let title = (t as? String) ?? ""
            return title.contains("Meet") || title.contains("meet.google.com")
        }
    }

    /// 시작은 3초, 끝은 5초 같은 상태가 이어져야 바꾼다 (접속음·헤드셋 교체로 깜빡이지 않게)
    private func evaluate() {
        state.axGranted = CPPermission.accessibility.granted
        let found = detect()
        let key = found.map { "\($0.0.name)-\($0.1.processIdentifier)" }
        // 마이크를 쓰는 동안만 5초마다 다시 본다 (앱이 바뀌어도 장치 알림이 오지 않는 경우)
        if CPDeviceUseMonitor.current().micOn || state.call != nil {
            if recheck == nil {
                let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.evaluate() }
                t.tolerance = 1
                RunLoop.main.add(t, forMode: .common)
                recheck = t
            }
        } else {
            recheck?.invalidate()
            recheck = nil
        }
        if key == state.callID { pending = nil; return }
        if pending?.key != key { pending = (key, Date()) }
        let wait: TimeInterval = key == nil ? 5 : 3
        let elapsed = Date().timeIntervalSince(pending?.since ?? Date())
        if elapsed >= wait {
            apply(found)
            pending = nil
        } else {
            pendingWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.evaluate() }
            pendingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + wait - elapsed + 0.1, execute: work)
        }
    }

    private func apply(_ found: (App, NSRunningApplication, Bool)?) {
        let old = state.call
        if let (app, running, guessed) = found {
            state.call = (app, running, Date(), guessed)
            state.muted = readMuted(app, running)
            CPSounds.play(.meetingStart)
            var actions: [ActivityAction] = []
            if case .unsupported = app.method(.mute) {} else {
                actions.append(ActivityAction(id: "mute", title: T("음소거", "Mute")) { [weak self] in self?.perform(.mute) })
            }
            if case .unsupported = app.method(.leave) {} else {
                actions.append(ActivityAction(id: "leave", title: T("나가기", "Leave"), role: .destructive) { [weak self] in self?.perform(.leave) })
            }
            context?.notice(T("\(app.name) 통화 중", "\(app.name) call"), guessed ? T("추정 (마이크 사용 + 앱 실행)", "Guessed (mic in use + app open)") : nil,
                            symbol: "video.bubble", tint: .green, tab: id, actions: actions)
        } else if let old {
            state.call = nil
            state.muted = nil
            CPSounds.play(.meetingEnd)
            let mins = Int(Date().timeIntervalSince(old.since) / 60)
            context?.notice(T("\(old.app.name) 통화 끝", "\(old.app.name) call ended"), T("\(mins)분", "\(mins) min"),
                            symbol: "phone.down.fill", tint: .red, tab: id, duration: 3)
        }
    }

    // MARK: 제어

    func perform(_ c: Control) {
        guard let call = state.call else { return }
        guard AXIsProcessTrusted() else {
            CPPermission.accessibility.request()
            state.message = T("손쉬운 사용 권한이 필요함", "Accessibility permission is needed")
            return
        }
        switch call.app.method(c) {
        case .unsupported(let why):
            state.message = why
        case .shortcut(let s):
            send(s, to: call.running)
            state.message = T("\(s.label)를 \(call.app.name)에 보냄 (앱이 앞으로 옴)", "Sent \(s.label) to \(call.app.name) (app comes to front)")
        case .menu(let titles, let fallback):
            if Self.pressMenu(titles, in: call.running) {
                state.message = T("\(call.app.name) 메뉴 항목을 누름", "Pressed the \(call.app.name) menu item")
            } else if let s = fallback {
                send(s, to: call.running)
                state.message = T("메뉴 항목을 못 찾아 \(s.label)를 보냄", "Menu item not found; sent \(s.label)")
            } else {
                state.message = T("메뉴 항목을 찾지 못함", "Menu item not found")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, let call = self.state.call else { return }
            self.state.muted = self.readMuted(call.app, call.running)
        }
    }

    func bringToFront() {
        state.call?.running.activate()
    }

    private func send(_ s: Shortcut, to app: NSRunningApplication) {
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: nil, virtualKey: s.key, keyDown: down)
                e?.flags = s.flags
                e?.post(tap: .cghidEventTap)
            }
        }
    }

    /// 앱 메뉴 막대에서 제목이 맞는 메뉴 항목을 찾아 누른다 (앱을 앞으로 가져오지 않음)
    static func pressMenu(_ titles: [String], in app: NSRunningApplication) -> Bool {
        guard let item = findMenuItem(titles, in: app) else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    static func findMenuItem(_ titles: [String], in app: NSRunningApplication) -> AXUIElement? {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.4)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXMenuBarAttribute as CFString, &bar) == .success, let menuBar = bar else { return nil }
        let wanted = Set(titles)
        var stack: [(AXUIElement, Int)] = [(menuBar as! AXUIElement, 0)]
        while let (el, depth) = stack.popLast() {
            var t: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &t)
            if let title = t as? String, wanted.contains(title), depth > 1 {
                var enabled: CFTypeRef?
                AXUIElementCopyAttributeValue(el, kAXEnabledAttribute as CFString, &enabled)
                if (enabled as? Bool) != false { return el }
            }
            guard depth < 4 else { continue }
            var kids: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kids) == .success, let list = kids as? [AXUIElement] {
                stack.append(contentsOf: list.map { ($0, depth + 1) })
            }
        }
        return nil
    }

    /// Zoom처럼 메뉴 항목 제목이 상태를 알려 줄 때만 읽는다 (모르면 nil)
    private func readMuted(_ app: App, _ running: NSRunningApplication) -> Bool? {
        guard AXIsProcessTrusted(), case .menu = app.method(.mute) else { return nil }
        if Self.findMenuItem(["Unmute Audio", "오디오 음소거 해제"], in: running) != nil { return true }
        if Self.findMenuItem(["Mute Audio", "오디오 음소거"], in: running) != nil { return false }
        return nil
    }

    func selfTest() -> [String] {
        let running = NSWorkspace.shared.runningApplications.compactMap { r -> String? in
            guard let app = Self.app(for: r.bundleIdentifier) else { return nil }
            return app.browser ? "\(r.localizedName ?? "browser") (for \(app.name))" : "\(app.name)"
        }
        let pids = CPDeviceUseMonitor.audioInputPIDs()
        return [
            "accessibility (no prompt): \(CPPermission.accessibility.granted)",
            "meeting-capable apps running: \(running.isEmpty ? "none" : running.joined(separator: ", "))",
            "mic in use now: \(CPDeviceUseMonitor.current().micOn), input processes: \(pids.count)",
            "per-process input API (macOS 14.2+): \(ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 14, minorVersion: 2, patchVersion: 0)))",
            "detected call now: \(detect().map { "\($0.0.name) guessed=\($0.2)" } ?? "none")",
            "no controls sent in self test",
        ]
    }
}

private struct MeetingTab: View {
    let module: MeetingModule
    @ObservedObject var state: MeetingModule.State

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let call = state.call {
                HStack(spacing: 10) {
                    if let icon = call.running.icon {
                        Image(nsImage: icon).resizable().frame(width: 30, height: 30)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(T("\(call.app.name) 통화 중", "\(call.app.name) call")).font(.system(size: 14, weight: .semibold))
                        HStack(spacing: 6) {
                            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                let s = Int(ctx.date.timeIntervalSince(call.since))
                                Text(String(format: "%d:%02d", s / 60, s % 60)).monospacedDigit()
                            }
                            if call.guessed { Text(T("· 추정", "· guessed")) }
                            if let m = state.muted { Text(m ? T("· 음소거됨", "· muted") : T("· 마이크 켜짐", "· mic on")) }
                        }
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                }
                HStack(spacing: 6) {
                    control(.mute, "mic.slash.fill", T("음소거", "Mute"), call.app)
                    control(.camera, "video.slash.fill", T("카메라", "Camera"), call.app)
                    control(.leave, "phone.down.fill", T("나가기", "Leave"), call.app, tint: .red)
                    CPTile(symbol: "arrow.uturn.backward.circle", title: T("회의로 돌아가기", "Back to Call")) { module.bringToFront() }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "video.bubble").font(.system(size: 18)).foregroundStyle(.white.opacity(0.4))
                    Text(T("지금 통화 없음. 회의 앱이 마이크를 쓰기 시작하면 3초 뒤 여기와 노치에 나온다.",
                           "No call now. When a meeting app starts using the microphone, it shows here and in the notch after 3 s."))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
            Text(T("지원: Zoom(메뉴 항목) · Teams·Slack·Webex·Discord·Meet(단축키, 앱이 앞으로 옴) · WhatsApp(상태만). Meet은 브라우저 창 제목으로 알아보며 손쉬운 사용 권한이 필요하다.",
                   "Supported: Zoom (menu items) · Teams, Slack, Webex, Discord, Meet (shortcuts; the app comes to front) · WhatsApp (status only). Meet is recognized by the browser window title and needs Accessibility."))
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            CPPermissionLine(permission: .accessibility, granted: state.axGranted)
            if let m = state.message {
                Text(m).font(.system(size: 10.5)).foregroundStyle(.orange).lineLimit(2)
            }
            CPUnsupported(title: T("마이크 레벨 표시 보류", "Mic level meter deferred"),
                          reason: T("소리 크기를 읽으려면 마이크 권한과 Info.plist 사용 목적 문구가 필요한데 지금 앱에는 없다.",
                                    "Reading levels needs microphone permission and an Info.plist usage string, which the app lacks."))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { state.axGranted = CPPermission.accessibility.granted }
    }

    private func control(_ c: MeetingModule.Control, _ symbol: String, _ title: String, _ app: MeetingModule.App, tint: Color = .white) -> some View {
        let method = app.method(c)
        var help = ""
        var disabled = false
        switch method {
        case .menu(_, let fb): help = T("메뉴 항목 누르기", "Press the menu item") + (fb.map { T(" (안 되면 \($0.label))", " (fallback \($0.label))") } ?? "")
        case .shortcut(let s): help = T("\(s.label) 보내기 · 앱이 앞으로 옴", "Send \(s.label) · app comes to front")
        case .unsupported(let why): help = why; disabled = true
        }
        return CPTile(symbol: symbol, title: title, tint: tint, help: help, disabled: disabled) { module.perform(c) }
    }
}

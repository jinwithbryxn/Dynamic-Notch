import AppKit
import SwiftUI

/// 개인정보 (M-J-015 카메라 사용 표시, M-J-016 마이크 사용 표시, M-J-018·019 Camera Guard, M-J-033 화면 잠금 버튼).
/// Camera Guard는 카메라가 이미 켜진 뒤에 알리고, 고르면 그 앱에 종료를 요청한다. 미리 막거나 첫 프레임을 막지 않는다.
final class PrivacyModule: NotchModule {
    let id = "privacy"
    var title: String { T("개인정보", "Privacy") }
    let symbol = "hand.raised"
    /// 장치 상태를 백그라운드에서 지켜보므로 기본 꺼짐
    var enabledByDefault: Bool { false }

    /// Camera Guard가 고른 앱 (추정)
    struct GuardEvent: Identifiable {
        let id = UUID()
        let date: Date
        let cameras: [String]
        let app: NSRunningApplication?
        let appName: String?
        let reason: String
        let others: [String]
    }

    final class State: ObservableObject {
        private let d = ModuleDefaults(module: "privacy")
        @Published var snapshot = CPDeviceUseMonitor.Snapshot()
        @Published var showInNotch: Bool { didSet { d.set(showInNotch, "showInNotch"); onChange?() } }
        @Published var guardOn: Bool { didSet { d.set(guardOn, "guard") } }
        @Published var allow: [String] { didSet { d.set(allow, "allow") } }
        @Published var lastGuard: GuardEvent?
        @Published var message: String?
        var onChange: (() -> Void)?

        init() {
            showInNotch = d.bool("showInNotch", default: true)
            guardOn = d.bool("guard", default: false)
            allow = d.strings("allow", default: [])
        }
    }

    let state = State()
    private let monitor = CPDeviceUseMonitor()
    private var context: ModuleContext?
    private var guardWork: DispatchWorkItem?

    func start(context: ModuleContext) {
        self.context = context
        state.onChange = { [weak self] in self?.updateIndicator() }
        monitor.onChange = { [weak self] s in self?.changed(s) }
        monitor.start()
        state.snapshot = monitor.snapshot
        updateIndicator()
    }

    func stop() {
        monitor.stop()
        monitor.onChange = nil
        guardWork?.cancel()
        context?.center.removePersistent(.privacy)
        context?.center.dismissTransient(kind: .privacy)
        state.onChange = nil
        context = nil
    }

    func settingsChanged() {
        let d = ModuleDefaults(module: id)
        state.allow = d.strings("allow", default: [])
    }

    func tabView() -> AnyView? { AnyView(PrivacyTab(module: self, state: state)) }
    var tabContentSize: CGSize { CGSize(width: 560, height: 200) }

    func paletteActions() -> [PaletteAction] {
        [
            PaletteAction(id: "privacy.lock", title: T("화면 잠금", "Lock Screen"), symbol: "lock.fill",
                          keywords: ["lock", "잠금", "화면 잠금"]) { [weak self] in self?.lockScreen() },
            PaletteAction(id: "privacy.displaysleep", title: T("디스플레이 끄기", "Turn Off Display"), symbol: "display",
                          keywords: ["display sleep", "디스플레이", "화면 끄기"]) { CPScreenLock.sleepDisplays() },
        ]
    }

    func settingsView() -> AnyView? { AnyView(PrivacySettings(state: state)) }

    // MARK: 상태 변화

    private func changed(_ s: CPDeviceUseMonitor.Snapshot) {
        let wasCamera = state.snapshot.cameraOn, wasMic = state.snapshot.micOn
        state.snapshot = s
        updateIndicator()
        if s.micOn && !wasMic { CPSounds.play(.micOn) }
        if s.cameraOn && !wasCamera && state.guardOn {
            // 카메라를 연 앱이 마이크도 여는 경우가 많아 잠깐 기다렸다가 고른다
            guardWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.cameraStarted() }
            guardWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
        }
        if !s.cameraOn { guardWork?.cancel() }
    }

    private func updateIndicator() {
        guard let center = context?.center else { return }
        let s = state.snapshot
        guard state.showInNotch, s.cameraOn || s.micOn else { center.removePersistent(.privacy); return }
        let text: String
        if s.cameraOn && s.micOn { text = T("카메라 마이크", "Cam Mic") }
        else if s.cameraOn { text = T("카메라", "Camera") }
        else { text = T("마이크", "Mic") }
        center.setPersistent(NotchActivity(
            kind: .privacy, priority: ActivityPriority.info, symbol: s.cameraOn ? "video.fill" : "mic.fill",
            tint: s.cameraOn ? .green : .orange, value: .text(text),
            title: T("사용 중: ", "In use: ") + (s.cameras + s.mics).joined(separator: ", "),
            wing: NotchActivity.compactWing, moduleTab: id))
    }

    /// 카메라를 쓰기 시작한 앱을 최선으로 추정한다 (확정할 공개 API가 없다)
    private func cameraStarted() {
        guard state.snapshot.cameraOn else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        var candidates: [(NSRunningApplication, String)] = []
        func add(_ app: NSRunningApplication?, _ why: String) {
            guard let app, app.processIdentifier != me, !candidates.contains(where: { $0.0 == app }) else { return }
            candidates.append((app, why))
        }
        let front = NSWorkspace.shared.frontmostApplication
        let frontApp = front?.processIdentifier == me ? ModuleServices.previousApp : front
        let micApps = CPDeviceUseMonitor.audioInputPIDs().compactMap { CPDeviceUseMonitor.owningApp($0) }
            .filter { $0.activationPolicy == .regular }
        // 앞에 있으면서 마이크도 쓰는 앱 → 마이크를 쓰는 앱 → 앞에 있는 앱 순
        for app in micApps where app == frontApp { add(app, T("앞에 있고 마이크도 쓰는 중", "frontmost and using the mic")) }
        for app in micApps { add(app, T("마이크도 쓰는 중", "also using the mic")) }
        if frontApp?.activationPolicy == .regular { add(frontApp, T("카메라가 켜질 때 앞에 있던 앱", "frontmost when the camera turned on")) }

        let allowed = Set(state.allow)
        let pick = candidates.first { !allowed.contains($0.0.bundleIdentifier ?? "") }
        if let first = candidates.first, allowed.contains(first.0.bundleIdentifier ?? "") {
            return   // 허용 목록 앱이 가장 유력하면 알리지 않는다
        }
        let event = GuardEvent(date: Date(), cameras: state.snapshot.cameras, app: pick?.0, appName: pick?.0.localizedName,
                               reason: pick?.1 ?? T("어떤 앱인지 알아낼 수 없음", "Could not tell which app"),
                               others: candidates.dropFirst().map { $0.0.localizedName ?? "?" })
        state.lastGuard = event
        CPSounds.play(.cameraGuard)
        var actions: [ActivityAction] = []
        if let app = event.app {
            actions.append(ActivityAction(id: "quit", title: T("앱 종료 요청", "Ask App to Quit"), role: .destructive) { [weak self] in self?.askToQuit(app) })
            actions.append(ActivityAction(id: "allow", title: T("허용 목록에 추가", "Always Allow")) { [weak self] in self?.allowApp(app) })
        }
        let title = event.appName.map { T("카메라 켜짐 · \($0) (추정)", "Camera on · \($0) (likely)") }
            ?? T("카메라 켜짐 · 앱을 알 수 없음", "Camera on · app unknown")
        context?.center.post(NotchActivity(kind: .privacy, priority: ActivityPriority.screenshot, presentation: .detail, duration: 12,
                                           symbol: "video.fill", tint: .yellow, title: title,
                                           subtitle: T("카메라가 켜진 뒤의 알림 · ", "Notice after the camera turned on · ") + event.reason,
                                           moduleTab: id, actions: actions))
    }

    /// 정상 종료 요청만 보낸다 (강제 종료 없음). 저장 여부는 그 앱이 묻는다.
    func askToQuit(_ app: NSRunningApplication) {
        let ok = app.terminate()
        state.message = ok ? T("\(app.localizedName ?? "앱")에 종료를 요청함", "Asked \(app.localizedName ?? "the app") to quit")
            : T("종료 요청을 보내지 못함", "Could not send the quit request")
    }

    func allowApp(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier, !state.allow.contains(id) else { return }
        state.allow.append(id)
        state.message = T("허용 목록에 추가: ", "Allowed: ") + (app.localizedName ?? id)
    }

    func lockScreen() {
        if let err = CPScreenLock.lockNow() { state.message = err }
    }

    func selfTest() -> [String] {
        let s = CPDeviceUseMonitor.current()
        let cams = CPDeviceUseMonitor.cameraDevices().map { CPDeviceUseMonitor.cmioName($0) }
        let mics = CPDeviceUseMonitor.inputDevices().map { CPDeviceUseMonitor.audioName($0) }
        let pids = CPDeviceUseMonitor.audioInputPIDs()
        let names = pids.compactMap { CPDeviceUseMonitor.owningApp($0)?.localizedName }
        // 장치 목록 알림이 몰려와도 한 번만 맞추고, 그대로인 장치의 알림은 다시 걸지 않는지 (2026-11-02 먹통 재발 방지)
        let probe = CPDeviceUseMonitor()
        probe.start()
        let addsAtStart = probe.listenerAdds
        let started = Date()
        for _ in 0..<5000 { probe.deviceListChanged() }
        let burstTime = Date().timeIntervalSince(started)
        RunLoop.main.run(until: Date().addingTimeInterval(CPDeviceUseMonitor.syncDelay + 0.7))
        let burst = "5000 device-list notifications: \(String(format: "%.3f", burstTime)) s, syncs \(probe.syncCount) (start + 1 expected), "
            + "listener adds \(probe.listenerAdds - addsAtStart) removes \(probe.listenerRemoves) (0 expected), device listeners \(probe.deviceListenerCount)"
        probe.stop()
        return [
            "camera devices (CoreMediaIO, no permission): \(cams.joined(separator: ", "))",
            "input devices (CoreAudio): \(mics.joined(separator: ", "))",
            "camera in use now: \(s.cameraOn) \(s.cameras)",
            "microphone in use now: \(s.micOn) \(s.mics)",
            "audio processes using input now (macOS 14.2+ API): \(pids.count) \(names)",
            burst,
            "lock function (SACLockScreenImmediate) found: \(CPScreenLock.privateLockAvailable) (not called)",
            "pmset present: \(FileManager.default.isExecutableFile(atPath: "/usr/bin/pmset")) (not run)",
        ]
    }
}

private struct PrivacyTab: View {
    let module: PrivacyModule
    @ObservedObject var state: PrivacyModule.State
    @State private var pressing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                device(symbol: "video.fill", title: T("카메라", "Camera"), on: state.snapshot.cameraOn, tint: .green, names: state.snapshot.cameras)
                device(symbol: "mic.fill", title: T("마이크", "Microphone"), on: state.snapshot.micOn, tint: .orange, names: state.snapshot.mics)
                lockButton
            }
            CPToggleRow(symbol: "video.badge.checkmark", title: "Camera Guard",
                        detail: T("카메라가 켜진 뒤 그 앱을 알리고, 고르면 종료를 요청한다. 미리 막지는 못하며 알림 전 영상이 앱에 갈 수 있다.",
                                  "After the camera turns on, names the app and can ask it to quit. It cannot block access in advance; frames may reach the app before the notice."),
                        isOn: $state.guardOn)
            if let g = state.lastGuard {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(g.appName.map { T("\(Self.time(g.date)) 카메라 켜짐 · \($0) (추정)", "\(Self.time(g.date)) camera on · \($0) (likely)") }
                             ?? T("\(Self.time(g.date)) 카메라 켜짐 · 앱을 알 수 없음", "\(Self.time(g.date)) camera on · app unknown"))
                            .font(.system(size: 11, weight: .semibold))
                        Text(g.reason + (g.others.isEmpty ? "" : T(" · 다른 후보: ", " · other candidates: ") + g.others.joined(separator: ", ")))
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let app = g.app, !app.isTerminated {
                        CPPill(symbol: "xmark.app", title: T("종료 요청", "Ask to Quit"), tint: .red,
                               help: T("정상 종료를 요청한다. 저장 안 한 작업은 그 앱이 묻는다.", "Sends a normal quit request; the app asks about unsaved work.")) { module.askToQuit(app) }
                        CPPill(symbol: "checkmark", title: T("허용", "Allow")) { module.allowApp(app) }
                    }
                }
                .padding(8)
                .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text(T("접근 자체를 막으려면 시스템 설정 › 개인정보 보호 및 보안 › 카메라에서 앱 권한을 끈다.",
                       "To block access itself, turn the app off in System Settings › Privacy & Security › Camera."))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
            HStack {
                Toggle(T("쓰는 동안 노치에 표시", "Show in the notch while in use"), isOn: $state.showInNotch).toggleStyle(.checkbox)
                Spacer()
                if let m = state.message {
                    Text(m).font(.system(size: 10.5)).foregroundStyle(.orange).lineLimit(2)
                }
            }
            .font(.system(size: 11))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func device(symbol: String, title: String, on: Bool, tint: Color, names: [String]) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(on ? tint.opacity(0.25) : Color.white.opacity(0.08))
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(on ? tint : .white.opacity(0.5))
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(on ? names.joined(separator: ", ") : T("쓰지 않음", "Not in use"))
                    .font(.system(size: 10)).foregroundStyle(on ? tint : .white.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// 누르면 잠금, 0.8초 누르고 있으면 디스플레이 끄기
    private var lockButton: some View {
        VStack(spacing: 3) {
            Image(systemName: pressing ? "display" : "lock.fill").font(.system(size: 15, weight: .semibold))
            Text(pressing ? T("디스플레이 끄기", "Display off") : T("화면 잠금", "Lock")).font(.system(size: 10, weight: .semibold))
        }
        .frame(width: 92, height: 46)
        .background(Color.white.opacity(pressing ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { module.lockScreen() }
        .onLongPressGesture(minimumDuration: 0.8, perform: { CPScreenLock.sleepDisplays() }, onPressingChanged: { pressing = $0 })
        .help(T("누르면 바로 잠금, 길게 누르면 디스플레이만 끈다 (끄기는 '잠자기 후 바로 암호 요구'가 켜져 있어야 잠긴다)",
                "Click to lock now; hold to turn off displays (that locks only if a password is required right after sleep)"))
        .accessibilityLabel(T("화면 잠금", "Lock Screen"))
        .accessibilityAddTraits(.isButton)
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: d)
    }
}

private struct PrivacySettings: View {
    @ObservedObject var state: PrivacyModule.State

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Camera Guard", isOn: $state.guardOn)
            Text(T("카메라를 쓰기 시작한 앱을 알리고, 고르면 그 앱에 종료를 요청한다. 감지는 카메라가 켜진 뒤에 일어나므로 그 사이 영상이 앱에 전달될 수 있다. 어떤 앱인지는 앞에 있던 앱과 마이크를 쓰는 앱으로 추정하며 틀릴 수 있다. 접근 자체를 막으려면 시스템 설정 › 개인정보 보호 및 보안 › 카메라에서 앱 권한을 끈다.",
                   "Names the app that started using the camera and can ask it to quit. Detection happens after the camera is on, so frames may reach the app first. The app is guessed from the frontmost app and apps using the microphone, and may be wrong. To block access, turn the app off in System Settings › Privacy & Security › Camera."))
                .font(.caption).foregroundStyle(.secondary)
            Text(T("허용 목록 (알리지 않음)", "Allow list (no notice)")).font(.headline)
            if state.allow.isEmpty {
                Text(T("없음", "None")).foregroundStyle(.secondary)
            }
            ForEach(state.allow, id: \.self) { id in
                HStack {
                    Text(NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id)
                    Spacer()
                    Button(T("빼기", "Remove")) { state.allow.removeAll { $0 == id } }
                }
            }
            Toggle(T("쓰는 동안 노치에 표시", "Show in the notch while in use"), isOn: $state.showInNotch)
        }
    }
}

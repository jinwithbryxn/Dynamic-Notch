import AppKit
import CoreAudio
import SwiftUI

/// 재생 도구: 셔플·반복(Music·Spotify), 15초 뒤로·앞으로(모든 소스, 장편이면 강조), 재생 속도(브라우저 영상),
/// 기본 음악 앱 열기, 헤드폰 연결 직후 Music 자동 실행 막기(선택).
final class MusicToolsModule: NotchModule {
    let id = "musictools"
    var title: String { T("재생 도구", "Playback Tools") }
    let symbol = "dial.medium"
    /// 자동화 권한(Apple 이벤트)을 쓰므로 기본 꺼짐
    let enabledByDefault = false

    let model = MBMusicToolsModel(module: "musictools")

    func start(context: ModuleContext) { model.start(context: context) }
    func stop() { model.stop() }
    func settingsChanged() { model.applySettings() }

    func tabView() -> AnyView? { AnyView(MusicToolsTab(model: model)) }
    var tabContentSize: CGSize { CGSize(width: 480, height: 250) }

    func paletteActions() -> [PaletteAction] {
        let app = model.defaultApp
        return [PaletteAction(id: "musictools.open", title: T("\(MBMusicToolsModel.appName(app)) 열기", "Open \(MBMusicToolsModel.appName(app))"),
                              subtitle: T("기본 음악 앱", "Default music app"), symbol: "music.note",
                              keywords: ["music", "음악", "player"], run: { MBMusicToolsModel.open(app) })]
    }

    func settingsView() -> AnyView? { AnyView(MusicToolsSettings(module: id)) }

    func selfTest() -> [String] {
        var lines: [String] = []
        lines.append("adapter resources present: \(MBPlayerFeed.adapterAvailable)")
        let installed = MBMusicToolsModel.musicApps.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        lines.append("installed music apps: \(installed.joined(separator: ", "))")
        lines.append("default music app setting: \(model.defaultApp)")
        let browsers = MBBrowserSpeed.Browser.allCases.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.rawValue) != nil }
        lines.append("installed browsers with a JavaScript bridge: \(browsers.map(\.name).joined(separator: ", "))")
        lines.append("running browsers: \(browsers.filter { MBPlayer.isRunning($0.rawValue) }.map(\.name).joined(separator: ", "))")
        lines.append("speed script (Chrome, 1.5x) length: \(MBBrowserSpeed.script(for: .chrome, rate: 1.5).count) chars")
        // 실제 재생 정보 (어댑터, 읽기만)
        let feed = MBPlayerFeed.shared
        feed.acquire("selftest")
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        if let t = feed.track {
            lines.append("now playing via adapter: \(t.appName) playing=\(t.playing) rate=\(t.rate) duration=\(Int(t.duration))s longForm=\(t.isLongForm) seekable=\(MBPlayer.canSeek(t))")
        } else {
            lines.append("now playing via adapter: nothing (adapter running=\(feed.adapterRunning))")
        }
        feed.release("selftest")
        return lines
    }
}

final class MBMusicToolsModel: ObservableObject {
    enum Repeat: String { case off, all, one }

    @Published private(set) var shuffle: Bool?
    @Published private(set) var repeatMode: Repeat?
    @Published private(set) var browserRate: Double?
    @Published private(set) var browserMessage: String?
    @Published private(set) var browserTarget: MBBrowserSpeed.Browser?

    static let musicApps = ["com.apple.Music", "com.spotify.client", "com.github.th-ch.youtube-music",
                            "com.tidal.desktop", "com.deezer.deezer-desktop", "com.apple.podcasts"]

    private let defaults: ModuleDefaults
    private var context: ModuleContext?
    private var running = false
    private var launchObserver: NSObjectProtocol?
    private let outputWatch = MBPropertyWatch()
    private var lastHeadphoneChange = Date.distantPast
    private var visibleCount = 0
    private var stateKey: String?

    init(module: String) { defaults = ModuleDefaults(module: module) }

    var defaultApp: String { defaults.string("defaultApp", default: "com.apple.Music") }

    static func appName(_ bundle: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return bundle }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func open(_ bundle: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    // MARK: 시작·정지

    func start(context: ModuleContext) {
        guard !running else { return }
        running = true
        self.context = context
        applySettings()
    }

    func stop() {
        guard running else { return }
        running = false
        removeBlocker()
        if visibleCount > 0 { MBPlayerFeed.shared.release("musictools") }
        visibleCount = 0
        context = nil
    }

    func applySettings() {
        guard running else { return }
        if defaults.bool("blockMusic", default: false) { installBlocker() } else { removeBlocker() }
    }

    func tabVisible(_ visible: Bool) {
        let was = visibleCount
        visibleCount = max(0, visibleCount + (visible ? 1 : -1))
        if was == 0, visibleCount > 0 { MBPlayerFeed.shared.acquire("musictools") }
        if was > 0, visibleCount == 0 { MBPlayerFeed.shared.release("musictools") }
    }

    // MARK: 셔플·반복 (Music·Spotify만 상태를 알려 준다)

    func readState(for t: MBTrack?) {
        guard let t, let b = t.bundleID, MBPlayer.scriptable.contains(b), !MBAudio.isDevTool else {
            shuffle = nil; repeatMode = nil; stateKey = nil
            return
        }
        let key = b + t.key
        guard stateKey != key else { return }
        stateKey = key
        MBPlayer.queue.async { [weak self] in
            var sh: Bool?, rp: Repeat?
            if b == "com.apple.Music" {
                sh = MBPlayer.run("tell application id \"com.apple.Music\" to get shuffle enabled").result?.booleanValue
                switch MBPlayer.run("tell application id \"com.apple.Music\" to get song repeat as text").result?.stringValue {
                case "one": rp = .one
                case "all": rp = .all
                case "off": rp = .off
                default: rp = nil
                }
            } else {
                sh = MBPlayer.run("tell application id \"com.spotify.client\" to get shuffling").result?.booleanValue
                rp = MBPlayer.run("tell application id \"com.spotify.client\" to get repeating").result.map { $0.booleanValue ? .all : .off }
            }
            DispatchQueue.main.async { self?.shuffle = sh; self?.repeatMode = rp }
        }
    }

    func toggleShuffle(_ t: MBTrack) {
        guard let b = t.bundleID, let cur = shuffle else { return }
        let prop = b == "com.apple.Music" ? "shuffle enabled" : "shuffling"
        shuffle = !cur
        MBPlayer.queue.async { [weak self] in
            _ = MBPlayer.run("tell application id \"\(b)\" to set \(prop) to \(!cur)")
            let actual = MBPlayer.run("tell application id \"\(b)\" to get \(prop)").result?.booleanValue
            DispatchQueue.main.async { self?.shuffle = actual }
        }
    }

    func cycleRepeat(_ t: MBTrack) {
        guard let b = t.bundleID, let cur = repeatMode else { return }
        if b == "com.apple.Music" {
            let next: Repeat = cur == .off ? .all : (cur == .all ? .one : .off)
            repeatMode = next
            MBPlayer.queue.async { _ = MBPlayer.run("tell application id \"com.apple.Music\" to set song repeat to \(next.rawValue)") }
        } else {
            // Spotify 스크립트는 반복 켬/끔만 있다
            let next: Repeat = cur == .off ? .all : .off
            repeatMode = next
            MBPlayer.queue.async { _ = MBPlayer.run("tell application id \"com.spotify.client\" to set repeating to \(next == .all)") }
        }
    }

    // MARK: 브라우저 영상 속도

    func pickBrowser(for t: MBTrack?) -> MBBrowserSpeed.Browser? {
        if let b = t?.bundleID, let br = MBBrowserSpeed.Browser(rawValue: b) { return br }
        let runningList = MBBrowserSpeed.Browser.allCases.filter { MBPlayer.isRunning($0.rawValue) }
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, let br = runningList.first(where: { $0.rawValue == front }) { return br }
        return runningList.first
    }

    /// rate가 nil이면 읽기만
    func browserSpeed(_ rate: Double?, track: MBTrack?) {
        guard let browser = pickBrowser(for: track) else {
            browserMessage = T("Safari나 Chrome 계열 브라우저가 실행 중이 아닙니다", "No Safari or Chromium browser is running")
            return
        }
        browserTarget = browser
        browserMessage = nil
        MBPlayer.queue.async { [weak self] in
            let r = MBPlayer.run(MBBrowserSpeed.script(for: browser, rate: rate ?? 0))
            DispatchQueue.main.async {
                guard let self else { return }
                if let (num, msg) = r.error {
                    self.browserRate = nil
                    self.browserMessage = MBBrowserSpeed.explain(num, msg, browser)
                } else if let s = r.result?.stringValue, let v = Double(s) {
                    self.browserRate = v
                } else {
                    self.browserRate = nil
                    self.browserMessage = T("\(browser.name) 앞쪽 탭에 영상·오디오가 없습니다", "No video or audio in \(browser.name)'s front tab")
                }
            }
        }
    }

    // MARK: Music 자동 실행 막기 (헤드폰 연결 직후에만)

    private func installBlocker() {
        guard launchObserver == nil, !MBAudio.isDevTool else { return }
        outputWatch.add(MBAudio.system, kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            let d = MBAudio.defaultOutput()
            let t = AudioOutput.transport(d)
            let name = (AudioOutput.name(d) ?? "").lowercased()
            if t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE || name.contains("headphone") || name.contains("헤드폰") {
                self?.lastHeadphoneChange = Date()
            }
        }
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                                           object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.Music", self.defaultApp != "com.apple.Music",
                  Date().timeIntervalSince(self.lastHeadphoneChange) < 8 else { return }
            app.terminate()
            let instead = self.defaults.bool("openInstead", default: true)
            if instead { Self.open(self.defaultApp) }
            self.context?.notice(T("Music 자동 실행을 막았어요", "Stopped Music from opening"),
                                 instead ? T("\(Self.appName(self.defaultApp)) 대신 열기", "Opened \(Self.appName(self.defaultApp)) instead") : nil,
                                 symbol: "music.note", tab: "musictools")
        }
    }

    private func removeBlocker() {
        if let o = launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        launchObserver = nil
        outputWatch.removeAll()
    }
}

/// 브라우저 앞쪽 탭의 video·audio 재생 속도 (AppleScript → JavaScript).
/// 브라우저의 'Apple 이벤트의 JavaScript 허용'이 켜져 있어야 한다. 이 앱은 그 설정을 바꾸지 않는다.
enum MBBrowserSpeed {
    enum Browser: String, CaseIterable {
        case safari = "com.apple.Safari"
        case chrome = "com.google.Chrome"
        case brave = "com.brave.Browser"
        case edge = "com.microsoft.edgemac"
        case vivaldi = "com.vivaldi.Vivaldi"
        case chromium = "org.chromium.Chromium"

        var name: String {
            switch self {
            case .safari: return "Safari"
            case .chrome: return "Chrome"
            case .brave: return "Brave"
            case .edge: return "Edge"
            case .vivaldi: return "Vivaldi"
            case .chromium: return "Chromium"
            }
        }

        var enableHint: String {
            self == .safari
                ? T("Safari 설정 → 고급 → '웹 개발자용 기능 보기'를 켠 뒤, 개발자 탭에서 'Apple 이벤트의 JavaScript 허용'을 켜세요.",
                    "In Safari Settings → Advanced, show web developer features, then enable 'Allow JavaScript from Apple Events' in the Developer tab.")
                : T("\(name) 메뉴 보기 → 개발자 → 'Apple 이벤트의 JavaScript 허용'을 켜세요.",
                    "In \(name), choose View → Developer → Allow JavaScript from Apple Events.")
        }
    }

    /// 재생 중인 미디어(없으면 첫 미디어)의 속도를 바꾸고(0이면 읽기만) 현재 값을 돌려준다
    static func javaScript(rate: Double) -> String {
        "(function(r){var m=Array.prototype.slice.call(document.querySelectorAll('video,audio'));if(!m.length)return 'none';"
            + "var p=m.filter(function(x){return !x.paused});var t=p.length?p:m;"
            + "if(r>0){t.forEach(function(x){x.playbackRate=r})}return String(t[0].playbackRate)})(\(rate))"
    }

    static func script(for browser: Browser, rate: Double) -> String {
        let js = javaScript(rate: rate).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        if browser == .safari {
            return "tell application id \"\(browser.rawValue)\" to do JavaScript \"\(js)\" in current tab of front window"
        }
        return "tell application id \"\(browser.rawValue)\" to execute active tab of front window javascript \"\(js)\""
    }

    static func explain(_ number: Int, _ message: String, _ browser: Browser) -> String {
        if number == -1743 {
            return T("\(browser.name) 자동화 권한이 없습니다. 시스템 설정 → 개인정보 보호 → 자동화에서 허용하세요.",
                     "No Automation permission for \(browser.name). Allow it in Privacy & Security → Automation.")
        }
        if message.localizedCaseInsensitiveContains("javascript") { return browser.enableHint }
        if number == -1719 || number == -1728 { return T("\(browser.name) 창이 없습니다", "\(browser.name) has no window") }
        return "\(browser.name): \(message) (\(number))"
    }
}

// MARK: - 화면

private struct MusicToolsTab: View {
    @ObservedObject var model: MBMusicToolsModel
    @ObservedObject private var feed = MBPlayerFeed.shared
    private let rates: [Double] = [1, 1.25, 1.5, 1.75, 2]

    var body: some View {
        let t = feed.track
        VStack(alignment: .leading, spacing: 10) {
            header(t)
            if let t {
                HStack(spacing: 8) {
                    controlsRow(t)
                }
                skipRow(t)
            }
            speedSection(t)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .onAppear { model.tabVisible(true); model.readState(for: feed.track) }
        .onDisappear { model.tabVisible(false) }
        .onChange(of: t?.key) { model.readState(for: feed.track) }
        .onChange(of: t?.bundleID) { model.readState(for: feed.track) }
    }

    private func header(_ t: MBTrack?) -> some View {
        HStack(spacing: 10) {
            Group {
                if let art = feed.artwork { Image(nsImage: art).resizable().aspectRatio(contentMode: .fill) }
                else { Image(systemName: "music.note").font(.system(size: 16)).foregroundStyle(.white.opacity(0.5)) }
            }
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(t?.title ?? T("재생 중인 곡 없음", "Nothing playing")).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(t.map { [$0.artist, $0.appName].filter { !$0.isEmpty }.joined(separator: " · ") }
                     ?? (feed.adapterRunning || !MBPlayerFeed.adapterAvailable ? "" : T("재생 정보를 기다리는 중", "Waiting for now playing")))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer()
            if t == nil {
                MBPillButton(title: T("\(MBMusicToolsModel.appName(model.defaultApp)) 열기", "Open \(MBMusicToolsModel.appName(model.defaultApp))"),
                             symbol: "arrow.up.forward.app") { MBMusicToolsModel.open(model.defaultApp) }
                    .help(T("설정에서 고른 기본 음악 앱", "The default music app chosen in Settings"))
            } else if t?.isLongForm == true {
                Text(T("장편", "Long-form")).font(.system(size: 9.5, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.8))).foregroundStyle(.black)
                    .help(T("팟캐스트·오디오북 또는 20분 넘는 오디오", "Podcast, audiobook or audio longer than 20 minutes"))
            }
        }
    }

    @ViewBuilder private func controlsRow(_ t: MBTrack) -> some View {
        if let b = t.bundleID, MBPlayer.scriptable.contains(b) {
            MBPillButton(title: T("셔플", "Shuffle"), symbol: "shuffle", active: model.shuffle == true, tint: .green) { model.toggleShuffle(t) }
                .disabled(model.shuffle == nil)
                .help(model.shuffle == nil ? T("상태를 읽는 중", "Reading state") : T("셔플 전환", "Toggle shuffle"))
            MBPillButton(title: repeatTitle, symbol: model.repeatMode == .one ? "repeat.1" : "repeat",
                         active: model.repeatMode == .all || model.repeatMode == .one, tint: .green) { model.cycleRepeat(t) }
                .disabled(model.repeatMode == nil)
                .help(b == "com.spotify.client" ? T("Spotify 스크립트는 반복 켬·끔만 지원", "Spotify's script supports repeat on/off only")
                                                 : T("반복: 끔 → 전체 → 한 곡", "Repeat: off → all → one"))
        } else {
            Text(T("\(t.appName)은(는) 셔플·반복 상태를 알려 주지 않아 버튼을 숨겼습니다", "\(t.appName) doesn't report shuffle or repeat, so the buttons are hidden"))
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
        }
        Spacer()
    }

    private var repeatTitle: String {
        switch model.repeatMode {
        case .one: return T("한 곡 반복", "Repeat One")
        case .all: return T("전체 반복", "Repeat All")
        default: return T("반복", "Repeat")
        }
    }

    private func skipRow(_ t: MBTrack) -> some View {
        HStack(spacing: 8) {
            MBPillButton(title: T("15초", "15s"), symbol: "gobackward.15") { MBPlayer.skip(t, by: -15) }
                .help(T("15초 뒤로", "Back 15 seconds")).disabled(!MBPlayer.canSeek(t))
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text("\(MBStorage.duration(t.position(at: ctx.date))) / \(MBStorage.duration(t.duration))")
                    .font(.system(size: 11, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
            }
            MBPillButton(title: T("15초", "15s"), symbol: "goforward.15") { MBPlayer.skip(t, by: 15) }
                .help(T("15초 앞으로", "Forward 15 seconds")).disabled(!MBPlayer.canSeek(t))
            Spacer()
            if !MBPlayer.canSeek(t) {
                Text(T("이 소스는 위치 이동을 알려 주지 않음", "This source can't seek")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    @ViewBuilder private func speedSection(_ t: MBTrack?) -> some View {
        let isBrowser = t?.bundleID.flatMap { MBBrowserSpeed.Browser(rawValue: $0) } != nil
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(T("재생 속도", "Speed")).font(.system(size: 11.5, weight: .semibold))
                if let t, t.rate > 0, !isBrowser {
                    Text(String(format: T("지금 %.2g×", "now %.2g×"), t.rate)).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                ForEach(rates, id: \.self) { r in
                    MBPillButton(title: String(format: "%g×", r), active: model.browserRate.map { abs($0 - r) < 0.01 } ?? false, tint: .cyan) {
                        model.browserSpeed(r, track: t)
                    }
                    .help(T("브라우저 앞쪽 탭의 영상·오디오 속도", "Speed of video or audio in the browser's front tab"))
                }
            }
            if let msg = model.browserMessage {
                Text(msg).font(.system(size: 10.5)).foregroundStyle(.yellow.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            } else if let r = model.browserRate, let b = model.browserTarget {
                Text(T("\(b.name): \(String(format: "%g", r))×", "\(b.name): \(String(format: "%g", r))×")).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
            } else {
                Text(T("속도 버튼은 Safari·Chrome 계열 브라우저 탭에 적용됩니다. Music·Spotify·팟캐스트 앱 속도는 기존 MediaRemote 어댑터에 속도 명령이 없어 지원하지 않습니다(대안: 앱의 재생 속도 메뉴).",
                       "Speed buttons apply to Safari or Chromium browser tabs. App speed (Music, Spotify, Podcasts) isn't supported because the MediaRemote adapter has no rate command (alternative: the app's own speed menu)."))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct MusicToolsSettings: View {
    let module: String
    @State private var app = "com.apple.Music"
    @State private var block = false
    @State private var instead = true

    var body: some View {
        let d = ModuleDefaults(module: module)
        VStack(alignment: .leading, spacing: 8) {
            Picker(T("기본 음악 앱", "Default music app"), selection: $app) {
                ForEach(MBMusicToolsModel.musicApps.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }, id: \.self) {
                    Text(MBMusicToolsModel.appName($0)).tag($0)
                }
            }
            .onChange(of: app) { _, newValue in d.set(newValue, "defaultApp") }
            Toggle(T("헤드폰을 연결한 직후 Music이 저절로 열리면 닫기", "Close Music when it opens right after headphones connect"), isOn: $block)
                .onChange(of: block) { _, newValue in d.set(newValue, "blockMusic") }
            Toggle(T("닫은 뒤 기본 음악 앱 열기", "Open the default music app instead"), isOn: $instead)
                .onChange(of: instead) { _, newValue in d.set(newValue, "openInstead") }
                .disabled(!block)
            Text(T("기본 음악 앱이 Music이 아닐 때만, 기본 출력이 블루투스·헤드폰으로 바뀐 뒤 8초 안에 Music이 실행되면 닫습니다. 재생 키로 열리는 경우는 입력 모니터링 권한이 필요해 다루지 않습니다.",
                   "Only when the default app isn't Music: Music is closed if it launches within 8 seconds after the output switches to Bluetooth or headphones. Launches from the play key need Input Monitoring and aren't covered."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            app = d.string("defaultApp", default: "com.apple.Music")
            block = d.bool("blockMusic", default: false)
            instead = d.bool("openInstead", default: true)
        }
    }
}

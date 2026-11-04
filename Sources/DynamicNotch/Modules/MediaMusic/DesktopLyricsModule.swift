import AppKit
import Combine
import SwiftUI

/// 데스크톱 가사: 재생 위치에 맞춘 가사를 떠 있는 패널과 이 탭에 보여 준다 (모든 Now Playing 소스).
/// - 가사 출처: Music 앱 정적 가사(로컬) / LRCLIB(켜면, 제목·아티스트·앨범·길이 전송) / NetEase(켜면, 비공식 API).
/// - 패널: 클릭 통과, 옮기기 모드, 화면 캡처·녹화에서 제외(sharingType none), 일시정지·잠금·잠자기·미러링 중 숨김.
final class DesktopLyricsModule: NotchModule {
    let id = "desktoplyrics"
    var title: String { T("가사", "Lyrics") }
    let symbol = "quote.bubble"
    /// 네트워크(선택)와 떠 있는 창을 쓰므로 기본 꺼짐
    let enabledByDefault = false

    let controller = MBLyricsController(module: "desktoplyrics")

    func start(context: ModuleContext) { controller.start() }
    func stop() { controller.stop() }

    func tabView() -> AnyView? { AnyView(LyricsTab(controller: controller)) }
    var tabContentSize: CGSize { CGSize(width: 500, height: 232) }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "desktoplyrics.toggle",
                       title: controller.windowOn ? T("데스크톱 가사 끄기", "Hide Desktop Lyrics") : T("데스크톱 가사 켜기", "Show Desktop Lyrics"),
                       symbol: "quote.bubble", keywords: ["lyrics", "가사"], run: { [weak self] in self?.controller.setWindow(!(self?.controller.windowOn ?? false)) })]
    }

    func selfTest() -> [String] {
        var lines = [
            "settings: lrclib=\(controller.option(.lrclib)) netease=\(controller.option(.netease)) translation=\(controller.option(.translation)) clickThrough=\(controller.option(.clickThrough)) offset=\(controller.offset)",
            "LRC parse check: \(LyricsProvider.parseLRC("[00:01.00]a\n[00:02.50]b").map { "\($0.time ?? -1):\($0.text)" }.joined(separator: " "))",
            "main display mirrored: \(CGDisplayIsInMirrorSet(CGMainDisplayID()) != 0)",
        ]
        // 네트워크 확인은 MB_SELFTEST_NET=1일 때만 (사용자 곡이 아닌 고정된 공개 곡으로)
        if ProcessInfo.processInfo.environment["MB_SELFTEST_NET"] == "1" {
            let probe = MBTrack(title: "Bohemian Rhapsody", artist: "Queen", album: "A Night at the Opera", duration: 354,
                                elapsed: 0, timestamp: Date(), rate: 1, playing: true, bundleID: "com.spotify.client")
            let l = MBLyricsSources.lrclib(probe)
            lines.append("lrclib fixed probe: \(l.map { MBLyricsSources.describe($0) } ?? "no result")")
            let n = MBLyricsSources.netease(probe, translation: true)
            lines.append("netease fixed probe: \(n.map { MBLyricsSources.describe($0) } ?? "no result")")
        } else {
            lines.append("network probes skipped (set MB_SELFTEST_NET=1)")
        }
        return lines
    }
}

/// 불러온 가사
enum MBLyrics: Equatable {
    case synced([LyricsProvider.Line], translations: [Int: String], source: String)
    case plain([LyricsProvider.Line], source: String)
    case none(String)
    case loading
}

/// 가사 출처 (백그라운드에서 부른다)
enum MBLyricsSources {
    static func describe(_ l: MBLyrics) -> String {
        switch l {
        case .synced(let lines, let tr, let src): return "\(src) synced \(lines.count) lines, \(tr.count) translations"
        case .plain(let lines, let src): return "\(src) plain \(lines.count) lines"
        case .none(let why): return "none (\(why))"
        case .loading: return "loading"
        }
    }

    private static func getJSON(_ url: URL, headers: [String: String] = [:]) -> Any? {
        HTTPFetch.data(url, timeout: 8, maxBytes: 2_000_000, headers: headers, wait: 10)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }

    private static var userAgent: String {
        "DynamicNotch/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (https://github.com/jinwithbryxn/Dynamic-Notch)"
    }

    /// LRCLIB: 정확히 맞는 곡 → 없으면 검색. 길이가 3초 넘게 다르면 동기 가사 대신 정적 가사로 (자동 스크롤 안 함)
    static func lrclib(_ t: MBTrack) -> MBLyrics? {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [URLQueryItem(name: "track_name", value: t.title), URLQueryItem(name: "artist_name", value: t.artist),
                        URLQueryItem(name: "album_name", value: t.album), URLQueryItem(name: "duration", value: String(Int(t.duration.rounded())))]
        var record = c.url.flatMap { getJSON($0, headers: ["User-Agent": userAgent]) } as? [String: Any]
        if record == nil {
            var s = URLComponents(string: "https://lrclib.net/api/search")!
            s.queryItems = [URLQueryItem(name: "track_name", value: t.title), URLQueryItem(name: "artist_name", value: t.artist)]
            let list = s.url.flatMap { getJSON($0, headers: ["User-Agent": userAgent]) } as? [[String: Any]] ?? []
            record = list.first { abs(($0["duration"] as? Double ?? 0) - t.duration) <= 3 } ?? list.first
        }
        guard let r = record else { return nil }
        let durationOK = t.duration <= 0 || abs((r["duration"] as? Double ?? t.duration) - t.duration) <= 3
        if durationOK, let synced = r["syncedLyrics"] as? String, !synced.isEmpty {
            let lines = LyricsProvider.parseLRC(synced)
            if !lines.isEmpty { return .synced(lines, translations: [:], source: "LRCLIB") }
        }
        if let plain = r["plainLyrics"] as? String, !plain.isEmpty { return .plain(plainLines(plain), source: "LRCLIB") }
        if let synced = r["syncedLyrics"] as? String, !synced.isEmpty {
            // 길이가 달라 시간을 믿을 수 없으면 글자만
            return .plain(LyricsProvider.parseLRC(synced).enumerated().map { LyricsProvider.Line(id: $0.offset, time: nil, text: $0.element.text) },
                          source: "LRCLIB")
        }
        return nil
    }

    /// NetEase Cloud Music 공개 웹 API (비공식, 지역에 따라 막힐 수 있다)
    static func netease(_ t: MBTrack, translation: Bool) -> MBLyrics? {
        let headers = ["Referer": "https://music.163.com/", "User-Agent": "Mozilla/5.0 (Macintosh)"]
        var s = URLComponents(string: "https://music.163.com/api/search/get")!
        s.queryItems = [URLQueryItem(name: "s", value: "\(t.title) \(t.artist)"), URLQueryItem(name: "type", value: "1"),
                        URLQueryItem(name: "offset", value: "0"), URLQueryItem(name: "limit", value: "5")]
        guard let url = s.url, let json = getJSON(url, headers: headers) as? [String: Any],
              let songs = (json["result"] as? [String: Any])?["songs"] as? [[String: Any]], !songs.isEmpty else { return nil }
        let pick = songs.first { abs(Double($0["duration"] as? Int ?? 0) / 1000 - t.duration) <= 3 } ?? (t.duration <= 0 ? songs.first : nil)
        guard let id = pick?["id"] as? Int,
              let lurl = URL(string: "https://music.163.com/api/song/lyric?id=\(id)&lv=1&tv=-1"),
              let lj = getJSON(lurl, headers: headers) as? [String: Any],
              let lrc = (lj["lrc"] as? [String: Any])?["lyric"] as? String, !lrc.isEmpty else { return nil }
        // 작사·작곡 같은 크레딧 줄은 뺀다
        let credit = try? NSRegularExpression(pattern: "^(作词|作曲|编曲|制作人|词|曲|Lyricist|Composer)\\s*[:：]")
        let lines = LyricsProvider.parseLRC(lrc).filter { l in
            !l.text.isEmpty && credit?.firstMatch(in: l.text, range: NSRange(location: 0, length: (l.text as NSString).length)) == nil
        }
            .enumerated().map { LyricsProvider.Line(id: $0.offset, time: $0.element.time, text: $0.element.text) }
        guard !lines.isEmpty else { return .plain(plainLines(lrc), source: "NetEase") }
        var tr: [Int: String] = [:]
        if translation, let tl = (lj["tlyric"] as? [String: Any])?["lyric"] as? String, !tl.isEmpty {
            // 같은 시각 줄끼리 짝짓는다
            var byTime: [Int: String] = [:]
            for l in LyricsProvider.parseLRC(tl) where !l.text.isEmpty { byTime[Int(((l.time ?? -1) * 100).rounded())] = l.text }
            for l in lines { if let x = byTime[Int(((l.time ?? -1) * 100).rounded())] { tr[l.id] = x } }
        }
        return .synced(lines, translations: tr, source: "NetEase")
    }

    /// Music 앱 정적 가사 (로컬, 자동화 권한)
    static func musicApp() -> MBLyrics? {
        guard let text = MBPlayer.run("tell application id \"com.apple.Music\" to get lyrics of current track").result?.stringValue,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .plain(plainLines(text), source: "Music")
    }

    static func plainLines(_ text: String) -> [LyricsProvider.Line] {
        text.components(separatedBy: .newlines).enumerated().map { LyricsProvider.Line(id: $0.offset, time: nil, text: $0.element) }
    }
}

final class MBLyricsController: ObservableObject {
    enum Option: String { case lrclib, netease, translation, clickThrough }

    @Published private(set) var lyrics: MBLyrics = .none(T("곡이 재생되면 가사가 여기에 나옵니다", "Lyrics appear here when a song plays"))
    @Published private(set) var windowOn = false
    @Published private(set) var moveMode = false
    @Published private(set) var hiddenReason: String?
    @Published private(set) var offset: Double = 0

    private let module: String
    private let defaults: ModuleDefaults
    private var running = false
    private var panel: MBPanel?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var trackObserver: Any?
    private var loadedKey: String?
    private var cache: [String: MBLyrics] = [:]
    private var visibleTabs = 0
    private var locked = false
    private var asleep = false
    private let loadQueue = DispatchQueue(label: "dmn.lyrics.load", qos: .userInitiated)

    init(module: String) {
        self.module = module
        defaults = ModuleDefaults(module: module)
        offset = defaults.double("offset", default: 0)
    }

    func option(_ o: Option) -> Bool { defaults.bool(o.rawValue, default: o == .clickThrough) }

    func setOption(_ o: Option, _ on: Bool) {
        objectWillChange.send()
        defaults.set(on, o.rawValue)
        if o == .clickThrough { applyMouse() }
        if o != .clickThrough { cache.removeAll(); loadedKey = nil; trackChanged() }
    }

    func setOffset(_ v: Double) {
        offset = (v * 10).rounded() / 10
        defaults.set(offset, "offset")
    }

    // MARK: 시작·정지

    func start() {
        guard !running else { return }
        running = true
        if defaults.bool("window", default: false), !MBAudio.isDevTool { setWindow(true) }
    }

    func stop() {
        guard running else { return }
        running = false
        closePanel()
        if visibleTabs > 0 { releaseFeed() }
        visibleTabs = 0
    }

    func tabVisible(_ v: Bool) {
        let was = visibleTabs
        visibleTabs = max(0, visibleTabs + (v ? 1 : -1))
        if was == 0, visibleTabs > 0 { acquireFeed() }
        if was > 0, visibleTabs == 0, panel == nil { releaseFeed() }
    }

    private var feedHeld = false

    private func acquireFeed() {
        guard !feedHeld else { return }
        feedHeld = true
        MBPlayerFeed.shared.acquire("desktoplyrics")
        trackObserver = MBPlayerFeed.shared.$track.receive(on: DispatchQueue.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.trackChanged() }
        }
        trackChanged()
    }

    private func releaseFeed() {
        guard feedHeld else { return }
        feedHeld = false
        trackObserver = nil
        MBPlayerFeed.shared.release("desktoplyrics")
    }

    // MARK: 가사 불러오기

    private func trackChanged() {
        updateVisibility()
        guard let t = MBPlayerFeed.shared.track else {
            lyrics = .none(T("곡이 재생되면 가사가 여기에 나옵니다", "Lyrics appear here when a song plays"))
            loadedKey = nil
            return
        }
        let key = (t.bundleID ?? "") + t.key
        guard key != loadedKey else { return }
        loadedKey = key
        if let c = cache[key] { lyrics = c; return }
        let useLRCLIB = option(.lrclib), useNetEase = option(.netease), tr = option(.translation)
        let devTool = MBAudio.isDevTool
        lyrics = .loading
        loadQueue.async { [weak self] in
            var result: MBLyrics?
            if useNetEase { result = MBLyricsSources.netease(t, translation: tr) }
            if result == nil, useLRCLIB { result = MBLyricsSources.lrclib(t) }
            if result == nil, t.bundleID == "com.apple.Music", !devTool { result = MBLyricsSources.musicApp() }
            let final = result ?? .none(useLRCLIB || useNetEase ? T("가사를 찾지 못했습니다", "No lyrics found")
                                                                : T("온라인 가사가 꺼져 있습니다", "Online lyrics are off"))
            DispatchQueue.main.async {
                guard let self, self.loadedKey == key else { return }
                if self.cache.count > 30 { self.cache.removeAll() }
                self.cache[key] = final
                self.lyrics = final
            }
        }
    }

    // MARK: 패널

    func setWindow(_ on: Bool) {
        defaults.set(on, "window")
        on ? openPanel() : closePanel()
    }

    func setMoveMode(_ on: Bool) {
        moveMode = on
        applyMouse()
        if on { panel?.orderFrontRegardless() }
    }

    private func applyMouse() {
        guard let p = panel else { return }
        p.ignoresMouseEvents = option(.clickThrough) && !moveMode
        p.isMovableByWindowBackground = moveMode
    }

    private func openPanel() {
        guard running, panel == nil, !MBAudio.isDevTool else { return }
        let size = CGSize(width: 720, height: 110)
        let p = MBPanel.make(size: size)
        p.hasShadow = false
        // 화면 캡처·녹화에 찍히지 않게
        p.sharingType = .none
        p.contentView = MBFirstMouseHostingView(rootView: DesktopLyricsView(controller: self).environment(\.colorScheme, .dark))
        let d = UserDefaults.standard
        if let x = d.object(forKey: "module.\(module).x") as? Double, let y = d.object(forKey: "module.\(module).y") as? Double,
           NSScreen.screens.contains(where: { $0.visibleFrame.contains(CGPoint(x: x + size.width / 2, y: y + size.height / 2)) }) {
            p.setFrameOrigin(CGPoint(x: x, y: y))
        } else if let f = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            p.setFrameOrigin(CGPoint(x: f.midX - size.width / 2, y: f.minY + 60))
        }
        panel = p
        windowOn = true
        applyMouse()
        let nc = NotificationCenter.default, ws = NSWorkspace.shared.notificationCenter, dnc = DistributedNotificationCenter.default()
        observers.append((nc, nc.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
            guard let self, let o = self.panel?.frame.origin else { return }
            d.set(Double(o.x), forKey: "module.\(self.module).x")
            d.set(Double(o.y), forKey: "module.\(self.module).y")
        }))
        observers.append((dnc, dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.locked = true; self?.updateVisibility()
        }))
        observers.append((dnc, dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.locked = false; self?.updateVisibility()
        }))
        observers.append((ws, ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.asleep = true; self?.updateVisibility()
        }))
        observers.append((ws, ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.asleep = false; self?.updateVisibility()
        }))
        observers.append((nc, nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateVisibility()
        }))
        acquireFeed()
        updateVisibility()
    }

    private func closePanel() {
        for (c, o) in observers { c.removeObserver(o) }
        observers.removeAll()
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        windowOn = false
        moveMode = false
        if visibleTabs == 0 { releaseFeed() }
    }

    /// 숨김 조건: 일시정지·재생 없음·잠금·화면 잠자기·미러링 (옮기기 모드에서는 늘 보임)
    private func updateVisibility() {
        guard let p = panel else { hiddenReason = nil; return }
        let t = MBPlayerFeed.shared.track
        var reason: String?
        if locked { reason = T("화면 잠김", "Screen locked") }
        else if asleep { reason = T("화면 잠자기", "Display asleep") }
        else if CGDisplayIsInMirrorSet(CGMainDisplayID()) != 0 { reason = T("화면 미러링 중", "Mirroring") }
        else if t == nil { reason = T("재생 중인 곡 없음", "Nothing playing") }
        else if t?.playing == false { reason = T("일시정지", "Paused") }
        if moveMode { reason = nil }
        hiddenReason = reason
        if reason == nil { p.orderFrontRegardless() } else { p.orderOut(nil) }
    }
}

// MARK: - 화면

/// 현재 줄과 다음 줄 (동기 가사), 정적 가사는 첫 줄들
private struct LyricLines: View {
    let lyrics: MBLyrics
    let position: Double
    var big: CGFloat = 22
    var showNext = true

    var body: some View {
        switch lyrics {
        case .synced(let lines, let tr, _):
            let i = LyricsProvider.currentIndex(lines, at: position)
            VStack(spacing: 4) {
                Text(i.map { lines[$0].text } ?? "♪").font(.system(size: big, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                if let i, let x = tr[lines[i].id] {
                    Text(x).font(.system(size: big * 0.62, weight: .medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                } else if showNext {
                    let n = (i ?? -1) + 1
                    Text(n < lines.count ? lines[n].text : " ").font(.system(size: big * 0.62)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
            }
        case .plain(let lines, _):
            Text(lines.map(\.text).filter { !$0.isEmpty }.prefix(2).joined(separator: "\n"))
                .font(.system(size: big * 0.7, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2)
        case .loading:
            Text(T("가사 찾는 중…", "Finding lyrics…")).font(.system(size: big * 0.6)).foregroundStyle(.white.opacity(0.6))
        case .none(let why):
            Text(why.isEmpty ? " " : why).font(.system(size: big * 0.6)).foregroundStyle(.white.opacity(0.6))
        }
    }
}

private struct DesktopLyricsView: View {
    @ObservedObject var controller: MBLyricsController
    @ObservedObject private var feed = MBPlayerFeed.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            LyricLines(lyrics: controller.lyrics, position: (feed.track?.position(at: ctx.date) ?? 0) + controller.offset, big: 30)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.9), radius: 3, y: 1)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(controller.moveMode ? 0.55 : 0)))
                .overlay(alignment: .topTrailing) {
                    if controller.moveMode {
                        Button { controller.setMoveMode(false) } label: {
                            Text(T("완료", "Done")).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.25)))
                        }
                        .buttonStyle(.plain).padding(8)
                    }
                }
        }
    }
}

private struct LyricsTab: View {
    @ObservedObject var controller: MBLyricsController
    @ObservedObject private var feed = MBPlayerFeed.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                LyricLines(lyrics: controller.lyrics, position: (feed.track?.position(at: ctx.date) ?? 0) + controller.offset, big: 18)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            }
            HStack(spacing: 6) {
                Text(feed.track.map { "\($0.title) · \($0.appName)" } ?? T("재생 중인 곡 없음", "Nothing playing"))
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                Spacer()
                Text(sourceText).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }
            HStack(spacing: 6) {
                MBPillButton(title: T("데스크톱 가사", "Desktop lyrics"), symbol: "macwindow", active: controller.windowOn, tint: .green) {
                    controller.setWindow(!controller.windowOn)
                }
                MBPillButton(title: T("클릭 통과", "Click-through"), symbol: "cursorarrow.motionlines", active: controller.option(.clickThrough)) {
                    controller.setOption(.clickThrough, !controller.option(.clickThrough))
                }
                .help(T("가사 창 위를 눌러도 아래 창이 눌립니다", "Clicks pass through the lyrics window"))
                MBPillButton(title: T("옮기기", "Move"), symbol: "arrow.up.and.down.and.arrow.left.and.right", active: controller.moveMode) {
                    controller.setMoveMode(!controller.moveMode)
                }
                .disabled(!controller.windowOn)
                Spacer()
                if let r = controller.hiddenReason, controller.windowOn {
                    Text(T("숨김: \(r)", "Hidden: \(r)")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
            }
            HStack(spacing: 6) {
                MBPillButton(title: "LRCLIB", symbol: "network", active: controller.option(.lrclib), tint: .cyan) {
                    controller.setOption(.lrclib, !controller.option(.lrclib))
                }
                .help(T("켜면 곡명·아티스트·앨범·길이를 lrclib.net에 보냅니다", "Sends title, artist, album and length to lrclib.net"))
                MBPillButton(title: "NetEase", symbol: "network", active: controller.option(.netease), tint: .cyan) {
                    controller.setOption(.netease, !controller.option(.netease))
                }
                .help(T("비공식 공개 API(music.163.com)에 곡명·아티스트를 보냅니다. 지역에 따라 안 될 수 있습니다.",
                        "Sends title and artist to an unofficial public API (music.163.com). May not work in every region."))
                MBPillButton(title: T("번역", "Translation"), active: controller.option(.translation), tint: .cyan) {
                    controller.setOption(.translation, !controller.option(.translation))
                }
                .disabled(!controller.option(.netease))
                .help(T("NetEase가 번역을 주면 원문 아래에 함께 보여 줍니다", "Shows NetEase translations under the original line"))
                Spacer()
                Text(T("싱크", "Sync")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                MBPillButton(title: "−", symbol: nil) { controller.setOffset(controller.offset - 0.5) }
                    .help(T("가사를 0.5초 늦게", "Lyrics 0.5 s later"))
                Text(String(format: "%+.1fs", controller.offset)).font(.system(size: 10.5, design: .rounded)).monospacedDigit().frame(width: 40)
                MBPillButton(title: "+", symbol: nil) { controller.setOffset(controller.offset + 0.5) }
                    .help(T("가사를 0.5초 빨리", "Lyrics 0.5 s earlier"))
            }
            Text(T("온라인 출처를 모두 끄면 Music 앱의 정적 가사만 씁니다. 길이가 3초 넘게 다른 동기 가사는 자동 스크롤하지 않습니다. 닫힌 노치 한 줄 가사·잠금 화면 가사는 본 앱 연결이 필요합니다.",
                   "With online sources off, only Music's static lyrics are used. Synced lyrics whose length differs by more than 3 s don't auto-scroll. The one-line pill and lock-screen lyrics need core app integration."))
                .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .onAppear { controller.tabVisible(true) }
        .onDisappear { controller.tabVisible(false) }
    }

    private var sourceText: String {
        switch controller.lyrics {
        case .synced(_, _, let s): return T("\(s) · 동기", "\(s) · synced")
        case .plain(_, let s): return T("\(s) · 정적", "\(s) · static")
        default: return ""
        }
    }
}

import AppKit
import SwiftUI

/// 음악 모듈이 함께 쓰는 재생 정보.
/// - 화면(탭·플로팅 창)을 쓰는 동안만 켠다 (`acquire`/`release`). 쓰는 곳이 없으면 프로세스·감시를 모두 멈춘다.
/// - 기존 MediaRemote 어댑터(앱 리소스의 mr_run.pl + libMRAdapter.dylib, 수정 없이 실행)로 모든 소스의 정보를 받고,
///   어댑터가 없으면 Music·Spotify 분산 알림으로 대신한다.
/// - 어댑터 명령은 기존 그대로 toggle / next / prev / seek <초> / refresh 뿐이다.
struct MBTrack: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var elapsed: Double
    var timestamp: Date
    var rate: Double
    var playing: Bool
    var bundleID: String?

    func position(at now: Date = Date()) -> Double {
        let p = elapsed + (playing ? now.timeIntervalSince(timestamp) * (rate > 0 ? rate : 1) : 0)
        return duration > 0 ? min(max(0, p), duration) : max(0, p)
    }

    var key: String { "\(title)|\(artist)|\(album)" }

    var appName: String {
        guard let b = bundleID else { return "" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return b
    }

    /// 팟캐스트·오디오북 같은 긴 오디오 (20분 이상 또는 해당 앱)
    var isLongForm: Bool {
        if let b = bundleID, MBPlayer.longFormApps.contains(where: { b.hasPrefix($0) }) { return true }
        return duration >= 20 * 60
    }
}

final class MBPlayerFeed: ObservableObject {
    static let shared = MBPlayerFeed()

    @Published private(set) var track: MBTrack?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var adapterRunning = false

    private var users: Set<String> = []
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var observers: [NSObjectProtocol] = []
    private var restartDelay: TimeInterval = 1
    private var artworkKey: String?

    var isActive: Bool { !users.isEmpty }

    func acquire(_ who: String) {
        let first = users.isEmpty
        users.insert(who)
        if first { begin() }
    }

    func release(_ who: String) {
        guard users.remove(who) != nil, users.isEmpty else { return }
        end()
    }

    private func begin() {
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] n in
            self?.notification(n.userInfo, bundle: "com.apple.Music")
        })
        observers.append(dnc.addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] n in
            self?.notification(n.userInfo, bundle: "com.spotify.client")
        })
        startAdapter()
    }

    private func end() {
        for o in observers { DistributedNotificationCenter.default().removeObserver(o) }
        observers.removeAll()
        if let p = process {
            p.terminationHandler = nil
            (p.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            if p.isRunning { p.terminate() }
        }
        try? input?.close()
        process = nil
        input = nil
        buffer.removeAll()
        adapterRunning = false
        track = nil
        artwork = nil
        artworkKey = nil
        restartDelay = 1
    }

    // MARK: 어댑터

    static var adapterAvailable: Bool {
        guard let r = Bundle.main.resourceURL else { return false }
        return FileManager.default.fileExists(atPath: r.appendingPathComponent("libMRAdapter.dylib").path)
            && FileManager.default.fileExists(atPath: r.appendingPathComponent("mr_run.pl").path)
    }

    private func startAdapter() {
        guard isActive, process == nil, Self.adapterAvailable, let res = Bundle.main.resourceURL else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [res.appendingPathComponent("mr_run.pl").path, res.appendingPathComponent("libMRAdapter.dylib").path]
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardInput = inp
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { h.readabilityHandler = nil; return }   // 끝(EOF)이면 더 부르지 않게
            DispatchQueue.main.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.process === p else { return }
                self.process = nil
                self.input = nil
                self.adapterRunning = false
                guard self.isActive else { return }
                // 쓰는 화면이 남아 있으면 다시 띄운다 (최대 60초 간격)
                let delay = self.restartDelay
                self.restartDelay = min(60, delay * 2)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.startAdapter() }
            }
        }
        do {
            try p.run()
            process = p
            input = inp.fileHandleForWriting
            adapterRunning = true
        } catch {
            adapterRunning = false
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            restartDelay = 1
            adapterReport(o)
        }
    }

    private func adapterReport(_ o: [String: Any]) {
        if o["error"] != nil { return }
        if let b64 = o["artwork"] as? String, let data = Data(base64Encoded: b64), let img = NSImage(data: data) {
            artwork = img
        }
        guard o["empty"] == nil, let title = o["title"] as? String, !title.isEmpty else {
            // 시스템에 재생 중인 앱이 없음 (Music·Spotify는 자체 알림이 따로 온다)
            if let b = track?.bundleID, MBPlayer.scriptable.contains(b) { return }
            track = nil
            return
        }
        let t = MBTrack(title: title, artist: o["artist"] as? String ?? "", album: o["album"] as? String ?? "",
                        duration: o["duration"] as? Double ?? 0, elapsed: o["elapsed"] as? Double ?? 0,
                        timestamp: (o["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date(),
                        rate: o["rate"] as? Double ?? 0,
                        playing: (o["playing"] as? Bool) ?? ((o["playing"] as? Int) == 1),
                        bundleID: o["bundle"] as? String)
        // 곡이 바뀌었는데 새 아트가 없으면 이전 곡 아트를 지운다
        if t.key != track?.key, o["artwork"] == nil { artworkKey = nil; artwork = nil }
        track = t
        loadScriptArtworkIfNeeded()
    }

    func send(_ line: String) {
        try? input?.write(contentsOf: Data((line + "\n").utf8))
    }

    // MARK: Music·Spotify 분산 알림 (권한 불필요)

    private func notification(_ info: [AnyHashable: Any]?, bundle: String) {
        guard let info else { return }
        // 어댑터가 다른 앱을 보여 주는 중이면 그대로 둔다
        if adapterRunning, let cur = track, cur.bundleID != bundle, cur.playing { return }
        let state = info["Player State"] as? String ?? ""
        guard state != "Stopped", let title = info["Name"] as? String else {
            if track?.bundleID == bundle { track = nil; artwork = nil }
            return
        }
        let ms = (info["Total Time"] as? Double) ?? (info["Duration"] as? Double) ?? 0
        let key = "\(title)|\(info["Artist"] as? String ?? "")|\(info["Album"] as? String ?? "")"
        let known = track.flatMap { $0.bundleID == bundle && $0.key == key ? $0.position() : nil }
        let t = MBTrack(title: title, artist: info["Artist"] as? String ?? "", album: info["Album"] as? String ?? "",
                        duration: ms / 1000, elapsed: (info["Playback Position"] as? Double) ?? known ?? 0, timestamp: Date(),
                        rate: state == "Playing" ? 1 : 0, playing: state == "Playing", bundleID: bundle)
        if t.key != track?.key { artworkKey = nil; if !adapterRunning { artwork = nil } }
        track = t
        if adapterRunning { send("refresh") } else { loadScriptArtworkIfNeeded() }
    }

    /// 어댑터가 없을 때만 Music·Spotify 아트를 AppleScript로 (곡마다 한 번)
    private func loadScriptArtworkIfNeeded() {
        guard !adapterRunning || artwork == nil, let t = track, let b = t.bundleID, MBPlayer.scriptable.contains(b),
              artworkKey != t.key, !MBAudio.isDevTool else { return }
        artworkKey = t.key
        let key = t.key
        MBPlayer.queue.async { [weak self] in
            var data: Data?
            if b == "com.apple.Music" {
                data = MBPlayer.run("tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track").result?.data
            } else if let s = MBPlayer.run("tell application id \"com.spotify.client\" to get artwork url of current track").result?.stringValue,
                      let url = URL(string: s), url.scheme == "https" {
                data = MediaController.download(url)   // 재생 명령과 같은 줄에서 돌므로 시간·크기 제한이 있는 받기를 쓴다
            }
            DispatchQueue.main.async {
                guard let self, self.track?.key == key, let data, let img = NSImage(data: data) else { return }
                self.artwork = img
            }
        }
    }
}

/// 재생 제어: Music·Spotify는 AppleScript(자동화 권한, 처음 쓸 때 묻는다), 그 밖은 기존 어댑터 명령, 어댑터가 없으면 미디어 키.
enum MBPlayer {
    static let queue = DispatchQueue(label: "dmn.music.applescript", qos: .userInitiated)
    static let scriptable: Set<String> = ["com.apple.Music", "com.spotify.client"]
    static let longFormApps = ["com.apple.podcasts", "com.apple.iBooksX", "com.audible", "fm.overcast", "au.com.shiftyjelly.podcasts"]

    /// AppleScript 실행 (백그라운드 큐에서 부른다). 실패하면 오류 번호·문구.
    static func run(_ source: String) -> (result: NSAppleEventDescriptor?, error: (Int, String)?) {
        var err: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err {
            return (nil, ((err[NSAppleScript.errorNumber] as? Int) ?? 0, (err[NSAppleScript.errorMessage] as? String) ?? ""))
        }
        return (r, nil)
    }

    static func isRunning(_ bundle: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
    }

    static func toggle(_ t: MBTrack?) { command(t, script: "playpause", adapter: "toggle", key: 16) }
    static func next(_ t: MBTrack?) { command(t, script: "next track", adapter: "next", key: 17) }
    static func previous(_ t: MBTrack?) { command(t, script: "previous track", adapter: "prev", key: 18) }

    private static func command(_ t: MBTrack?, script: String, adapter: String, key: Int) {
        if let b = t?.bundleID, scriptable.contains(b) {
            queue.async { _ = run("tell application id \"\(b)\" to \(script)") }
        } else if MBPlayerFeed.shared.adapterRunning {
            MBPlayerFeed.shared.send(adapter)
        } else {
            MediaController.postMediaKey(key)
        }
    }

    static func seek(_ t: MBTrack, to seconds: Double) {
        let s = max(0, t.duration > 0 ? min(seconds, t.duration - 1) : seconds)
        if let b = t.bundleID, scriptable.contains(b) {
            queue.async { _ = run("tell application id \"\(b)\" to set player position to \(s)") }
        } else {
            MBPlayerFeed.shared.send("seek \(s)")
        }
    }

    /// 15초 뒤로(-15)·앞으로(+15)
    static func skip(_ t: MBTrack, by delta: Double) { seek(t, to: t.position() + delta) }

    static func canSeek(_ t: MBTrack?) -> Bool {
        guard let t else { return false }
        if let b = t.bundleID, scriptable.contains(b) { return true }
        return MBPlayerFeed.shared.adapterRunning && t.duration > 0
    }
}

/// 비활성 패널에서도 첫 클릭이 버튼에 바로 가도록
final class MBFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 이 앱 데이터 폴더 (검토용 앱과 설치본이 섞이지 않게 번들 ID별)
enum MBStorage {
    static func folder() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.dynamicnotch.app", isDirectory: true)
            .appendingPathComponent("Modules", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func duration(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let total = Int(s)
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
                             : String(format: "%d:%02d", total / 60, total % 60)
    }
}

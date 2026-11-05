import AppKit
import SwiftUI

/// YouTube Music 데스크톱 앱(th-ch/youtube-music)의 API Server 플러그인 연동.
/// 이 Mac 안(127.0.0.1:26538, /api/v1)에만 요청하고, 탭이 보이는 동안만 1초마다 읽는다.
/// 플러그인 기본 인증(AUTH_AT_FIRST)이면 '연결'을 눌렀을 때 YouTube Music이 허용 창을 띄우고, 받은 토큰은 키체인에 둔다.
final class YouTubeMusicModule: NotchModule {
    let id = "ytmusic"
    var title: String { "YouTube Music" }
    let symbol = "play.rectangle.fill"
    let enabledByDefault = false

    let client = MBYTMusicClient()

    func start(context: ModuleContext) { client.running = true }
    func stop() {
        client.running = false
        client.stopPolling()
    }

    func tabView() -> AnyView? { AnyView(YTMusicTab(client: client)) }
    var tabContentSize: CGSize { CGSize(width: 460, height: 210) }

    func selfTest() -> [String] {
        var lines = ["app installed: \(NSWorkspace.shared.urlForApplication(withBundleIdentifier: MBYTMusicClient.bundleID) != nil) (\(MBYTMusicClient.bundleID))",
                     "app running: \(MBPlayer.isRunning(MBYTMusicClient.bundleID))",
                     "token stored: \(KeychainStore.has(MBYTMusicClient.tokenAccount))"]
        // 이 Mac 안의 포트만 확인 (읽기, 서버가 없으면 연결 거부)
        let r = MBYTMusicClient.requestSync("GET", "song", token: nil)
        lines.append("GET http://127.0.0.1:\(MBYTMusicClient.port)/api/v1/song -> \(r.status.map(String.init) ?? "no response") \(r.error ?? "")")
        return lines
    }
}

final class MBYTMusicClient: ObservableObject {
    static let bundleID = "com.github.th-ch.youtube-music"
    static let port = 26538
    static let tokenAccount = "ytmusic.apiserver.token"
    static let clientID = "dynamic-notch"

    enum State: Equatable { case notInstalled, notRunning, unreachable(String), needsAuth, denied, connected, nothingPlaying }

    struct Song: Equatable {
        var title: String, artist: String, duration: Double, elapsed: Double, paused: Bool, at: Date
        func position(at now: Date) -> Double { min(duration, elapsed + (paused ? 0 : now.timeIntervalSince(at))) }
    }

    @Published private(set) var state: State = .notRunning
    @Published private(set) var song: Song?
    @Published private(set) var shuffle: Bool?
    @Published private(set) var repeatMode: String?   // NONE / ALL / ONE
    @Published private(set) var like: String?         // LIKE / DISLIKE / INDIFFERENT
    @Published private(set) var artwork: NSImage?
    var running = false

    private var timer: Timer?
    private var artworkURL: String?
    private let queue = DispatchQueue(label: "dmn.ytmusic", qos: .userInitiated)
    private var busy = false

    // MARK: 요청 (이 Mac 안에서만)

    struct Response { var status: Int?; var data: Data?; var error: String? }

    static func requestSync(_ method: String, _ path: String, body: [String: Any]? = nil, token: String?, auth: Bool = false) -> Response {
        let base = auth ? "http://127.0.0.1:\(port)/auth/" : "http://127.0.0.1:\(port)/api/v1/"
        guard let url = URL(string: base + path) else { return Response(error: "url") }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: auth ? 60 : 2)
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        let sem = DispatchSemaphore(value: 0)
        var out = Response()
        URLSession.shared.dataTask(with: req) { data, resp, err in
            out.status = (resp as? HTTPURLResponse)?.statusCode
            out.data = data
            out.error = err?.localizedDescription
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + (auth ? 65 : 4))
        return out
    }

    /// 키체인은 처음 한 번만 읽고 기억한다. 1초마다 읽으면 재빌드 뒤 키체인 확인 창이 거듭 뜰 수 있다.
    private lazy var cachedToken: String? = KeychainStore.get(Self.tokenAccount)
    private var token: String? { cachedToken }

    // MARK: 읽기 (탭이 보이는 동안만)

    func tabVisible(_ v: Bool) {
        v ? startPolling() : stopPolling()
    }

    func startPolling() {
        guard running, timer == nil else { return }
        poll()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) != nil || MBPlayer.isRunning(Self.bundleID) else {
            state = .notInstalled; song = nil; return
        }
        guard MBPlayer.isRunning(Self.bundleID) else { state = .notRunning; song = nil; return }
        guard !busy else { return }
        busy = true
        let token = self.token
        queue.async { [weak self] in
            let r = Self.requestSync("GET", "song", token: token)
            var shuffle: Bool?, rep: String?, like: String?
            if r.status == 200 {
                shuffle = Self.json(Self.requestSync("GET", "shuffle", token: token))?["state"] as? Bool
                rep = Self.json(Self.requestSync("GET", "repeat-mode", token: token))?["mode"] as? String
                like = Self.json(Self.requestSync("GET", "like-state", token: token))?["state"] as? String
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.apply(r, shuffle: shuffle, repeatMode: rep, like: like)
            }
        }
    }

    private static func json(_ r: Response) -> [String: Any]? {
        guard r.status == 200, let d = r.data else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    private func apply(_ r: Response, shuffle: Bool?, repeatMode: String?, like: String?) {
        switch r.status {
        case 200:
            guard let j = Self.json(r) else { state = .unreachable("bad JSON"); return }
            state = .connected
            song = Song(title: j["title"] as? String ?? "", artist: j["artist"] as? String ?? "",
                        duration: j["songDuration"] as? Double ?? 0, elapsed: j["elapsedSeconds"] as? Double ?? 0,
                        paused: j["isPaused"] as? Bool ?? true, at: Date())
            self.shuffle = shuffle
            self.repeatMode = repeatMode
            self.like = like
            if let src = j["imageSrc"] as? String, src != artworkURL { loadArtwork(src) }
        case 204:
            state = .nothingPlaying; song = nil
        case 401, 403:
            state = .needsAuth; song = nil
        case .some(let code):
            state = .unreachable("HTTP \(code)"); song = nil
        case nil:
            state = .unreachable(r.error ?? T("응답 없음", "No response")); song = nil
        }
    }

    private func loadArtwork(_ src: String) {
        artworkURL = src
        guard let url = URL(string: src), url.scheme == "https" else { artwork = nil; return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let img = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async { if self?.artworkURL == src { self?.artwork = img } }
        }.resume()
    }

    // MARK: 동작

    /// 사용자가 '연결'을 눌렀을 때만: YouTube Music이 허용 창을 띄운다
    func authorize() {
        queue.async { [weak self] in
            let r = Self.requestSync("POST", Self.clientID, token: nil, auth: true)
            let tokenValue = Self.json(r)?["accessToken"] as? String
            DispatchQueue.main.async {
                guard let self else { return }
                if let tokenValue {
                    KeychainStore.set(tokenValue, for: Self.tokenAccount)
                    self.cachedToken = tokenValue
                    self.state = .connected
                    self.poll()
                } else {
                    self.state = r.status == 403 ? .denied : .unreachable(r.error ?? "HTTP \(r.status ?? 0)")
                }
            }
        }
    }

    func forget() {
        KeychainStore.set(nil, for: Self.tokenAccount)
        cachedToken = nil
        state = .needsAuth
    }

    func send(_ path: String, body: [String: Any]? = nil) {
        let token = self.token
        queue.async { [weak self] in
            _ = Self.requestSync("POST", path, body: body, token: token)
            DispatchQueue.main.async { self?.poll() }
        }
    }
}

private struct YTMusicTab: View {
    @ObservedObject var client: MBYTMusicClient

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch client.state {
            case .notInstalled:
                MBUnsupportedBox(title: T("YouTube Music 데스크톱 앱 없음", "YouTube Music desktop app not found"),
                                 reason: T("이 연동은 오픈 소스 'YouTube Music' 데스크톱 앱(th-ch/youtube-music)의 API Server 플러그인을 씁니다.",
                                           "This uses the API Server plugin of the open-source YouTube Music desktop app (th-ch/youtube-music)."),
                                 alternative: T("대안: 브라우저의 YouTube Music은 기본 재생 정보·제어(노치 음악)로 동작합니다", "Alternative: YouTube Music in a browser works through the regular now-playing controls"))
            case .notRunning:
                MBUnsupportedBox(title: T("YouTube Music이 실행 중이 아님", "YouTube Music isn't running"),
                                 reason: T("앱을 실행하면 자동으로 연결을 확인합니다.", "Start the app and the connection is checked automatically."))
                MBPillButton(title: T("YouTube Music 열기", "Open YouTube Music"), symbol: "arrow.up.forward.app") { MBMusicToolsModel.open(MBYTMusicClient.bundleID) }
            case .unreachable(let why):
                MBUnsupportedBox(title: T("API Server에 연결할 수 없음", "Can't reach the API Server"),
                                 reason: T("YouTube Music → 플러그인 → API Server를 켜고 포트를 26538(기본)으로 두세요. (\(why))",
                                           "In YouTube Music, enable Plugins → API Server and keep port 26538 (default). (\(why))"),
                                 alternative: T("대안: 노치의 기본 음악 제어", "Alternative: the notch's regular music controls"))
            case .needsAuth, .denied:
                MBUnsupportedBox(title: client.state == .denied ? T("YouTube Music에서 거부됨", "Denied in YouTube Music") : T("인증 필요", "Authorization needed"),
                                 reason: T("'연결'을 누르면 YouTube Music이 허용 창을 띄웁니다. 받은 토큰은 키체인에만 둡니다.",
                                           "Click Connect and YouTube Music shows an Allow dialog. The token is kept in the Keychain only."))
                MBPillButton(title: T("연결", "Connect"), symbol: "link") { client.authorize() }
            case .nothingPlaying:
                Text(T("YouTube Music에서 재생 중인 곡이 없습니다", "Nothing is playing in YouTube Music")).font(.island(.subhead)).foregroundStyle(.secondary)
            case .connected:
                if let s = client.song { player(s) }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .onAppear { client.tabVisible(true) }
        .onDisappear { client.tabVisible(false) }
    }

    private func player(_ s: MBYTMusicClient.Song) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Group {
                    if let a = client.artwork { Image(nsImage: a).resizable().aspectRatio(contentMode: .fill) }
                    else { Image(systemName: "music.note").foregroundStyle(.white.opacity(0.4)) }
                }
                .frame(width: 52, height: 52).background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title).font(.island(.subhead, .semibold)).lineLimit(1)
                    Text(s.artist).font(.island(.footnote)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer()
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let pos = s.position(at: ctx.date)
                ScrubBar(fraction: s.duration > 0 ? pos / s.duration : 0, enabled: true, spacing: 6, thickness: 4,
                         onScrub: { f in client.send("seek-to", body: ["seconds": Int(f * s.duration)]) }, onEnd: {},
                         leading: { Text(MBStorage.duration(pos)).font(.island(.caption, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.5)) },
                         trailing: { Text(MBStorage.duration(s.duration)).font(.island(.caption, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.5)) })
            }
            HStack(spacing: 8) {
                MBPillButton(title: "", symbol: "shuffle", active: client.shuffle == true, tint: .green) { client.send("shuffle") }
                    .help(T("셔플", "Shuffle")).disabled(client.shuffle == nil)
                MBPillButton(title: "", symbol: "backward.fill") { client.send("previous") }.help(T("이전", "Previous"))
                MBPillButton(title: "", symbol: s.paused ? "play.fill" : "pause.fill") { client.send("toggle-play") }.help(T("재생/일시정지", "Play/Pause"))
                MBPillButton(title: "", symbol: "forward.fill") { client.send("next") }.help(T("다음", "Next"))
                MBPillButton(title: "", symbol: client.repeatMode == "ONE" ? "repeat.1" : "repeat",
                             active: client.repeatMode == "ALL" || client.repeatMode == "ONE", tint: .green) {
                    client.send("switch-repeat", body: ["iteration": 1])
                }
                .help(T("반복 전환", "Cycle repeat")).disabled(client.repeatMode == nil)
                Spacer()
                MBPillButton(title: "", symbol: client.like == "LIKE" ? "hand.thumbsup.fill" : "hand.thumbsup", active: client.like == "LIKE", tint: .white) {
                    client.send("like")
                }
                .help(T("좋아요", "Like"))
            }
        }
    }
}

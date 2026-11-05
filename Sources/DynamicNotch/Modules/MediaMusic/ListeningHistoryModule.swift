import AppKit
import SwiftUI

/// 청취 기록(최근 500곡)과 음악 북마크.
/// Music·Spotify가 보내는 분산 알림만 듣는다 (권한 불필요, 이 Mac에만 저장, 업로드 없음).
/// 지우기는 저장 파일을 휴지통으로 보낸다.
final class ListeningHistoryModule: NotchModule {
    let id = "listenhistory"
    var title: String { T("청취 기록", "Listening History") }
    let symbol = "clock.arrow.circlepath"
    /// 백그라운드에서 알림을 들으므로 기본 꺼짐
    let enabledByDefault = false

    let store = MBHistoryStore()

    func start(context: ModuleContext) { store.start() }
    func stop() { store.stop() }
    /// 설정 창에서 지우면 파일을 다시 읽는다 (메모리의 목록이 파일을 되살리지 않게)
    func settingsChanged() { store.reload() }

    func tabView() -> AnyView? { AnyView(HistoryTab(store: store)) }
    var tabContentSize: CGSize { CGSize(width: 460, height: 280) }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "listenhistory.bookmark", title: T("지금 곡 북마크", "Bookmark Current Song"), symbol: "bookmark",
                       keywords: ["bookmark", "북마크", "music"], run: { [weak self] in self?.store.bookmarkCurrent() })]
    }

    func settingsView() -> AnyView? {
        AnyView(VStack(alignment: .leading, spacing: 8) {
            Text(T("Music·Spotify에서 새 곡이 재생되면 제목·아티스트·앨범·앱·시각을 이 Mac에만 저장합니다 (최대 500곡). 업로드하지 않습니다.",
                   "When Music or Spotify starts a new song, its title, artist, album, app and time are saved on this Mac only (up to 500). Nothing is uploaded."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(T("청취 기록 지우기", "Clear Listening History")) {
                    MBHistoryStore.trashFile(MBHistoryStore.historyURL)
                    ModuleDefaults(module: "listenhistory").set(Date().timeIntervalSince1970, "cleared")
                }
                Button(T("음악 북마크 지우기", "Clear Music Bookmarks")) {
                    MBHistoryStore.trashFile(MBHistoryStore.bookmarksURL)
                    ModuleDefaults(module: "listenhistory").set(Date().timeIntervalSince1970, "cleared")
                }
            }
            Text(T("지운 파일은 휴지통으로 갑니다.", "Cleared files go to the Trash.")).font(.caption).foregroundStyle(.secondary)
        })
    }

    func selfTest() -> [String] {
        let h = MBHistoryStore.load(MBHistoryStore.historyURL)
        let b = MBHistoryStore.load(MBHistoryStore.bookmarksURL)
        return ["storage folder: \(MBStorage.folder().path)",
                "history entries: \(h.count) (limit \(MBHistoryStore.limit)), bookmarks: \(b.count)",
                "sources: com.apple.Music.playerInfo, com.spotify.client.PlaybackStateChanged (distributed notifications)",
                "parse check: \(MBHistoryStore.parse(["Player State": "Playing", "Name": "T", "Artist": "A", "Album": "B", "Total Time": 180000.0], bundle: "com.apple.Music").map { "\($0.title)/\($0.artist) \(Int($0.duration))s" } ?? "failed")"]
    }
}

struct MBHistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var artist: String
    var album: String
    var app: String
    var date: Date
    var duration: Double
    var position: Double? = nil

    var key: String { "\(title)|\(artist)|\(album)" }
}

final class MBHistoryStore: ObservableObject {
    static let limit = 500
    static var historyURL: URL { MBStorage.folder().appendingPathComponent("listening-history.json") }
    static var bookmarksURL: URL { MBStorage.folder().appendingPathComponent("music-bookmarks.json") }

    @Published private(set) var history: [MBHistoryEntry] = []
    @Published private(set) var bookmarks: [MBHistoryEntry] = []
    /// 마지막으로 알림이 알려 준 곡 (북마크용)
    @Published private(set) var current: MBHistoryEntry?

    private var observers: [NSObjectProtocol] = []
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        history = Self.load(Self.historyURL)
        bookmarks = Self.load(Self.bookmarksURL)
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] n in
            self?.received(n.userInfo, bundle: "com.apple.Music")
        })
        observers.append(dnc.addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] n in
            self?.received(n.userInfo, bundle: "com.spotify.client")
        })
    }

    func reload() {
        guard running else { return }
        history = Self.load(Self.historyURL)
        bookmarks = Self.load(Self.bookmarksURL)
    }

    func stop() {
        guard running else { return }
        running = false
        for o in observers { DistributedNotificationCenter.default().removeObserver(o) }
        observers.removeAll()
    }

    static func parse(_ info: [AnyHashable: Any]?, bundle: String) -> MBHistoryEntry? {
        guard let info, (info["Player State"] as? String) == "Playing", let title = info["Name"] as? String, !title.isEmpty else { return nil }
        let ms = (info["Total Time"] as? Double) ?? (info["Duration"] as? Double) ?? 0
        let app = bundle == "com.apple.Music" ? "Music" : "Spotify"
        return MBHistoryEntry(title: title, artist: info["Artist"] as? String ?? "", album: info["Album"] as? String ?? "",
                              app: app, date: Date(), duration: ms / 1000, position: info["Playback Position"] as? Double)
    }

    private func received(_ info: [AnyHashable: Any]?, bundle: String) {
        guard let e = Self.parse(info, bundle: bundle) else { return }
        current = e
        // 같은 곡을 잠깐 멈췄다 다시 재생하면 새로 적지 않는다 (10분 안)
        if let last = history.first, last.key == e.key, e.date.timeIntervalSince(last.date) < 600 { return }
        history.insert(e, at: 0)
        if history.count > Self.limit { history.removeLast(history.count - Self.limit) }
        Self.save(history, Self.historyURL)
    }

    func bookmarkCurrent() {
        let feedTrack = MBPlayerFeed.shared.track
        var e = current
        if let t = feedTrack {
            e = MBHistoryEntry(title: t.title, artist: t.artist, album: t.album, app: t.appName, date: Date(), duration: t.duration, position: t.position())
        }
        guard let e else { return }
        toggleBookmark(e)
    }

    func isBookmarked(_ e: MBHistoryEntry) -> Bool { bookmarks.contains { $0.key == e.key } }

    func toggleBookmark(_ e: MBHistoryEntry) {
        if let i = bookmarks.firstIndex(where: { $0.key == e.key }) { bookmarks.remove(at: i) }
        else { var b = e; b.id = UUID(); b.date = Date(); bookmarks.insert(b, at: 0) }
        Self.save(bookmarks, Self.bookmarksURL)
    }

    func clearHistory() {
        Self.trashFile(Self.historyURL)
        history = []
    }

    func clearBookmarks() {
        Self.trashFile(Self.bookmarksURL)
        bookmarks = []
    }

    static func load(_ url: URL) -> [MBHistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([MBHistoryEntry].self, from: data)) ?? []
    }

    static func save(_ list: [MBHistoryEntry], _ url: URL) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(list) { try? data.write(to: url, options: .atomic) }
    }

    /// 영구 삭제 대신 휴지통으로
    static func trashFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    static func copy(_ e: MBHistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString([e.title, e.artist].filter { !$0.isEmpty }.joined(separator: " – "), forType: .string)
    }

    /// Spotify는 검색 주소로 연다. Music은 공개 검색 주소가 앱으로 열리지 않을 수 있어 복사만.
    static func openSearch(_ e: MBHistoryEntry) {
        guard e.app == "Spotify" else { copy(e); return }
        let q = "\(e.title) \(e.artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "spotify:search:\(q)") { NSWorkspace.shared.open(url) }
    }
}

private struct HistoryTab: View {
    @ObservedObject var store: MBHistoryStore
    @State private var showBookmarks = false
    @State private var confirmClear = false

    var body: some View {
        let list = showBookmarks ? store.bookmarks : store.history
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                MBPillButton(title: T("기록 \(store.history.count)", "History \(store.history.count)"), active: !showBookmarks) { showBookmarks = false; confirmClear = false }
                MBPillButton(title: T("북마크 \(store.bookmarks.count)", "Bookmarks \(store.bookmarks.count)"), active: showBookmarks) { showBookmarks = true; confirmClear = false }
                Spacer()
                MBPillButton(title: T("지금 곡", "Current"), symbol: "bookmark") { store.bookmarkCurrent() }
                    .help(T("지금 재생 중인 곡을 북마크에 넣거나 뺍니다", "Add or remove the current song from bookmarks"))
                    .disabled(store.current == nil && MBPlayerFeed.shared.track == nil)
                MBPillButton(title: confirmClear ? T("한 번 더 눌러 지우기", "Click again to clear") : T("지우기", "Clear"),
                             symbol: "trash", active: confirmClear, tint: .red) {
                    if confirmClear {
                        showBookmarks ? store.clearBookmarks() : store.clearHistory()
                        confirmClear = false
                    } else { confirmClear = true }
                }
                .disabled(list.isEmpty)
                .help(T("저장 파일을 휴지통으로 보냅니다", "Moves the saved file to the Trash"))
            }
            if list.isEmpty {
                Spacer()
                Text(showBookmarks ? T("북마크한 곡이 없습니다", "No bookmarks yet")
                                   : T("Music·Spotify에서 재생한 곡이 여기에 쌓입니다", "Songs played in Music or Spotify appear here"))
                    .font(.island(.footnote)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(list) { e in row(e) }
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func row(_ e: MBHistoryEntry) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title).font(.island(.footnote)).lineLimit(1)
                Text([e.artist, e.app, Self.relative(e.date)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.island(.caption)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer()
            Button { MBHistoryStore.openSearch(e) } label: {
                Image(systemName: e.app == "Spotify" ? "magnifyingglass" : "doc.on.doc").font(.island(.caption)).frame(width: 18, height: 18)
            }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
            .help(e.app == "Spotify" ? T("Spotify에서 찾기", "Search in Spotify") : T("제목 – 아티스트 복사", "Copy title – artist"))
            Button { store.toggleBookmark(e) } label: {
                Image(systemName: store.isBookmarked(e) ? "bookmark.fill" : "bookmark").font(.island(.caption)).frame(width: 18, height: 18)
            }
            .buttonStyle(.plain).foregroundStyle(store.isBookmarked(e) ? .yellow : .white.opacity(0.6))
            .help(T("북마크", "Bookmark")).accessibilityLabel(T("북마크", "Bookmark"))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
    }

    private static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

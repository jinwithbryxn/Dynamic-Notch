import AppKit
import SwiftUI

/// 이 Mac에 설치된 앱 하나 (Info.plist에서 읽음)
struct PkgLocalApp: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleID: String
    let shortVersion: String
    let build: String
    let isAppStore: Bool
    let feedURL: URL?
    var id: String { url.path }

    /// 응용 프로그램 폴더(한 단계 하위 폴더 포함)와 ~/Applications의 앱
    static func scan() -> [PkgLocalApp] {
        let fm = FileManager.default
        var urls: [URL] = []
        let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true), FAKit.home.appendingPathComponent("Applications", isDirectory: true)]
        for root in roots {
            for u in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [] {
                if u.pathExtension == "app" { urls.append(u); continue }
                guard (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                for v in (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] where v.pathExtension == "app" {
                    urls.append(v)
                }
            }
        }
        return urls.compactMap(read).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func read(_ url: URL) -> PkgLocalApp? {
        let contents = url.appendingPathComponent("Contents")
        guard let info = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist")) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String else { return nil }
        let name = (info["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        let feed = (info["SUFeedURL"] as? String).flatMap { s -> URL? in
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : URL(string: t)
        }
        return PkgLocalApp(url: url, name: name, bundleID: bundleID,
                           shortVersion: info["CFBundleShortVersionString"] as? String ?? "",
                           build: info["CFBundleVersion"] as? String ?? "",
                           isAppStore: FileManager.default.fileExists(atPath: contents.appendingPathComponent("_MASReceipt/receipt").path),
                           feedURL: feed)
    }
}

/// 업데이트 목록 한 줄
struct PkgUpdate: Identifiable, Hashable {
    enum Source: String {
        case brew, appStore, sparkle
        var label: String {
            switch self {
            case .brew: return "Homebrew"
            case .appStore: return "App Store"
            case .sparkle: return "Sparkle"
            }
        }
    }
    let source: Source
    let name: String
    let installed: String
    let latest: String
    var appURL: URL? = nil
    var storeID: Int? = nil
    var brewItem: PkgBrewItem? = nil
    var id: String { source.rawValue + ":" + (brewItem?.id ?? appURL?.path ?? name) }
}

/// Homebrew 오래된 항목 + App Store 앱(영수증이 있는 앱, Apple 조회 API) + Sparkle 앱(앱 Info.plist의 SUFeedURL)을 한 목록으로.
/// 사용자가 '확인'을 누를 때만 조회한다. 백그라운드 확인·자동 설치는 없다.
final class PkgUpdateStore: ObservableObject {
    @Published private(set) var items: [PkgUpdate] = []
    @Published private(set) var checking = false
    @Published private(set) var checkedAt: Date?
    @Published private(set) var notes: [String] = []

    private var task: Task<Void, Never>?
    private var session: URLSession?

    func check(brew: PkgBrewStore, appStore: Bool, sparkle: Bool) {
        guard !checking else { return }
        checking = true
        notes = []
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config)
        self.session = session
        let brewItems = brew.outdated.map { b in
            PkgUpdate(source: .brew, name: b.displayName ?? b.name, installed: b.version ?? "?", latest: b.latest ?? "?", brewItem: b)
        }
        let caskApps = brew.caskAppNames
        task = Task.detached(priority: .userInitiated) { [self] in
            var found = brewItems
            var notes: [String] = []
            let apps = PkgLocalApp.scan()
            if appStore {
                let mas = apps.filter(\.isAppStore)
                do {
                    let r = try await Self.appStoreUpdates(mas, session: session)
                    found += r
                    notes.append(T("App Store 앱 \(mas.count)개 확인 (\(Self.storeCountry.uppercased()) 스토어 기준)",
                                   "Checked \(mas.count) App Store apps (\(Self.storeCountry.uppercased()) store)"))
                } catch {
                    if !(error is CancellationError) { notes.append(T("App Store 조회 실패: ", "App Store lookup failed: ") + error.localizedDescription) }
                }
            }
            if sparkle {
                let candidates = apps.filter { !$0.isAppStore && $0.feedURL != nil && !caskApps.contains($0.url.lastPathComponent) }
                let (r, skipped, failed) = await Self.sparkleUpdates(candidates, session: session)
                found += r
                var note = T("Sparkle 앱 \(candidates.count - skipped)개 확인", "Checked \(candidates.count - skipped) Sparkle apps")
                if skipped > 0 { note += T(" · https가 아닌 주소 \(skipped)개 건너뜀", " · skipped \(skipped) non-https feeds") }
                if failed > 0 { note += T(" · 응답 없음 \(failed)개", " · \(failed) didn't respond") }
                notes.append(note)
            }
            if Task.isCancelled { return }
            // 앱(App Store·Sparkle)을 먼저, Homebrew cask, formula 순
            func rank(_ u: PkgUpdate) -> Int {
                switch u.source {
                case .appStore: return 0
                case .sparkle: return 1
                case .brew: return u.brewItem?.isCask == true ? 2 : 3
                }
            }
            found.sort { rank($0) != rank($1) ? rank($0) < rank($1) : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            await MainActor.run { [found, notes] in
                self.items = found
                self.notes = notes
                self.checking = false
                self.checkedAt = Date()
                self.session?.finishTasksAndInvalidate()
                self.session = nil
            }
        }
    }

    /// 기능을 끌 때: 진행 중인 조회를 멈춘다
    func cancel() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        checking = false
    }

    // MARK: App Store

    static var storeCountry: String { (Locale.current.region?.identifier ?? "US").lowercased() }

    /// https://itunes.apple.com/lookup 에 번들 ID만 보낸다 (50개씩)
    static func appStoreUpdates(_ apps: [PkgLocalApp], session: URLSession) async throws -> [PkgUpdate] {
        var out: [PkgUpdate] = []
        let byID = Dictionary(apps.map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
        let ids = Array(byID.keys).sorted()
        for start in stride(from: 0, to: ids.count, by: 50) {
            try Task.checkCancellation()
            let chunk = ids[start..<min(ids.count, start + 50)]
            var comps = URLComponents(string: "https://itunes.apple.com/lookup")!
            comps.queryItems = [URLQueryItem(name: "bundleId", value: chunk.joined(separator: ",")),
                                URLQueryItem(name: "country", value: storeCountry),
                                URLQueryItem(name: "entity", value: "macSoftware")]
            let (data, response) = try await session.data(from: comps.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for r in root["results"] as? [[String: Any]] ?? [] {
                guard let bid = r["bundleId"] as? String, let app = byID[bid], let version = r["version"] as? String,
                      isNewer(version, than: app.shortVersion) else { continue }
                out.append(PkgUpdate(source: .appStore, name: app.name, installed: app.shortVersion, latest: version,
                                     appURL: app.url, storeID: r["trackId"] as? Int))
            }
        }
        return out
    }

    // MARK: Sparkle

    /// 각 앱의 업데이트 주소(appcast)를 읽어 이 Mac에서 쓸 수 있는 가장 새 항목과 비교한다 (최대 40개, 동시에 4개).
    static func sparkleUpdates(_ apps: [PkgLocalApp], session: URLSession) async -> (updates: [PkgUpdate], skipped: Int, failed: Int) {
        let secure = apps.filter { $0.feedURL?.scheme?.lowercased() == "https" }.prefix(40)
        let skipped = apps.count - apps.filter { $0.feedURL?.scheme?.lowercased() == "https" }.count
        var updates: [PkgUpdate] = []
        var failed = 0
        await withTaskGroup(of: (PkgUpdate?, Bool).self) { group in
            var iterator = secure.makeIterator()
            func addNext() -> Bool {
                guard let app = iterator.next(), let feed = app.feedURL else { return false }
                group.addTask {
                    guard let (data, response) = try? await session.data(from: feed),
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return (nil, false) }
                    guard let latest = PkgAppcast.latest(data) else { return (nil, true) }
                    let newer: Bool
                    if let v = latest.version, !app.build.isEmpty { newer = isNewer(v, than: app.build) }
                    else if let s = latest.shortVersion { newer = isNewer(s, than: app.shortVersion) }
                    else { newer = false }
                    guard newer else { return (nil, true) }
                    return (PkgUpdate(source: .sparkle, name: app.name, installed: app.shortVersion,
                                      latest: latest.shortVersion ?? latest.version ?? "?", appURL: app.url), true)
                }
                return true
            }
            for _ in 0..<4 { if !addNext() { break } }
            while let (update, ok) = await group.next() {
                if let update { updates.append(update) }
                if !ok { failed += 1 }
                _ = addNext()
            }
        }
        return (updates, skipped, failed)
    }

    /// "1.10" > "1.9" 처럼 숫자 단위로 비교
    static func isNewer(_ a: String, than b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a.compare(b, options: .numeric) == .orderedDescending
    }
}

/// Sparkle appcast에서 이 Mac에 맞는 가장 새 항목 (베타 채널·더 높은 macOS 요구 항목 제외)
enum PkgAppcast {
    struct Entry { var version: String?; var shortVersion: String?; var minimumSystem: String?; var channel: String? }

    static func latest(_ data: Data) -> Entry? {
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        guard parser.parse() || !delegate.entries.isEmpty else { return nil }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let current = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let usable = delegate.entries.filter { e in
            (e.channel ?? "").isEmpty
                && (e.minimumSystem.map { $0.compare(current, options: .numeric) != .orderedDescending } ?? true)
                && (e.version != nil || e.shortVersion != nil)
        }
        return usable.max { a, b in
            let x = a.version ?? a.shortVersion ?? "", y = b.version ?? b.shortVersion ?? ""
            return x.compare(y, options: .numeric) == .orderedAscending
        }
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var entries: [Entry] = []
        private var current: Entry?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            text = ""
            if name == "item" { current = Entry() }
            if name == "enclosure", current != nil {
                if let v = attributes["sparkle:version"] { current?.version = v }
                if let s = attributes["sparkle:shortVersionString"] { current?.shortVersion = s }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "item": if let c = current { entries.append(c) }; current = nil
            case "sparkle:version": if !value.isEmpty { current?.version = value }
            case "sparkle:shortVersionString": if !value.isEmpty { current?.shortVersion = value }
            case "sparkle:minimumSystemVersion": if !value.isEmpty { current?.minimumSystem = value }
            case "sparkle:channel": if !value.isEmpty { current?.channel = value }
            default: break
            }
            text = ""
        }
    }
}

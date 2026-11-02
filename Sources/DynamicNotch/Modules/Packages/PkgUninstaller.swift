import AppKit
import SwiftUI

/// 앱과 함께 지울 후보 파일 하나
struct PkgLeftover: Identifiable, Hashable {
    let url: URL
    let category: String
    var size: Int64?
    /// 번들 ID가 아니라 앱 이름으로 찾은 항목 (기본 선택 안 함)
    let byName: Bool
    let isApp: Bool
    var selected: Bool
    var id: String { url.path }
}

enum PkgUninstaller {
    /// 앱의 관련 파일 (~/Library 아래 번들 ID·앱 이름이 정확히 같은 항목만) + 앱 자체(마지막).
    /// includeContainers가 false면 다른 앱 컨테이너는 보지 않는다 (자체 검사에서 macOS 허용 창을 띄우지 않기 위해).
    static func related(to app: PkgLocalApp, includeContainers: Bool = true, computeSizes: Bool = true) -> [PkgLeftover] {
        let lib = FAKit.home.appendingPathComponent("Library", isDirectory: true)
        let fm = FileManager.default
        let b = app.bundleID
        let n = app.url.deletingPathExtension().lastPathComponent
        var out: [PkgLeftover] = []
        var seen = Set<String>()

        func add(_ url: URL, _ category: String, byName: Bool = false) {
            guard FAKit.exists(url), seen.insert(url.standardizedFileURL.path).inserted else { return }
            out.append(PkgLeftover(url: url, category: category, size: nil, byName: byName, isApp: false, selected: !byName))
        }
        func both(_ folder: String, _ category: String) {
            add(lib.appendingPathComponent(folder).appendingPathComponent(b), category)
            if n != b, n.count >= 3 { add(lib.appendingPathComponent(folder).appendingPathComponent(n), category, byName: true) }
        }
        func matching(_ folder: String, _ category: String, _ test: (String) -> Bool) {
            let dir = lib.appendingPathComponent(folder)
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where test(name) {
                add(dir.appendingPathComponent(name), category)
            }
        }

        both("Application Support", T("지원 파일", "Application Support"))
        both("Caches", T("캐시", "Caches"))
        add(lib.appendingPathComponent("Preferences/\(b).plist"), T("환경설정", "Preferences"))
        matching("Preferences/ByHost", T("환경설정", "Preferences")) { $0.hasPrefix(b + ".") && $0.hasSuffix(".plist") }
        add(lib.appendingPathComponent("Saved Application State/\(b).savedState"), T("저장된 상태", "Saved State"))
        both("Logs", T("로그", "Logs"))
        add(lib.appendingPathComponent("HTTPStorages/\(b)"), T("웹 데이터", "Web Data"))
        add(lib.appendingPathComponent("HTTPStorages/\(b).binarycookies"), T("쿠키", "Cookies"))
        add(lib.appendingPathComponent("WebKit/\(b)"), T("웹 데이터", "Web Data"))
        add(lib.appendingPathComponent("Cookies/\(b).binarycookies"), T("쿠키", "Cookies"))
        add(lib.appendingPathComponent("Application Scripts/\(b)"), T("스크립트", "Scripts"))
        matching("LaunchAgents", T("런치 에이전트", "Launch Agents")) { $0.hasPrefix(b) && $0.hasSuffix(".plist") }
        if includeContainers {
            add(lib.appendingPathComponent("Containers/\(b)"), T("컨테이너", "Container"))
            matching("Group Containers", T("그룹 컨테이너", "Group Container")) { $0 == b || $0.hasSuffix("." + b) }
        }
        if computeSizes {
            for i in out.indices { out[i].size = FAKit.allocatedSize(out[i].url) }
        }
        out.append(PkgLeftover(url: app.url, category: T("앱", "App"), size: computeSizes ? FAKit.allocatedSize(app.url) : nil,
                               byName: false, isApp: true, selected: true))
        return out
    }

    /// 지울 수 없는 앱 (Apple 앱, 이 앱)
    static func isProtected(_ app: PkgLocalApp) -> Bool {
        let mine = Bundle.main.bundleIdentifier ?? ""
        return app.bundleID.hasPrefix("com.apple.") || app.bundleID == mine || app.bundleID.hasPrefix("com.dynamicnotch.")
    }

    /// 실행 중이거나 그 앱의 도우미(번들 ID로 시작)가 돌고 있으면 그 이름
    static func runningProcess(for app: PkgLocalApp) -> String? {
        NSWorkspace.shared.runningApplications.first { r in
            guard let id = r.bundleIdentifier else { return false }
            return id == app.bundleID || id.hasPrefix(app.bundleID + ".")
        }.map { $0.localizedName ?? app.name }
    }

    static func isRootOwned(_ url: URL) -> Bool {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.ownerAccountID] as? NSNumber)?.intValue == 0
    }
}

/// 앱 제거 화면 상태. 휴지통으로만 옮기고 영구 삭제는 하지 않는다.
final class PkgUninstallStore: ObservableObject {
    @Published private(set) var apps: [PkgLocalApp] = []
    @Published var filter = ""
    @Published private(set) var selected: PkgLocalApp?
    @Published var leftovers: [PkgLeftover] = []
    @Published private(set) var scanning = false
    @Published private(set) var trashing = false
    @Published private(set) var running: String?
    @Published private(set) var message: String?
    @Published private(set) var messageIsError = false
    @Published private(set) var loadingApps = false

    var onFinished: ((String, Bool) -> Void)?
    /// 다른 앱 컨테이너까지 볼지 (화면 그리기 검사에서만 끔)
    var includeContainers = true
    private var generation = 0

    var filtered: [PkgLocalApp] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? apps : apps.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
    }

    var selectedBytes: Int64 { leftovers.filter(\.selected).compactMap(\.size).reduce(0, +) }

    func loadApps() {
        guard !loadingApps else { return }
        loadingApps = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let list = PkgLocalApp.scan().filter { !PkgUninstaller.isProtected($0) }
            DispatchQueue.main.async {
                self?.apps = list
                self?.loadingApps = false
            }
        }
    }

    func select(_ app: PkgLocalApp) {
        generation += 1
        let gen = generation
        selected = app
        leftovers = []
        message = nil
        running = PkgUninstaller.runningProcess(for: app)
        scanning = true
        let containers = includeContainers
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let list = PkgUninstaller.related(to: app, includeContainers: containers)
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.leftovers = list
                self.scanning = false
            }
        }
    }

    func back() {
        generation += 1
        selected = nil
        leftovers = []
        scanning = false
        message = nil
    }

    func toggle(_ item: PkgLeftover) {
        guard let i = leftovers.firstIndex(of: item) else { return }
        leftovers[i].selected.toggle()
    }

    /// 지원 파일을 먼저, 앱을 마지막으로 휴지통에 옮긴다. root 소유 앱이나 옮길 수 없는 앱은 Finder 방식(macOS가 비밀번호를 물음)으로.
    func trashSelected() {
        guard let app = selected, !trashing else { return }
        if let r = PkgUninstaller.runningProcess(for: app) {
            running = r
            setMessage(T("\(r)을(를) 먼저 끝내세요", "Quit \(r) first"), error: true)
            return
        }
        let chosen = leftovers.filter(\.selected)
        guard !chosen.isEmpty else { return }
        trashing = true
        let support = chosen.filter { !$0.isApp }
        let appItem = chosen.first { $0.isApp }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var moved = 0
            var freed: Int64 = 0
            var failures: [String] = []
            for item in support {
                do {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                    moved += 1
                    freed += item.size ?? 0
                } catch {
                    failures.append(item.url.lastPathComponent)
                }
            }
            var needsFinder = false
            if let appItem {
                if PkgUninstaller.isRootOwned(appItem.url) {
                    needsFinder = true
                } else {
                    do {
                        try FileManager.default.trashItem(at: appItem.url, resultingItemURL: nil)
                        moved += 1
                        freed += appItem.size ?? 0
                    } catch {
                        needsFinder = true
                    }
                }
            }
            let (m, f, fl) = (moved, freed, failures)
            DispatchQueue.main.async {
                guard let self else { return }
                if needsFinder, let appItem {
                    NSWorkspace.shared.recycle([appItem.url]) { done, error in
                        let ok = !done.isEmpty
                        let note = appItem.url.lastPathComponent + (error.map { " (\($0.localizedDescription))" } ?? "")
                        DispatchQueue.main.async {
                            self.trashed(app, moved: m + (ok ? 1 : 0), freed: f + (ok ? appItem.size ?? 0 : 0),
                                         failures: ok ? fl : fl + [note])
                        }
                    }
                } else {
                    self.trashed(app, moved: m, freed: f, failures: fl)
                }
            }
        }
    }

    private func trashed(_ app: PkgLocalApp, moved: Int, freed: Int64, failures: [String]) {
        trashing = false
        let ok = failures.isEmpty
        var text = T("\(moved)개를 휴지통으로 옮김 (\(FAKit.bytes(freed))). Finder 휴지통에서 '되돌려 놓기'로 복구할 수 있음",
                     "Moved \(moved) items to the Trash (\(FAKit.bytes(freed))). Use Put Back in the Trash to restore")
        if !ok { text += " · " + T("옮기지 못함: ", "Not moved: ") + failures.prefix(3).joined(separator: ", ") }
        onFinished?(T("\(app.name) 제거", "Removed \(app.name)"), ok)
        let appGone = !FAKit.exists(app.url)
        if appGone {
            apps.removeAll { $0.id == app.id }
            selected = nil
            leftovers = []
        } else {
            leftovers = leftovers.filter { FAKit.exists($0.url) }
        }
        setMessage(text, error: !ok)
    }

    func cancel() { generation += 1 }

    private func setMessage(_ text: String, error: Bool) {
        message = text
        messageIsError = error
    }
}

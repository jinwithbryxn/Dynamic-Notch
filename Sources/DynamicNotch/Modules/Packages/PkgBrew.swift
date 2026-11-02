import AppKit
import SwiftUI

/// Homebrew 항목 하나 (검색 결과·설치됨·오래됨 공용)
struct PkgBrewItem: Identifiable, Hashable {
    let name: String
    let isCask: Bool
    var desc: String = ""
    var displayName: String? = nil
    var version: String? = nil      // 설치된 버전
    var latest: String? = nil       // 오래된 항목의 새 버전
    var pinned = false
    var id: String { (isCask ? "cask:" : "formula:") + name }
}

/// 사용자가 설치한 Homebrew를 찾아 검색·목록·설치·업그레이드·제거를 한다.
/// 조회는 자동 업데이트 없이(HOMEBREW_NO_AUTO_UPDATE) 돌리고, 바꾸는 작업은 사용자가 누를 때만 비대화식으로 실행한다.
final class PkgBrewStore: ObservableObject {
    static let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    struct Job: Equatable {
        let title: String
        let command: String
        var log: [String] = []
        var running = true
        var status: Int32? = nil
        var hint: String? = nil
    }

    enum Action { case install, upgrade, uninstall, upgradeAll, update }

    @Published private(set) var brewPath: String?
    @Published var query = ""
    @Published private(set) var results: [PkgBrewItem] = []
    @Published private(set) var searching = false
    @Published private(set) var searchedQuery = ""
    @Published private(set) var installed: [PkgBrewItem] = []
    @Published private(set) var dependencies: [PkgBrewItem] = []
    @Published private(set) var outdated: [PkgBrewItem] = []
    @Published private(set) var loadingLists = false
    @Published private(set) var listsLoadedAt: Date?
    @Published private(set) var error: String?
    @Published private(set) var job: Job?
    /// 설치된 cask가 넣은 앱 이름 ("Firefox.app"): Sparkle 확인에서 겹치지 않게 뺀다
    private(set) var caskAppNames: Set<String> = []

    let processes = FAProcessGroup()
    /// 작업이 끝나면 (제목, 성공) — 노치 알림용
    var onJobFinished: ((String, Bool) -> Void)?

    static let baseEnv: [String: String] = [
        "HOMEBREW_NO_ENV_HINTS": "1", "HOMEBREW_NO_COLOR": "1", "HOMEBREW_NO_EMOJI": "1", "NONINTERACTIVE": "1",
        "PATH": "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    ]
    static var queryEnv: [String: String] { baseEnv.merging(["HOMEBREW_NO_AUTO_UPDATE": "1"]) { $1 } }

    static func findBrew() -> String? { candidates.first { FileManager.default.isExecutableFile(atPath: $0) } }

    func detect() {
        let found = Self.findBrew()
        if found != brewPath { brewPath = found }
    }

    /// 이름이 옵션처럼 보이거나 이상한 글자가 있으면 실행하지 않는다
    static func validName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, CharacterSet.alphanumerics.contains(first) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@+._/-"))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // MARK: 검색 (brew desc --search: 이름과 설명)

    func search() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let brew = brewPath else { return }
        guard q.count >= 2, !q.hasPrefix("-") else { results = []; searchedQuery = ""; return }
        searching = true
        error = nil
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let r = processes.run(brew, ["desc", "--search", q], env: Self.queryEnv, timeout: 120)
            let items = r.map { Self.parseDesc($0.outText) } ?? []
            DispatchQueue.main.async {
                guard q == self.query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                self.searching = false
                self.searchedQuery = q
                // 이름이 정확히 같은 것, 이름이 그 글자로 시작하는 것, 나머지 순
                let lq = q.lowercased()
                func rank(_ i: PkgBrewItem) -> Int { i.name.lowercased() == lq ? 0 : i.name.lowercased().hasPrefix(lq) ? 1 : 2 }
                self.results = items.enumerated().sorted { a, b in
                    rank(a.element) != rank(b.element) ? rank(a.element) < rank(b.element) : a.offset < b.offset
                }.map { self.withInstallState($0.element) }
                if items.isEmpty, let r, !r.ok {
                    self.error = r.errText.split(separator: "\n").first.map(String.init) ?? T("검색 실패", "Search failed")
                }
            }
        }
    }

    func clearSearch() {
        query = ""
        results = []
        searchedQuery = ""
    }

    /// "==> Formulae / ==> Casks" 구역 아래 "이름: 설명" 줄. cask 설명은 "(앱 이름) 설명" 꼴.
    static func parseDesc(_ text: String) -> [PkgBrewItem] {
        var isCask = false
        var out: [PkgBrewItem] = []
        for raw in text.split(separator: "\n") {
            let line = String(raw)
            if line.hasPrefix("==>") { isCask = line.lowercased().contains("cask"); continue }
            guard let colon = line.range(of: ": ") else { continue }
            let name = String(line[..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard validName(name) else { continue }
            var desc = String(line[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
            var display: String?
            if isCask, desc.hasPrefix("("), let close = desc.firstIndex(of: ")") {
                display = String(desc[desc.index(after: desc.startIndex)..<close])
                desc = String(desc[desc.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            }
            out.append(PkgBrewItem(name: name, isCask: isCask, desc: desc, displayName: display))
        }
        return out
    }

    private func withInstallState(_ item: PkgBrewItem) -> PkgBrewItem {
        var i = item
        if let match = (installed + dependencies).first(where: { $0.id == item.id }) { i.version = match.version }
        if let old = outdated.first(where: { $0.id == item.id }) { i.latest = old.latest }
        return i
    }

    // MARK: 설치됨·오래됨

    func loadLists() {
        guard let brew = brewPath, !loadingLists else { return }
        loadingLists = true
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let info = processes.run(brew, ["info", "--json=v2", "--installed"], env: Self.queryEnv, timeout: 180)
            let old = processes.run(brew, ["outdated", "--json=v2", "--greedy-auto-updates"], env: Self.queryEnv, timeout: 180)
            let parsed = info.flatMap { Self.parseInstalled($0.out) }
            let outdatedItems = old.flatMap { Self.parseOutdated($0.out) } ?? []
            DispatchQueue.main.async {
                self.loadingLists = false
                if let parsed {
                    self.installed = parsed.leaves
                    self.dependencies = parsed.deps
                    self.caskAppNames = parsed.caskApps
                    self.listsLoadedAt = Date()
                } else {
                    self.error = T("설치 목록을 읽지 못함", "Couldn't read the installed list")
                }
                self.outdated = outdatedItems.map { o in
                    var item = o
                    item.desc = (parsed.map { $0.leaves + $0.deps } ?? []).first { $0.id == o.id }?.desc ?? ""
                    return item
                }
                self.results = self.results.map(self.withInstallState)
            }
        }
    }

    static func parseInstalled(_ data: Data) -> (leaves: [PkgBrewItem], deps: [PkgBrewItem], caskApps: Set<String>)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var leaves: [PkgBrewItem] = [], deps: [PkgBrewItem] = []
        for f in root["formulae"] as? [[String: Any]] ?? [] {
            guard let name = f["name"] as? String else { continue }
            let inst = f["installed"] as? [[String: Any]] ?? []
            let item = PkgBrewItem(name: name, isCask: false, desc: f["desc"] as? String ?? "",
                                   version: inst.last?["version"] as? String, pinned: f["pinned"] as? Bool ?? false)
            if inst.contains(where: { $0["installed_on_request"] as? Bool == true }) { leaves.append(item) } else { deps.append(item) }
        }
        var apps = Set<String>()
        for c in root["casks"] as? [[String: Any]] ?? [] {
            guard let token = c["token"] as? String else { continue }
            leaves.append(PkgBrewItem(name: token, isCask: true, desc: c["desc"] as? String ?? "",
                                      displayName: (c["name"] as? [String])?.first, version: c["installed"] as? String))
            for a in c["artifacts"] as? [[String: Any]] ?? [] {
                for app in a["app"] as? [Any] ?? [] {
                    if let s = app as? String { apps.insert((s as NSString).lastPathComponent) }
                    else if let d = app as? [String: Any], let target = d["target"] as? String { apps.insert((target as NSString).lastPathComponent) }
                }
            }
        }
        return (leaves.sorted { $0.name < $1.name }, deps.sorted { $0.name < $1.name }, apps)
    }

    static func parseOutdated(_ data: Data) -> [PkgBrewItem]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var out: [PkgBrewItem] = []
        for (key, isCask) in [("formulae", false), ("casks", true)] {
            for o in root[key] as? [[String: Any]] ?? [] {
                guard let name = o["name"] as? String else { continue }
                out.append(PkgBrewItem(name: name, isCask: isCask, version: (o["installed_versions"] as? [String])?.last,
                                       latest: o["current_version"] as? String, pinned: o["pinned"] as? Bool ?? false))
            }
        }
        return out
    }

    // MARK: 설치·업그레이드·제거 (사용자가 누를 때만)

    func perform(_ action: Action, _ item: PkgBrewItem? = nil) {
        guard let brew = brewPath, job?.running != true else { return }
        let cask = item?.isCask == true ? ["--cask"] : []
        let args: [String]
        let title: String
        switch action {
        case .install:
            guard let item, Self.validName(item.name) else { return }
            args = ["install"] + cask + [item.name]; title = T("\(item.name) 설치", "Installing \(item.name)")
        case .upgrade:
            guard let item, Self.validName(item.name) else { return }
            args = ["upgrade"] + cask + [item.name]; title = T("\(item.name) 업그레이드", "Upgrading \(item.name)")
        case .uninstall:
            guard let item, Self.validName(item.name) else { return }
            args = ["uninstall"] + cask + [item.name]; title = T("\(item.name) 제거", "Uninstalling \(item.name)")
        case .upgradeAll:
            args = ["upgrade"]; title = T("모두 업그레이드", "Upgrading everything")
        case .update:
            args = ["update"]; title = T("Homebrew 목록 새로 받기", "Updating Homebrew")
        }
        job = Job(title: title, command: "brew " + args.joined(separator: " "))
        let started = processes.stream(brew, args, env: Self.baseEnv, onLine: { [weak self] line in
            guard let self, var j = self.job else { return }
            j.log.append(line)
            if j.log.count > 400 { j.log.removeFirst(j.log.count - 400) }
            self.job = j
        }, onExit: { [weak self] status in
            self?.jobEnded(status)
        })
        if started == nil {
            job?.running = false
            job?.status = -1
            job?.log.append(T("brew를 실행하지 못함", "Couldn't start brew"))
        }
    }

    private func jobEnded(_ status: Int32) {
        guard var j = job else { return }
        j.running = false
        j.status = status
        if status != 0 {
            let text = j.log.joined(separator: "\n").lowercased()
            if text.contains("sudo") || text.contains("password") || text.contains("a terminal is required") {
                j.hint = T("관리자 비밀번호가 필요한 작업이라 여기서는 할 수 없음. 터미널에서 직접 실행하세요.",
                           "This needs an administrator password, which can't be typed here. Run it in Terminal.")
            } else if status == SIGTERM || status == 15 {
                j.hint = T("중단함", "Stopped")
            }
        }
        job = j
        onJobFinished?(j.title, status == 0)
        loadLists()
    }

    func cancelJob() { if job?.running == true { processes.terminateAll() } }
    func dismissJob() { if job?.running != true { job = nil } }

    func copyCommand() {
        guard let cmd = job?.command else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
    }
}

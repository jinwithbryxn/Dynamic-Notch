import AppKit
import Security
import SwiftUI
import UniformTypeIdentifiers

/// 설정 백업·초기화와 제거 도구 (설정 화면 전용, 탭·배경 작업 없음).
/// 내보내기: 이 앱의 UserDefaults 도메인을 .plist로 (키체인 비밀값·이 Mac 전용 값 제외).
/// 가져오기: 미리 보기 후 합치기. 초기화: 기능별 키 접두사 또는 전체. 바꾸기 전에는 항상 자동 백업을 남긴다.
final class AppDataModule: NotchModule {
    let id = "appdata"
    var title: String { T("설정 백업·초기화", "Backup & Reset") }
    let symbol = "arrow.counterclockwise.circle"

    func start(context: ModuleContext) {}
    func stop() {}

    func settingsView() -> AnyView? { AnyView(ADSettingsView()) }

    func selfTest() -> [String] {
        var lines: [String] = []
        let cur = ADBackup.current()
        let exportable = ADBackup.exportable()
        lines.append("domain \(ADBackup.domain): \(cur.count) keys, exportable \(exportable.count), excluded \(cur.keys.filter(ADBackup.excluded).sorted())")
        lines.append("module key groups: \(ADBackup.moduleKeys().mapValues(\.count))")
        do {
            // 파일로 쓰고 다시 읽어 미리 보기 (설정은 바꾸지 않음)
            let data = try ADBackup.exportData()
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dmn-appdata-selftest-\(UUID().uuidString).plist")
            try data.write(to: tmp)
            let p = try ADBackup.preview(try Data(contentsOf: tmp))
            try? FileManager.default.removeItem(at: tmp)   // 검사가 만든 임시 파일
            lines.append("export round trip: \(data.count) bytes, preview added \(p.added.count) changed \(p.changed.count) unchanged \(p.unchanged) skipped \(p.skipped.count)")
            // 일부러 바뀐 값과 비밀처럼 보이는 키를 넣은 파일 미리 보기
            var fake = ADBackup.exportable()
            fake["module.selftest.sample"] = 1
            fake["someApiToken"] = "x"
            fake["trayItems"] = Data([1])
            let d2 = try PropertyListSerialization.data(fromPropertyList: fake, format: .xml, options: 0)
            let p2 = try ADBackup.preview(d2)
            lines.append("bare plist preview: added \(p2.added) skipped \(p2.skipped.sorted())")
        } catch {
            lines.append("FAIL export/preview: \(error.localizedDescription)")
        }
        lines += sandboxTest()
        lines.append("keychain service \(ADBackup.keychainService): \(ADBackup.keychainAccounts().count) items (names not printed)")
        for f in ADBackup.appFolders() {
            lines.append("folder \(FAKit.shortPath(f.url)): \(FAKit.allocatedSize(f.url).map(FAKit.bytes) ?? "?")")
        }
        lines.append("backup folder: \(FAKit.shortPath(ADBackup.backupFolder))")
        lines.append("no settings changed, nothing removed")
        return lines
    }
}

extension AppDataModule {
    /// 버려도 되는 검사용 도메인에서 가져오기(합치기)·기능별 초기화·전체 초기화를 실제로 돌려 본다
    func sandboxTest() -> [String] {
        let domain = "com.dynamicnotch.selftest.appdata"
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dmn-appdata-\(UUID().uuidString)", isDirectory: true)
        guard let defaults = UserDefaults(suiteName: domain) else { return ["FAIL sandbox domain"] }
        let s = ADStore(domain: domain, defaults: defaults, backupFolder: tmp, notifies: false)
        defer {
            defaults.removePersistentDomain(forName: domain)   // 검사용 도메인만 지운다
            try? FileManager.default.removeItem(at: tmp)
        }
        defaults.setPersistentDomain(["transientDuration": 2.5, "module.clock.zones": ["Asia/Seoul"], "module.clock.enabled": true,
                                      "trayItems": Data([9]), "onboardingDone": true], forName: domain)
        var lines: [String] = []
        do {
            let incoming: [String: Any] = ["transientDuration": 4.0, "module.clock.zones": ["Asia/Seoul"], "module.news.enabled": true,
                                           "trayItems": Data([1]), "myApiToken": "x"]
            let p = try ADBackup.preview(try PropertyListSerialization.data(fromPropertyList: incoming, format: .xml, options: 0), s)
            let b1 = try ADBackup.apply(p, s)
            var cur = ADBackup.current(s)
            let merged = (cur["transientDuration"] as? Double) == 4 && cur["module.news.enabled"] as? Bool == true
                && (cur["trayItems"] as? Data) == Data([9]) && cur["myApiToken"] == nil && cur["onboardingDone"] as? Bool == true
            lines.append("\(merged ? "ok  " : "FAIL") import merge: added \(p.added) changed \(p.changed) skipped \(p.skipped.sorted()) backup=\(FAKit.exists(b1))")
            _ = try ADBackup.resetModule("clock", s)
            cur = ADBackup.current(s)
            let moduleReset = cur["module.clock.zones"] == nil && cur["module.clock.enabled"] as? Bool == true && cur["transientDuration"] != nil
            lines.append("\(moduleReset ? "ok  " : "FAIL") reset module keeps .enabled and other keys")
            _ = try ADBackup.resetAll(s)
            cur = ADBackup.current(s)
            let allReset = cur["transientDuration"] == nil && cur["module.news.enabled"] == nil && cur["trayItems"] != nil && cur["onboardingDone"] != nil
            let backups = (try? FileManager.default.contentsOfDirectory(atPath: tmp.path).count) ?? 0
            lines.append("\(allReset ? "ok  " : "FAIL") reset all keeps per-Mac keys \(cur.keys.sorted()); backups written \(backups)")
        } catch {
            lines.append("FAIL sandbox: \(error.localizedDescription)")
        }
        return lines
    }
}

// MARK: - 백업·가져오기·초기화

/// 설정을 읽고 쓸 곳. 본 앱 도메인이 기본이고, 자체 검사는 버려도 되는 검사용 도메인을 쓴다.
struct ADStore {
    let domain: String
    let defaults: UserDefaults
    let backupFolder: URL
    /// 본 앱·기능에 바뀜을 알릴지 (검사용 도메인이면 false)
    let notifies: Bool

    static var app: ADStore {
        let d = Bundle.main.bundleIdentifier ?? "com.dynamicnotch.app"
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(d, isDirectory: true).appendingPathComponent("Settings Backups", isDirectory: true)
        return ADStore(domain: d, defaults: .standard, backupFolder: folder, notifies: true)
    }
}

enum ADBackup {
    static var domain: String { ADStore.app.domain }
    static let fileMarker = "DynamicNotchSettings"
    static var keychainService: String { domain + ".secrets" }

    /// 이 Mac에만 맞는 값: 파일 북마크, 권한 요청 기록, 캐시, 업데이트 확인 시각, 첫 실행 안내 완료
    private static let machineLocal: Set<String> = [
        "trayItems", "btSymbolCache", "filesPermissionRequested", "migratedFromNotchIsland", "updateLastCheck", "onboardingDone",
    ]

    static func isMachineLocal(_ key: String) -> Bool {
        machineLocal.contains(key) || key.hasPrefix("NS") || key.hasPrefix("Apple") || key.hasPrefix("com.apple.")
            || key.lowercased().contains("permission") || key.hasSuffix("Cache") || key.hasSuffix("LastCheck")
    }

    /// 비밀값은 키체인에만 있어야 하지만, 혹시 이름이 비밀처럼 보이면 내보내지도 가져오지도 않는다
    static func looksSecret(_ key: String) -> Bool {
        let k = key.lowercased()
        return ["token", "secret", "password", "apikey", "api_key", "credential", "cookie"].contains { k.contains($0) }
    }

    static func excluded(_ key: String) -> Bool { isMachineLocal(key) || looksSecret(key) }

    static func current(_ s: ADStore = .app) -> [String: Any] {
        CFPreferencesAppSynchronize(s.domain as CFString)
        return s.defaults.persistentDomain(forName: s.domain) ?? [:]
    }

    static func exportable(_ s: ADStore = .app) -> [String: Any] { current(s).filter { !excluded($0.key) } }

    static func exportData(_ s: ADStore = .app) throws -> Data {
        let wrapper: [String: Any] = [
            fileMarker: 1,
            "bundleID": s.domain,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "exportedAt": Date(),
            "settings": exportable(s),
        ]
        return try PropertyListSerialization.data(fromPropertyList: wrapper, format: .xml, options: 0)
    }

    struct Preview {
        let values: [String: Any]
        let added: [String]
        let changed: [String]
        let unchanged: Int
        let skipped: [String]
        let sourceBundleID: String?
        let exportedAt: Date?
    }

    enum ADError: LocalizedError {
        case notSettings
        var errorDescription: String? { T("설정 파일이 아님 (속성 목록 사전이어야 함)", "Not a settings file (expected a property list dictionary)") }
    }

    /// 내보낸 파일 또는 `defaults export`로 만든 plist를 읽어 지금 값과 비교한다
    static func preview(_ data: Data, _ s: ADStore = .app) throws -> Preview {
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw ADError.notSettings }
        let wrapped = root[fileMarker] != nil
        let settings = wrapped ? (root["settings"] as? [String: Any] ?? [:]) : root
        let cur = current(s)
        var added: [String] = [], changed: [String] = [], skipped: [String] = []
        var unchanged = 0
        for (k, v) in settings {
            if excluded(k) { skipped.append(k); continue }
            if let old = cur[k] {
                if (old as AnyObject).isEqual(v) { unchanged += 1 } else { changed.append(k) }
            } else {
                added.append(k)
            }
        }
        return Preview(values: settings, added: added.sorted(), changed: changed.sorted(), unchanged: unchanged, skipped: skipped.sorted(),
                       sourceBundleID: wrapped ? root["bundleID"] as? String : nil, exportedAt: wrapped ? root["exportedAt"] as? Date : nil)
    }

    /// 자동 백업을 남기고 새 값·바뀐 값만 덮는다 (파일에 없는 키는 그대로 = 합치기)
    @discardableResult
    static func apply(_ p: Preview, _ s: ADStore = .app) throws -> URL {
        let backup = try writeBackup("before-import", s)
        let keys = p.added + p.changed
        for k in keys { s.defaults.set(p.values[k], forKey: k) }
        CFPreferencesAppSynchronize(s.domain as CFString)
        if s.notifies { notify(keys) }
        return backup
    }

    /// "module.<id>.<이름>"의 기능 id
    static func moduleID(of key: String) -> String? {
        let parts = key.split(separator: ".", maxSplits: 2)
        guard parts.count == 3, parts[0] == "module" else { return nil }
        return String(parts[1])
    }

    static func moduleKeys(_ s: ADStore = .app) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for k in current(s).keys { if let m = moduleID(of: k) { out[m, default: []].append(k) } }
        return out
    }

    /// 그 기능의 설정만 기본값으로 (켜짐 여부는 그대로)
    @discardableResult
    static func resetModule(_ id: String, _ s: ADStore = .app) throws -> URL {
        let backup = try writeBackup("before-reset-\(id)", s)
        let keys = current(s).keys.filter { $0.hasPrefix("module.\(id).") && $0 != "module.\(id).enabled" }
        keys.forEach { s.defaults.removeObject(forKey: $0) }
        CFPreferencesAppSynchronize(s.domain as CFString)
        if s.notifies { notify(Array(keys)) }
        return backup
    }

    /// 모든 설정을 기본값으로 (이 Mac 전용 값은 남김)
    @discardableResult
    static func resetAll(_ s: ADStore = .app) throws -> URL {
        let backup = try writeBackup("before-reset-all", s)
        let keys = current(s).keys.filter { !isMachineLocal($0) }
        keys.forEach { s.defaults.removeObject(forKey: $0) }
        CFPreferencesAppSynchronize(s.domain as CFString)
        if s.notifies { notify(Array(keys)) }
        return backup
    }

    /// 본 앱이 앱 설정을 다시 읽고, 바뀐 기능의 settingsChanged()가 불리게 한다
    static func notify(_ keys: [String]) {
        let dnc = DistributedNotificationCenter.default()
        dnc.postNotificationName(AppSettings.changedNotification, object: "appdata", userInfo: nil, deliverImmediately: true)
        for m in Set(keys.compactMap(moduleID(of:))) {
            dnc.postNotificationName(ModuleDefaults.changedNotification, object: m, userInfo: nil, deliverImmediately: true)
        }
    }

    static var backupFolder: URL { ADStore.app.backupFolder }

    /// 바꾸기 직전 값 전체(비밀처럼 보이는 키 제외)를 앱 지원 폴더에 남긴다
    static func writeBackup(_ reason: String, _ s: ADStore = .app) throws -> URL {
        try FileManager.default.createDirectory(at: s.backupFolder, withIntermediateDirectories: true)
        let values = current(s).filter { !looksSecret($0.key) }
        let wrapper: [String: Any] = [fileMarker: 1, "bundleID": s.domain, "exportedAt": Date(), "settings": values]
        let data = try PropertyListSerialization.data(fromPropertyList: wrapper, format: .xml, options: 0)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        return try FAKit.writeNew(data, in: s.backupFolder, base: "settings-\(stamp)-\(reason)", ext: "plist")
    }

    // MARK: 키체인 (이름만 읽음, 값은 읽지 않음)

    static func keychainAccounts() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    // MARK: 이 앱이 만든 폴더

    struct Folder: Identifiable {
        let label: String
        let url: URL
        var id: String { url.path }
    }

    static func appFolders() -> [Folder] {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let list = [
            Folder(label: T("파일 선반 복사본", "Tray copies"), url: support.appendingPathComponent("Dynamic Notch", isDirectory: true)),
            Folder(label: T("설정 백업", "Settings backups"), url: support.appendingPathComponent(domain, isDirectory: true)),
            Folder(label: T("캐시", "Cache"), url: caches.appendingPathComponent(domain, isDirectory: true)),
        ]
        return list.filter { FAKit.exists($0.url) }
    }
}

// MARK: - 설정 화면 (설정 도우미 프로세스)

private struct ADSettingsView: View {
    @State private var preview: ADBackup.Preview?
    @State private var status: String?
    @State private var statusIsError = false
    @State private var moduleCounts: [String: Int] = [:]
    @State private var accounts: [String] = []
    @State private var folders: [(ADBackup.Folder, Int64?)] = []
    @State private var confirmModule: String?
    @State private var confirmResetAll = false
    @State private var confirmKeychain: String?
    @State private var confirmFolder: String?
    @State private var needsRestart = false

    private var titles: [String: String] {
        Dictionary(ModuleRegistry.shared.modules.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            exportImport
            Divider()
            reset
            Divider()
            removal
            if let status {
                Text(status).font(.caption).foregroundStyle(statusIsError ? .red : .secondary).textSelection(.enabled)
            }
            if needsRestart {
                HStack {
                    Text(T("일부 설정은 앱을 다시 시작해야 반영된다.", "Some settings apply after a restart.")).font(.caption)
                    Button(T("다시 시작", "Restart now")) { Helper.sendToMain("restart"); needsRestart = false }
                }
            }
        }
        .onAppear(perform: reload)
        .alert(T("모든 설정을 기본값으로 되돌릴까요?", "Reset all settings?"), isPresented: $confirmResetAll) {
            Button(T("먼저 내보내기", "Export first")) { exportSettings() }
            Button(T("초기화", "Reset"), role: .destructive) {
                run(T("모든 설정을 기본값으로 되돌림", "All settings reset")) { try ADBackup.resetAll() }
            }
            Button(T("취소", "Cancel"), role: .cancel) {}
        } message: {
            Text(T("지금 설정은 자동 백업으로 남긴다. 파일 선반·권한 기록처럼 이 Mac에만 맞는 값과 키체인 항목은 그대로 둔다.",
                   "Current settings are backed up automatically. Per-Mac values (tray, permission records) and Keychain items stay."))
        }
    }

    // MARK: 내보내기·가져오기

    private var exportImport: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(T("내보내기·가져오기", "Export & import")).font(.headline)
            Text(T("모든 설정을 .plist 파일로 저장한다. 키체인의 API 키·토큰과 이 Mac에만 맞는 값(파일 선반, 권한 기록, 캐시)은 넣지 않는다. iCloud Drive 폴더에 저장하면 다른 Mac에서 가져올 수 있다.",
                   "Saves every setting to a .plist file. Keychain API keys and tokens and per-Mac values (tray, permission records, caches) are left out. Save it to iCloud Drive to bring it to another Mac."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(T("내보내기…", "Export…")) { exportSettings() }
                Button(T("가져오기…", "Import…")) { pickImport() }
            }
            if let p = preview {
                VStack(alignment: .leading, spacing: 4) {
                    Text(T("새 항목 \(p.added.count) · 바뀌는 항목 \(p.changed.count) · 같음 \(p.unchanged) · 건너뜀 \(p.skipped.count)",
                           "\(p.added.count) new · \(p.changed.count) changed · \(p.unchanged) same · \(p.skipped.count) skipped"))
                        .font(.callout.weight(.medium))
                    if let src = p.sourceBundleID, src != ADBackup.domain {
                        Text(T("다른 빌드(\(src))에서 내보낸 파일", "Exported from a different build (\(src))")).font(.caption).foregroundStyle(.orange)
                    }
                    if let at = p.exportedAt {
                        Text(T("내보낸 시각: ", "Exported: ") + at.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                    let keys = p.changed + p.added
                    if !keys.isEmpty {
                        Text(keys.prefix(14).joined(separator: ", ") + (keys.count > 14 ? " …" : ""))
                            .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(4)
                    }
                    if !p.skipped.isEmpty {
                        Text(T("건너뜀(이 Mac 전용·비밀처럼 보이는 키): ", "Skipped (per-Mac or secret-looking): ") + p.skipped.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    HStack {
                        Button(T("합쳐서 가져오기", "Merge into my settings")) {
                            run(T("가져옴", "Imported")) { try ADBackup.apply(p) }
                            preview = nil
                        }
                        .disabled(p.added.isEmpty && p.changed.isEmpty)
                        Button(T("취소", "Cancel")) { preview = nil }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
            }
        }
    }

    // MARK: 기본값 복원

    private var reset: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(T("기본값 복원", "Restore defaults")).font(.headline)
            let ids = moduleCounts.keys.sorted { (titles[$0] ?? $0) < (titles[$1] ?? $1) }
            if ids.isEmpty {
                Text(T("기능별로 바꾼 설정이 없음", "No feature settings have been changed")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(ids, id: \.self) { id in
                HStack {
                    Text(titles[id] ?? id)
                    Text(T("\(moduleCounts[id] ?? 0)개", "\(moduleCounts[id] ?? 0) keys")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if confirmModule == id {
                        Button(T("확인", "Confirm"), role: .destructive) {
                            confirmModule = nil
                            run(T("\(titles[id] ?? id) 기본값으로", "\(titles[id] ?? id) reset")) { try ADBackup.resetModule(id) }
                        }
                        Button(T("취소", "Cancel")) { confirmModule = nil }
                    } else {
                        Button(T("기본값으로", "Restore")) { confirmModule = id }
                            .help(T("이 기능의 설정만 지운다 (켜짐 여부는 그대로)", "Clears this feature's settings (keeps it on or off)"))
                    }
                }
            }
            Button(T("모든 설정 초기화…", "Reset all settings…")) { confirmResetAll = true }
        }
    }

    // MARK: 제거 도구

    private var removal: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(T("이 앱이 남긴 것", "What this app added")).font(.headline)
            LabeledContent(T("설정", "Settings")) {
                Text("\(ADBackup.domain) · \(T("\(ADBackup.current().count)개 키", "\(ADBackup.current().count) keys"))").foregroundStyle(.secondary)
            }
            LabeledContent(T("키체인", "Keychain")) {
                Text("\(ADBackup.keychainService) · \(T("\(accounts.count)개", "\(accounts.count) items"))").foregroundStyle(.secondary)
            }
            ForEach(accounts, id: \.self) { a in
                HStack {
                    Text(a).font(.callout.monospaced())
                    Spacer()
                    if confirmKeychain == a {
                        Button(T("지우기 확인", "Confirm delete"), role: .destructive) {
                            confirmKeychain = nil
                            KeychainStore.set(nil, for: a)
                            reload()
                            setStatus(T("키체인 항목을 지움: \(a)", "Deleted Keychain item: \(a)"))
                        }
                        Button(T("취소", "Cancel")) { confirmKeychain = nil }
                    } else {
                        Button(T("지우기", "Delete")) { confirmKeychain = a }
                            .help(T("이 앱이 저장한 비밀값. 지우면 그 기능에서 다시 입력해야 함", "A secret this app stored; you'll need to enter it again"))
                    }
                }
                .padding(.leading, 12)
            }
            ForEach(folders, id: \.0.id) { f, size in
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(f.label)
                        Text(FAKit.shortPath(f.url)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(size.map(FAKit.bytes) ?? "—").foregroundStyle(.secondary).monospacedDigit()
                    Button(T("보기", "Show")) { FAKit.reveal([f.url]) }
                    if confirmFolder == f.id {
                        Button(T("휴지통으로 확인", "Confirm"), role: .destructive) {
                            confirmFolder = nil
                            do {
                                try FileManager.default.trashItem(at: f.url, resultingItemURL: nil)
                                setStatus(T("휴지통으로 옮김: ", "Moved to Trash: ") + FAKit.shortPath(f.url))
                            } catch { setStatus(error.localizedDescription, error: true) }
                            reload()
                        }
                    } else {
                        Button(T("휴지통으로", "Move to Trash")) { confirmFolder = f.id }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(T("각 기능이 관리하는 것", "Managed by their features")).font(.callout.weight(.medium))
                Text(T("셸 훅(~/.zshrc 등), Claude Code·Codex 훅, 충전·팬 도우미 같은 시스템 변경은 그 기능이 직접 넣고 뺀다. 그 기능을 끄면 그 기능이 넣은 부분만 지운다.",
                       "Shell hooks (~/.zshrc etc.), Claude Code and Codex hooks, and charging or fan helpers are added and removed by the feature that owns them. Turning that feature off removes only what it added."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(T("앱 자체는 앱을 끝낸 뒤 Finder에서 휴지통으로 옮긴다.", "To remove the app itself, quit it and move it to the Trash in Finder."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 도우미

    private func reload() {
        moduleCounts = ADBackup.moduleKeys().mapValues { keys in keys.filter { !$0.hasSuffix(".enabled") }.count }.filter { $0.value > 0 }
        accounts = ADBackup.keychainAccounts()
        folders = ADBackup.appFolders().map { ($0, FAKit.allocatedSize($0.url)) }
    }

    private func run(_ done: String, _ work: () throws -> URL) {
        do {
            let backup = try work()
            setStatus(done + " · " + T("자동 백업: ", "backup: ") + FAKit.shortPath(backup))
            needsRestart = true
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
        reload()
    }

    private func setStatus(_ text: String, error: Bool = false) {
        status = text
        statusIsError = error
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.propertyList]
        let day = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "Dynamic Notch Settings \(day).plist"
        panel.title = T("설정 내보내기", "Export Settings")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // 사용자가 저장 창에서 고른 경로 (같은 이름이면 macOS가 바꿀지 먼저 물음)
            try ADBackup.exportData().write(to: url, options: .atomic)
            setStatus(T("내보냄: ", "Exported: ") + FAKit.shortPath(url))
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    private func pickImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        panel.title = T("설정 가져오기", "Import Settings")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            preview = try ADBackup.preview(try Data(contentsOf: url))
            status = nil
        } catch {
            preview = nil
            setStatus(error.localizedDescription, error: true)
        }
    }
}

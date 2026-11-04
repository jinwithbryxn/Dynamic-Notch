import AppKit
import CryptoKit
import ImageIO

/// 클립보드 기록 저장소.
/// `~/Library/Application Support/<번들 ID>/Clipboard/`에 색인(index.json)과 이미지 파일(Images/)을 소유자 전용(0700·0600)으로 둔다.
/// 지운 항목의 이미지 파일은 0바이트로 덮어써 빈 칸으로 남기고 다음 이미지가 다시 쓴다 (사용자 파일은 건드리지 않음).
/// '종료 후에도 기록 유지'를 끄면 고정·목록 항목만 디스크에 두고 나머지는 메모리에만 둔다.
final class ClipStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var lists: [ClipList] = []

    let directory: URL
    /// 설정 도우미·명령줄 검사에서는 읽기만 한다
    let readOnly: Bool
    private(set) var persistHistory = true
    private(set) var limit = 40

    private var memoryImages: [String: Data] = [:]
    private let io = DispatchQueue(label: "dmn.clipboard.store", qos: .utility)
    private var saveWork: DispatchWorkItem?
    private let thumbs = NSCache<NSString, NSImage>()

    init(directory: URL = ClipStore.defaultDirectory(), readOnly: Bool) {
        self.directory = directory
        self.readOnly = readOnly
        thumbs.countLimit = 300
    }

    /// 기본 저장 위치. 명령줄 검사(도우미 프로세스)에서만 DMN_CLIPBOARD_DIR로 바꿀 수 있다.
    static func defaultDirectory() -> URL {
        if AppSettings.isHelper, let custom = ProcessInfo.processInfo.environment["DMN_CLIPBOARD_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.dynamicnotch.app", isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true)
    }

    var indexURL: URL { directory.appendingPathComponent("index.json") }
    var imagesDir: URL { directory.appendingPathComponent("Images", isDirectory: true) }

    // MARK: 읽기

    func load() {
        // 다시 읽으면 메모리에만 있던 항목은 사라지므로 그 이미지도 버린다
        memoryImages.removeAll()
        guard let data = try? Data(contentsOf: indexURL) else { items = []; lists = []; return }
        do {
            let index = try JSONDecoder().decode(ClipIndex.self, from: data)
            items = index.items
            lists = index.lists
        } catch {
            // 읽을 수 없는 색인은 지우지 않고 옆으로 옮겨 둔다
            if !readOnly {
                let aside = directory.appendingPathComponent("index-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: indexURL, to: aside)
            }
            items = []; lists = []
        }
    }

    /// 설정 화면용: 디스크의 저장 개수 (전체, 고정·목록)
    static func peekCounts(directory: URL = ClipStore.defaultDirectory()) -> (total: Int, saved: Int) {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("index.json")),
              let index = try? JSONDecoder().decode(ClipIndex.self, from: data) else { return (0, 0) }
        return (index.items.count, index.items.filter(\.isSaved).count)
    }

    // MARK: 설정 반영

    func configure(persist: Bool, limit: Int) {
        self.limit = limit
        if persist != persistHistory {
            persistHistory = persist
            for item in items { syncImageLocation(item) }
        }
        applyLimit()
        scheduleSave()
    }

    // MARK: 바꾸기

    /// 새 항목을 맨 위에 넣는다. 같은 내용이 이미 있으면 그 항목을 맨 위로 올린다.
    @discardableResult
    func insert(_ new: ClipItem, imageData: Data?) -> ClipItem {
        if let i = duplicateIndex(of: new) {
            var existing = items.remove(at: i)
            existing.date = new.date
            existing.appID = new.appID ?? existing.appID
            existing.appName = new.appName ?? existing.appName
            items.insert(existing, at: 0)
            scheduleSave()
            return existing
        }
        var item = new
        if let imageData {
            item.imageFile = storeImage(imageData, saved: item.isSaved)
        }
        items.insert(item, at: 0)
        applyLimit()
        trimMemoryImages()
        scheduleSave()
        return item
    }

    /// 메모리에만 둔 이미지가 이 크기를 넘으면 오래된 일반 이미지 항목부터 뺀다
    static let memoryBudget = 200 * 1024 * 1024

    private func trimMemoryImages() {
        var total = memoryImages.values.reduce(0) { $0 + $1.count }
        guard total > Self.memoryBudget else { return }
        for item in items.reversed() where item.kind == .image && !item.isSaved {
            guard let name = item.imageFile, let data = memoryImages[name] else { continue }
            items.removeAll { $0.id == item.id }
            memoryImages[name] = nil
            total -= data.count
            if total <= Self.memoryBudget { break }
        }
    }

    private func duplicateIndex(of new: ClipItem) -> Int? {
        items.firstIndex { old in
            guard old.kind == new.kind else { return false }
            switch new.kind {
            case .image: return old.digest != nil && old.digest == new.digest
            case .file: return old.paths == new.paths
            case .burst: return false
            default: return old.text == new.text
            }
        }
    }

    /// 맨 위로 올린다 (다시 붙여넣었을 때)
    func bump(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: i)
        item.date = Date()
        items.insert(item, at: 0)
        scheduleSave()
    }

    func update(_ id: UUID, _ mutate: (inout ClipItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[i]
        mutate(&item)
        guard item != items[i] else { return }
        items[i] = item
        syncImageLocation(item)
        applyLimit()
        scheduleSave()
    }

    func remove(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: i)
        releaseImage(of: item)
        scheduleSave()
    }

    /// 고정·목록 항목을 빼고 모두 지운다. 지운 개수를 돌려준다.
    @discardableResult
    func clearHistory() -> Int {
        let gone = items.filter { !$0.isSaved }
        guard !gone.isEmpty else { return 0 }
        items.removeAll { !$0.isSaved }
        gone.forEach(releaseImage)
        scheduleSave()
        return gone.count
    }

    /// 정한 시각보다 오래된 일반 항목을 지운다.
    @discardableResult
    func prune(olderThan cutoff: Date) -> Int {
        let gone = items.filter { !$0.isSaved && $0.date < cutoff }
        guard !gone.isEmpty else { return 0 }
        let ids = Set(gone.map(\.id))
        items.removeAll { ids.contains($0.id) }
        gone.forEach(releaseImage)
        scheduleSave()
        return gone.count
    }

    /// 보관 한도를 넘는 오래된 일반 항목을 지운다 (고정·목록 항목은 한도에서 빠짐).
    func applyLimit() {
        var kept = 0
        var gone: [ClipItem] = []
        for item in items where !item.isSaved {
            kept += 1
            if kept > limit { gone.append(item) }
        }
        guard !gone.isEmpty else { return }
        let ids = Set(gone.map(\.id))
        items.removeAll { ids.contains($0.id) }
        gone.forEach(releaseImage)
        scheduleSave()
    }

    /// 한도를 이 값으로 낮추면 지워질 개수
    static func overflow(items: [ClipItem], limit: Int) -> Int {
        max(0, items.filter { !$0.isSaved }.count - limit)
    }

    // MARK: 목록

    @discardableResult
    func addList(_ name: String) -> ClipList {
        let list = ClipList(name: name)
        lists.append(list)
        scheduleSave()
        return list
    }

    /// 목록만 지운다. 항목은 기록에 남고 다시 한도의 적용을 받는다.
    func deleteList(_ id: UUID) {
        lists.removeAll { $0.id == id }
        for item in items where item.lists?.contains(id) == true {
            update(item.id) { $0.lists?.removeAll { $0 == id }; if $0.lists?.isEmpty == true { $0.lists = nil } }
        }
        scheduleSave()
    }

    func toggle(_ itemID: UUID, in listID: UUID) {
        update(itemID) { item in
            var l = item.lists ?? []
            if let i = l.firstIndex(of: listID) { l.remove(at: i) } else { l.append(listID) }
            item.lists = l.isEmpty ? nil : l
        }
    }

    // MARK: 검색

    func search(_ query: String, kind: ClipKind? = nil, pinnedOnly: Bool = false, list: UUID? = nil) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = items.filter { item in
            if let kind, item.kind != kind { return false }
            if pinnedOnly, !item.isPinned { return false }
            if let list, item.lists?.contains(list) != true { return false }
            return true
        }
        let found = q.isEmpty ? base : base.filter { $0.searchText.localizedStandardContains(q) }
        // 고정 항목은 맨 위, 나머지는 최신순
        return found.filter(\.isPinned) + found.filter { !$0.isPinned }
    }

    // MARK: 이미지

    func imageData(for item: ClipItem) -> Data? {
        guard let name = item.imageFile else { return nil }
        if let d = memoryImages[name] { return d }
        let url = imagesDir.appendingPathComponent(name)
        guard let d = try? Data(contentsOf: url), !d.isEmpty else { return nil }
        return d
    }

    /// 목록용 작은 썸네일 (캐시)
    func thumbnail(for item: ClipItem, maxPixel: Int = 96) -> NSImage? {
        let key = "\(item.id.uuidString)-\(maxPixel)" as NSString
        if let t = thumbs.object(forKey: key) { return t }
        guard let data = imageData(for: item), let img = Self.downsample(data, maxPixel: maxPixel) else { return nil }
        thumbs.setObject(img, forKey: key)
        return img
    }

    static func downsample(_ data: Data, maxPixel: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 이미지 데이터를 둔다: 디스크에 둘 항목이면 빈 칸 파일을 다시 쓰거나 새 파일, 아니면 메모리.
    private func storeImage(_ data: Data, saved: Bool) -> String {
        if readOnly || !(persistHistory || saved) {
            let name = UUID().uuidString + ".png"
            memoryImages[name] = data
            return name
        }
        let name = freeSlot() ?? (UUID().uuidString + ".png")
        writeImage(data, name: name)
        return name
    }

    private func writeImage(_ data: Data, name: String) {
        ensureDirectories()
        let url = imagesDir.appendingPathComponent(name)
        try? data.write(to: url)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// 디스크의 빈 칸(0바이트, 어느 항목도 쓰지 않는 파일)
    private func freeSlot() -> String? {
        let used = Set(items.compactMap(\.imageFile))
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: imagesDir.path) else { return nil }
        return names.first { name in
            guard name.hasSuffix(".png"), !used.contains(name) else { return false }
            let size = (try? FileManager.default.attributesOfItem(atPath: imagesDir.appendingPathComponent(name).path)[.size] as? NSNumber)?.intValue
            return size == 0
        }
    }

    /// 항목이 지워질 때 이미지를 비운다 (파일은 0바이트로 덮어쓰기, 메모리는 버림)
    private func releaseImage(of item: ClipItem) {
        guard let name = item.imageFile else { return }
        if memoryImages.removeValue(forKey: name) != nil { return }
        guard !readOnly else { return }
        let url = imagesDir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { try? Data().write(to: url) }
    }

    /// 저장 설정·고정 여부에 맞게 이미지를 디스크↔메모리로 옮긴다.
    private func syncImageLocation(_ item: ClipItem) {
        guard !readOnly, let name = item.imageFile else { return }
        let wantDisk = persistHistory || item.isSaved
        if wantDisk, let data = memoryImages.removeValue(forKey: name) {
            writeImage(data, name: name)
        } else if !wantDisk, memoryImages[name] == nil {
            let url = imagesDir.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                memoryImages[name] = data
                try? Data().write(to: url)
            }
        }
    }

    // MARK: 저장

    private func ensureDirectories() {
        let fm = FileManager.default
        for dir in [directory, imagesDir] where !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
    }

    private func scheduleSave() {
        guard !readOnly else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// 지금 바로 저장 (종료·정지 때)
    func saveNow() {
        guard !readOnly else { return }
        saveWork?.cancel()
        saveWork = nil
        let snapshot = ClipIndex(items: persistHistory ? items : items.filter(\.isSaved), lists: lists)
        let url = indexURL
        ensureDirectories()
        io.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    /// 저장 작업이 끝날 때까지 기다린다 (검사용)
    func waitForWrites() { io.sync {} }

    /// 시작할 때: 색인에 없는 이미지 파일(이전 실행이 남긴 것)을 비운다
    func reclaimOrphans() {
        guard !readOnly, let names = try? FileManager.default.contentsOfDirectory(atPath: imagesDir.path) else { return }
        let used = Set(items.compactMap(\.imageFile))
        for name in names where name.hasSuffix(".png") && !used.contains(name) {
            let url = imagesDir.appendingPathComponent(name)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            if size > 0 { try? Data().write(to: url) }
        }
        // 이미지 파일이 비어 있는 항목은 보여 줄 수 없으므로 뺀다
        let broken = items.filter { $0.kind == .image && imageData(for: $0) == nil }
        if !broken.isEmpty {
            let ids = Set(broken.map(\.id))
            items.removeAll { ids.contains($0.id) }
            scheduleSave()
        }
    }
}

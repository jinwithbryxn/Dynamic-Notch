import AppKit
import CryptoKit

/// 알림 공개 범위
enum NMPrivacy: Int, CaseIterable, Identifiable {
    case appOnly = 0, sender = 1, full = 2
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .appOnly: return T("앱 이름만", "App name only")
        case .sender: return T("보낸 사람·제목까지", "Sender / title")
        case .full: return T("본문까지", "Full body")
        }
    }
}

/// 저장되는 알림 사본 한 건. 공개 범위를 넘는 글자는 처음부터 저장하지 않는다.
struct NMItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var app: String
    var title: String
    var subtitle: String
    var body: String
    /// 알림 센터 기록(전체 디스크 접근)에서 온 것인지
    var fromDatabase = false

    /// 공개 범위에 맞춘 사본
    static func make(app: String, title: String, subtitle: String, body: String, date: Date, privacy: NMPrivacy) -> NMItem {
        switch privacy {
        case .appOnly: return NMItem(date: date, app: app, title: "", subtitle: "", body: "")
        case .sender: return NMItem(date: date, app: app, title: title, subtitle: "", body: "")
        case .full: return NMItem(date: date, app: app, title: title, subtitle: subtitle, body: body)
        }
    }

    /// 화면 표시 줄 (첫 줄, 둘째 줄)
    func lines(_ privacy: NMPrivacy) -> (String, String?) {
        let appLabel = app.isEmpty ? T("알림", "Notification") : app
        switch privacy {
        case .appOnly: return (appLabel, T("새 알림", "New notification"))
        case .sender: return (title.isEmpty ? appLabel : title, title.isEmpty ? nil : appLabel)
        case .full:
            let second = [subtitle, body].filter { !$0.isEmpty }.joined(separator: " · ")
            return (title.isEmpty ? appLabel : title, second.isEmpty ? appLabel : second)
        }
    }
}

/// 미러링한 알림 사본 저장소. 내용은 AES-GCM으로 암호화하고 키는 키체인(이 기기 전용)에 둔다.
/// 파일: ~/Library/Application Support/<번들 ID>/NotifyMirror/history.sealed
/// 지우기는 파일을 휴지통으로 보낸다 (키를 지우면 남은 사본은 읽을 수 없다).
final class NMStore {
    static let keyAccount = "notifymirror.historyKey"
    static let maxItems = 300

    let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let bundle = Bundle.main.bundleIdentifier ?? "com.dynamicnotch.app"
        fileURL = base.appendingPathComponent(bundle).appendingPathComponent("NotifyMirror/history.sealed")
    }

    var fileExists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    // MARK: 암호화 (자체 검사에서도 쓰는 순수 함수)

    static func seal(_ items: [NMItem], key: SymmetricKey) throws -> Data {
        let json = try JSONEncoder().encode(items)
        guard let combined = try AES.GCM.seal(json, using: key).combined else { throw CocoaError(.coderInvalidValue) }
        return combined
    }

    static func open(_ data: Data, key: SymmetricKey) throws -> [NMItem] {
        let box = try AES.GCM.SealedBox(combined: data)
        return try JSONDecoder().decode([NMItem].self, from: AES.GCM.open(box, using: key))
    }

    // MARK: 키

    private func existingKey() -> SymmetricKey? {
        guard let b64 = KeychainStore.get(Self.keyAccount), let raw = Data(base64Encoded: b64), raw.count == 32 else { return nil }
        return SymmetricKey(data: raw)
    }

    private func makeKey() -> SymmetricKey? {
        let key = SymmetricKey(size: .bits256)
        let b64 = key.withUnsafeBytes { Data($0).base64EncodedString() }
        return KeychainStore.set(b64, for: Self.keyAccount) ? key : nil
    }

    // MARK: 읽기·쓰기

    /// 저장된 사본을 읽는다. 파일이 없으면 키체인을 건드리지 않는다.
    func load(retentionDays: Int) -> [NMItem] {
        guard fileExists, let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let key = existingKey(), let items = try? Self.open(data, key: key) else {
            // 키가 없거나 맞지 않음: 읽을 수 없는 사본은 휴지통으로 보내고 새로 시작한다
            trash()
            return []
        }
        return prune(items, retentionDays: retentionDays)
    }

    func save(_ items: [NMItem]) {
        guard let key = existingKey() ?? makeKey(), let sealed = try? Self.seal(items, key: key) else { return }
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? sealed.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func prune(_ items: [NMItem], retentionDays: Int) -> [NMItem] {
        let cutoff = Date().addingTimeInterval(-Double(max(1, retentionDays)) * 86_400)
        return Array(items.filter { $0.date >= cutoff }.sorted { $0.date > $1.date }.prefix(Self.maxItems))
    }

    /// 사본 파일을 휴지통으로 보낸다.
    func trash() {
        guard fileExists else { return }
        try? FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
    }

    /// 기능을 끌 때: 사본은 휴지통으로, 키체인 키는 지운다 (기능 명세 6.10).
    func eraseKeyAndTrash() {
        trash()
        KeychainStore.set(nil, for: Self.keyAccount)
    }
}

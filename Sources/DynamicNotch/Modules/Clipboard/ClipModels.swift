import AppKit
import Carbon.HIToolbox

/// 클립보드 기록 항목 종류
enum ClipKind: String, Codable, CaseIterable {
    case text, link, image, file, color, burst

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        case .burst: return "square.stack.3d.up"
        }
    }

    var label: String {
        switch self {
        case .text: return T("텍스트", "Text")
        case .link: return T("링크", "Links")
        case .image: return T("이미지", "Images")
        case .file: return T("파일", "Files")
        case .color: return T("색상", "Colors")
        case .burst: return T("묶음", "Bursts")
        }
    }

    /// 한 항목을 가리키는 이름 (줄 아래 설명)
    var singular: String {
        switch self {
        case .text: return T("텍스트", "Text")
        case .link: return T("링크", "Link")
        case .image: return T("이미지", "Image")
        case .file: return T("파일", "File")
        case .color: return T("색상", "Color")
        case .burst: return T("연속 복사", "Burst")
        }
    }

    /// 글자로 다루는 종류 (연속 복사 묶음에 넣을 수 있음)
    var isTextual: Bool { self == .text || self == .link || self == .color }
}

/// 기록 한 줄. 내용은 이 Mac에만 저장한다.
struct ClipItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: ClipKind
    var date = Date()
    /// 글자·링크·색상 코드 (묶음은 조각을 합친 글자)
    var text: String?
    /// 연속 복사 묶음의 각 조각
    var parts: [String]?
    /// 파일 경로
    var paths: [String]?
    /// 이미지 파일 이름 (Clipboard/Images/ 안)
    var imageFile: String?
    var imageWidth: Int?
    var imageHeight: Int?
    /// 같은 이미지인지 판별하는 SHA-256
    var digest: String?
    /// 이미지에서 인식한 글자 (기기 안 Vision)
    var ocrText: String?
    /// 복사할 때 앞에 있던 앱
    var appID: String?
    var appName: String?
    var pinned: Bool? = nil
    /// 사용자가 붙인 제목
    var title: String?
    /// 들어 있는 저장 목록
    var lists: [UUID]?

    var isPinned: Bool { pinned ?? false }
    /// 고정했거나 목록에 넣은 항목: 보관 한도·지우기·자동 삭제에서 빠진다
    var isSaved: Bool { isPinned || !(lists ?? []).isEmpty }

    /// 목록 줄에 보일 제목
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        switch kind {
        case .text, .link, .color:
            return Self.firstLine(text ?? "")
        case .burst:
            let n = parts?.count ?? 0
            return T("\(n)개 묶음 · ", "\(n) copies · ") + Self.firstLine(parts?.last ?? "")
        case .image:
            if let w = imageWidth, let h = imageHeight { return T("이미지 \(w)×\(h)", "Image \(w)×\(h)") }
            return T("이미지", "Image")
        case .file:
            let names = (paths ?? []).map { ($0 as NSString).lastPathComponent }
            if names.count > 1 { return T("\(names[0]) 외 \(names.count - 1)개", "\(names[0]) and \(names.count - 1) more") }
            return names.first ?? T("파일", "File")
        }
    }

    /// 검색에 쓰는 글자 (내용·제목·파일 이름·OCR·앱 이름)
    var searchText: String {
        var s: [String] = []
        if let title { s.append(title) }
        if let text { s.append(text.count > 50_000 ? String(text.prefix(50_000)) : text) }
        if let ocrText { s.append(ocrText) }
        if let paths { s.append(contentsOf: paths.map { ($0 as NSString).lastPathComponent }) }
        if let appName { s.append(appName) }
        return s.joined(separator: "\n")
    }

    static func firstLine(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
        let collapsed = line.replacingOccurrences(of: "\t", with: " ")
        return collapsed.count > 300 ? String(collapsed.prefix(300)) + "…" : collapsed
    }
}

/// 이름 붙인 저장 목록
struct ClipList: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
}

/// 디스크에 저장하는 색인 파일 (index.json)
struct ClipIndex: Codable {
    var version = 1
    var items: [ClipItem]
    var lists: [ClipList]
}

/// 클립보드 기능 설정 (ModuleDefaults "module.clipboard.*")
struct ClipPrefs: Equatable {
    static let limits = [40, 100, 200, 500]
    static let burstChoices: [Double] = [0, 2, 3, 5]
    static let maxAgeChoices = [0, 1, 24, 168, 720]          // 시간, 0 = 끔
    static let idleChoices = [1, 5, 15, 30, 60]               // 분
    static let sounds = ["Tink", "Pop", "Morse", "Purr", "Bottle", "Glass", "Ping", "Frog",
                         "Submarine", "Hero", "Funk", "Blow", "Basso", "Sosumi"]
    /// 비밀번호 관리자 기본 제외 목록 (번들 ID)
    static let defaultExcluded = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx",
        "com.apple.Passwords", "com.apple.keychainaccess", "com.bitwarden.desktop",
        "org.keepassxc.keepassxc", "com.lastpass.LastPass", "in.sinew.Enpass-Desktop",
    ]
    static let defaultOpenShortcut = HotKeyCenter.Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey))
    static let defaultPlainShortcut = HotKeyCenter.Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey | shiftKey))

    enum LinkMode: String, CaseIterable { case off, suggest, auto }

    var limit = 40
    var keepAfterQuit = true
    var paused = false
    var ocrAuto = true
    var burstSeconds: Double = 3
    var sound = false
    var soundName = "Tink"
    var excluded = ClipPrefs.defaultExcluded
    var maxAgeHours = 0
    var clearOnSleep = false
    var clearOnLock = false
    var emptyIdle = false
    var emptyIdleMinutes = 5
    var emptyOnSleepLock = false
    var linkMode = LinkMode.suggest
    var pasteOnSelect = true
    var numberPaste = true
    var copyTwice = false
    var openShortcutOn = true
    var openShortcut = ClipPrefs.defaultOpenShortcut
    var plainShortcutOn = false
    var plainShortcut = ClipPrefs.defaultPlainShortcut

    static func load(_ d: ModuleDefaults = ModuleDefaults(module: "clipboard")) -> ClipPrefs {
        var p = ClipPrefs()
        let limit = d.int("limit", default: 40)
        p.limit = limits.contains(limit) ? limit : 40
        p.keepAfterQuit = d.bool("keepAfterQuit", default: true)
        p.paused = d.bool("paused", default: false)
        p.ocrAuto = d.bool("ocrAuto", default: true)
        p.burstSeconds = d.double("burstSeconds", default: 3)
        p.sound = d.bool("sound", default: false)
        p.soundName = d.string("soundName", default: "Tink")
        p.excluded = d.strings("excluded", default: defaultExcluded)
        p.maxAgeHours = d.int("maxAgeHours", default: 0)
        p.clearOnSleep = d.bool("clearOnSleep", default: false)
        p.clearOnLock = d.bool("clearOnLock", default: false)
        p.emptyIdle = d.bool("emptyIdle", default: false)
        p.emptyIdleMinutes = max(1, d.int("emptyIdleMinutes", default: 5))
        p.emptyOnSleepLock = d.bool("emptyOnSleepLock", default: false)
        p.linkMode = LinkMode(rawValue: d.string("linkMode", default: "suggest")) ?? .suggest
        p.pasteOnSelect = d.bool("pasteOnSelect", default: true)
        p.numberPaste = d.bool("numberPaste", default: true)
        p.copyTwice = d.bool("copyTwice", default: false)
        p.openShortcutOn = d.bool("openShortcutOn", default: true)
        p.openShortcut = shortcut(d, "openShortcut") ?? defaultOpenShortcut
        p.plainShortcutOn = d.bool("plainShortcutOn", default: false)
        p.plainShortcut = shortcut(d, "plainShortcut") ?? defaultPlainShortcut
        return p
    }

    static func shortcut(_ d: ModuleDefaults, _ name: String) -> HotKeyCenter.Shortcut? {
        d.data(name).flatMap { try? JSONDecoder().decode(HotKeyCenter.Shortcut.self, from: $0) }
    }

    static func saveShortcut(_ s: HotKeyCenter.Shortcut, _ name: String, _ d: ModuleDefaults = ModuleDefaults(module: "clipboard")) {
        if let data = try? JSONEncoder().encode(s) { d.set(data, name) }
    }

    static func maxAgeLabel(_ hours: Int) -> String {
        switch hours {
        case 0: return T("끔", "Never")
        case 1: return T("1시간 뒤", "After 1 hour")
        case 24: return T("하루 뒤", "After 1 day")
        case 168: return T("7일 뒤", "After 7 days")
        default: return T("\(hours / 24)일 뒤", "After \(hours / 24) days")
        }
    }

    static func burstLabel(_ s: Double) -> String {
        s == 0 ? T("끔", "Off") : T("\(Int(s))초 안의 복사", "Copies within \(Int(s))s")
    }
}

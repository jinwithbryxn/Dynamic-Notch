import AppKit
import CoreText
import SwiftUI

/// 이모지 목록. 문자 뷰어와 같은 이름(macOS CoreEmoji 자료의 한국어·영어 이름)을 쓰고,
/// 자료가 없으면 유니코드 이름으로 대신한다. 맥 글꼴이 그릴 수 있는 것만 넣는다.
final class EmojiCatalog {
    struct Item: Hashable { let emoji: String; let en: String; let ko: String }
    static let shared = EmojiCatalog()

    private(set) lazy var items: [Item] = load()
    private(set) var source = "?"

    private func load() -> [Item] {
        let base = "/System/Library/PrivateFrameworks/CoreEmoji.framework/Versions/A/Resources/"
        func names(_ lang: String) -> [String: String] {
            (NSDictionary(contentsOfFile: base + lang + ".lproj/AppleName.strings") as? [String: String]) ?? [:]
        }
        let en = names("en"), ko = names("ko")
        var list: [Item] = []
        if !en.isEmpty {
            source = "CoreEmoji AppleName.strings"
            for (e, n) in en where Self.canDraw(e) { list.append(Item(emoji: e, en: n.lowercased(), ko: ko[e] ?? "")) }
        } else {
            source = "Unicode scalar names"
            let ranges: [ClosedRange<UInt32>] = [0x1F300...0x1F5FF, 0x1F600...0x1F64F, 0x1F680...0x1F6FF, 0x1F900...0x1F9FF,
                                                  0x1FA70...0x1FAFF, 0x2600...0x27BF]
            for r in ranges {
                for v in r {
                    guard let s = Unicode.Scalar(v), s.properties.isEmojiPresentation, !s.properties.isEmojiModifier,
                          let n = s.properties.name else { continue }
                    let e = String(Character(s))
                    if Self.canDraw(e) { list.append(Item(emoji: e, en: n.lowercased(), ko: "")) }
                }
            }
        }
        return list.sorted {
            let a = Self.rank($0.emoji), b = Self.rank($1.emoji)
            return a.0 != b.0 ? a.0 < b.0 : a.1.lexicographicallyPrecedes(b.1)
        }
    }

    /// 얼굴·사람·손을 먼저, 나머지는 코드 순서
    private static func rank(_ e: String) -> (Int, [UInt32]) {
        let v = e.unicodeScalars.map(\.value)
        let f = v.first ?? 0
        let group: Int
        switch f {
        case 0x1F600...0x1F64F, 0x1F910...0x1F92F, 0x1F970...0x1F97F, 0x1F9D0...0x1F9DF, 0x1FAE0...0x1FAEF: group = 0
        case 0x1F440...0x1F4AF, 0x1F930...0x1F94F, 0x1F9B0...0x1F9CF, 0x1FAF0...0x1FAFF, 0x270A...0x270D, 0x261D: group = 1
        case 0x2764, 0x1F493...0x1F49F, 0x1F9E1, 0x1F90D, 0x1F90E, 0x1FA75...0x1FA77: group = 2
        case 0x1F1E6...0x1F1FF: group = 9
        default: group = 5
        }
        return (group, v)
    }

    private static let emojiFont = CTFontCreateWithName("AppleColorEmoji" as CFString, 16, nil)

    static func canDraw(_ s: String) -> Bool {
        let font = emojiFont
        let utf16 = Array(s.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        guard CTFontGetGlyphsForCharacters(font, utf16, &glyphs, utf16.count) else { return false }
        return glyphs.first.map { $0 != 0 } ?? false
    }

    /// 국기 이모지면 나라 이름(한국어·영어)을 더한 검색 글
    private lazy var haystacks: [String] = items.map { i in
        var h = i.en + " " + i.ko.lowercased()
        let v = i.emoji.unicodeScalars.map(\.value)
        if v.count == 2, v.allSatisfy({ (0x1F1E6...0x1F1FF).contains($0) }) {
            let code = String(v.map { Character(Unicode.Scalar($0 - 0x1F1E6 + 65)!) })
            for loc in ["ko", "en"] {
                if let n = Locale(identifier: loc).localizedString(forRegionCode: code) { h += " " + n.lowercased() }
            }
        }
        return h
    }

    /// 검색: 모든 낱말이 이름(한국어·영어, 국기는 나라 이름)에 들어 있는 것. 이름이 같으면 맨 앞.
    func search(_ query: String, limit: Int = 300) -> [Item] {
        let words = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return Array(items.prefix(limit)) }
        let q = words.joined(separator: " ")
        func has(_ hay: String, _ w: String) -> Bool {
            hay.contains(w) || (w.count >= 4 && w.allSatisfy(\.isASCII) && hay.contains(String(w.dropLast())))   // smile → smiling
        }
        var scored: [(Int, Int, Item)] = []
        for (idx, i) in items.enumerated() {
            let hay = haystacks[idx]
            guard words.allSatisfy({ has(hay, $0) }) else { continue }
            let score: Int
            if hay.contains(" " + q + " ") || hay.hasSuffix(" " + q) || i.en == q || i.ko == q { score = 0 }
            else if i.en.hasPrefix(q) || i.ko.hasPrefix(q) { score = 1 }
            else if hay.contains(" " + q) { score = 2 }
            else { score = 3 }
            scored.append((score, idx, i))
        }
        // 점수 → 짧은 이름 → 원래 순서
        return scored.sorted {
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            if $0.2.en.count != $1.2.en.count { return $0.2.en.count < $1.2.en.count }
            return $0.1 < $1.1
        }.prefix(limit).map(\.2)
    }

    func item(_ emoji: String) -> Item? { items.first { $0.emoji == emoji } }

    /// 피부톤 적용 (0 = 기본, 1–5 = 밝음~어두움). 한 글자 이모지 중 지원하는 것만.
    static func applyTone(_ e: String, tone: Int) -> String {
        guard tone > 0, tone <= 5 else { return e }
        let scalars = e.unicodeScalars.filter { $0.value != 0xFE0F }
        guard scalars.count == 1, let base = scalars.first, base.properties.isEmojiModifierBase,
              let mod = Unicode.Scalar(0x1F3FB + UInt32(tone - 1)) else { return e }
        var s = String.UnicodeScalarView()
        s.append(base); s.append(mod)
        return String(s)
    }
}

/// 이모지 탭: 이름(한국어·영어)으로 검색, Return이나 클릭으로 노치를 열기 전 앱에 넣는다.
/// 최근 12개, 피부톤, 국기는 나라 이름으로 찾는다. 오른쪽 클릭으로 복사만.
final class EmojiModule: NotchModule {
    let id = "emoji"
    var title: String { T("이모지", "Emoji") }
    let symbol = "face.smiling"
    var enabledByDefault: Bool { true }

    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }
    fileprivate var context: ModuleContext?

    var recent: [String] { UserDefaults.standard.stringArray(forKey: "module.emoji.recent") ?? [] }
    var tone: Int { defaults.int("tone", default: 0) }
    func setTone(_ t: Int) { defaults.set(t, "tone") }

    func start(context: ModuleContext) { self.context = context }
    func stop() { context = nil }

    func tabView() -> AnyView? { AnyView(EmojiTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 480, height: 250) }

    private func remember(_ e: String) {
        var list = recent.filter { $0 != e }
        list.insert(e, at: 0)
        UserDefaults.standard.set(Array(list.prefix(12)), forKey: "module.emoji.recent")
    }

    /// 이전 앱에 넣는다. 클립보드 기록 앱이 남기지 않도록 일시 항목 표시를 붙인다.
    func insert(_ raw: String) {
        let e = EmojiCatalog.applyTone(raw, tone: tone)
        remember(raw)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(e, forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        context?.collapse()
        if !ModuleServices.pasteCurrentClipboard() {
            context?.notice(T("클립보드에 복사함", "Copied to clipboard"),
                            T("손쉬운 사용 권한이 있으면 바로 붙여넣음", "With Accessibility access it pastes directly"), symbol: "doc.on.clipboard")
        }
    }

    func copyOnly(_ raw: String) {
        let e = EmojiCatalog.applyTone(raw, tone: tone)
        remember(raw)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(e, forType: .string)
    }

    /// 팔레트: ":heart" 또는 "emoji 하트" / "이모지 하트"
    func paletteResults(for query: String) -> [PaletteAction] {
        let t = query.trimmingCharacters(in: .whitespaces)
        var q: String?
        if t.hasPrefix(":"), t.count >= 3 { q = String(t.dropFirst()) }
        for p in ["emoji ", "이모지 "] where t.lowercased().hasPrefix(p) { q = String(t.dropFirst(p.count)) }
        guard let q, !q.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return EmojiCatalog.shared.search(q, limit: 5).map { i in
            PaletteAction(id: "emoji.\(i.emoji)", title: "\(EmojiCatalog.applyTone(i.emoji, tone: tone))  \(L10n.isEnglish || i.ko.isEmpty ? i.en : i.ko)",
                          subtitle: T("Return: 앞 앱에 넣기", "Return: insert into the previous app"), symbol: symbol) { [weak self] in
                self?.insert(i.emoji)
            }
        }
    }

    func selfTest() -> [String] {
        let c = EmojiCatalog.shared
        var out = ["catalog: \(c.items.count) emoji from \(c.source)"]
        for q in ["heart", "하트", "smile", "웃는", "korea", "대한민국", "japan", "thumbs up", "고양이"] {
            out.append("\(q): " + c.search(q, limit: 6).map(\.emoji).joined())
        }
        out.append("tone 👍 + 3: \(EmojiCatalog.applyTone("👍", tone: 3)) · 😀 + 3: \(EmojiCatalog.applyTone("😀", tone: 3))")
        out.append("recent: \(recent.joined()) · tone setting \(tone)")
        out.append("palette \":cat\": " + paletteResults(for: ":cat").map(\.title).joined(separator: " | "))
        out.append("pasted in self test: no")
        return out
    }
}

private struct EmojiTab: View {
    let module: EmojiModule
    @State private var query = ""
    @State private var results: [EmojiCatalog.Item] = []
    @State private var recent: [String] = []
    @State private var tone = 0
    @State private var hovered: String?
    @FocusState private var focused: Bool

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 4), count: 12)
    private let tones = ["✋", "✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                LaunchField(placeholder: T("이모지 이름 또는 나라 (예: 하트, cat, 일본)", "Emoji name or country (heart, cat, Japan)"),
                            text: $query, focus: $focused) {
                    if let first = results.first { module.insert(first.emoji) }
                }
                Menu {
                    ForEach(tones.indices, id: \.self) { i in
                        Button(tones[i]) { tone = i; module.setTone(i) }
                    }
                } label: { Text(tones[tone]).font(.island(.title3)) }
                .menuStyle(.borderlessButton).fixedSize()
                .help(T("피부톤", "Skin tone")).accessibilityLabel(T("피부톤", "Skin tone"))
            }
            Text(caption).font(.island(.caption)).foregroundStyle(LaunchUI.secondary).lineLimit(1)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    if query.isEmpty {
                        ForEach(recent, id: \.self) { e in cell(e, name: name(e)) }
                    }
                    ForEach(results, id: \.self) { i in cell(i.emoji, name: L10n.isEnglish || i.ko.isEmpty ? i.en : i.ko) }
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            recent = module.recent
            tone = module.tone
            results = EmojiCatalog.shared.search("")
            module.context?.focusInput()
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: query) { _, q in results = EmojiCatalog.shared.search(q) }
    }

    private var caption: String {
        if let h = hovered { return h }
        if !query.isEmpty { return results.isEmpty ? T("찾는 이모지 없음", "No matches") : T("Return: 첫 번째 넣기 · 오른쪽 클릭: 복사만", "Return: insert first · right-click: copy only") }
        return recent.isEmpty ? T("클릭해서 앞 앱에 넣기", "Click to insert into the previous app") : T("최근 사용 · 전체", "Recent · all")
    }

    private func name(_ e: String) -> String {
        guard let i = EmojiCatalog.shared.item(e) else { return e }
        return L10n.isEnglish || i.ko.isEmpty ? i.en : i.ko
    }

    private func cell(_ e: String, name: String) -> some View {
        Button { module.insert(e) } label: {
            Text(EmojiCatalog.applyTone(e, tone: tone)).font(.island(.title1))
                .frame(width: 34, height: 32)
                .background(RoundedRectangle(cornerRadius: 7).fill(hovered == name ? LaunchUI.fill : .clear))
        }
        .buttonStyle(.plain)
        .help(name).accessibilityLabel(name)
        .onHover { hovered = $0 ? name : (hovered == name ? nil : hovered) }
        .contextMenu {
            Button(T("복사만", "Copy only")) { module.copyOnly(e) }
        }
    }
}

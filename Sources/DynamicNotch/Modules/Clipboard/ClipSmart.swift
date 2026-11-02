import AppKit

// MARK: 색상 코드

/// sRGB 색 (각 값 0...1)
struct ClipRGBA: Equatable {
    var r: Double, g: Double, b: Double, a: Double = 1
}

/// 색을 복사할 때 쓰는 형식
enum ClipColorFormat: String, CaseIterable, Identifiable {
    case hex, rgb, hsl, swiftUI
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hex: return "HEX"
        case .rgb: return "RGB"
        case .hsl: return "HSL"
        case .swiftUI: return "SwiftUI"
        }
    }
}

enum ClipColors {
    /// "#3A7BFF", "#fff", "rgb(58, 123, 255)", "rgba(...)", "hsl(220, 100%, 61%)" 를 읽는다. 문자열 전체가 색일 때만.
    static func parse(_ raw: String) -> ClipRGBA? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty, s.count <= 64 else { return nil }
        if s.hasPrefix("#") { return parseHex(String(s.dropFirst())) }
        for prefix in ["rgba(", "rgb("] where s.hasPrefix(prefix) && s.hasSuffix(")") {
            let n = numbers(String(s.dropFirst(prefix.count).dropLast()))
            guard n.count == 3 || n.count == 4 else { return nil }
            func ch(_ v: (Double, Bool)) -> Double? {
                let x = v.1 ? v.0 / 100 : v.0 / 255
                return (0...1).contains(x) ? x : nil
            }
            guard let r = ch(n[0]), let g = ch(n[1]), let b = ch(n[2]) else { return nil }
            var a = 1.0
            if n.count == 4 { a = n[3].1 ? n[3].0 / 100 : n[3].0; guard (0...1).contains(a) else { return nil } }
            return ClipRGBA(r: r, g: g, b: b, a: a)
        }
        for prefix in ["hsla(", "hsl("] where s.hasPrefix(prefix) && s.hasSuffix(")") {
            let n = numbers(String(s.dropFirst(prefix.count).dropLast()).replacingOccurrences(of: "deg", with: ""))
            guard n.count == 3 || n.count == 4 else { return nil }
            let h = n[0].0.truncatingRemainder(dividingBy: 360) / 360
            let sat = n[1].0 / 100, l = n[2].0 / 100
            guard (0...1).contains(sat), (0...1).contains(l) else { return nil }
            var a = 1.0
            if n.count == 4 { a = n[3].1 ? n[3].0 / 100 : n[3].0; guard (0...1).contains(a) else { return nil } }
            var c = hslToRGB(h: h < 0 ? h + 1 : h, s: sat, l: l)
            c.a = a
            return c
        }
        return nil
    }

    private static func parseHex(_ h: String) -> ClipRGBA? {
        guard [3, 4, 6, 8].contains(h.count), h.allSatisfy(\.isHexDigit), let v = UInt64(h, radix: 16) else { return nil }
        switch h.count {
        case 3, 4:
            let n = h.count
            func nib(_ i: Int) -> Double { Double((v >> UInt64(4 * (n - 1 - i))) & 0xF) * 17 / 255 }
            return ClipRGBA(r: nib(0), g: nib(1), b: nib(2), a: n == 4 ? nib(3) : 1)
        default:
            let n = h.count / 2
            func byte(_ i: Int) -> Double { Double((v >> UInt64(8 * (n - 1 - i))) & 0xFF) / 255 }
            return ClipRGBA(r: byte(0), g: byte(1), b: byte(2), a: n == 4 ? byte(3) : 1)
        }
    }

    /// "58, 123, 255" / "58 123 255 / 50%" → (값, 퍼센트 여부)
    private static func numbers(_ s: String) -> [(Double, Bool)] {
        s.replacingOccurrences(of: "/", with: " ").replacingOccurrences(of: ",", with: " ")
            .split(separator: " ").compactMap { part in
                let pct = part.hasSuffix("%")
                return Double(pct ? String(part.dropLast()) : String(part)).map { ($0, pct) }
            }
    }

    static func hslToRGB(h: Double, s: Double, l: Double) -> ClipRGBA {
        if s == 0 { return ClipRGBA(r: l, g: l, b: l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func hue(_ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return ClipRGBA(r: hue(h + 1.0 / 3), g: hue(h), b: hue(h - 1.0 / 3))
    }

    static func hsl(_ c: ClipRGBA) -> (h: Double, s: Double, l: Double) {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        let l = (mx + mn) / 2
        guard mx != mn else { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == c.r { h = (c.g - c.b) / d + (c.g < c.b ? 6 : 0) }
        else if mx == c.g { h = (c.b - c.r) / d + 2 }
        else { h = (c.r - c.g) / d + 4 }
        h /= 6
        return (h * 360, s, l)
    }

    static func format(_ c: ClipRGBA, _ f: ClipColorFormat) -> String {
        func b(_ x: Double) -> Int { Int((max(0, min(1, x)) * 255).rounded()) }
        let alpha = c.a < 0.999
        switch f {
        case .hex:
            var s = String(format: "#%02X%02X%02X", b(c.r), b(c.g), b(c.b))
            if alpha { s += String(format: "%02X", b(c.a)) }
            return s
        case .rgb:
            return alpha ? "rgba(\(b(c.r)), \(b(c.g)), \(b(c.b)), \(trim(c.a)))" : "rgb(\(b(c.r)), \(b(c.g)), \(b(c.b)))"
        case .hsl:
            let v = hsl(c)
            let body = "\(Int(v.h.rounded()) % 360), \(Int((v.s * 100).rounded()))%, \(Int((v.l * 100).rounded()))%"
            return alpha ? "hsla(\(body), \(trim(c.a)))" : "hsl(\(body))"
        case .swiftUI:
            let body = String(format: "red: %.3f, green: %.3f, blue: %.3f", c.r, c.g, c.b)
            return alpha ? "Color(\(body), opacity: \(trim(c.a)))" : "Color(\(body))"
        }
    }

    private static func trim(_ x: Double) -> String {
        let s = String(format: "%.2f", x)
        return s.hasSuffix("0") ? String(s.dropLast()) : s
    }

    static func nsColor(_ c: ClipRGBA) -> NSColor {
        NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }

    static func from(_ color: NSColor) -> ClipRGBA? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        return ClipRGBA(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent), a: Double(c.alphaComponent))
    }
}

// MARK: 링크 추적 요소 정리

/// 링크의 추적용 파라미터를 지운다. 페이지 내용을 바꾸는 파라미터(영상 ID, 검색어 등)와 애매한 파라미터는 남긴다.
enum ClipLinkCleaner {
    /// 어느 사이트에서나 추적용인 이름
    static let globalNames: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "mc_cid", "mc_eid", "igshid",
        "_hsenc", "_hsmi", "__hssc", "__hstc", "__hsfp", "hsctatracking", "mkt_tok", "yclid", "twclid", "ttclid",
        "li_fat_id", "s_cid", "vero_conv", "vero_id", "oly_anon_id", "oly_enc_id", "rb_clickid", "wickedid",
        "_openstat", "_ga", "_gl", "srsltid", "epik", "ndclid", "sccid", "irclickid", "cvid",
    ]
    /// 이 글자로 시작하는 이름은 추적용 (utm_source 등)
    static let globalPrefixes = ["utm_", "mtm_", "pk_campaign", "pk_kwd", "pk_source", "pk_medium", "hsa_"]

    /// 사이트별 규칙: 호스트 끝부분 → 지울 이름
    static let siteRules: [(hosts: [String], names: Set<String>, prefixes: [String])] = [
        (["youtube.com", "youtu.be"], ["si", "feature", "pp", "ab_channel", "embeds_referring_euri", "source_ve_path"], []),
        (["x.com", "twitter.com"], ["s", "t", "ref_src", "ref_url", "cn"], []),
        (["instagram.com"], ["igsh", "img_index_tracking", "utm_source"], []),
        (["facebook.com", "fb.com", "fb.watch"], ["mibextid", "__tn__", "eav", "paipv", "rdid", "sfnsn", "ref", "refsrc", "hc_ref"], ["__cft__"]),
        (["spotify.com"], ["si", "context", "nd", "dl_branch"], []),
        (["reddit.com", "redd.it"], ["share_id", "rdt", "ref", "ref_source", "correlation_id"], []),
        (["amazon.com", "amazon.co.uk", "amazon.de", "amazon.co.jp", "amazon.fr", "amazon.ca", "amazon.it", "amazon.es", "amazon.in"],
         ["ref", "ref_", "pd_rd_w", "pd_rd_r", "pd_rd_wg", "pd_rd_i", "pf_rd_p", "pf_rd_r", "pf_rd_s", "pf_rd_t", "pf_rd_i", "pf_rd_m",
          "content-id", "crid", "sprefix", "qid", "sr", "dib", "dib_tag", "linkcode", "creativeasin", "linkid", "ascsubtag", "smid", "spla"], ["pd_rd_", "pf_rd_"]),
        (["ebay.com", "ebay.co.uk", "ebay.de"], ["_trkparms", "_trksid", "hash", "amdata", "mkcid", "mkevt", "mkrid", "campid", "toolid", "customid", "_from"], []),
        (["linkedin.com"], ["trk", "trackingid", "refid", "lipi", "midtoken", "midsig", "trkemail", "eid", "originalsubdomain", "rcm"], []),
        (["etsy.com"], ["click_key", "click_sum", "ref", "pro", "frs", "sts", "organic_search_click", "plkey"], ["ga_"]),
        (["tiktok.com"], ["_r", "_t", "is_from_webapp", "sender_device", "share_app_id", "share_link_id", "tt_from", "u_code", "social_sharing", "is_copy_url", "web_id"], []),
        (["google.com", "google.co.kr", "google.co.uk", "google.de", "google.co.jp"],
         ["ved", "ei", "sca_esv", "sxsrf", "gs_lp", "gs_lcrp", "oq", "aqs", "sourceid", "ie", "uact", "sclient", "iflsig", "source", "bih", "biw", "rlz", "sa", "usg"], []),
        (["naver.com"], ["ntype", "sm", "where_from"], []),
        (["coupang.com"], ["itemsid", "src", "spec", "addtag", "ctag", "lptag", "wtrid", "wpcid", "traceid", "requestid", "sourcetype", "q_rank", "searchid", "isaddedcart"], []),
    ]

    private static func rule(for host: String) -> (names: Set<String>, prefixes: [String]) {
        var names = Set<String>(), prefixes: [String] = []
        let h = host.lowercased()
        for r in siteRules where r.hosts.contains(where: { h == $0 || h.hasSuffix("." + $0) }) {
            names.formUnion(r.names)
            prefixes += r.prefixes
        }
        return (names, prefixes)
    }

    /// 지울 파라미터 이름들 (없으면 빈 배열)
    static func trackers(in url: URL) -> [String] {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.percentEncodedQueryItems, !items.isEmpty else { return [] }
        let site = rule(for: comps.host ?? "")
        return items.map(\.name).filter { isTracker($0, site: site) }
    }

    private static func isTracker(_ raw: String, site: (names: Set<String>, prefixes: [String])) -> Bool {
        let n = (raw.removingPercentEncoding ?? raw).lowercased()
        if globalNames.contains(n) || site.names.contains(n) { return true }
        return (globalPrefixes + site.prefixes).contains { n.hasPrefix($0) }
    }

    /// 정리한 링크. 지울 것이 없으면 nil.
    static func clean(_ url: URL) -> URL? {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.percentEncodedQueryItems, !items.isEmpty else { return nil }
        let site = rule(for: comps.host ?? "")
        let kept = items.filter { !isTracker($0.name, site: site) }
        guard kept.count != items.count else { return nil }
        comps.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return comps.url
    }

    /// 문자열 전체가 링크일 때 정리한 문자열. 바꿀 것이 없으면 nil.
    static func cleanString(_ s: String) -> String? {
        guard let url = ClipDetect.link(s), let cleaned = clean(url) else { return nil }
        return cleaned.absoluteString
    }
}

// MARK: 내용 감지 (스마트 액션)

enum ClipDetect {
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let phoneDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
    private static let addressDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)

    /// 문자열 전체가 웹 링크 하나일 때 (http·https·ftp, 또는 www.로 시작)
    static func link(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count < 8000, !s.contains(where: { $0.isWhitespace }) else { return nil }
        let lower = s.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("ftp://") {
            guard let url = URL(string: s), url.host != nil else { return nil }
            return url
        }
        if lower.hasPrefix("www."), let url = URL(string: "https://" + s), url.host?.contains(".") == true { return url }
        return nil
    }

    /// 문자열 전체가 이메일 주소일 때
    static func email(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("mailto:") { s = String(s.dropFirst(7)) }
        guard s.count <= 254, !s.contains(where: { $0.isWhitespace }) else { return nil }
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return s.range(of: pattern, options: .regularExpression) != nil ? s : nil
    }

    /// 문자열 전체가 전화번호일 때
    static func phone(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 7, s.count <= 24, s.filter(\.isNumber).count >= 7,
              s.allSatisfy({ $0.isNumber || " +-().".contains($0) }) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = phoneDetector?.firstMatch(in: s, range: range), m.range.length >= range.length - 1 else { return nil }
        return m.phoneNumber ?? s
    }

    /// 글자 대부분이 주소 하나일 때 (지도에서 열기)
    static func address(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 8, s.count <= 200 else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = addressDetector?.firstMatch(in: s, range: range), Double(m.range.length) >= Double(range.length) * 0.8 else { return nil }
        return s
    }

    /// 수식이면 결과 (예: "12*(3+4)" → 84). 날짜·전화번호 같은 '-'만 있는 글자는 수식으로 보지 않는다.
    static func math(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 3, s.count <= 200 else { return nil }
        let allowed = Set("0123456789.,+-*/×÷%^() ")
        guard s.allSatisfy({ allowed.contains($0) }), s.contains(where: \.isNumber) else { return nil }
        let strongOps = s.contains { "+*/×÷^%".contains($0) }
        let spacedMinus = s.contains(" - ") || s.contains("(")
        guard strongOps || spacedMinus else { return nil }
        var parser = ClipMathParser(s)
        guard let v = parser.parse(), v.isFinite else { return nil }
        return v
    }

    static func formatNumber(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumSignificantDigits = 12
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    /// JSON 객체·배열이면 들여쓰기한 글자 (이미 같으면 nil)
    static func prettyJSON(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = s.first, first == "{" || first == "[", s.count <= 2_000_000,
              let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes]),
              let pretty = String(data: out, encoding: .utf8) else { return nil }
        return pretty == s ? nil : pretty
    }
}

/// 사칙연산·거듭제곱·괄호만 읽는 작은 계산기 (NSExpression은 잘못된 입력에서 앱이 죽을 수 있어 쓰지 않는다)
struct ClipMathParser {
    private let chars: [Character]
    private var i = 0

    init(_ s: String) {
        chars = Array(s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/"))
    }

    mutating func parse() -> Double? {
        guard let v = expr(), i == chars.count else { return nil }
        return v
    }

    private mutating func expr() -> Double? {
        guard var v = term() else { return nil }
        while i < chars.count, chars[i] == "+" || chars[i] == "-" {
            let op = chars[i]; i += 1
            guard let r = term() else { return nil }
            v = op == "+" ? v + r : v - r
        }
        return v
    }

    private mutating func term() -> Double? {
        guard var v = power() else { return nil }
        while i < chars.count, "*/%".contains(chars[i]) {
            let op = chars[i]; i += 1
            guard let r = power() else { return nil }
            switch op {
            case "*": v *= r
            case "/": guard r != 0 else { return nil }; v /= r
            default: guard r != 0 else { return nil }; v = v.truncatingRemainder(dividingBy: r)
            }
        }
        return v
    }

    private mutating func power() -> Double? {
        guard let base = unary() else { return nil }
        if i < chars.count, chars[i] == "^" {
            i += 1
            guard let e = power() else { return nil }
            return pow(base, e)
        }
        return base
    }

    private mutating func unary() -> Double? {
        if i < chars.count, chars[i] == "-" { i += 1; return unary().map { -$0 } }
        if i < chars.count, chars[i] == "+" { i += 1; return unary() }
        return primary()
    }

    private mutating func primary() -> Double? {
        guard i < chars.count else { return nil }
        if chars[i] == "(" {
            i += 1
            guard let v = expr(), i < chars.count, chars[i] == ")" else { return nil }
            i += 1
            return v
        }
        let start = i
        while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
        guard i > start else { return nil }
        return Double(String(chars[start..<i]))
    }
}

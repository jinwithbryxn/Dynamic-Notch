import Foundation

/// 키 순서와 원래 글자(문자열·숫자 토큰)를 지키는 JSON.
/// 다른 앱 설정 파일(~/.claude/settings.json, ~/.codex/hooks.json)에 항목을 넣고 뺄 때,
/// 건드리지 않은 부분이 그대로 남도록 쓴다. 출력은 JSON.stringify(값, null, 2)와 같은 모양이다.
indirect enum OrderedJSON: Equatable {
    case object([Member])
    case array([OrderedJSON])
    /// value: 해석한 글자, raw: 파일에 있던 그대로의 토큰 (따옴표 포함, 새로 만든 값은 nil)
    case string(String, raw: String?)
    case number(String)
    case bool(Bool)
    case null

    struct Member: Equatable {
        var key: String
        var rawKey: String?
        var value: OrderedJSON
    }

    static func str(_ s: String) -> OrderedJSON { .string(s, raw: nil) }
    static func obj(_ pairs: [(String, OrderedJSON)]) -> OrderedJSON { .object(pairs.map { Member(key: $0.0, rawKey: nil, value: $0.1) }) }

    // MARK: 읽기 도우미

    subscript(key: String) -> OrderedJSON? {
        guard case .object(let m) = self else { return nil }
        return m.first { $0.key == key }?.value
    }

    var stringValue: String? { if case .string(let s, _) = self { return s }; return nil }
    var arrayValue: [OrderedJSON]? { if case .array(let a) = self { return a }; return nil }
    var isObject: Bool { if case .object = self { return true }; return false }

    /// 키 값을 바꾸거나(같은 자리) 끝에 더한다
    mutating func set(_ key: String, _ value: OrderedJSON) {
        guard case .object(var m) = self else { return }
        if let i = m.firstIndex(where: { $0.key == key }) { m[i].value = value } else { m.append(Member(key: key, rawKey: nil, value: value)) }
        self = .object(m)
    }

    mutating func remove(_ key: String) {
        guard case .object(var m) = self else { return }
        m.removeAll { $0.key == key }
        self = .object(m)
    }

    // MARK: 쓰기 (JSON.stringify(_, null, 2) 모양)

    func stringify(indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let inner = String(repeating: "  ", count: indent + 1)
        switch self {
        case .object(let m):
            if m.isEmpty { return "{}" }
            return "{\n" + m.map { inner + ($0.rawKey ?? Self.quote($0.key)) + ": " + $0.value.stringify(indent: indent + 1) }
                .joined(separator: ",\n") + "\n" + pad + "}"
        case .array(let a):
            if a.isEmpty { return "[]" }
            return "[\n" + a.map { inner + $0.stringify(indent: indent + 1) }.joined(separator: ",\n") + "\n" + pad + "]"
        case .string(let s, let raw): return raw ?? Self.quote(s)
        case .number(let n): return n
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        }
    }

    /// JSON.stringify와 같은 이스케이프 (비ASCII·슬래시는 그대로)
    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    // MARK: 읽기 (엄격한 JSON. 주석·끝 쉼표는 오류)

    struct ParseError: Error, LocalizedError {
        let offset: Int
        let reason: String
        var errorDescription: String? { "JSON \(reason) @\(offset)" }
    }

    static func parse(_ text: String) throws -> OrderedJSON {
        var p = Parser(bytes: Array(text.utf8))
        p.skip()
        let v = try p.value()
        p.skip()
        guard p.i == p.bytes.count else { throw ParseError(offset: p.i, reason: "trailing data") }
        return v
    }

    private struct Parser {
        let bytes: [UInt8]
        var i = 0

        mutating func skip() {
            while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
        }

        mutating func value() throws -> OrderedJSON {
            guard i < bytes.count else { throw ParseError(offset: i, reason: "unexpected end") }
            switch bytes[i] {
            case UInt8(ascii: "{"): return try object()
            case UInt8(ascii: "["): return try array()
            case UInt8(ascii: "\""):
                let (s, raw) = try string()
                return .string(s, raw: raw)
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default: return try number()
            }
        }

        mutating func literal(_ word: String) throws {
            let w = Array(word.utf8)
            guard i + w.count <= bytes.count, Array(bytes[i..<(i + w.count)]) == w else { throw ParseError(offset: i, reason: "bad literal") }
            i += w.count
        }

        mutating func number() throws -> OrderedJSON {
            let start = i
            while i < bytes.count, "+-0123456789.eE".utf8.contains(bytes[i]) { i += 1 }
            guard i > start else { throw ParseError(offset: i, reason: "unexpected character") }
            let raw = String(decoding: bytes[start..<i], as: UTF8.self)
            guard Double(raw) != nil else { throw ParseError(offset: start, reason: "bad number") }
            return .number(raw)
        }

        mutating func string() throws -> (String, String) {
            let start = i
            i += 1
            var scalars = String.UnicodeScalarView()
            var chunkStart = i
            func flush(_ end: Int) { scalars.append(contentsOf: String(decoding: bytes[chunkStart..<end], as: UTF8.self).unicodeScalars) }
            while true {
                guard i < bytes.count else { throw ParseError(offset: i, reason: "unterminated string") }
                let c = bytes[i]
                if c == UInt8(ascii: "\"") { flush(i); i += 1; break }
                if c < 0x20 { throw ParseError(offset: i, reason: "control character in string") }
                if c == UInt8(ascii: "\\") {
                    flush(i)
                    i += 1
                    guard i < bytes.count else { throw ParseError(offset: i, reason: "bad escape") }
                    let e = bytes[i]
                    i += 1
                    switch e {
                    case UInt8(ascii: "\""): scalars.append("\"")
                    case UInt8(ascii: "\\"): scalars.append("\\")
                    case UInt8(ascii: "/"): scalars.append("/")
                    case UInt8(ascii: "b"): scalars.append("\u{08}")
                    case UInt8(ascii: "f"): scalars.append("\u{0C}")
                    case UInt8(ascii: "n"): scalars.append("\n")
                    case UInt8(ascii: "r"): scalars.append("\r")
                    case UInt8(ascii: "t"): scalars.append("\t")
                    case UInt8(ascii: "u"):
                        var code = try hex4()
                        if (0xD800...0xDBFF).contains(code), i + 1 < bytes.count, bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") {
                            i += 2
                            let low = try hex4()
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        }
                        scalars.append(Unicode.Scalar(code) ?? "\u{FFFD}")
                    default: throw ParseError(offset: i, reason: "bad escape")
                    }
                    chunkStart = i
                    continue
                }
                i += 1
            }
            return (String(scalars), String(decoding: bytes[start..<i], as: UTF8.self))
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= bytes.count, let v = UInt32(String(decoding: bytes[i..<(i + 4)], as: UTF8.self), radix: 16) else {
                throw ParseError(offset: i, reason: "bad unicode escape")
            }
            i += 4
            return v
        }

        mutating func array() throws -> OrderedJSON {
            i += 1
            var items: [OrderedJSON] = []
            skip()
            if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array([]) }
            while true {
                skip()
                items.append(try value())
                skip()
                guard i < bytes.count else { throw ParseError(offset: i, reason: "unterminated array") }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
                throw ParseError(offset: i, reason: "expected , or ]")
            }
        }

        mutating func object() throws -> OrderedJSON {
            i += 1
            var members: [Member] = []
            skip()
            if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object([]) }
            while true {
                skip()
                guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw ParseError(offset: i, reason: "expected key") }
                let (k, raw) = try string()
                skip()
                guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { throw ParseError(offset: i, reason: "expected :") }
                i += 1
                skip()
                members.append(Member(key: k, rawKey: raw, value: try value()))
                skip()
                guard i < bytes.count else { throw ParseError(offset: i, reason: "unterminated object") }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(members) }
                throw ParseError(offset: i, reason: "expected , or }")
            }
        }
    }
}

import Foundation

/// 작은 수식 해석기. NSExpression을 쓰지 않아 이상한 입력에도 앱이 죽지 않는다.
/// 지원: + - * / ^ ( ) , 퍼센트, 계승(!), 도(°), mod, 상수(pi, e, tau, ans), 함수(sqrt, sin, log 등), 곱셈 생략(2pi, 3(4+1)).
/// 퍼센트 규칙: "200 + 10%" = 220, "200 - 10%" = 180, "10% * 200" = 20 (일반 계산기와 같음).
enum CalcEngine {
    enum CalcError: Error { case syntax, unknown(String), domain, tooLong }

    /// 계산 결과. 실패하면 nil.
    static func evaluate(_ text: String, ans: Double? = nil) -> Double? {
        try? evaluateThrowing(text, ans: ans)
    }

    static func evaluateThrowing(_ text: String, ans: Double?) throws -> Double {
        guard text.count <= 400 else { throw CalcError.tooLong }
        var p = Parser(tokens: try lex(text), ans: ans)
        let v = try p.parseExpression()
        guard p.atEnd else { throw CalcError.syntax }
        guard v.isFinite else { throw CalcError.domain }
        return v
    }

    /// 수식처럼 보이는지 (팔레트에서 숫자 하나만 친 경우 등은 결과를 내지 않는다)
    static func looksLikeMath(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let toks = try? lex(t), toks.count >= 2 else { return false }
        let hasOp = toks.contains { tok in
            switch tok {
            case .op, .percent, .bang, .degree: return true
            case .ident(let s): return functions[s] != nil || constants[s] != nil || s == "ans" || s == "mod"
            default: return false
            }
        }
        let hasNumber = toks.contains { if case .number = $0 { return true }; return false }
        return hasOp && (hasNumber || toks.contains { if case .ident(let s) = $0 { return constants[s] != nil || s == "ans" }; return false })
    }

    // MARK: 표시

    /// 화면용: 자릿수 구분, 최대 10자리 소수, 아주 크거나 작으면 지수 표기
    static func format(_ v: Double, grouping: Bool = true) -> String {
        if v == 0 { return "0" }
        let a = abs(v)
        if a >= 1e15 || a < 1e-9 {
            let f = NumberFormatter()
            f.numberStyle = .scientific
            f.maximumFractionDigits = 8
            f.exponentSymbol = "e"
            return f.string(from: NSNumber(value: v)) ?? String(v)
        }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = grouping
        f.groupingSeparator = ","
        f.decimalSeparator = "."
        f.maximumFractionDigits = max(0, 10 - Int(log10(max(a, 1))))
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    // MARK: 낱말 나누기

    enum Token: Equatable {
        case number(Double)
        case ident(String)
        case op(Character)      // + - * / ^
        case lparen, rparen, comma, percent, bang, degree
    }

    static let constants: [String: Double] = ["pi": .pi, "π": .pi, "e": M_E, "tau": 2 * .pi]
    static let functions: [String: ([Double]) throws -> Double] = {
        func one(_ f: @escaping (Double) -> Double) -> ([Double]) throws -> Double {
            { a in guard a.count == 1 else { throw CalcError.syntax }; return f(a[0]) }
        }
        return [
            "sqrt": one(sqrt), "cbrt": one(cbrt), "abs": one(abs),
            "sin": one(sin), "cos": one(cos), "tan": one(tan),
            "asin": one(asin), "acos": one(acos), "atan": one(atan),
            "sinh": one(sinh), "cosh": one(cosh), "tanh": one(tanh),
            "ln": one(log), "log2": one(log2), "exp": one(exp),
            "floor": one(floor), "ceil": one(ceil),
            "log": { a in
                if a.count == 1 { return log10(a[0]) }
                if a.count == 2 { return log(a[0]) / log(a[1]) }
                throw CalcError.syntax
            },
            "round": { a in
                if a.count == 1 { return a[0].rounded() }
                if a.count == 2 { let m = pow(10, a[1].rounded()); return (a[0] * m).rounded() / m }
                throw CalcError.syntax
            },
            "pow": { a in guard a.count == 2 else { throw CalcError.syntax }; return pow(a[0], a[1]) },
            "min": { a in guard let m = a.min() else { throw CalcError.syntax }; return m },
            "max": { a in guard let m = a.max() else { throw CalcError.syntax }; return m },
        ]
    }()

    static func lex(_ text: String) throws -> [Token] {
        var out: [Token] = []
        let chars = Array(text)
        var i = 0
        var callDepth: [Bool] = []   // 괄호마다 함수 호출 괄호인지
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isNumber && c.isASCII || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                var s = ""
                while i < chars.count {
                    let d = chars[i]
                    if d.isASCII && d.isNumber || d == "." { s.append(d); i += 1; continue }
                    // 자릿수 쉼표 (함수 인자 구분이 아닐 때만): 1,000
                    if d == ",", callDepth.last != true, i + 3 < chars.count,
                       (1...3).allSatisfy({ chars[i + $0].isASCII && chars[i + $0].isNumber }),
                       !(i + 4 < chars.count && chars[i + 4].isASCII && chars[i + 4].isNumber) {
                        i += 1; continue
                    }
                    // 지수 표기 1e5, 2.5e-3
                    if (d == "e" || d == "E"), i + 1 < chars.count,
                       chars[i + 1].isNumber || ((chars[i + 1] == "-" || chars[i + 1] == "+") && i + 2 < chars.count && chars[i + 2].isNumber) {
                        s.append("e"); i += 1
                        if chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
                        continue
                    }
                    break
                }
                guard s.filter({ $0 == "." }).count <= 1, let v = Double(s) else { throw CalcError.syntax }
                out.append(.number(v))
                continue
            }
            if c.isLetter || c == "π" {
                var s = ""
                while i < chars.count, chars[i].isLetter || chars[i] == "π" || (chars[i].isNumber && !s.isEmpty) { s.append(chars[i]); i += 1 }
                out.append(.ident(s.lowercased()))
                continue
            }
            switch c {
            case "+": out.append(.op("+"))
            case "-", "−", "–": out.append(.op("-"))
            case "*", "×", "·": out.append(.op("*"))
            case "/", "÷": out.append(.op("/"))
            case "^": out.append(.op("^"))
            case "(":
                let isCall: Bool = { if case .ident(let s)? = out.last { return functions[s] != nil }; return false }()
                callDepth.append(isCall)
                out.append(.lparen)
            case ")":
                _ = callDepth.popLast()
                out.append(.rparen)
            case ",": out.append(.comma)
            case "%": out.append(.percent)
            case "!": out.append(.bang)
            case "°": out.append(.degree)
            default: throw CalcError.unknown(String(c))
            }
            i += 1
        }
        return out
    }

    // MARK: 해석 (재귀 하강)

    private struct Parser {
        let tokens: [Token]
        let ans: Double?
        var pos = 0
        var depth = 0

        init(tokens: [Token], ans: Double?) { self.tokens = tokens; self.ans = ans }

        var atEnd: Bool { pos >= tokens.count }
        func peek(_ o: Int = 0) -> Token? { pos + o < tokens.count ? tokens[pos + o] : nil }
        mutating func next() -> Token? { defer { pos += 1 }; return peek() }

        mutating func parseExpression() throws -> Double {
            depth += 1
            defer { depth -= 1 }
            guard depth < 64 else { throw CalcError.syntax }
            var v = try parseTerm().value
            while let t = peek(), case .op(let o) = t, o == "+" || o == "-" {
                pos += 1
                let rhs = try parseTerm()
                // a ± b% → a × (1 ± b/100)
                let r = rhs.barePercent ? v * rhs.value : rhs.value
                v = o == "+" ? v + r : v - r
            }
            return v
        }

        /// barePercent: 이 항이 "b%" 하나뿐인지 (덧셈·뺄셈 퍼센트 규칙용)
        mutating func parseTerm() throws -> (value: Double, barePercent: Bool) {
            var first = try parseUnary()
            var v = first.value
            var count = 1
            while let t = peek() {
                if case .op(let o) = t, o == "*" || o == "/" {
                    pos += 1
                    let r = try parseUnary().value
                    if o == "/" { guard r != 0 else { throw CalcError.domain }; v /= r } else { v *= r }
                } else if case .ident("mod") = t {
                    pos += 1
                    let r = try parseUnary().value
                    guard r != 0 else { throw CalcError.domain }
                    v = v.truncatingRemainder(dividingBy: r)
                } else if startsOperand(t) {
                    // 곱셈 생략: 2pi, 3(1+2), (1+2)(3+4)
                    v *= try parseUnary().value
                } else { break }
                count += 1
            }
            if count > 1 { first.barePercent = false }
            return (v, first.barePercent && count == 1)
        }

        func startsOperand(_ t: Token) -> Bool {
            switch t {
            case .number, .lparen: return true
            case .ident(let s): return s != "mod" && s != "to" && s != "in"
            default: return false
            }
        }

        mutating func parseUnary() throws -> (value: Double, barePercent: Bool) {
            if case .op(let o)? = peek(), o == "-" || o == "+" {
                pos += 1
                let u = try parseUnary()
                return (o == "-" ? -u.value : u.value, u.barePercent)
            }
            return try parsePower()
        }

        mutating func parsePower() throws -> (value: Double, barePercent: Bool) {
            let base = try parsePostfix()
            if case .op("^")? = peek() {
                pos += 1
                let e = try parseUnary().value
                return (pow(base.value, e), false)
            }
            return base
        }

        mutating func parsePostfix() throws -> (value: Double, barePercent: Bool) {
            var v = try parsePrimary()
            var percent = false
            while let t = peek() {
                switch t {
                case .percent:
                    pos += 1; v /= 100; percent = true
                case .bang:
                    pos += 1
                    guard v >= 0, v <= 170, v == v.rounded() else { throw CalcError.domain }
                    v = (1...max(1, Int(v))).reduce(1.0) { $0 * Double($1) }
                    percent = false
                case .degree:
                    pos += 1; v = v * .pi / 180; percent = false
                default:
                    return (v, percent)
                }
            }
            return (v, percent)
        }

        mutating func parsePrimary() throws -> Double {
            guard let t = next() else { throw CalcError.syntax }
            switch t {
            case .number(let v): return v
            case .lparen:
                let v = try parseExpression()
                guard case .rparen? = next() else { throw CalcError.syntax }
                return v
            case .ident(let name):
                if name == "ans" { guard let ans else { throw CalcError.unknown(name) }; return ans }
                if let c = CalcEngine.constants[name] { return c }
                if let f = CalcEngine.functions[name] {
                    guard case .lparen? = next() else { throw CalcError.syntax }
                    var args: [Double] = []
                    if case .rparen? = peek() { pos += 1 } else {
                        while true {
                            args.append(try parseExpression())
                            guard let n = next() else { throw CalcError.syntax }
                            if case .rparen = n { break }
                            guard case .comma = n else { throw CalcError.syntax }
                        }
                    }
                    return try f(args)
                }
                throw CalcError.unknown(name)
            default:
                throw CalcError.syntax
            }
        }
    }
}

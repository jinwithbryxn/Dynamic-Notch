import Foundation

/// 아주 작은 터미널 화면 모델 (xterm의 자주 쓰는 부분만): 글자, 커서 이동, 지우기, 스크롤 영역,
/// SGR 색(16·256·트루컬러), 대체 화면(vim·less), 넓은 글자(한글), 커서 키 모드, 붙여넣기 모드.
final class TerminalScreen {
    struct Cell: Equatable {
        var ch: String = " "
        var fg: Int32 = -1          // -1 기본, 0–255 팔레트, 0x1000000|rgb 트루컬러
        var bg: Int32 = -1
        var bold = false
        var underline = false
        var inverse = false
        /// 넓은 글자의 오른쪽 반 칸
        var continuation = false
    }

    private(set) var cols: Int
    private(set) var rows: Int
    private(set) var lines: [[Cell]]
    private(set) var scrollback: [[Cell]] = []
    private var savedMain: (lines: [[Cell]], cx: Int, cy: Int)?
    private(set) var cx = 0
    private(set) var cy = 0
    private var pendingWrap = false
    private var pen = Cell()
    private var saved: (cx: Int, cy: Int, pen: Cell) = (0, 0, Cell())
    private var top = 0
    private var bottom: Int
    private(set) var cursorVisible = true
    private(set) var applicationCursor = false
    private(set) var bracketedPaste = false
    private(set) var title = ""
    var isAltScreen: Bool { savedMain != nil }
    static let maxScrollback = 1000

    /// 터미널이 프로그램에 돌려줄 응답 (커서 위치 질의 등)
    var respond: (([UInt8]) -> Void)?

    private enum State { case ground, escape, csi, osc, oscEscape, charset }
    private var state = State.ground
    private var params = ""
    private var oscText = ""
    private var utf8: [UInt8] = []

    init(cols: Int, rows: Int) {
        self.cols = max(2, cols)
        self.rows = max(2, rows)
        bottom = self.rows - 1
        lines = Array(repeating: Array(repeating: Cell(), count: self.cols), count: self.rows)
    }

    private func blankLine() -> [Cell] {
        var c = Cell()
        c.bg = pen.bg
        return Array(repeating: c, count: cols)
    }

    func resize(cols newCols: Int, rows newRows: Int) {
        let nc = max(2, newCols), nr = max(2, newRows)
        guard nc != cols || nr != rows else { return }
        var newLines = lines.map { row -> [Cell] in
            row.count >= nc ? Array(row.prefix(nc)) : row + Array(repeating: Cell(), count: nc - row.count)
        }
        if newLines.count > nr {
            // 위쪽을 스크롤백으로 (커서가 보이도록)
            let extra = min(newLines.count - nr, max(0, cy - nr + 1))
            scrollback += newLines.prefix(extra)
            newLines.removeFirst(extra)
            newLines = Array(newLines.prefix(nr))
            cy -= extra
        } else {
            newLines += Array(repeating: Array(repeating: Cell(), count: nc), count: nr - newLines.count)
        }
        cols = nc
        rows = nr
        lines = newLines
        top = 0
        bottom = rows - 1
        cx = min(cx, cols - 1)
        cy = min(max(0, cy), rows - 1)
        pendingWrap = false
        trimScrollback()
    }

    // MARK: 입력 바이트

    func feed(_ bytes: [UInt8]) {
        for b in bytes { step(b) }
    }

    private func step(_ b: UInt8) {
        switch state {
        case .ground:
            if !utf8.isEmpty || b >= 0x80 {
                utf8.append(b)
                decodeUTF8()
                return
            }
            switch b {
            case 0x1B: state = .escape
            case 0x07: break
            case 0x08: if cx > 0 { cx -= 1 }; pendingWrap = false
            case 0x09: cx = min(cols - 1, (cx / 8 + 1) * 8); pendingWrap = false
            case 0x0A, 0x0B, 0x0C: lineFeed()
            case 0x0D: cx = 0; pendingWrap = false
            case 0x00...0x1F, 0x7F: break
            default: put(String(UnicodeScalar(b)))
            }
        case .escape:
            state = .ground
            switch b {
            case UInt8(ascii: "["): state = .csi; params = ""
            case UInt8(ascii: "]"): state = .osc; oscText = ""
            case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "*"), UInt8(ascii: "+"): state = .charset
            case UInt8(ascii: "7"): saved = (cx, cy, pen)
            case UInt8(ascii: "8"): (cx, cy, pen) = saved; pendingWrap = false
            case UInt8(ascii: "D"): lineFeed()
            case UInt8(ascii: "E"): cx = 0; lineFeed()
            case UInt8(ascii: "M"): reverseIndex()
            case UInt8(ascii: "c"): reset()
            default: break
            }
        case .charset:
            state = .ground
        case .csi:
            if (0x30...0x3F).contains(b) || (0x20...0x2F).contains(b) {
                if params.count < 64 { params.append(Character(UnicodeScalar(b))) }
            } else if (0x40...0x7E).contains(b) {
                state = .ground
                csi(Character(UnicodeScalar(b)))
            } else if b == 0x1B {
                state = .escape
            } else if b < 0x20 {
                // CSI 안의 제어 문자는 바로 실행
                let s = state
                state = .ground
                step(b)
                state = s
            } else {
                state = .ground
            }
        case .osc:
            if b == 0x07 { finishOSC() }
            else if b == 0x1B { state = .oscEscape }
            else if oscText.utf8.count < 512 { oscText.unicodeScalars.append(UnicodeScalar(b)) }
        case .oscEscape:
            finishOSC()
            if b != UInt8(ascii: "\\") { step(b) }
        }
    }

    private func finishOSC() {
        state = .ground
        // 0·2: 창 제목
        if oscText.hasPrefix("0;") || oscText.hasPrefix("2;") { title = String(oscText.dropFirst(2).prefix(120)) }
    }

    private func decodeUTF8() {
        guard let first = utf8.first else { return }
        let need: Int
        switch first {
        case 0xC0...0xDF: need = 2
        case 0xE0...0xEF: need = 3
        case 0xF0...0xF7: need = 4
        default: utf8.removeAll(); put("\u{FFFD}"); return
        }
        if utf8.count < need { return }
        let s = String(decoding: utf8.prefix(need), as: UTF8.self)
        utf8.removeAll()
        put(s)
    }

    // MARK: 글자 쓰기

    static func isWide(_ s: String) -> Bool {
        guard let v = s.unicodeScalars.first?.value else { return false }
        return (0x1100...0x115F).contains(v) || (0x2E80...0xA4CF).contains(v) || (0xAC00...0xD7A3).contains(v)
            || (0xF900...0xFAFF).contains(v) || (0xFE30...0xFE4F).contains(v) || (0xFF00...0xFF60).contains(v)
            || (0xFFE0...0xFFE6).contains(v) || (0x1F300...0x1F64F).contains(v) || (0x1F900...0x1FAFF).contains(v)
            || (0x20000...0x3FFFD).contains(v)
    }

    private func put(_ s: String) {
        // 결합 문자(악센트 등)는 앞 칸에 붙인다
        if let v = s.unicodeScalars.first?.value, (0x0300...0x036F).contains(v) || (0x200D == v) || (0xFE00...0xFE0F).contains(v) {
            let x = max(0, cx - (pendingWrap ? 0 : 1))
            if x < cols { lines[cy][x].ch += s }
            return
        }
        let wide = Self.isWide(s)
        if pendingWrap || (wide && cx == cols - 1) {
            cx = 0
            lineFeed()
            pendingWrap = false
        }
        var c = pen
        c.ch = s
        c.continuation = false
        lines[cy][cx] = c
        if wide, cx + 1 < cols {
            var cont = pen
            cont.ch = ""
            cont.continuation = true
            lines[cy][cx + 1] = cont
            cx += 1
        }
        if cx == cols - 1 { pendingWrap = true } else { cx += 1 }
    }

    private func lineFeed() {
        pendingWrap = false
        if cy == bottom { scrollUp(1) } else if cy < rows - 1 { cy += 1 }
    }

    private func reverseIndex() {
        if cy == top { scrollDown(1) } else if cy > 0 { cy -= 1 }
    }

    private func scrollUp(_ n: Int) {
        for _ in 0..<max(1, n) {
            let gone = lines.remove(at: top)
            if top == 0 && !isAltScreen { scrollback.append(gone) }
            lines.insert(blankLine(), at: bottom)
        }
        trimScrollback()
    }

    private func scrollDown(_ n: Int) {
        for _ in 0..<max(1, n) {
            lines.remove(at: bottom)
            lines.insert(blankLine(), at: top)
        }
    }

    private func trimScrollback() {
        if scrollback.count > Self.maxScrollback { scrollback.removeFirst(scrollback.count - Self.maxScrollback) }
    }

    private func reset() {
        pen = Cell()
        lines = Array(repeating: blankLine(), count: rows)
        cx = 0; cy = 0; top = 0; bottom = rows - 1
        cursorVisible = true; applicationCursor = false; bracketedPaste = false
        savedMain = nil
    }

    // MARK: CSI

    private func csi(_ final: Character) {
        let priv = params.hasPrefix("?")
        let body = params.trimmingCharacters(in: CharacterSet(charactersIn: "?>=! "))
        let nums = body.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        func p(_ i: Int, _ def: Int = 1) -> Int { i < nums.count && nums[i] != 0 ? nums[i] : def }
        pendingWrap = false
        switch final {
        case "A": cy = max(cy >= top ? top : 0, cy - p(0))
        case "B", "e": cy = min(cy <= bottom ? bottom : rows - 1, cy + p(0))
        case "C", "a": cx = min(cols - 1, cx + p(0))
        case "D": cx = max(0, cx - p(0))
        case "E": cx = 0; cy = min(rows - 1, cy + p(0))
        case "F": cx = 0; cy = max(0, cy - p(0))
        case "G", "`": cx = min(cols - 1, max(0, p(0) - 1))
        case "d": cy = min(rows - 1, max(0, p(0) - 1))
        case "H", "f": cy = min(rows - 1, max(0, p(0) - 1)); cx = min(cols - 1, max(0, p(1) - 1))
        case "J": eraseDisplay(nums.first ?? 0)
        case "K": eraseLine(nums.first ?? 0)
        case "L": if (top...bottom).contains(cy) { for _ in 0..<p(0) { lines.remove(at: bottom); lines.insert(blankLine(), at: cy) } }
        case "M": if (top...bottom).contains(cy) { for _ in 0..<p(0) { lines.remove(at: cy); lines.insert(blankLine(), at: bottom) } }
        case "P":
            let n = min(p(0), cols - cx)
            lines[cy].removeSubrange(cx..<(cx + n))
            lines[cy] += Array(repeating: Cell(), count: n)
        case "@":
            let n = min(p(0), cols - cx)
            lines[cy].insert(contentsOf: Array(repeating: Cell(), count: n), at: cx)
            lines[cy] = Array(lines[cy].prefix(cols))
        case "X":
            for x in cx..<min(cols, cx + p(0)) { lines[cy][x] = Cell() }
        case "S": scrollUp(p(0))
        case "T": scrollDown(p(0))
        case "m": sgr(body.isEmpty ? [0] : nums)
        case "r":
            let t = max(0, p(0) - 1), b = min(rows - 1, p(1, rows) - 1)
            if t < b { top = t; bottom = b } else { top = 0; bottom = rows - 1 }
            cx = 0; cy = 0
        case "s": saved = (cx, cy, pen)
        case "u": (cx, cy, pen) = saved
        case "h", "l": mode(priv: priv, nums: nums, on: final == "h")
        case "n":
            if nums.first == 6 { respond?(Array("\u{1B}[\(cy + 1);\(cx + 1)R".utf8)) }
            else if nums.first == 5 { respond?(Array("\u{1B}[0n".utf8)) }
        case "c":
            if !params.hasPrefix(">") { respond?(Array("\u{1B}[?1;2c".utf8)) }
        default: break
        }
    }

    private func mode(priv: Bool, nums: [Int], on: Bool) {
        guard priv else { return }
        for n in nums {
            switch n {
            case 1: applicationCursor = on
            case 25: cursorVisible = on
            case 2004: bracketedPaste = on
            case 47, 1047, 1049:
                if on, savedMain == nil {
                    savedMain = (lines, cx, cy)
                    lines = Array(repeating: blankLine(), count: rows)
                    if n == 1049 { cx = 0; cy = 0 }
                } else if !on, let s = savedMain {
                    lines = s.lines.count == rows ? s.lines : Array(repeating: blankLine(), count: rows)
                    cx = min(s.cx, cols - 1); cy = min(s.cy, rows - 1)
                    savedMain = nil
                }
                top = 0; bottom = rows - 1
            default: break
            }
        }
    }

    private func eraseDisplay(_ mode: Int) {
        switch mode {
        case 0:
            eraseLine(0)
            for y in (cy + 1)..<rows { lines[y] = blankLine() }
        case 1:
            eraseLine(1)
            for y in 0..<cy { lines[y] = blankLine() }
        case 2: lines = Array(repeating: blankLine(), count: rows)
        case 3: scrollback.removeAll(); lines = Array(repeating: blankLine(), count: rows)
        default: break
        }
    }

    private func eraseLine(_ mode: Int) {
        var blank = Cell()
        blank.bg = pen.bg
        switch mode {
        case 0: for x in cx..<cols { lines[cy][x] = blank }
        case 1: for x in 0...min(cx, cols - 1) { lines[cy][x] = blank }
        default: lines[cy] = blankLine()
        }
    }

    private func sgr(_ n: [Int]) {
        var i = 0
        while i < n.count {
            let v = n[i]
            switch v {
            case 0: pen = Cell()
            case 1: pen.bold = true
            case 4: pen.underline = true
            case 7: pen.inverse = true
            case 22: pen.bold = false
            case 24: pen.underline = false
            case 27: pen.inverse = false
            case 30...37: pen.fg = Int32(v - 30)
            case 39: pen.fg = -1
            case 40...47: pen.bg = Int32(v - 40)
            case 49: pen.bg = -1
            case 90...97: pen.fg = Int32(v - 90 + 8)
            case 100...107: pen.bg = Int32(v - 100 + 8)
            case 38, 48:
                var color: Int32?
                if i + 2 < n.count, n[i + 1] == 5 { color = Int32(min(255, max(0, n[i + 2]))); i += 2 }
                else if i + 4 < n.count, n[i + 1] == 2 {
                    color = 0x1000000 | Int32((n[i + 2] & 255) << 16 | (n[i + 3] & 255) << 8 | (n[i + 4] & 255)); i += 4
                }
                if let color { if v == 38 { pen.fg = color } else { pen.bg = color } }
            default: break
            }
            i += 1
        }
    }

    // MARK: 읽기 (화면·검사용)

    func text(row: Int) -> String {
        guard row >= 0, row < rows else { return "" }
        return lines[row].filter { !$0.continuation }.map(\.ch).joined().replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    }

    var allText: String { (0..<rows).map { text(row: $0) }.joined(separator: "\n") }
}

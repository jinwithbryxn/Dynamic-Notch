import AppKit
import SwiftUI

/// 터미널 색 (xterm 16색 + 256색 + 트루컬러)
enum TerminalPalette {
    static let base: [NSColor] = [
        (0, 0, 0), (205, 49, 49), (13, 188, 121), (229, 229, 16), (36, 114, 200), (188, 63, 188), (17, 168, 205), (229, 229, 229),
        (102, 102, 102), (241, 76, 76), (35, 209, 139), (245, 245, 67), (59, 142, 234), (214, 112, 214), (41, 184, 219), (255, 255, 255),
    ].map { NSColor(srgbRed: CGFloat($0.0) / 255, green: CGFloat($0.1) / 255, blue: CGFloat($0.2) / 255, alpha: 1) }
    static let foreground = NSColor(white: 0.9, alpha: 1)
    static let background = NSColor(white: 0.07, alpha: 1)

    static func color(_ v: Int32) -> NSColor? {
        if v < 0 { return nil }
        if v & 0x1000000 != 0 {
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
        }
        if v < 16 { return base[Int(v)] }
        if v < 232 {
            let i = Int(v) - 16
            let levels: [CGFloat] = [0, 95, 135, 175, 215, 255]
            return NSColor(srgbRed: levels[i / 36] / 255, green: levels[(i / 6) % 6] / 255, blue: levels[i % 6] / 255, alpha: 1)
        }
        let g = CGFloat(8 + (Int(v) - 232) * 10) / 255
        return NSColor(srgbRed: g, green: g, blue: g, alpha: 1)
    }
}

/// 키 → 터미널 바이트 (검사할 수 있게 순수 함수로 뺌)
enum TerminalKeys {
    /// 한국어 자판에서도 ctrl+C가 되도록 ANSI 키 위치로 글자를 찾는다
    static let letterByKeyCode: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 42: "\\", 30: "]", 45: "n", 46: "m",
    ]

    static func controlByte(keyCode: UInt16, chars: String?) -> UInt8? {
        var c = chars?.lowercased().first
        if c == nil || !(c!.isASCII) { c = letterByKeyCode[keyCode] }
        guard let ch = c, let a = ch.asciiValue else { return nil }
        switch ch {
        case "a"..."z": return a - 96
        case "@", " ", "2": return 0
        case "[": return 27
        case "\\": return 28
        case "]": return 29
        case "^", "6": return 30
        case "_", "-": return 31
        case "?": return 127
        default: return nil
        }
    }

    static func special(keyCode: UInt16, flags: NSEvent.ModifierFlags, appCursor: Bool) -> [UInt8]? {
        let esc: UInt8 = 27
        let opt = flags.contains(.option), shift = flags.contains(.shift)
        func csi(_ s: String) -> [UInt8] { [esc] + Array(("[" + s).utf8) }
        func arrow(_ c: String) -> [UInt8] { [esc] + Array(((appCursor ? "O" : "[") + c).utf8) }
        switch keyCode {
        case 36, 76: return [13]
        case 48: return shift ? csi("Z") : [9]
        case 51: return opt ? [esc, 127] : [127]
        case 117: return csi("3~")
        case 53: return [esc]
        case 126: return arrow("A")
        case 125: return arrow("B")
        case 124: return opt ? [esc, UInt8(ascii: "f")] : arrow("C")
        case 123: return opt ? [esc, UInt8(ascii: "b")] : arrow("D")
        case 115: return appCursor ? [esc] + Array("OH".utf8) : csi("H")
        case 119: return appCursor ? [esc] + Array("OF".utf8) : csi("F")
        case 116: return csi("5~")
        case 121: return csi("6~")
        case 122: return [esc] + Array("OP".utf8)
        case 120: return [esc] + Array("OQ".utf8)
        case 99: return [esc] + Array("OR".utf8)
        case 118: return [esc] + Array("OS".utf8)
        default: return nil
        }
    }

    static func bytes(keyCode: UInt16, flags: NSEvent.ModifierFlags, chars: String?, appCursor: Bool) -> [UInt8]? {
        let f = flags.intersection(.deviceIndependentFlagsMask)
        if f.contains(.control), !f.contains(.command), let b = controlByte(keyCode: keyCode, chars: chars) { return [b] }
        return special(keyCode: keyCode, flags: f, appCursor: appCursor)
    }
}

/// 셀을 직접 그리는 터미널 화면. 한글 입력기(조합 중 글자)를 위해 NSTextInputClient를 따른다.
final class TerminalNSView: NSView, NSTextInputClient {
    weak var controller: TerminalController?
    private(set) var font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private var boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    private(set) var cellW: CGFloat = 7
    private(set) var cellH: CGFloat = 15
    let pad: CGFloat = 6
    private var scrollOffset = 0
    private var scrollAccum: CGFloat = 0
    private var markedText = ""

    private struct Pos: Comparable {
        var line: Int, col: Int
        static func < (a: Pos, b: Pos) -> Bool { a.line != b.line ? a.line < b.line : a.col < b.col }
    }
    private var selAnchor: Pos?
    private var selEnd: Pos?

    init(controller: TerminalController, fontSize: CGFloat) {
        self.controller = controller
        super.init(frame: CGRect(x: 0, y: 0, width: 600, height: 260))
        setFont(size: fontSize)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setFont(size: CGFloat) {
        font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        boldFont = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        cellW = ("M" as NSString).size(withAttributes: [.font: font]).width
        cellH = ceil(font.ascender - font.descender + font.leading) + 1
        needsLayout = true
        needsDisplay = true
    }

    var gridSize: (cols: Int, rows: Int) {
        (max(10, Int((bounds.width - 2 * pad) / cellW)), max(3, Int((bounds.height - 2 * pad) / cellH)))
    }

    override func layout() {
        super.layout()
        guard bounds.width > 40, bounds.height > 30, let c = controller else { return }
        let g = gridSize
        if let s = c.session { s.resize(cols: g.cols, rows: g.rows) } else { c.ensureStarted(cols: g.cols, rows: g.rows) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        needsLayout = true
        DispatchQueue.main.async { [weak self] in self?.focus() }
    }

    func focus() {
        guard let w = window else { return }
        controller?.requestFocus()
        w.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    // MARK: 그리기

    private func line(_ screen: TerminalScreen, abs: Int) -> [TerminalScreen.Cell] {
        let sb = screen.scrollback.count
        if abs < sb { return abs >= 0 ? screen.scrollback[abs] : [] }
        let i = abs - sb
        return i < screen.lines.count ? screen.lines[i] : []
    }

    private var selection: (Pos, Pos)? {
        guard let a = selAnchor, let b = selEnd, a != b else { return nil }
        return a < b ? (a, b) : (b, a)
    }

    override func draw(_ dirtyRect: NSRect) {
        TerminalPalette.background.setFill()
        bounds.fill()
        guard let screen = controller?.session?.screen else { return }
        let sb = screen.scrollback.count
        let offset = min(scrollOffset, sb)
        let sel = selection
        for row in 0..<screen.rows {
            let abs = sb - offset + row
            drawLine(line(screen, abs: abs), row: row, abs: abs, cols: screen.cols, sel: sel)
        }
        // 커서
        if offset == 0, screen.cursorVisible {
            let cx = min(screen.cx, screen.cols - 1), cy = min(screen.cy, screen.rows - 1)
            let origin = CGPoint(x: pad + CGFloat(cx) * cellW, y: pad + CGFloat(cy) * cellH)
            if !markedText.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white, .backgroundColor: NSColor(white: 0.25, alpha: 1), .underlineStyle: NSUnderlineStyle.single.rawValue]
                (markedText as NSString).draw(at: origin, withAttributes: attrs)
            } else {
                let row = screen.lines[cy]
                let wide = cx + 1 < row.count && row[cx + 1].continuation
                let r = CGRect(x: origin.x, y: origin.y, width: cellW * (wide ? 2 : 1), height: cellH)
                if window?.firstResponder === self {
                    NSColor(white: 0.85, alpha: 0.9).setFill()
                    r.fill()
                    let ch = row[cx].ch
                    if ch != " " { (ch as NSString).draw(at: origin, withAttributes: [.font: row[cx].bold ? boldFont : font, .foregroundColor: NSColor.black]) }
                } else {
                    NSColor(white: 0.7, alpha: 0.8).setStroke()
                    NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
                }
            }
        }
        // 스크롤백을 보는 중 표시
        if offset > 0 {
            let s = T("↑ \(offset)줄 위 · 아무 키나 누르면 맨 아래로", "↑ \(offset) lines up · any key returns") as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.black]
            let size = s.size(withAttributes: attrs)
            let r = CGRect(x: bounds.width - size.width - 14, y: 4, width: size.width + 10, height: size.height + 4)
            NSColor(white: 0.85, alpha: 0.9).setFill()
            NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
            s.draw(at: CGPoint(x: r.minX + 5, y: r.minY + 2), withAttributes: attrs)
        }
    }

    private func drawLine(_ cells: [TerminalScreen.Cell], row: Int, abs: Int, cols: Int, sel: (Pos, Pos)?) {
        let y = pad + CGFloat(row) * cellH
        let n = min(cells.count, cols)
        // 배경 먼저
        var col = 0
        while col < n {
            let c = cells[col]
            var bg = c.inverse ? (TerminalPalette.color(c.fg) ?? TerminalPalette.foreground) : TerminalPalette.color(c.bg)
            if let s = sel, Pos(line: abs, col: col) >= s.0, Pos(line: abs, col: col) < s.1 { bg = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.6) }
            if let bg {
                bg.setFill()
                CGRect(x: pad + CGFloat(col) * cellW, y: y, width: cellW + 0.5, height: cellH).fill()
            }
            col += 1
        }
        // 글자: ASCII는 같은 모양끼리 묶어 한 번에, 그 밖의 글자는 칸마다
        col = 0
        while col < n {
            let c = cells[col]
            if c.continuation || c.ch == " " { col += 1; continue }
            let fg = c.inverse ? (TerminalPalette.color(c.bg) ?? TerminalPalette.background) : (TerminalPalette.color(c.fg).map { c.bold && c.fg < 8 && c.fg >= 0 ? TerminalPalette.base[Int(c.fg) + 8] : $0 } ?? TerminalPalette.foreground)
            var attrs: [NSAttributedString.Key: Any] = [.font: c.bold ? boldFont : font, .foregroundColor: fg]
            if c.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            let isASCII = c.ch.utf8.count == 1
            var text = c.ch
            var end = col + 1
            if isASCII {
                while end < n {
                    let d = cells[end]
                    guard d.ch.utf8.count == 1, !d.continuation, d.fg == c.fg, d.bg == c.bg, d.bold == c.bold, d.underline == c.underline, d.inverse == c.inverse else { break }
                    text += d.ch
                    end += 1
                }
            }
            let x = pad + CGFloat(col) * cellW
            if isASCII {
                (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            } else {
                // 넓은 글자는 두 칸 가운데에
                let w = (end < n && cells[end].continuation) ? 2 * cellW : cellW
                let size = (text as NSString).size(withAttributes: attrs)
                (text as NSString).draw(at: CGPoint(x: x + max(0, (w - size.width) / 2), y: y + (cellH - size.height) / 2), withAttributes: attrs)
            }
            col = end
        }
    }

    // MARK: 키 입력

    override func keyDown(with event: NSEvent) {
        guard let c = controller else { return }
        guard let s = c.session, s.running else {
            if event.keyCode == 36 { c.restart() }
            return
        }
        scrollOffset = 0
        clearSelection()
        if hasMarkedText() { interpretKeyEvents([event]); return }
        if let b = TerminalKeys.bytes(keyCode: event.keyCode, flags: event.modifierFlags, chars: event.charactersIgnoringModifiers, appCursor: s.screen.applicationCursor) {
            s.write(b)
            return
        }
        interpretKeyEvents([event])
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard f == .command else { return super.performKeyEquivalent(with: event) }
        switch event.keyCode {
        case 9: paste(nil); return true
        case 8: copy(nil); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        scrollOffset = 0
        controller?.session?.paste(text)
    }

    @objc func copy(_ sender: Any?) {
        guard let text = selectedText(), !text.isEmpty else { return }
        AIDevPasteboard.copy(text)
    }

    private func write(_ text: String) {
        guard !text.isEmpty else { return }
        controller?.session?.write(text)
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        markedText = ""
        write(text)
        needsDisplay = true
    }

    override func doCommand(by selector: Selector) {
        guard let s = controller?.session else { return }
        let app = s.screen.applicationCursor
        let map: [Selector: UInt16] = [
            #selector(insertNewline(_:)): 36, #selector(insertTab(_:)): 48, #selector(deleteBackward(_:)): 51,
            #selector(deleteForward(_:)): 117, #selector(cancelOperation(_:)): 53, #selector(moveUp(_:)): 126,
            #selector(moveDown(_:)): 125, #selector(moveLeft(_:)): 123, #selector(moveRight(_:)): 124,
        ]
        if selector == #selector(insertBacktab(_:)) { s.write([27] + Array("[Z".utf8)); return }
        if let code = map[selector], let b = TerminalKeys.special(keyCode: code, flags: [], appCursor: app) { s.write(b) }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markedText = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        needsDisplay = true
    }
    func unmarkText() { markedText = ""; needsDisplay = true }
    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
    func markedRange() -> NSRange { markedText.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: markedText.utf16.count) }
    func hasMarkedText() -> Bool { !markedText.isEmpty }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func characterIndex(for point: NSPoint) -> Int { 0 }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let screen = controller?.session?.screen, let w = window else { return .zero }
        let r = CGRect(x: pad + CGFloat(screen.cx) * cellW, y: pad + CGFloat(screen.cy) * cellH, width: cellW, height: cellH)
        return w.convertToScreen(convert(r, to: nil))
    }

    // MARK: 마우스 (선택·스크롤)

    private func pos(_ event: NSEvent) -> Pos? {
        guard let screen = controller?.session?.screen else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        let row = min(max(0, Int((p.y - pad) / cellH)), screen.rows - 1)
        let col = min(max(0, Int(((p.x - pad) / cellW).rounded())), screen.cols)
        return Pos(line: screen.scrollback.count - min(scrollOffset, screen.scrollback.count) + row, col: col)
    }

    override func mouseDown(with event: NSEvent) {
        focus()
        selAnchor = pos(event)
        selEnd = selAnchor
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) { selEnd = pos(event); needsDisplay = true }

    private func clearSelection() {
        guard selAnchor != nil else { return }
        selAnchor = nil
        selEnd = nil
        needsDisplay = true
    }

    func selectedText() -> String? {
        guard let (a, b) = selection, let screen = controller?.session?.screen else { return nil }
        var out: [String] = []
        for l in a.line...b.line {
            let cells = line(screen, abs: l)
            let from = l == a.line ? a.col : 0
            let to = l == b.line ? min(b.col, cells.count) : cells.count
            guard from < to else { out.append(""); continue }
            let s = cells[from..<to].filter { !$0.continuation }.map(\.ch).joined()
            out.append(s.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression))
        }
        return out.joined(separator: "\n")
    }

    override func scrollWheel(with event: NSEvent) {
        guard let s = controller?.session else { return }
        scrollAccum += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / cellH : event.scrollingDeltaY
        let lines = Int(scrollAccum)
        guard lines != 0 else { return }
        scrollAccum -= CGFloat(lines)
        if s.screen.isAltScreen {
            // 전체 화면 프로그램(less, vim)에는 화살표로 보낸다
            let key: UInt16 = lines > 0 ? 126 : 125
            if let b = TerminalKeys.special(keyCode: key, flags: [], appCursor: s.screen.applicationCursor) {
                for _ in 0..<min(abs(lines), 5) { s.write(b) }
            }
        } else {
            scrollOffset = min(max(0, scrollOffset + lines), s.screen.scrollback.count)
            needsDisplay = true
        }
    }
}

/// SwiftUI에 끼우는 껍데기. 같은 NSView를 탭을 오가도 다시 쓴다 (셸이 계속 돈다).
struct TerminalHost: NSViewRepresentable {
    let controller: TerminalController
    func makeNSView(context: Context) -> TerminalNSView { controller.view }
    func updateNSView(_ nsView: TerminalNSView, context: Context) {}
}

import AppKit
import Foundation

/// 터미널 자체 검사: 해석기 단위 검사 + 실제 PTY 위 /bin/zsh -f (사용자 설정 파일 안 읽음)
enum TerminalSelfTest {
    static func run() -> [String] {
        var out: [String] = []
        func check(_ ok: Bool, _ what: String) { out.append("\(ok ? "PASS" : "FAIL") \(what)") }

        // 1) 해석기
        func screen(_ s: String, cols: Int = 20, rows: Int = 5) -> TerminalScreen {
            let t = TerminalScreen(cols: cols, rows: rows)
            t.feed(Array(s.utf8))
            return t
        }
        var t = screen("hello\r\nworld")
        check(t.text(row: 0).hasPrefix("hello") && t.text(row: 1).hasPrefix("world"), "CR LF moves to the next line")
        t = screen("\u{1B}[1;31mR\u{1B}[0mn")
        check(t.lines[0][0].bold && t.lines[0][0].fg == 1 && !t.lines[0][1].bold && t.lines[0][1].fg == -1, "SGR bold red then reset")
        t = screen("\u{1B}[38;5;200mX\u{1B}[48;2;1;2;3mY")
        check(t.lines[0][0].fg == 200 && t.lines[0][1].bg == (0x1000000 | 0x010203), "256 colour and true colour")
        t = screen("\u{1B}[2J\u{1B}[3;5HZ")
        check(t.lines[2][4].ch == "Z", "cursor position CSI 3;5H")
        t = screen("abcdef\r\u{1B}[2CX\u{1B}[K")
        check(t.text(row: 0).trimmingCharacters(in: .whitespaces) == "abX", "cursor forward + erase to end of line")
        t = screen("한글a")
        check(t.lines[0][0].ch == "한" && t.lines[0][1].continuation && t.lines[0][2].ch == "글" && t.lines[0][4].ch == "a", "wide Hangul takes two cells")
        t = screen((1...30).map { "line\($0)" }.joined(separator: "\r\n"), rows: 10)
        check(t.scrollback.count == 20 && t.text(row: 9).hasPrefix("line30"), "scrolling keeps 20 lines of scrollback")
        t = screen("main\u{1B}[?1049h\u{1B}[2Jalt")
        let inAlt = t.isAltScreen && t.text(row: 0).hasPrefix("alt")
        t.feed(Array("\u{1B}[?1049l".utf8))
        check(inAlt && !t.isAltScreen && t.text(row: 0).hasPrefix("main"), "alternate screen enter and restore")
        var reply: [UInt8] = []
        t = TerminalScreen(cols: 20, rows: 5)
        t.respond = { reply += $0 }
        t.feed(Array("ab\u{1B}[6n".utf8))
        check(String(decoding: reply, as: UTF8.self) == "\u{1B}[1;3R", "cursor position report \(String(decoding: reply, as: UTF8.self).debugDescription)")
        t = screen("\u{1B}[?2004h\u{1B}[?1h\u{1B}]0;my title\u{07}")
        check(t.bracketedPaste && t.applicationCursor && t.title == "my title", "bracketed paste, application cursor, OSC title")
        t = screen("a\r\nb\r\nc\r\nd\r\nlast", rows: 5)
        t.resize(cols: 10, rows: 3)
        check(t.text(row: 2).hasPrefix("last") && t.cols == 10, "resize keeps the cursor line")

        // 2) 키 변환
        let k = TerminalKeys.self
        check(k.bytes(keyCode: 8, flags: .control, chars: "ㅊ", appCursor: false) == [3], "ctrl+C with a Korean layout sends 0x03")
        check(k.bytes(keyCode: 126, flags: [], chars: nil, appCursor: false) == [27, 91, 65] && k.bytes(keyCode: 126, flags: [], chars: nil, appCursor: true) == [27, 79, 65], "up arrow normal and application mode")
        check(k.bytes(keyCode: 36, flags: [], chars: "\r", appCursor: false) == [13] && k.bytes(keyCode: 51, flags: [], chars: nil, appCursor: false) == [127], "return and delete")
        check(k.bytes(keyCode: 0, flags: [], chars: "a", appCursor: false) == nil, "plain letters go to the input method")

        // 3) 실제 PTY
        let dir = AIDevTest.dir("terminal")
        let s = TerminalSession(cols: 80, rows: 24)
        var exitCode: Int32?
        s.onExit = { exitCode = $0 }
        do {
            try s.start(shell: "/bin/zsh", args: ["-f"], cwd: dir.path, extraEnv: ["PS1": "dmn%# "])
        } catch {
            return out + ["FAIL start: \(error.localizedDescription)"]
        }
        let t0 = Date()
        func waitFor(_ text: String, _ timeout: TimeInterval = 4) -> Bool { AIDevTest.wait(timeout) { (s.screen.scrollback.map { $0.map(\.ch).joined() } + [s.screen.allText]).joined(separator: "\n").contains(text) } }
        check(AIDevTest.wait(4) { !s.screen.allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "zsh -f printed a prompt in \(Int(Date().timeIntervalSince(t0) * 1000)) ms (pid \(s.pid))")
        s.write("echo dmn-$((6*7))\r")
        check(waitFor("dmn-42"), "command runs and output is drawn")
        s.write("tty; stty size; echo $TERM\r")
        check(waitFor("/dev/ttys") && waitFor("24 80") && waitFor("xterm-256color"), "real tty, 24x80, TERM=xterm-256color")
        s.resize(cols: 100, rows: 30)
        s.write("stty size\r")
        check(waitFor("30 100") && s.ptySize.map { $0 == (100, 30) } == true, "resize reaches the PTY (TIOCSWINSZ)")
        s.write("echo 한글테스트\r")
        check(waitFor("한글테스트"), "UTF-8 Hangul round trip")
        s.write("printf '\\033[32mGREEN\\033[0m\\n'\r")
        check(AIDevTest.wait(3) { s.screen.lines.contains { row in row.contains { $0.ch == "G" && $0.fg == 2 } } }, "program colours reach the cells")
        func outputLine(_ text: String) -> Bool { (0..<s.screen.rows).contains { s.screen.text(row: $0).trimmingCharacters(in: .whitespaces) == text } }
        s.write("ps -o tt= -p $$ | sed 's/^/CTTY=/'\r")
        var ctty = ""
        _ = AIDevTest.wait(3) {
            if let r = s.screen.allText.range(of: #"(?m)^CTTY=\S+"#, options: .regularExpression) { ctty = String(s.screen.allText[r].dropFirst(5)) }
            return !ctty.isEmpty
        }
        check(!ctty.isEmpty && ctty != "??", "the PTY is the shell's controlling terminal (\(ctty))")
        s.write("sleep 30\r")
        AIDevTest.wait(0.5) { false }
        s.write([3])
        AIDevTest.wait(0.3) { false }
        s.write("echo after-int\r")
        check(AIDevTest.wait(3) { outputLine("after-int") }, "ctrl+C interrupts a running command (output line, not just echoed input)")
        s.write("exit 7\r")
        check(AIDevTest.wait(3) { exitCode != nil } && exitCode == 7 && !s.running, "exit is detected with code \(exitCode.map(String.init) ?? "-")")

        // 4) 끝내기: 셸과 백그라운드 작업이 모두 끝나고 좀비가 안 남는지
        let s2 = TerminalSession(cols: 80, rows: 24)
        try? s2.start(shell: "/bin/zsh", args: ["-f"], cwd: dir.path)
        _ = AIDevTest.wait(3) { !s2.screen.allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        s2.write("sleep 300 & echo BG=$!\r")
        var bg: pid_t = 0
        _ = AIDevTest.wait(3) {
            if let r = s2.screen.allText.range(of: #"BG=(\d+)"#, options: .regularExpression) { bg = pid_t(s2.screen.allText[r].dropFirst(3)) ?? 0 }
            return bg > 0
        }
        let shellPid = s2.pid
        s2.terminate()
        let gone = AIDevTest.wait(4) { kill(shellPid, 0) != 0 && (bg == 0 || kill(bg, 0) != 0) }
        check(gone && bg > 0, "stop ends the shell (pid \(shellPid)) and its background job (pid \(bg)), both reaped")

        // 5) 모듈: 켜고 끄면 셸이 정리되는지
        let m = TerminalModule()
        m.start(context: ModuleContext(center: ActivityCenter(), openTab: { _ in }, collapse: {}, focusInput: {}))
        m.controller.command = ("/bin/zsh", ["-f"])
        m.controller.cwd = dir.path
        m.controller.ensureStarted(cols: 80, rows: 20)
        let mpid = m.controller.session?.pid ?? 0
        let started = m.controller.status == .running && mpid > 0
        m.stop()
        m.controller.ensureStarted(cols: 80, rows: 20)
        check(started && AIDevTest.wait(4) { kill(mpid, 0) != 0 } && m.controller.session == nil, "module stop() ends its shell (pid \(mpid)) and a hidden tab can't relaunch it while off")
        return out
    }
}

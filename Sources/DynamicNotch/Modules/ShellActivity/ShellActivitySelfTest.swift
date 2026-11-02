import Foundation

/// 셸 명령 활동 자체 검사: ~/.zshrc는 읽기만 해서 사본에 설치·제거하고,
/// 실제 zsh(ZDOTDIR=검사 폴더, 사용자 설정 안 읽음)로 블록을 돌려 임시 포트 서버까지 보낸다.
enum ShellActivitySelfTest {
    static func run() -> [String] {
        var out: [String] = []
        let dir = AIDevTest.dir("shell")
        let fm = FileManager.default

        // 1) 사본에 설치·제거
        let copy = dir.appendingPathComponent("zshrc-copy")
        let realData = try? Data(contentsOf: ShellHookInstaller.liveFile)
        if let realData { try? realData.write(to: copy); out.append("copied ~/.zshrc -> test/shell/zshrc-copy (\(realData.count) bytes, real file only read)") }
        else { try? Data("export FOO=1\n".utf8).write(to: copy); out.append("~/.zshrc missing, using a sample") }
        for (name, file) in [("zshrc copy", copy), ("no trailing newline", { () -> URL in
            let u = dir.appendingPathComponent("zshrc-nonl"); try? Data("alias ll='ls -l'".utf8).write(to: u); return u }()), ("missing file", dir.appendingPathComponent("zshrc-new"))] {
            let before = try? Data(contentsOf: file)
            let inst = ShellHookInstaller(file: file, endpointPath: dir.appendingPathComponent("hooks/endpoint").path)
            do {
                let backup = try inst.install()
                let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                let prefixKept = before.map { text.hasPrefix(String(decoding: $0, as: UTF8.self)) } ?? true
                let syntax = Process()
                syntax.executableURL = URL(fileURLWithPath: "/bin/zsh")
                syntax.arguments = ["-n", file.path]
                try? syntax.run(); syntax.waitUntilExit()
                out.append("\(inst.isInstalled && prefixKept && syntax.terminationStatus == 0 ? "PASS" : "FAIL") \(name): installed between markers, original kept, zsh -n ok, backup \(backup?.lastPathComponent ?? "none")")
                try inst.install()
                let count = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").components(separatedBy: ShellHookInstaller.begin).count - 1
                out.append("\(count == 1 ? "PASS" : "FAIL") \(name): installing twice keeps one block")
                try inst.uninstall()
                let after = try? Data(contentsOf: file)
                let same = before == nil ? (after == Data()) : (after == before)
                out.append("\(same ? "PASS" : "FAIL") \(name): uninstall restores original bytes")
            } catch { out.append("FAIL \(name): \(error.localizedDescription)") }
        }
        out.append("\((try? Data(contentsOf: ShellHookInstaller.liveFile)) == realData ? "PASS" : "FAIL") real ~/.zshrc untouched")

        // 2) 제외 규칙
        let ex = ShellActivityModule.defaultExcluded
        let cases: [(String, Bool)] = [("npm run dev", true), ("FOO=1 vim notes.md", true), ("sudo htop", true), ("npm test", false), ("make -j8", false), ("/usr/bin/ssh host", true)]
        let wrong = cases.filter { ShellActivityModule.isExcluded($0.0, list: ex) != $0.1 }
        out.append("\(wrong.isEmpty ? "PASS" : "FAIL") exclusions \(cases.map { "\($0.0)=\($0.1 ? "skip" : "show")" })")

        // 3) 실제 zsh로 블록 실행 → 임시 포트 서버
        var store: [String: String] = [:]
        let hooks = dir.appendingPathComponent("hooks")
        let server = LocalAPIServer(config: .init(loadToken: { store[$0] }, saveToken: { store[$0] = $1 }, endpointDir: hooks, port: { 0 }, fallbackToEphemeral: false))
        let center = ActivityCenter()
        let module = ShellActivityModule(server: server)
        module.threshold = 0.3
        module.start(context: ModuleContext(center: center, openTab: { _ in }, collapse: {}, focusInput: {}))
        guard AIDevTest.wait(3, until: { server.boundPort != nil }) else { return out + ["FAIL server did not start"] }
        let zdot = dir.appendingPathComponent("zdotdir")
        try? fm.createDirectory(at: zdot, withIntermediateDirectories: true)
        let rc = zdot.appendingPathComponent(".zshrc")
        _ = try? ShellHookInstaller(file: rc, endpointPath: hooks.appendingPathComponent("endpoint").path).install()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-i", "-c", #"_dmn_preexec 'make "x" \ test'; sleep 0.8; false; _dmn_precmd"#]
        var env = ProcessInfo.processInfo.environment
        env["ZDOTDIR"] = zdot.path
        env["TERM_PROGRAM"] = nil
        env["TERM_SESSION_ID"] = nil
        p.environment = env
        p.currentDirectoryURL = dir
        let errPipe = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = errPipe
        let t0 = Date()
        try? p.run()
        let gotStart = AIDevTest.wait(3) { module.running.values.contains { $0.command == #"make "x" \ test"# } }
        out.append("\(gotStart ? "PASS" : "FAIL") preexec sent start; command JSON-escaped round trip: \(module.running.values.first?.command ?? "-")")
        let live = AIDevTest.wait(3) { center.persistent[.shell] != nil }
        out.append("\(live ? "PASS" : "FAIL") live activity after threshold: \(center.persistent[.shell]?.title ?? "-") (\(center.persistent[.shell]?.subtitle ?? "-"))")
        AIDevTest.wait(5) { !p.isRunning }
        let ended = AIDevTest.wait(2) { module.running.isEmpty && center.transient?.subtitle?.contains("1") == true }
        out.append("\(ended ? "PASS" : "FAIL") precmd sent end -> \(center.transient?.title ?? "-") / \(center.transient?.subtitle ?? "-") after \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
        let stderr = String(decoding: errPipe.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        out.append("zsh stderr: \(stderr.isEmpty ? "(none)" : String(stderr.prefix(200)))")

        // 4) 앱이 꺼져 있으면 셸에 영향 없음: 서버를 닫고 같은 블록을 돌려 출력·지연이 없는지
        module.stop()
        AIDevTest.wait(1) { server.boundPort == nil }
        let q = Process()
        q.executableURL = URL(fileURLWithPath: "/bin/zsh")
        q.arguments = ["-i", "-c", "_dmn_preexec 'ls'; _dmn_precmd; echo done"]
        q.environment = env
        let qOut = Pipe(), qErr = Pipe()
        q.standardOutput = qOut
        q.standardError = qErr
        let t1 = Date()
        try? q.run(); q.waitUntilExit()
        let o = String(decoding: qOut.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let e = String(decoding: qErr.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        out.append("\(o == "done" && e.isEmpty ? "PASS" : "FAIL") app off: shell output '\(o)', stderr '\(e.prefix(80))', \(Int(Date().timeIntervalSince(t1) * 1000)) ms for a whole zsh -i run")
        return out
    }
}

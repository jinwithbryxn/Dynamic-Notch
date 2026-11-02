import Foundation

/// 코딩 에이전트 자체 검사.
/// 실제 ~/.claude/settings.json·~/.codex/hooks.json·config.toml은 읽기만 해서 $REVIEW_OUT/test/agents/ 아래 사본을 만들고,
/// 설치·제거는 사본에만 한다. 승인 흐름은 임시 포트 서버 + 실제 perl 훅 스크립트로 끝까지 돌린다.
enum AgentHubSelfTest {
    static func run() -> [String] {
        var out: [String] = []
        let dir = AIDevTest.dir("agents")
        out += installerTests(dir)
        out += approvalTests(dir)
        out += costTest()
        return out
    }

    // MARK: 설치기 (사본)

    private static func installerTests(_ dir: URL) -> [String] {
        var out: [String] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        let hooksDir = dir.appendingPathComponent("hooks")
        let script = hooksDir.appendingPathComponent(AgentHookInstaller.scriptName).path
        let state = hooksDir.appendingPathComponent("install-state.json")

        func copyReal(_ rel: String, as name: String, fallback: String) -> URL {
            let dst = dir.appendingPathComponent(name)
            try? FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? Data(contentsOf: home.appendingPathComponent(rel)) {
                try? data.write(to: dst)
                out.append("copied ~/\(rel) -> test/agents/\(name) (\(data.count) bytes, real file only read)")
            } else {
                try? Data(fallback.utf8).write(to: dst)
                out.append("~/\(rel) missing, using a sample")
            }
            return dst
        }

        for (agent, rel, name, sample) in [
            (AgentHookInstaller.Agent.claude, ".claude/settings.json", "claude/settings.json",
             "{\n  \"hooks\": {\n    \"Stop\": [\n      {\n        \"hooks\": [\n          {\n            \"type\": \"command\",\n            \"command\": \"/Users/me/.local/bin/notch-agent-done claude\"\n          }\n        ]\n      }\n    ]\n  }\n}"),
            (.codex, ".codex/hooks.json", "codex/hooks.json", "{\n  \"hooks\": {}\n}\n"),
        ] {
            let file = copyReal(rel, as: name, fallback: sample)
            let original = (try? Data(contentsOf: file)) ?? Data()
            let text = String(decoding: original, as: UTF8.self)
            // 그대로 읽고 다시 쓰면 같은 글자인지 (JSON.stringify 2칸 모양 파일)
            if let parsed = try? OrderedJSON.parse(text) {
                let again = parsed.stringify() + (text.hasSuffix("\n") ? "\n" : "")
                out.append("\(again == text ? "PASS" : "INFO") \(agent.name): parse → stringify round trip \(again == text ? "byte-identical" : "reformats (file not in 2-space JSON.stringify form)")")
            }
            let inst = AgentHookInstaller(agent: agent, file: file, scriptPath: script, stateFile: state)
            let othersBefore = inst.otherHookCommands()
            do {
                let backup = try inst.install()
                let st = inst.status()
                let othersAfter = inst.otherHookCommands()
                out.append("\(st == .installed ? "PASS" : "FAIL") \(agent.name): install on copy -> \(st), backup \(backup?.lastPathComponent ?? "none")")
                out.append("\(othersBefore == othersAfter ? "PASS" : "FAIL") \(agent.name): existing hooks kept (\(othersBefore.count)): \(othersBefore.map { String($0.prefix(70)) }.joined(separator: " | "))")
                try inst.install()
                let root = try OrderedJSON.parse(String(contentsOf: file, encoding: .utf8))
                let counts = inst.hooks.map { h in (root["hooks"]?[h.event]?.arrayValue ?? []).flatMap { $0["hooks"]?.arrayValue ?? [] }.filter(AgentHookInstaller.isOurs).count }
                out.append("\(counts.allSatisfy { $0 == 1 } ? "PASS" : "FAIL") \(agent.name): installing twice keeps one entry per event \(counts)")
                try inst.uninstall()
                let after = (try? Data(contentsOf: file)) ?? Data()
                out.append("\(after == original ? "PASS" : "FAIL") \(agent.name): uninstall restores the copy byte-for-byte (\(after.count) bytes)")
                out.append("\(inst.otherHookCommands() == othersBefore ? "PASS" : "FAIL") \(agent.name): user hooks still there after uninstall")
            } catch {
                out.append("FAIL \(agent.name): \(error.localizedDescription)")
            }
        }

        // Codex notify 체인은 config.toml에 있고 이 설치기는 그 파일을 열지 않는다
        let toml = copyReal(".codex/config.toml", as: "codex/config.toml", fallback: "notify = [\"/bin/echo\"]\n")
        let tomlBefore = try? Data(contentsOf: toml)
        let codex = AgentHookInstaller(agent: .codex, file: dir.appendingPathComponent("codex/hooks.json"), scriptPath: script, stateFile: state)
        _ = try? codex.install(); _ = try? codex.uninstall()
        let notifyLine = (try? String(contentsOf: toml, encoding: .utf8))?.split(separator: "\n").first { $0.hasPrefix("notify") }.map(String.init) ?? "(none)"
        out.append("\((try? Data(contentsOf: toml)) == tomlBefore ? "PASS" : "FAIL") Codex notify chain untouched: \(notifyLine.prefix(110))")

        // 새 파일 → 설치 → 제거: 키까지 깨끗이
        let fresh = dir.appendingPathComponent("fresh/settings.json")
        try? FileManager.default.createDirectory(at: fresh.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("{\n  \"model\": \"x\"\n}".utf8).write(to: fresh)
        let fi = AgentHookInstaller(agent: .claude, file: fresh, scriptPath: script, stateFile: state)
        _ = try? fi.install(); _ = try? fi.uninstall()
        out.append("\((try? String(contentsOf: fresh, encoding: .utf8)) == "{\n  \"model\": \"x\"\n}" ? "PASS" : "FAIL") keys created by the app are removed again")

        // 깨진 JSON은 고치지 않는다
        let broken = dir.appendingPathComponent("broken/settings.json")
        try? FileManager.default.createDirectory(at: broken.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("{ \"hooks\": { ,, }".utf8).write(to: broken)
        let bi = AgentHookInstaller(agent: .claude, file: broken, scriptPath: script, stateFile: state)
        let threw = (try? bi.install()) == nil
        out.append("\(threw && (try? String(contentsOf: broken, encoding: .utf8)) == "{ \"hooks\": { ,, }" ? "PASS" : "FAIL") invalid JSON: refused, file unchanged (\(bi.status()))")
        return out
    }

    // MARK: 승인 흐름 (임시 포트 + 실제 perl 훅)

    private static func approvalTests(_ dir: URL) -> [String] {
        var out: [String] = []
        let hooksDir = dir.appendingPathComponent("hooks")
        var store: [String: String] = [:]
        let server = LocalAPIServer(config: .init(loadToken: { store[$0] }, saveToken: { store[$0] = $1 },
                                                  endpointDir: hooksDir, port: { 0 }, fallbackToEphemeral: false))
        let center = ActivityCenter()
        var ledgerData: Data?
        let hub = AgentHub(ledger: AgentAllowLedger(load: { ledgerData }, save: { ledgerData = $0 }))
        hub.resolveTarget = { _ in nil }
        hub.processAlive = { _ in true }
        hub.start(center: center, openTab: { _ in })
        AgentHubModule.registerCommands(on: server, hub: hub, owner: "agents") { true }
        server.acquire("agents")
        guard AIDevTest.wait(3, until: { server.boundPort != nil }), let port = server.boundPort else { return ["FAIL server did not start"] }
        guard let script = try? AgentHookInstaller.writeScript(to: hooksDir) else { return ["FAIL could not write hook script"] }
        out.append("hook script \(script.lastPathComponent) written to test dir, server 127.0.0.1:\(port)")

        let proj = dir.appendingPathComponent("proj")
        try? FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        func request(_ session: String, command: String) -> String {
            let obj: [String: Any] = [
                "session_id": session, "cwd": proj.path, "hook_event_name": "PermissionRequest", "permission_mode": "default",
                "tool_name": "Bash", "tool_input": ["command": command, "description": "test"],
                "permission_suggestions": [["type": "addRules", "rules": [["toolName": "Bash", "ruleContent": command]],
                                            "behavior": "allow", "destination": "localSettings"]],
            ]
            return String(decoding: try! JSONSerialization.data(withJSONObject: obj), as: UTF8.self)
        }

        final class Run { var p = Process(); var out = Pipe(); var stdout = "" }
        func spawn(_ args: [String], stdin: String, scriptURL: URL = script, env: [String: String] = [:]) -> Run {
            let r = Run()
            r.p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            r.p.arguments = [scriptURL.path] + args
            var e = ProcessInfo.processInfo.environment
            e["CLAUDE_PROJECT_DIR"] = proj.path
            for (k, v) in env { e[k] = v }
            r.p.environment = e
            let input = Pipe()
            r.p.standardInput = input
            r.p.standardOutput = r.out
            r.p.standardError = FileHandle.nullDevice
            try? r.p.run()
            input.fileHandleForWriting.write(Data(stdin.utf8))
            try? input.fileHandleForWriting.close()
            return r
        }
        func finish(_ r: Run, timeout: TimeInterval = 5) -> Bool {
            let ok = AIDevTest.wait(timeout) { !r.p.isRunning }
            r.stdout = String(decoding: r.out.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return ok
        }

        // 1) 허용
        var r = spawn(["claude", "PermissionRequest"], stdin: request("s1", command: "npm run lint"))
        if AIDevTest.wait(5, until: { hub.approvals.count == 1 }), let a = hub.approvals.first {
            let card = center.transient
            let titles = card?.actions.map(\.title) ?? []
            out.append("\(card?.kind == .agentApproval ? "PASS" : "FAIL") approval card shown: \(card?.title ?? "-") / \(card?.subtitle ?? "-") buttons \(titles)")
            hub.decide(a.id, .allow)
            _ = finish(r)
            let expected = #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#
            out.append("\(r.stdout == expected ? "PASS" : "FAIL") Allow -> hook stdout \(r.stdout)")
            out.append("\(center.transient?.kind != .agentApproval ? "PASS" : "FAIL") card cleared after decision")
            // 같은 버튼을 다시 누르면 무시
            hub.decide(a.id, .deny)
            out.append("\(hub.message != nil ? "PASS" : "FAIL") stale button ignored: \(hub.message ?? "-")")
        } else { out.append("FAIL approval did not arrive"); r.p.terminate() }

        // 2) 거부
        r = spawn(["claude", "PermissionRequest"], stdin: request("s1", command: "rm -rf build"))
        if AIDevTest.wait(5, until: { hub.approvals.count == 1 }), let a = hub.approvals.first {
            hub.decide(a.id, .deny)
            _ = finish(r)
            out.append("\(r.stdout.contains(#""behavior":"deny""#) ? "PASS" : "FAIL") Deny -> \(r.stdout)")
        } else { out.append("FAIL deny request did not arrive"); r.p.terminate() }

        // 3) 항상 허용: 규칙을 프로젝트 로컬 설정에 저장하게 하고, 이 앱 기록에 남긴다
        r = spawn(["claude", "PermissionRequest"], stdin: request("s1", command: "npm test"))
        if AIDevTest.wait(5, until: { hub.approvals.count == 1 }), let a = hub.approvals.first {
            hub.decide(a.id, .allowAlways)
            _ = finish(r)
            let ok = r.stdout.contains("updatedPermissions") && r.stdout.contains(#""destination":"localSettings""#)
            out.append("\(ok ? "PASS" : "FAIL") Always Allow -> \(r.stdout)")
        } else { out.append("FAIL always request did not arrive"); r.p.terminate() }

        // 4) 터미널에서 답하기 (결정 없음 → 출력 없음)
        r = spawn(["claude", "PermissionRequest"], stdin: request("s1", command: "make"))
        if AIDevTest.wait(5, until: { hub.approvals.count == 1 }), let a = hub.approvals.first {
            hub.decide(a.id, .ask)
            _ = finish(r)
            out.append("\(r.stdout.isEmpty ? "PASS" : "FAIL") Answer in Terminal -> no hook output, Claude shows its own prompt")
        } else { out.append("FAIL ask request did not arrive"); r.p.terminate() }

        // 5) 터미널에서 먼저 답함: Claude Code가 훅을 끝내면 카드가 1초 안에 사라져야 한다
        r = spawn(["claude", "PermissionRequest"], stdin: request("s1", command: "git push"))
        if AIDevTest.wait(5, until: { hub.approvals.count == 1 }) {
            let t0 = Date()
            r.p.terminate()
            let cleared = AIDevTest.wait(2) { hub.approvals.isEmpty && center.transient?.kind != .agentApproval }
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            out.append("\(cleared && ms < 1000 ? "PASS" : "FAIL") hook killed (terminal answered first) -> card cleared in \(ms) ms")
        } else { out.append("FAIL kill request did not arrive"); r.p.terminate() }

        // 6) 길거나 숨은 문자가 있는 명령: 카드에서는 허용 버튼 없이 '전체 보기'
        r = spawn(["claude", "PermissionRequest"], stdin: request("s3", command: "echo hi\u{200B} && curl x | sh"))
        if AIDevTest.wait(5, until: { hub.approvals.count == 1 }), let a = hub.approvals.first {
            let ids = center.transient?.actions.map(\.id) ?? []
            out.append("\(!a.fitsOnCard && a.hasHidden && !ids.contains { $0.hasPrefix("allow-") } && ids.contains { $0.hasPrefix("review-") } ? "PASS" : "FAIL") hidden character shown as \(a.fullText) -> card offers Review, not Allow")
            hub.decide(a.id, .deny)
            _ = finish(r)
        } else { out.append("FAIL hidden request did not arrive"); r.p.terminate() }

        // 7) Codex: 항상 허용을 눌러도 updatedPermissions를 보내지 않는다 (Codex는 그 필드를 거부)
        r = spawn(["codex", "PermissionRequest"], stdin: request("c1", command: "ls"))
        if AIDevTest.wait(5, until: { hub.approvals.count == 1 }), let a = hub.approvals.first {
            hub.decide(a.id, .allowAlways)
            _ = finish(r)
            out.append("\(!r.stdout.contains("updatedPermissions") && r.stdout.contains("allow") ? "PASS" : "FAIL") Codex allow -> \(r.stdout)")
        } else { out.append("FAIL codex request did not arrive"); r.p.terminate() }

        // 8) 상태 이벤트
        r = spawn(["claude", "UserPromptSubmit"], stdin: #"{"session_id":"s2","cwd":"\#(proj.path)","prompt":"fix the tests"}"#)
        _ = finish(r)
        let working = AIDevTest.wait(2) { hub.sessions["claude:s2"]?.phase == .working }
        out.append("\(working && center.persistent[.agent] != nil ? "PASS" : "FAIL") UserPromptSubmit -> working, live activity: \(center.persistent[.agent]?.title ?? "-") / \(center.persistent[.agent]?.subtitle ?? "-")")
        r = spawn(["claude", "Notification"], stdin: #"{"session_id":"s2","notification_type":"idle_prompt","message":"waiting"}"#)
        _ = finish(r)
        out.append("\(AIDevTest.wait(2) { hub.sessions["claude:s2"]?.phase == .needsInput } ? "PASS" : "FAIL") Notification idle_prompt -> waiting for input")
        r = spawn(["claude", "StopFailure"], stdin: #"{"session_id":"s2","error":"rate_limit"}"#)
        _ = finish(r)
        out.append("\(AIDevTest.wait(2) { hub.sessions["claude:s2"]?.phase == .error } ? "PASS" : "FAIL") StopFailure -> error")
        r = spawn(["claude", "Stop"], stdin: #"{"session_id":"s2","last_assistant_message":"All green"}"#)
        _ = finish(r)
        out.append("\(AIDevTest.wait(2) { hub.sessions["claude:s2"]?.phase == .done } ? "PASS" : "FAIL") Stop -> done (\(center.persistent[.agent]?.value == .check ? "check shown" : "no check"))")
        r = spawn(["claude", "SessionEnd"], stdin: #"{"session_id":"s2","reason":"other"}"#)
        _ = finish(r)
        out.append("\(AIDevTest.wait(2) { hub.sessions["claude:s2"] == nil } ? "PASS" : "FAIL") SessionEnd -> session removed")

        // 9) 잘못된 토큰 / 앱 꺼짐: 훅은 조용히 끝나고 출력이 없다
        let ep = hooksDir.appendingPathComponent("endpoint")
        let good = (try? String(contentsOf: ep, encoding: .utf8)) ?? ""
        try? good.replacingOccurrences(of: server.ensureHookToken(), with: "wrong-token").write(to: ep, atomically: true, encoding: .utf8)
        var t0 = Date()
        r = spawn(["claude", "PermissionRequest"], stdin: request("s4", command: "ls"))
        _ = finish(r)
        out.append("\(r.stdout.isEmpty && hub.approvals.isEmpty ? "PASS" : "FAIL") bad token -> rejected, hook exits in \(Int(Date().timeIntervalSince(t0) * 1000)) ms with no output")
        server.writeEndpointFile()
        let lonely = dir.appendingPathComponent("no-app")
        let lonelyScript = (try? AgentHookInstaller.writeScript(to: lonely)) ?? script
        t0 = Date()
        r = spawn(["claude", "PermissionRequest"], stdin: request("s5", command: "ls"), scriptURL: lonelyScript)
        _ = finish(r)
        out.append("\(r.stdout.isEmpty && r.p.terminationStatus == 0 ? "PASS" : "FAIL") app not running -> exit 0 in \(Int(Date().timeIntervalSince(t0) * 1000)) ms, no output (agent continues as usual)")

        // 10) 상시 승인 철회: 기록된 규칙만 빼고 사용자의 규칙은 둔다
        let localFile = proj.appendingPathComponent(".claude/settings.local.json")
        try? FileManager.default.createDirectory(at: localFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("{\n  \"permissions\": {\n    \"allow\": [\n      \"Bash(ls)\",\n      \"Bash(npm test)\"\n    ]\n  }\n}\n".utf8).write(to: localFile)
        let ledger = AgentAllowLedger(load: { ledgerData }, save: { ledgerData = $0 })
        let recorded = ledger.rules.map(\.rule)
        let res = ledger.revokeAll()
        let left = AgentAllowLedger.allowList(localFile) ?? []
        out.append("\(left == ["Bash(ls)"] && res.removed == 1 && res.backups.count == 1 ? "PASS" : "FAIL") revoke: ledger \(recorded) -> removed \(res.removed), left \(left), backup \(res.backups.first?.lastPathComponent ?? "-")")

        hub.stop()
        server.release("agents")
        return out
    }

    // MARK: 비용 요약 (실제 로그 읽기 전용)

    private static func costTest() -> [String] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return ["no Claude logs"] }
        var newest: (URL, Date)?
        for case let u as URL in en where u.pathExtension == "jsonl" && !u.path.contains("/subagents/") {
            if let d = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, d > (newest?.1 ?? .distantPast) { newest = (u, d) }
        }
        guard let (url, _) = newest else { return ["no Claude transcripts"] }
        let t0 = Date()
        let r = ClaudeLogScanner.sessionCost(transcript: url, turnSince: Date().addingTimeInterval(-600))
        let a = AgentHub.costActivity(project: "test", total: r.total, turn: r.turn, unpriced: r.unpriced, target: nil)
        return ["PASS session cost of newest transcript (read-only, \(Int(Date().timeIntervalSince(t0) * 1000)) ms): \(AIDevFormat.tokens(r.tokens)) tokens -> card '\(a.subtitle ?? "")'"]
    }
}

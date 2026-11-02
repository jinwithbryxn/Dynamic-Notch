import Foundation

/// Claude Code(~/.claude/settings.json)·Codex(~/.codex/hooks.json)에 이 앱의 에이전트 훅을 넣고 뺀다.
///
/// 원칙 (MODULE-GUIDE·FEATURE-MATRIX 6.11)
/// - 대상 파일 경로는 주입한다 (검사는 사본에서만).
/// - 원래 JSON을 키 순서·원래 토큰 그대로 읽고, 이 앱 항목만 더하거나 뺀다. 읽기 실패면 고치지 않는다.
/// - 쓰기 전에 원본을 시각 붙은 백업으로 남기고, 한 번에 바꿔 쓴다.
/// - 이 앱 항목은 명령 안의 스크립트 이름(`dmn-agent-hook`)으로 알아본다. 사용자의 다른 훅(notch-agent-done 등)은 그대로 둔다.
/// - 이 앱이 새로 만든 키(예: hooks.PermissionRequest)는 상태 파일에 적어 두고, 뺄 때 비면 그 키도 지운다 → 원본과 같은 바이트로 돌아간다.
final class AgentHookInstaller {
    enum Agent: String { case claude, codex
        var name: String { self == .claude ? "Claude Code" : "Codex" }
    }

    struct Hook: Equatable {
        let event: String
        let timeout: Int
        let async: Bool
    }

    enum Status: Equatable {
        case notInstalled
        case installed
        case partial([String])     // 빠진 이벤트
        case unreadable(String)
    }

    static let marker = "dmn-agent-hook"
    static let scriptName = "dmn-agent-hook.pl"

    let agent: Agent
    let file: URL
    let scriptPath: String
    let stateFile: URL
    var now: () -> Date = Date.init

    init(agent: Agent, file: URL, scriptPath: String, stateFile: URL) {
        self.agent = agent
        self.file = file
        self.scriptPath = scriptPath
        self.stateFile = stateFile
    }

    /// 실제 위치 (앱에서만 씀)
    static func live(_ agent: Agent, hooksDir: URL = LocalAPIServer.defaultEndpointDir) -> AgentHookInstaller {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let file = agent == .claude ? home.appendingPathComponent(".claude/settings.json") : home.appendingPathComponent(".codex/hooks.json")
        return AgentHookInstaller(agent: agent, file: file, scriptPath: hooksDir.appendingPathComponent(scriptName).path,
                                  stateFile: hooksDir.appendingPathComponent("install-state.json"))
    }

    /// 넣을 훅. 승인 요청만 답을 기다리고(앱이 답하지 않으면 110초 뒤 터미널 프롬프트로), 나머지는 바로 끝난다.
    var hooks: [Hook] {
        switch agent {
        case .claude:
            return [Hook(event: "PermissionRequest", timeout: 120, async: false),
                    Hook(event: "UserPromptSubmit", timeout: 10, async: true),
                    Hook(event: "Notification", timeout: 10, async: true),
                    Hook(event: "Stop", timeout: 10, async: true),
                    Hook(event: "StopFailure", timeout: 10, async: true),
                    Hook(event: "SessionStart", timeout: 10, async: true),
                    Hook(event: "SessionEnd", timeout: 10, async: true)]
        case .codex:
            // Codex hooks.json: async 항목이 없다. 스크립트는 앱이 없으면 바로, 있으면 1초 안에 끝난다.
            return [Hook(event: "PermissionRequest", timeout: 120, async: false),
                    Hook(event: "UserPromptSubmit", timeout: 5, async: false),
                    Hook(event: "Stop", timeout: 5, async: false),
                    Hook(event: "SessionStart", timeout: 5, async: false),
                    Hook(event: "SessionEnd", timeout: 3, async: false)]
        }
    }

    func command(_ event: String) -> String {
        "/usr/bin/perl '\(scriptPath.replacingOccurrences(of: "'", with: "'\\''"))' \(agent.rawValue) \(event)"
    }

    private func entry(_ h: Hook) -> OrderedJSON {
        var pairs: [(String, OrderedJSON)] = [("type", .str("command")), ("command", .str(command(h.event))), ("timeout", .number(String(h.timeout)))]
        if h.async { pairs.append(("async", .bool(true))) }
        return .obj([("hooks", .array([.obj(pairs)]))])
    }

    static func isOurs(_ hookEntry: OrderedJSON) -> Bool {
        hookEntry["command"]?.stringValue?.contains(marker) == true
    }

    // MARK: 읽기

    private func read() throws -> (root: OrderedJSON, text: String?) {
        guard FileManager.default.fileExists(atPath: file.path) else { return (.object([]), nil) }
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            throw InstallError.unreadable(T("파일을 읽을 수 없음", "Can't read the file"))
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (.object([]), text) }
        do {
            let root = try OrderedJSON.parse(text)
            guard root.isObject else { throw InstallError.unreadable(T("맨 위가 JSON 객체가 아님", "Top level is not a JSON object")) }
            return (root, text)
        } catch let e as InstallError {
            throw e
        } catch {
            throw InstallError.unreadable(T("JSON 형식 오류 (\(error.localizedDescription))", "Invalid JSON (\(error.localizedDescription))"))
        }
    }

    enum InstallError: LocalizedError {
        case unreadable(String)
        case writeFailed(String)
        var errorDescription: String? {
            switch self { case .unreadable(let s), .writeFailed(let s): return s }
        }
    }

    func status() -> Status {
        do {
            let (root, _) = try read()
            let present = Set(ourEvents(root))
            let wanted = hooks.map(\.event)
            if present.isEmpty { return .notInstalled }
            let missing = wanted.filter { !present.contains($0) }
            return missing.isEmpty ? .installed : .partial(missing)
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    /// 이 앱 훅이 들어 있는 이벤트들
    func ourEvents(_ root: OrderedJSON) -> [String] {
        guard case .object(let events)? = root["hooks"] else { return [] }
        return events.filter { m in
            (m.value.arrayValue ?? []).contains { g in (g["hooks"]?.arrayValue ?? []).contains(where: Self.isOurs) }
        }.map(\.key)
    }

    /// 사용자가 이미 둔 다른 훅 명령 (보존 대상, 화면 표시용)
    func otherHookCommands() -> [String] {
        guard let (root, _) = try? read(), case .object(let events)? = root["hooks"] else { return [] }
        var out: [String] = []
        for m in events {
            for g in m.value.arrayValue ?? [] {
                for h in g["hooks"]?.arrayValue ?? [] where !Self.isOurs(h) {
                    if let c = h["command"]?.stringValue { out.append("\(m.key): \(c)") }
                }
            }
        }
        return out
    }

    /// 바뀔 내용 미리보기 (설치 전에 보여 준다)
    func preview() -> [String] {
        ["\(file.path)"] + hooks.map { "+ hooks.\($0.event): \(command($0.event))\($0.async ? " (async)" : "")" }
    }

    // MARK: 설치·제거

    /// 설치. 바뀐 게 있으면 백업 파일 경로를 돌려준다.
    @discardableResult
    func install() throws -> URL? {
        var (root, text) = try read()
        var created = loadState()
        var hooksObj = root["hooks"] ?? .object([])
        if root["hooks"] == nil { created.insert("hooks") }
        guard hooksObj.isObject else { throw InstallError.unreadable(T("hooks 값이 객체가 아님", "hooks is not an object")) }
        for h in hooks {
            var groups = hooksObj[h.event]?.arrayValue ?? []
            if hooksObj[h.event] == nil { created.insert("hooks.\(h.event)") }
            groups = Self.removingOurs(groups)
            groups.append(entry(h))
            hooksObj.set(h.event, .array(groups))
        }
        root.set("hooks", hooksObj)
        let backup = try write(root, original: text)
        saveState(created)
        return backup
    }

    /// 제거: 이 앱 항목만 뺀다. 바뀐 게 있으면 백업 파일 경로를 돌려준다.
    @discardableResult
    func uninstall() throws -> URL? {
        guard FileManager.default.fileExists(atPath: file.path) else { saveState([]); return nil }
        var (root, text) = try read()
        let created = loadState()
        guard case .object(let events)? = root["hooks"] else { saveState([]); return nil }
        var hooksObj = OrderedJSON.object(events)
        for m in events {
            guard let groups = m.value.arrayValue else { continue }
            let kept = Self.removingOurs(groups)
            guard kept.count != groups.count || kept != groups else { continue }
            if kept.isEmpty, created.contains("hooks.\(m.key)") { hooksObj.remove(m.key) } else { hooksObj.set(m.key, .array(kept)) }
        }
        if case .object(let left) = hooksObj, left.isEmpty, created.contains("hooks") { root.remove("hooks") } else { root.set("hooks", hooksObj) }
        let backup = try write(root, original: text)
        saveState([])
        return backup
    }

    /// 그룹 안에서 이 앱 훅을 빼고, 그 때문에 빈 그룹은 지운다 (원래 빈 그룹은 그대로)
    static func removingOurs(_ groups: [OrderedJSON]) -> [OrderedJSON] {
        groups.compactMap { g in
            guard let list = g["hooks"]?.arrayValue else { return g }
            let kept = list.filter { !isOurs($0) }
            if kept.count == list.count { return g }
            if kept.isEmpty { return nil }
            var copy = g
            copy.set("hooks", .array(kept))
            return copy
        }
    }

    private func write(_ root: OrderedJSON, original: String?) throws -> URL? {
        var out = root.stringify()
        // 원래 끝 줄바꿈 여부를 따른다 (새 파일은 줄바꿈으로 끝냄)
        if original?.hasSuffix("\n") ?? true { out += "\n" }
        if out == original { return nil }
        let fm = FileManager.default
        var backup: URL?
        if let original, fm.fileExists(atPath: file.path) {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            f.locale = Locale(identifier: "en_US_POSIX")
            var b = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".dmn-backup-" + f.string(from: now()))
            var n = 1
            while fm.fileExists(atPath: b.path) { n += 1; b = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".dmn-backup-" + f.string(from: now()) + "-\(n)") }
            do { try Data(original.utf8).write(to: b, options: .withoutOverwriting) } catch {
                throw InstallError.writeFailed(T("백업을 만들지 못해 고치지 않음: \(error.localizedDescription)", "Couldn't make a backup, nothing changed: \(error.localizedDescription)"))
            }
            backup = b
        } else {
            try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        do { try Data(out.utf8).write(to: file, options: .atomic) } catch {
            throw InstallError.writeFailed(error.localizedDescription)
        }
        return backup
    }

    // MARK: 상태 파일 (대상 파일별로 이 앱이 만든 키)

    private func loadState() -> Set<String> {
        guard let data = try? Data(contentsOf: stateFile),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String]] else { return [] }
        return Set(obj[file.path] ?? [])
    }

    private func saveState(_ keys: Set<String>) {
        var obj = ((try? Data(contentsOf: stateFile)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: [String]]) ?? [:]
        obj[file.path] = keys.isEmpty ? nil : keys.sorted()
        try? FileManager.default.createDirectory(at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: stateFile, options: .atomic) }
    }

    // MARK: 훅 스크립트 쓰기

    /// 훅 폴더에 스크립트를 쓴다 (0700). 내용이 같으면 그대로 둔다.
    static func writeScript(to dir: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = dir.appendingPathComponent(scriptName)
        if (try? String(contentsOf: url, encoding: .utf8)) != AgentHookScript.perl {
            try Data(AgentHookScript.perl.utf8).write(to: url, options: .atomic)
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}

/// 훅 스크립트 본문. 설치할 때 훅 폴더에 써 둔다.
/// 앱이 꺼져 있거나 endpoint 파일이 없으면 아무것도 출력하지 않고 끝난다 → 에이전트는 원래대로 동작.
enum AgentHookScript {
    static let perl = #"""
#!/usr/bin/perl
# dmn-agent-hook: Dynamic Notch agent hook.
# Installed and removed by Dynamic Notch (Coding Agents). Do not edit; it is rewritten on install.
# Sends Claude Code / Codex hook events to the app's local API on 127.0.0.1 with the hook token
# from the endpoint file next to this script. If the app is not running it exits silently.
use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;
use JSON::PP;

my ($source, $event) = @ARGV;
exit 0 unless defined $event && $source =~ /^(claude|codex)$/ && $event =~ /^[A-Za-z]+$/;
my $input = do { local $/; <STDIN> };
$input = '' unless defined $input;
(my $dir = $0) =~ s{/[^/]*$}{};
open(my $fh, '<', "$dir/endpoint") or exit 0;
my @ep = <$fh>;
close $fh;
chomp @ep;
my ($port, $token, $wait) = @ep;
exit 0 unless defined $port && $port =~ /^\d+$/ && defined $token && length $token;
$wait = 110 unless defined $wait && $wait =~ /^\d+$/;
my $payload = eval { decode_json($input) };
$payload = {} unless ref $payload eq 'HASH';
my $blocking = $event eq 'PermissionRequest' ? 1 : 0;
my $msg = {
    command     => $blocking ? 'approval.request' : 'agent.event',
    token       => $token,
    source      => $source,
    event       => $event,
    payload     => $payload,
    ppid        => getppid(),
    project_dir => (defined $ENV{CLAUDE_PROJECT_DIR} ? $ENV{CLAUDE_PROJECT_DIR} : ''),
};
my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, Proto => 'tcp', Timeout => 1) or exit 0;
$sock->autoflush(1);
print {$sock} JSON::PP->new->utf8->canonical->encode($msg), "\n";
my $sel = IO::Select->new($sock);
my $deadline = time + ($blocking ? $wait : 1);
my $buf = '';
while (time <= $deadline) {
    exit 0 if getppid() == 1;
    next unless $sel->can_read(0.25);
    my $n = sysread($sock, $buf, 65536, length $buf);
    last unless $n;
    last if index($buf, "\n") >= 0;
}
exit 0 unless $blocking;
my ($line) = split /\n/, $buf;
my $reply = eval { decode_json(defined $line ? $line : '') };
exit 0 unless ref $reply eq 'HASH' && ref $reply->{hook_output} eq 'HASH';
print JSON::PP->new->utf8->canonical->encode($reply->{hook_output}), "\n";
exit 0;
"""#
}

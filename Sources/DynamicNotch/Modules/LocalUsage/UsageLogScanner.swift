import Foundation

// 로컬 로그에서 AI 사용량을 읽는다 (읽기 전용).
// - Claude Code: ~/.claude/projects/**/*.jsonl 의 assistant 줄 message.usage
// - Codex: ~/.codex/sessions/**/rollout-*.jsonl 의 token_count 이벤트 (토큰 + 서버가 준 한도 스냅샷)
// 파일 끝까지 읽은 위치를 기억해 다음에는 덧붙은 부분만 읽는다.

/// Anthropic API 요금표 (1M 토큰당 USD, 2026-10 기준). 구독 사용자는 실제 청구가 아니라 API 요금 기준 추정치다.
enum ClaudePricing {
    struct Price { let input: Double; let output: Double; let cacheRead: Double }

    /// 모델 id 앞부분으로 찾는다 (날짜 접미사가 붙은 옛 id도 맞도록)
    static let table: [(prefix: String, price: Price)] = [
        ("claude-fable-5-1", Price(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-mythos-5-1", Price(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-fable-5", Price(input: 10, output: 50, cacheRead: 1.0)),
        ("claude-mythos-5", Price(input: 10, output: 50, cacheRead: 1.0)),
        ("claude-opus-5-5", Price(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("claude-opus-4-8", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("claude-opus-4-7", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("claude-opus-4-6", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("claude-opus-4-5", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("claude-sonnet-5-5", Price(input: 2, output: 10, cacheRead: 0.20)),
        ("claude-sonnet-5", Price(input: 2, output: 10, cacheRead: 0.20)),
        ("claude-sonnet-4-6", Price(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-sonnet-4-5", Price(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-haiku-5-5", Price(input: 0.10, output: 0.50, cacheRead: 0.01)),
        ("claude-haiku-4-5", Price(input: 1, output: 5, cacheRead: 0.10)),
    ]

    static func price(for model: String) -> Price? {
        let m = model.lowercased()
        // 긴 접두어부터 (claude-opus-5-5 가 claude-opus-5 보다 먼저)
        return table.sorted { $0.prefix.count > $1.prefix.count }.first { m.hasPrefix($0.prefix) }?.price
    }

    /// 캐시 쓰기: 5분 1.25배, 1시간 2배. 빠른 모드는 2배.
    static func cost(_ e: ClaudeUsageEntry) -> Double? {
        guard let p = price(for: e.model) else { return nil }
        let mt = 1_000_000.0
        var c = Double(e.input) * p.input / mt
            + Double(e.output) * p.output / mt
            + Double(e.cacheWrite5m) * p.input * 1.25 / mt
            + Double(e.cacheWrite1h) * p.input * 2 / mt
            + Double(e.cacheRead) * p.cacheRead / mt
        if e.fast { c *= 2 }
        return c
    }
}

struct ClaudeUsageEntry {
    var time: Date
    var model: String
    var input = 0
    var output = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0
    var cacheRead = 0
    var fast = false
    var session = ""
    var project = ""

    var totalTokens: Int { input + output + cacheWrite5m + cacheWrite1h + cacheRead }
    var cost: Double { ClaudePricing.cost(self) ?? 0 }
    var priced: Bool { ClaudePricing.price(for: model) != nil }
}

/// 줄 단위 바이트 도우미
enum LogBytes {
    /// needle이 처음(또는 마지막) 나오는 위치
    static func find(_ hay: UnsafeRawBufferPointer, _ needle: [UInt8], last: Bool = false) -> Int? {
        guard let base = hay.baseAddress, hay.count >= needle.count, !needle.isEmpty else { return nil }
        if !last {
            return needle.withUnsafeBytes { n -> Int? in
                guard let p = memmem(base, hay.count, n.baseAddress, n.count) else { return nil }
                return base.distance(to: UnsafeRawPointer(p))
            }
        }
        var found: Int?
        var start = 0
        while start < hay.count, let r = find(UnsafeRawBufferPointer(rebasing: hay[start...]), needle) {
            found = start + r
            start += r + 1
        }
        return found
    }

    /// "key":"값" 의 값 (이스케이프 없는 단순 값만)
    static func string(_ line: UnsafeRawBufferPointer, key: String, last: Bool = false) -> String? {
        let needle = Array("\"\(key)\":\"".utf8)
        guard let at = find(line, needle, last: last) else { return nil }
        var i = at + needle.count
        let start = i
        while i < line.count, line[i] != UInt8(ascii: "\"") {
            if line[i] == UInt8(ascii: "\\") { return nil }
            i += 1
        }
        return String(decoding: UnsafeRawBufferPointer(rebasing: line[start..<i]), as: UTF8.self)
    }

    /// "key":{...} 객체 부분 (문자열 안의 괄호는 건너뜀)
    static func object(_ line: UnsafeRawBufferPointer, key: String) -> Data? {
        let needle = Array("\"\(key)\":{".utf8)
        guard let at = find(line, needle) else { return nil }
        let start = at + needle.count - 1
        var depth = 0, i = start, inString = false
        while i < line.count {
            let c = line[i]
            if inString {
                if c == UInt8(ascii: "\\") { i += 2; continue }
                if c == UInt8(ascii: "\"") { inString = false }
            } else if c == UInt8(ascii: "\"") { inString = true }
            else if c == UInt8(ascii: "{") { depth += 1 }
            else if c == UInt8(ascii: "}") {
                depth -= 1
                if depth == 0 { return Data(UnsafeRawBufferPointer(rebasing: line[start...i])) }
            }
            i += 1
        }
        return nil
    }

    /// "2026-11-02T02:08:44.963Z" → Date (UTC)
    static func isoDate(_ s: String) -> Date? {
        let b = Array(s.utf8)
        guard b.count >= 19 else { return nil }
        func num(_ from: Int, _ len: Int) -> Int? {
            var v = 0
            for k in from..<(from + len) {
                let c = b[k]
                guard c >= 48, c <= 57 else { return nil }
                v = v * 10 + Int(c - 48)
            }
            return v
        }
        guard let y = num(0, 4), let mo = num(5, 2), let d = num(8, 2), let h = num(11, 2), let mi = num(14, 2), let se = num(17, 2) else { return nil }
        var t = tm()
        t.tm_year = Int32(y - 1900); t.tm_mon = Int32(mo - 1); t.tm_mday = Int32(d)
        t.tm_hour = Int32(h); t.tm_min = Int32(mi); t.tm_sec = Int32(se)
        var frac = 0.0
        if b.count > 20, b[19] == UInt8(ascii: ".") {
            var k = 20, scale = 0.1
            while k < b.count, b[k] >= 48, b[k] <= 57 { frac += Double(b[k] - 48) * scale; scale /= 10; k += 1 }
        }
        return Date(timeIntervalSince1970: Double(timegm(&t)) + frac)
    }

    /// 파일의 offset부터 끝까지, 마지막 줄바꿈까지만 줄 단위로 넘긴다. 새 offset을 돌려준다.
    static func eachLine(_ url: URL, from offset: UInt64, _ body: (UnsafeRawBufferPointer) -> Void) -> UInt64 {
        guard let h = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? h.close() }
        try? h.seek(toOffset: offset)
        var pos = offset
        var carry = Data()
        while true {
            guard let chunk = try? h.read(upToCount: 8 << 20), !chunk.isEmpty else { break }
            var data = carry
            data.append(chunk)
            var consumed = 0
            data.withUnsafeBytes { raw in
                var start = 0
                while start < raw.count, let nl = memchr(raw.baseAddress! + start, 0x0A, raw.count - start) {
                    let end = raw.baseAddress!.distance(to: UnsafeRawPointer(nl))
                    if end > start { body(UnsafeRawBufferPointer(rebasing: raw[start..<end])) }
                    start = end + 1
                }
                consumed = start
            }
            pos += UInt64(consumed)
            carry = data.subdata(in: consumed..<data.count)
            // 아주 긴 줄이 끝나지 않으면 더 읽는다 (최대 64MB)
            if carry.count > 64 << 20 { break }
        }
        return pos
    }
}

/// Claude Code 로그 스캐너 (점진적)
final class ClaudeLogScanner {
    let root: URL
    private var offsets: [String: UInt64] = [:]
    /// 메시지 id(+요청 id) → 항목. 같은 응답이 여러 줄로 나뉘어 기록되므로 큰 값으로 합친다.
    private(set) var entries: [String: ClaudeUsageEntry] = [:]
    private(set) var filesScanned = 0
    private(set) var bytesScanned: UInt64 = 0

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")) {
        self.root = root
    }

    /// since 이후 수정된 파일만 읽는다. 오래된 항목은 버린다.
    func scan(since: Date) {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                                     options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in en where url.pathExtension == "jsonl" {
            guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mod = v.contentModificationDate, mod >= since else { continue }
            let size = UInt64(v.fileSize ?? 0)
            let key = url.path
            var from = offsets[key] ?? 0
            if from > size { from = 0 }   // 파일이 줄었으면 처음부터
            guard from < size else { continue }
            let project = Self.projectName(url)
            let newOffset = LogBytes.eachLine(url, from: from) { line in self.ingest(line, project: project) }
            bytesScanned += newOffset - from
            offsets[key] = newOffset
            filesScanned += 1
        }
        entries = entries.filter { $0.value.time >= since }
    }

    /// 프로젝트 폴더 이름(-Users-me-Documents-app) → 마지막 부분
    static func projectName(_ url: URL) -> String {
        var dir = url.deletingLastPathComponent()
        if dir.lastPathComponent == "subagents" { dir = dir.deletingLastPathComponent().deletingLastPathComponent() }
        return dir.lastPathComponent.split(separator: "-").last.map(String.init) ?? dir.lastPathComponent
    }

    private static let usageNeedle = Array("\"usage\":{".utf8)
    private static let assistantNeedle = Array("\"type\":\"assistant\"".utf8)

    func ingest(_ line: UnsafeRawBufferPointer, project: String) {
        guard LogBytes.find(line, Self.usageNeedle) != nil, LogBytes.find(line, Self.assistantNeedle) != nil,
              let entry = Self.parse(line, project: project) else { return }
        let id = (LogBytes.string(line, key: "id") ?? "") + ":" + (LogBytes.string(line, key: "requestId", last: true) ?? "")
        let key = id == ":" ? "\(entry.time.timeIntervalSince1970)-\(entry.output)" : id
        if var old = entries[key] {
            old.input = max(old.input, entry.input); old.output = max(old.output, entry.output)
            old.cacheWrite5m = max(old.cacheWrite5m, entry.cacheWrite5m); old.cacheWrite1h = max(old.cacheWrite1h, entry.cacheWrite1h)
            old.cacheRead = max(old.cacheRead, entry.cacheRead)
            entries[key] = old
        } else {
            entries[key] = entry
        }
    }

    static func parse(_ line: UnsafeRawBufferPointer, project: String) -> ClaudeUsageEntry? {
        guard let model = LogBytes.string(line, key: "model"), model != "<synthetic>",
              let ts = LogBytes.string(line, key: "timestamp", last: true), let time = LogBytes.isoDate(ts),
              let usageData = LogBytes.object(line, key: "usage"),
              let u = (try? JSONSerialization.jsonObject(with: usageData)) as? [String: Any],
              u["output_tokens"] != nil else { return nil }
        func n(_ k: String) -> Int { (u[k] as? NSNumber)?.intValue ?? 0 }
        var e = ClaudeUsageEntry(time: time, model: model)
        e.input = n("input_tokens")
        e.output = n("output_tokens")
        e.cacheRead = n("cache_read_input_tokens")
        let creation = n("cache_creation_input_tokens")
        if let split = u["cache_creation"] as? [String: Any] {
            e.cacheWrite1h = (split["ephemeral_1h_input_tokens"] as? NSNumber)?.intValue ?? 0
            e.cacheWrite5m = (split["ephemeral_5m_input_tokens"] as? NSNumber)?.intValue ?? max(0, creation - e.cacheWrite1h)
        } else {
            e.cacheWrite5m = creation
        }
        e.fast = (u["speed"] as? String) == "fast"
        e.session = LogBytes.string(line, key: "sessionId", last: true) ?? ""
        e.project = project
        return e
    }

    /// 대화 하나(대화 기록 파일)의 추정 비용. since를 주면 그 뒤 항목만 따로 더한다 (마지막 답변).
    static func sessionCost(transcript: URL, turnSince: Date?) -> (total: Double, turn: Double?, tokens: Int, unpriced: Bool) {
        let s = ClaudeLogScanner(root: transcript.deletingLastPathComponent())
        _ = LogBytes.eachLine(transcript, from: 0) { s.ingest($0, project: "") }
        // 같은 대화의 하위 에이전트 기록도 더한다 (<session>/subagents/*.jsonl)
        let sub = transcript.deletingPathExtension().appendingPathComponent("subagents")
        if let files = try? FileManager.default.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension == "jsonl" { _ = LogBytes.eachLine(f, from: 0) { s.ingest($0, project: "") } }
        }
        let list = Array(s.entries.values)
        let total = list.reduce(0) { $0 + $1.cost }
        let turn = turnSince.map { t in list.filter { $0.time >= t }.reduce(0) { $0 + $1.cost } }
        return (total, turn, list.reduce(0) { $0 + $1.totalTokens }, list.contains { !$0.priced })
    }
}

/// Codex 서버가 응답과 함께 준 한도 (rollout에 기록됨). 실제 계정 값이다.
struct CodexLimitSnapshot {
    struct Window { let usedPercent: Double; let windowMinutes: Int; let resetsAt: Date? }
    let time: Date
    let primary: Window?
    let secondary: Window?
    let plan: String?
    let creditsBalance: Double?
    let unlimitedCredits: Bool
}

struct CodexTokenEntry {
    let time: Date
    let input: Int
    let cached: Int
    let output: Int
    var total: Int { input + output }
}

/// Codex 로그 스캐너 (점진적)
final class CodexLogScanner {
    let root: URL
    private var offsets: [String: UInt64] = [:]
    private var lastTotals: [String: Int] = [:]
    private var lastInput: [String: Int] = [:]
    private var lastCached: [String: Int] = [:]
    private var lastOutput: [String: Int] = [:]
    private(set) var tokens: [CodexTokenEntry] = []
    private(set) var snapshots: [CodexLimitSnapshot] = []
    private(set) var filesScanned = 0

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")) {
        self.root = root
    }

    private static let needle = Array("\"type\":\"token_count\"".utf8)

    func scan(since: Date) {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                     options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in en where url.pathExtension == "jsonl" {
            guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mod = v.contentModificationDate, mod >= since else { continue }
            let size = UInt64(v.fileSize ?? 0)
            let key = url.path
            var from = offsets[key] ?? 0
            if from > size { from = 0; lastTotals[key] = nil }
            guard from < size else { continue }
            offsets[key] = LogBytes.eachLine(url, from: from) { line in
                guard LogBytes.find(line, Self.needle) != nil else { return }
                self.ingest(Data(line), file: key)
            }
            filesScanned += 1
        }
        tokens.removeAll { $0.time < since }
        snapshots.removeAll { $0.time < since }
        snapshots.sort { $0.time < $1.time }
    }

    func ingest(_ data: Data, file: String) {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let ts = obj["timestamp"] as? String, let time = LogBytes.isoDate(ts),
              let payload = obj["payload"] as? [String: Any], payload["type"] as? String == "token_count" else { return }
        if let info = payload["info"] as? [String: Any], let total = info["total_token_usage"] as? [String: Any] {
            func n(_ k: String) -> Int { (total[k] as? NSNumber)?.intValue ?? 0 }
            let t = n("total_tokens")
            let prev = lastTotals[file] ?? 0
            if t > prev {
                tokens.append(CodexTokenEntry(time: time, input: max(0, n("input_tokens") - (lastInput[file] ?? 0)),
                                              cached: max(0, n("cached_input_tokens") - (lastCached[file] ?? 0)),
                                              output: max(0, n("output_tokens") - (lastOutput[file] ?? 0))))
                lastTotals[file] = t
                lastInput[file] = n("input_tokens"); lastCached[file] = n("cached_input_tokens"); lastOutput[file] = n("output_tokens")
            }
        }
        if let rl = payload["rate_limits"] as? [String: Any] {
            func window(_ any: Any?) -> CodexLimitSnapshot.Window? {
                guard let w = any as? [String: Any], let p = (w["used_percent"] as? NSNumber)?.doubleValue else { return nil }
                let reset = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                    ?? (w["resets_in_seconds"] as? NSNumber).map { time.addingTimeInterval($0.doubleValue) }
                return .init(usedPercent: p, windowMinutes: (w["window_minutes"] as? NSNumber)?.intValue ?? 0, resetsAt: reset)
            }
            let credits = rl["credits"] as? [String: Any]
            let balance = (credits?["balance"] as? String).flatMap(Double.init) ?? (credits?["balance"] as? NSNumber)?.doubleValue
            let snap = CodexLimitSnapshot(time: time, primary: window(rl["primary"]), secondary: window(rl["secondary"]),
                                          plan: rl["plan_type"] as? String, creditsBalance: balance,
                                          unlimitedCredits: credits?["unlimited"] as? Bool ?? false)
            if snap.primary != nil || snap.secondary != nil { snapshots.append(snap) }
        }
    }

    var latest: CodexLimitSnapshot? { snapshots.max { $0.time < $1.time } }
}

/// 5시간 사용 구간 (Claude 구독 한도와 같은 방식 추정: 첫 메시지 시각의 정시부터 5시간)
struct UsageBlock {
    var start: Date
    var end: Date
    var tokens = 0
    var cost = 0.0
    var count = 0
}

enum UsageMath {
    static func blocks(_ entries: [ClaudeUsageEntry]) -> [UsageBlock] {
        var out: [UsageBlock] = []
        for e in entries.sorted(by: { $0.time < $1.time }) {
            if out.isEmpty || e.time >= out[out.count - 1].end {
                let start = Date(timeIntervalSince1970: floor(e.time.timeIntervalSince1970 / 3600) * 3600)
                out.append(UsageBlock(start: start, end: start.addingTimeInterval(5 * 3600)))
            }
            out[out.count - 1].tokens += e.totalTokens
            out[out.count - 1].cost += e.cost
            out[out.count - 1].count += 1
        }
        return out
    }

    /// 지금 속도로 가면 한도(100%)에 닿는 시각. 최근 60분 기울기 기준. 리셋 전에 닿지 않으면 nil.
    static func projectedExhaustion(points: [(Date, Double)], now: Date = Date(), resetsAt: Date?) -> Date? {
        let recent = points.filter { now.timeIntervalSince($0.0) <= 3600 }.sorted { $0.0 < $1.0 }
        guard let first = recent.first, let last = recent.last, last.0.timeIntervalSince(first.0) >= 300, last.1 > first.1 else { return nil }
        let rate = (last.1 - first.1) / last.0.timeIntervalSince(first.0)   // %/초
        guard rate > 0, last.1 < 100 else { return nil }
        let hit = last.0.addingTimeInterval((100 - last.1) / rate)
        if let r = resetsAt, hit >= r { return nil }
        return hit
    }
}

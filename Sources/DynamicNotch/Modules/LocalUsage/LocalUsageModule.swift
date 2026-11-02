import AppKit
import SwiftUI

/// 로컬 AI 사용량 (M-K-002·003·008·009·010·011·012 일부):
/// Claude Code·Codex가 이 Mac에 남긴 로그만 읽어(읽기 전용) 오늘·5시간·7일 토큰과 추정 비용을 보여 준다.
/// 값마다 출처를 붙인다: "로컬 로그 추정"(Claude 토큰·비용) / "계정 값"(Codex 서버가 응답과 함께 준 한도, 기존 웹 로그인 사용량).
/// 50·80·100% 도달, 지금 속도로 리셋 전에 바닥날 때, 리셋될 때 노치에 알린다. 기본 꺼짐.
final class LocalUsageModule: NotchModule {
    let id = "localusage"
    var title: String { T("AI 사용량 (로컬 로그)", "AI Usage (Local Logs)") }
    let symbol = "chart.bar.xaxis"
    var enabledByDefault: Bool { false }

    let model = LocalUsageModel()
    private var context: ModuleContext?
    private var timer: Timer?

    func start(context: ModuleContext) {
        guard self.context == nil else { return }
        self.context = context
        model.onUpdate = { [weak self] s in self?.evaluateAlerts(s) }
        model.refresh()
        let minutes = max(2, ModuleDefaults(module: id).int("refreshMinutes", default: 5))
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in self?.model.refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        model.onUpdate = nil
        context = nil
    }

    func settingsChanged() {
        guard let context else { return }
        stop()
        start(context: context)
    }

    func tabView() -> AnyView? { AnyView(LocalUsageTab(model: model)) }
    var tabContentSize: CGSize { CGSize(width: 580, height: 262) }
    func settingsView() -> AnyView? { AnyView(LocalUsageSettings()) }

    // MARK: 알림 (M-K-009)

    struct Meter {
        let key: String
        let name: String
        let percent: Double
        let resetsAt: Date?
        let source: String
        let points: [(Date, Double)]
    }

    static func meters(_ s: LocalUsageSummary, budget5h: Double, budgetWeek: Double, now: Date = Date()) -> [Meter] {
        var out: [Meter] = []
        if let snap = s.codexSnapshot, now.timeIntervalSince(snap.time) < 6 * 3600 {
            for (w, tag) in [(snap.primary, "primary"), (snap.secondary, "secondary")] {
                guard let w else { continue }
                let pts = s.codexHistory.compactMap { h -> (Date, Double)? in
                    let hw = tag == "primary" ? h.primary : h.secondary
                    return hw.map { (h.time, $0.usedPercent) }
                }
                out.append(Meter(key: "codex.\(tag).\(Int(w.resetsAt?.timeIntervalSince1970 ?? 0))", name: "Codex \(LocalUsageSummary.windowName(w.windowMinutes))",
                                 percent: w.usedPercent, resetsAt: w.resetsAt, source: T("계정", "account"), points: pts))
            }
        }
        if let acc = s.claudeAccount, now.timeIntervalSince(acc.fetched) < 6 * 3600 {
            for w in acc.windows {
                out.append(Meter(key: "claude.web.\(Int(w.seconds)).\(Int(w.resetsAt?.timeIntervalSince1970 ?? 0))", name: "Claude \(w.label)",
                                 percent: w.percent, resetsAt: w.resetsAt, source: T("계정", "account"), points: []))
            }
        }
        if budget5h > 0, let b = s.claudeBlock, b.end > now {
            out.append(Meter(key: "claude.budget5h.\(Int(b.start.timeIntervalSince1970))", name: T("Claude 5시간 예산", "Claude 5-hour budget"),
                             percent: b.cost / budget5h * 100, resetsAt: b.end, source: T("로그 추정", "log estimate"),
                             points: s.claudeBlockPoints.map { ($0.0, $0.1 / budget5h * 100) }))
        }
        if budgetWeek > 0 {
            let weekStart = Int(now.timeIntervalSince1970 / 604800)
            out.append(Meter(key: "claude.budgetWeek.\(weekStart)", name: T("Claude 7일 예산", "Claude 7-day budget"),
                             percent: s.claudeWeek.cost / budgetWeek * 100, resetsAt: nil, source: T("로그 추정", "log estimate"), points: []))
        }
        return out
    }

    /// 새로 넘은 임계값·소진 예상 알림을 고른다 (이미 알린 것은 alerted에 있음)
    static func alerts(_ meters: [Meter], alerted: Set<String>, now: Date = Date()) -> [(key: String, title: String, subtitle: String, level: Double)] {
        var out: [(String, String, String, Double)] = []
        for m in meters {
            for t in [100.0, 80, 50] where m.percent >= t {
                let k = "\(m.key)|\(Int(t))"
                if !alerted.contains(k) {
                    let reset = m.resetsAt.map { T(" · 리셋 \(AIDevFormat.until($0, now: now))", " · resets \(AIDevFormat.until($0, now: now))") } ?? ""
                    out.append((k, T("\(m.name) \(Int(m.percent.rounded()))% 사용", "\(m.name) \(Int(m.percent.rounded()))% used"),
                                "\(m.source)\(reset)", t))
                }
                break
            }
            if m.percent < 100, let hit = UsageMath.projectedExhaustion(points: m.points, now: now, resetsAt: m.resetsAt) {
                let k = "\(m.key)|pace"
                if !alerted.contains(k) {
                    out.append((k, T("\(m.name): 지금 속도면 \(AIDevFormat.until(hit, now: now)) 바닥", "\(m.name): at this pace, exhausted \(AIDevFormat.until(hit, now: now))"),
                                T("\(m.source) · 현재 \(Int(m.percent.rounded()))%", "\(m.source) · now \(Int(m.percent.rounded()))%"), 90))
                }
            }
        }
        return out
    }

    private func evaluateAlerts(_ s: LocalUsageSummary) {
        let d = ModuleDefaults(module: id)
        guard d.bool("alerts", default: true), let context else { return }
        let ms = Self.meters(s, budget5h: d.double("budget5h", default: 0), budgetWeek: d.double("budgetWeek", default: 0))
        var alerted = Set(d.strings("alerted", default: []))
        // 리셋 알림: 80% 넘었던 창의 리셋 시각이 지나 새 창이 시작됨
        let previous = d.strings("highMeters", default: [])
        let nowHigh = ms.filter { $0.percent >= 80 }.map(\.key)
        for k in previous where k.hasPrefix("codex.") {
            // 같은 창(primary/secondary)의 새 리셋 시각이 보이면 리셋된 것 (값이 오래돼 사라진 경우는 제외)
            let prefix = k.split(separator: ".").prefix(2).joined(separator: ".") + "."
            if let m = ms.first(where: { $0.key.hasPrefix(prefix) && $0.key != k }) {
                context.notice(T("\(m.name) 한도가 리셋됐습니다", "\(m.name) limit reset"), T("계정 값 · 지금 \(Int(m.percent))%", "account · now \(Int(m.percent))%"),
                               symbol: "arrow.counterclockwise.circle", tab: id)
            }
        }
        d.set(nowHigh, "highMeters")
        let list = Self.alerts(ms, alerted: alerted)
        for a in list.prefix(2) {
            context.notice(a.title, a.subtitle, symbol: a.level >= 100 ? "exclamationmark.octagon.fill" : "gauge.with.dots.needle.67percent",
                           tint: a.level >= 80 ? .orange : .white, tab: id, duration: 6)
        }
        for a in list { alerted.insert(a.key) }
        if !list.isEmpty { d.set(Array(alerted.sorted().suffix(80)), "alerted") }
    }

    // MARK: 자체 검사 (실제 로그 읽기 전용)

    func selfTest() -> [String] {
        var out: [String] = []
        let t0 = Date()
        let s = LocalUsageModel.compute(claude: ClaudeLogScanner(), codex: CodexLogScanner())
        out.append("scanned \(s.filesScanned) files, \(s.bytesScanned / 1_000_000) MB in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s (read-only)")
        out.append("Claude today: \(AIDevFormat.tokens(s.claudeToday.tokens)) tok, \(AIDevFormat.usd(s.claudeToday.cost)) (API-rate estimate)")
        out.append("Claude 7 days: \(AIDevFormat.tokens(s.claudeWeek.tokens)) tok, \(AIDevFormat.usd(s.claudeWeek.cost)); top model \(s.claudeTopModel ?? "-"); unpriced models: \(s.claudeUnpriced)")
        if let b = s.claudeBlock {
            out.append("Claude current 5h block: \(AIDevFormat.clock(b.start))–\(AIDevFormat.clock(b.end)) \(AIDevFormat.tokens(b.tokens)) tok \(AIDevFormat.usd(b.cost)) (\(b.count) msgs); highest block 7d \(AIDevFormat.usd(s.claudeMaxBlockCost))")
        } else { out.append("Claude: no active 5h block") }
        out.append("Claude account (web login cache): \(s.claudeAccount.map { "\($0.windows.map { "\($0.label) \(Int($0.percent))%" }) fetched \(AIDevFormat.clock($0.fetched))" } ?? "none in this app's defaults")")
        out.append("Codex today: \(AIDevFormat.tokens(s.codexToday)) tok, 7 days \(AIDevFormat.tokens(s.codexWeek)) tok")
        if let snap = s.codexSnapshot {
            func w(_ x: CodexLimitSnapshot.Window?) -> String {
                x.map { "\(LocalUsageSummary.windowName($0.windowMinutes)) \(Int($0.usedPercent))% reset \($0.resetsAt.map { AIDevFormat.clock($0) } ?? "-")" } ?? "-"
            }
            out.append("Codex account snapshot \(AIDevFormat.clock(snap.time)): primary \(w(snap.primary)), secondary \(w(snap.secondary)), plan \(snap.plan ?? "-"), credits \(snap.creditsBalance.map { String(format: "%.0f", $0) } ?? "-")")
        } else { out.append("Codex: no rate-limit snapshot in the last 8 days") }
        let ms = Self.meters(s, budget5h: 0, budgetWeek: 0)
        out.append("meters with real percent: \(ms.map { "\($0.name) \(Int($0.percent))% [\($0.source)]" })")

        // 알림 논리 (가짜 값이 아니라 고정 입력으로 계산만 확인)
        let now = Date()
        let pts: [(Date, Double)] = [(now.addingTimeInterval(-1800), 60), (now.addingTimeInterval(-60), 75)]
        let m = Meter(key: "test", name: "Test", percent: 82, resetsAt: now.addingTimeInterval(4 * 3600), source: "test", points: pts)
        let a1 = Self.alerts([m], alerted: [], now: now)
        let a2 = Self.alerts([m], alerted: Set(a1.map(\.key)), now: now)
        out.append("\(a1.count == 2 && a1[0].level == 80 && a2.isEmpty ? "PASS" : "FAIL") alerts: 82% -> \(a1.map(\.title)); repeated -> \(a2.count)")
        let blocks = UsageMath.blocks([ClaudeUsageEntry(time: Date(timeIntervalSince1970: 3600 * 10 + 1200), model: "claude-opus-5-5", output: 1000),
                                       ClaudeUsageEntry(time: Date(timeIntervalSince1970: 3600 * 14 + 3000), model: "claude-opus-5-5", output: 1000),
                                       ClaudeUsageEntry(time: Date(timeIntervalSince1970: 3600 * 15 + 10), model: "claude-opus-5-5", output: 1000)])
        out.append("\(blocks.count == 2 && blocks[0].count == 2 ? "PASS" : "FAIL") 5h blocks start on the hour of the first message (\(blocks.count) blocks)")
        let price = ClaudePricing.cost(ClaudeUsageEntry(time: now, model: "claude-opus-5-5", input: 1_000_000, output: 1_000_000, cacheWrite5m: 1_000_000, cacheWrite1h: 0, cacheRead: 1_000_000)) ?? 0
        out.append("\(abs(price - (4 + 20 + 5 + 0.2)) < 0.001 ? "PASS" : "FAIL") pricing opus-5-5 1M each (in/out/5m write/read) = \(AIDevFormat.usd(price))")
        return out
    }
}

/// 화면에 쓰는 요약
struct LocalUsageSummary {
    var generated = Date()
    var claudeToday: (tokens: Int, cost: Double) = (0, 0)
    var claudeWeek: (tokens: Int, cost: Double) = (0, 0)
    var claudeBlock: UsageBlock?
    var claudeBlockPoints: [(Date, Double)] = []
    var claudeMaxBlockCost = 0.0
    var claudeTopModel: String?
    var claudeUnpriced = false
    var claudeAccount: ServiceUsage?
    var codexToday = 0
    var codexWeek = 0
    var codexSnapshot: CodexLimitSnapshot?
    var codexHistory: [CodexLimitSnapshot] = []
    var filesScanned = 0
    var bytesScanned: UInt64 = 0
    var hasClaudeLogs = false
    var hasCodexLogs = false

    static func windowName(_ minutes: Int) -> String {
        if minutes >= 6 * 1440 && minutes <= 8 * 1440 { return T("주간", "weekly") }
        if minutes > 0 && minutes <= 12 * 60 { return T("\(max(1, minutes / 60))시간", "\(max(1, minutes / 60))-hour") }
        return minutes > 0 ? T("\(minutes / 1440)일", "\(minutes / 1440)-day") : T("한도", "limit")
    }
}

final class LocalUsageModel: ObservableObject {
    @Published private(set) var summary: LocalUsageSummary?
    @Published private(set) var scanning = false
    var onUpdate: ((LocalUsageSummary) -> Void)?
    private let claude = ClaudeLogScanner()
    private let codex = CodexLogScanner()
    private let queue = DispatchQueue(label: "com.dynamicnotch.localusage", qos: .utility)

    func refresh() {
        guard !scanning else { return }
        scanning = true
        queue.async { [weak self] in
            guard let self else { return }
            let s = Self.compute(claude: self.claude, codex: self.codex)
            DispatchQueue.main.async {
                self.summary = s
                self.scanning = false
                self.onUpdate?(s)
            }
        }
    }

    /// 로그를 (덧붙은 부분만) 읽고 요약을 만든다. 백그라운드에서 부른다.
    static func compute(claude: ClaudeLogScanner, codex: CodexLogScanner, now: Date = Date()) -> LocalUsageSummary {
        let since = now.addingTimeInterval(-8 * 86400)
        claude.scan(since: since)
        codex.scan(since: since)
        var s = LocalUsageSummary(generated: now)
        let fm = FileManager.default
        s.hasClaudeLogs = fm.fileExists(atPath: claude.root.path)
        s.hasCodexLogs = fm.fileExists(atPath: codex.root.path)
        let startOfDay = Calendar.current.startOfDay(for: now)
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        let entries = Array(claude.entries.values)
        var byModel: [String: Double] = [:]
        for e in entries {
            if e.time >= weekAgo {
                s.claudeWeek.tokens += e.totalTokens
                s.claudeWeek.cost += e.cost
                byModel[e.model, default: 0] += Double(e.totalTokens)
                if !e.priced { s.claudeUnpriced = true }
            }
            if e.time >= startOfDay {
                s.claudeToday.tokens += e.totalTokens
                s.claudeToday.cost += e.cost
            }
        }
        s.claudeTopModel = byModel.max { $0.value < $1.value }?.key
        let blocks = UsageMath.blocks(entries.filter { $0.time >= weekAgo })
        s.claudeMaxBlockCost = blocks.map(\.cost).max() ?? 0
        if let last = blocks.last, last.end > now {
            s.claudeBlock = last
            var acc = 0.0
            s.claudeBlockPoints = entries.filter { $0.time >= last.start }.sorted { $0.time < $1.time }.map { acc += $0.cost; return ($0.time, acc) }
        }
        // 기존 웹 로그인 사용량(같은 앱 설정에 저장된 캐시)이 있으면 Claude 계정 값으로 같이 보여 준다
        if let data = UserDefaults.standard.data(forKey: "aiUsageCache"),
           let cache = try? JSONDecoder().decode([String: ServiceUsage].self, from: data),
           let c = cache["claude"], c.hasData {
            s.claudeAccount = c
        }
        for t in codex.tokens {
            if t.time >= weekAgo { s.codexWeek += t.total }
            if t.time >= startOfDay { s.codexToday += t.total }
        }
        s.codexSnapshot = codex.latest
        s.codexHistory = codex.snapshots.filter { now.timeIntervalSince($0.time) <= 3 * 3600 }
        s.filesScanned = claude.filesScanned + codex.filesScanned
        s.bytesScanned = claude.bytesScanned
        return s
    }
}

// MARK: - 탭

private struct LocalUsageTab: View {
    @ObservedObject var model: LocalUsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let s = model.summary {
                HStack(alignment: .top, spacing: 8) {
                    claudeColumn(s)
                    codexColumn(s)
                }
                HStack {
                    Text(T("토큰·비용은 로컬 로그 추정(API 요금 기준, 실제 청구 아님) · 계정 값은 서버가 준 마지막 값",
                           "Tokens & cost: local-log estimate (API rates, not your bill) · account values: last value from the server"))
                    Spacer()
                    Text(model.scanning ? T("읽는 중…", "Reading…") : T("갱신 \(AIDevFormat.clock(s.generated))", "Updated \(AIDevFormat.clock(s.generated))"))
                    Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).help(T("다시 읽기", "Refresh")).accessibilityLabel(T("다시 읽기", "Refresh"))
                }
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            } else {
                Spacer()
                HStack { Spacer(); ProgressView().controlSize(.small); Text(T("로컬 로그 읽는 중…", "Reading local logs…")).font(.system(size: 12)); Spacer() }
                Spacer()
            }
        }
        .foregroundStyle(.white)
        .onAppear { if model.summary == nil { model.refresh() } }
    }

    private func claudeColumn(_ s: LocalUsageSummary) -> some View {
        AIDevBox {
            VStack(alignment: .leading, spacing: 5) {
                header("Claude Code", AgentSource.claude.tint, s.claudeTopModel)
                if !s.hasClaudeLogs {
                    Text(T("~/.claude/projects 로그가 없습니다", "No logs in ~/.claude/projects")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                } else {
                    if let b = s.claudeBlock {
                        let budget = ModuleDefaults(module: "localusage").double("budget5h", default: 0)
                        meter(T("5시간 구간", "5-hour block"), percent: budget > 0 ? b.cost / budget * 100 : nil,
                              value: "\(AIDevFormat.usd(b.cost)) · \(AIDevFormat.tokens(b.tokens))",
                              note: T("로그 추정 · \(AIDevFormat.clock(b.end))에 끝남", "log estimate · ends \(AIDevFormat.clock(b.end))"))
                    } else {
                        line(T("5시간 구간", "5-hour block"), T("지금 진행 중인 구간 없음", "No active block"))
                    }
                    line(T("오늘", "Today"), "\(AIDevFormat.usd(s.claudeToday.cost)) · \(AIDevFormat.tokens(s.claudeToday.tokens))")
                    line(T("최근 7일", "Last 7 days"), "\(AIDevFormat.usd(s.claudeWeek.cost)) · \(AIDevFormat.tokens(s.claudeWeek.tokens))")
                    line(T("최고 5시간", "Top 5-hour"), AIDevFormat.usd(s.claudeMaxBlockCost))
                    if let acc = s.claudeAccount {
                        Text(T("계정(웹 로그인): ", "Account (web login): ") + acc.windows.map { "\($0.label) \(Int($0.percent))%" }.joined(separator: " · ")
                             + " · " + AIDevFormat.clock(acc.fetched))
                            .font(.system(size: 10.5)).foregroundStyle(.green.opacity(0.9)).lineLimit(1)
                    } else {
                        Text(T("실제 한도: 홈 'AI 사용량'에서 웹 로그인하면 함께 표시", "Real limits: sign in under Home → AI Usage to show them here"))
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(2)
                    }
                }
            }
        }
    }

    private func codexColumn(_ s: LocalUsageSummary) -> some View {
        AIDevBox {
            VStack(alignment: .leading, spacing: 5) {
                header("Codex", AgentSource.codex.tint, s.codexSnapshot?.plan.map { T("요금제 ", "plan ") + $0 })
                if !s.hasCodexLogs {
                    Text(T("~/.codex/sessions 로그가 없습니다", "No logs in ~/.codex/sessions")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                } else {
                    if let snap = s.codexSnapshot {
                        ForEach(Array([snap.primary, snap.secondary].compactMap { $0 }.enumerated()), id: \.offset) { _, w in
                            meter(LocalUsageSummary.windowName(w.windowMinutes).capitalized, percent: w.usedPercent, value: "\(Int(w.usedPercent.rounded()))%",
                                  note: T("계정 · ", "account · ") + (w.resetsAt.map { T("리셋 \(AIDevFormat.until($0))", "resets \(AIDevFormat.until($0))") } ?? "")
                                    + T(" · \(AIDevFormat.clock(snap.time)) 기준", " · as of \(AIDevFormat.clock(snap.time))"))
                        }
                        if let c = snap.creditsBalance {
                            line(T("크레딧", "Credits"), snap.unlimitedCredits ? T("무제한", "unlimited") : String(format: "%.0f", c))
                        }
                    } else {
                        line(T("한도", "Limits"), T("최근 8일 기록 없음", "none in the last 8 days"))
                    }
                    line(T("오늘", "Today"), AIDevFormat.tokens(s.codexToday) + T(" 토큰", " tok"))
                    line(T("최근 7일", "Last 7 days"), AIDevFormat.tokens(s.codexWeek) + T(" 토큰", " tok"))
                }
            }
        }
    }

    private func header(_ name: String, _ tint: Color, _ sub: String?) -> some View {
        HStack {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(name).font(.system(size: 12.5, weight: .semibold))
            Spacer()
            if let sub { Text(sub).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1) }
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value).font(.system(size: 11.5, design: .rounded)).monospacedDigit()
        }
    }

    private func meter(_ label: String, percent: Double?, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(value).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            if let p = percent {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(p >= 80 ? Color.orange : Color.white).frame(width: g.size.width * min(1, max(0, p / 100)))
                    }
                }
                .frame(height: 4)
            }
            Text(note).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
        }
    }
}

private struct LocalUsageSettings: View {
    @State private var budget5h = ModuleDefaults(module: "localusage").double("budget5h", default: 0)
    @State private var budgetWeek = ModuleDefaults(module: "localusage").double("budgetWeek", default: 0)
    @State private var alerts = ModuleDefaults(module: "localusage").bool("alerts", default: true)
    @State private var minutes = ModuleDefaults(module: "localusage").int("refreshMinutes", default: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(T("50·80·100% 도달, 소진 예상, 리셋 알림", "Alerts at 50/80/100 %, projected exhaustion and resets"), isOn: $alerts)
                .onChange(of: alerts) { _, v in ModuleDefaults(module: "localusage").set(v, "alerts") }
            HStack {
                Text(T("Claude 5시간 예산 (USD, 0이면 끔)", "Claude 5-hour budget (USD, 0 = off)"))
                TextField("0", value: $budget5h, format: .number).frame(width: 70)
                    .onSubmit { ModuleDefaults(module: "localusage").set(max(0, budget5h), "budget5h") }
            }
            HStack {
                Text(T("Claude 7일 예산 (USD, 0이면 끔)", "Claude 7-day budget (USD, 0 = off)"))
                TextField("0", value: $budgetWeek, format: .number).frame(width: 70)
                    .onSubmit { ModuleDefaults(module: "localusage").set(max(0, budgetWeek), "budgetWeek") }
            }
            Stepper(T("다시 읽는 간격: \(minutes)분", "Refresh every \(minutes) min"), value: $minutes, in: 2...60)
                .onChange(of: minutes) { _, v in ModuleDefaults(module: "localusage").set(v, "refreshMinutes") }
            Text(T("Claude Code는 로컬 로그만으로 실제 한도를 알 수 없어, 예산을 정하면 그 값 대비 %로 알립니다. Codex는 Codex가 로그에 남긴 서버 한도 값을 그대로 씁니다. 로그는 읽기만 합니다.",
                   "Claude Code's real limits aren't in local logs, so a budget you set is used for %. Codex uses the server limit values Codex wrote to its logs. Logs are only read."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

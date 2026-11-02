import AppKit
import SwiftUI

/// 주식: 관심 종목 검색·추가·삭제, 당일 5분봉 차트(전일 종가 기준선), 노치 티커(고정 종목 순환),
/// "이상·이하" 가격 알림(실제로 선을 넘을 때만), 마지막 갱신 시각과 장 구분.
/// 네트워크는 기능이 켜져 있고 탭이 보이거나 티커·가격 알림이 있을 때만 쓴다.
final class StocksModule: NotchModule {
    let id = "stocks"
    var title: String { T("주식", "Stocks") }
    let symbol = "chart.line.uptrend.xyaxis"
    var enabledByDefault: Bool { false }

    let model: StocksModel

    init() { model = StocksModel(defaults: ModuleDefaults(module: "stocks")) }

    func start(context: ModuleContext) { model.start(context: context, tab: id) }
    func stop() { model.stop() }
    func settingsChanged() { model.reloadSettings() }

    func tabView() -> AnyView? { AnyView(StocksTab(model: model)) }
    var tabContentSize: CGSize { CGSize(width: 620, height: 290) }

    func paletteActions() -> [PaletteAction] {
        model.items.map { item in
            let q = model.quotes[item.symbol]
            return PaletteAction(id: "stocks.\(item.symbol)", title: "\(item.symbol) " + (q.map { $0.priceText() } ?? ""),
                                 subtitle: q.map { "\($0.changeText) · \($0.session.label)" } ?? item.name,
                                 symbol: symbol, keywords: ["stock", "주식", item.name]) { [weak self] in
                guard let self else { return }
                self.model.selected = item.symbol
                self.model.context?.openTab(self.id)
            }
        }
    }

    func settingsView() -> AnyView? { AnyView(StocksSettings(model: model)) }

    func selfTest() -> [String] {
        var lines: [String] = []
        let sem = DispatchSemaphore(value: 0)
        // 네트워크 응답은 메인 큐로 오므로 런루프를 돌리며 기다린다
        func wait() {
            let deadline = Date().addingTimeInterval(12)
            while sem.wait(timeout: .now()) == .timedOut, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        StocksAPI.search("Apple") { r in
            switch r {
            case .success(let list): lines.append("search 'Apple': " + list.prefix(4).map { "\($0.symbol) (\($0.exchange), \($0.type))" }.joined(separator: ", "))
            case .failure(let e): lines.append("search failed: \(e)")
            }
            sem.signal()
        }
        wait()
        StocksAPI.chart("AAPL") { r in
            switch r {
            case .success(let q):
                lines.append("AAPL \(q.priceText()) prev close \(q.priceText(q.previousClose)) \(q.changeText) session \(q.session.rawValue) market time \(q.marketTime) points \(q.closes.count) exchange \(q.exchange)")
            case .failure(let e): lines.append("chart failed: \(e)")
            }
            sem.signal()
        }
        wait()
        lines.append("watchlist \(model.items.map(\.symbol).joined(separator: ",")) (stored locally)")
        // 노치 티커: 저장하지 않는 임시 목록으로 실제 시세를 받아 상시 표시가 만들어지는지
        let center = ActivityCenter()
        let probe = StocksModel(defaults: ModuleDefaults(module: "stocks.selftest"))
        probe.start(context: ModuleContext(center: center, openTab: { _ in }, collapse: {}, focusInput: {}), tab: id)
        probe.selfTestUse([StockItem(symbol: "AAPL", name: "Apple Inc.", exchange: "NASDAQ", pinned: true),
                           StockItem(symbol: "MSFT", name: "Microsoft", exchange: "NASDAQ", pinned: true)])
        let deadline = Date().addingTimeInterval(12)
        while probe.lastUpdate == nil, probe.status == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        if let a = center.persistent[.stocks] {
            lines.append("ticker persistent: value \(a.value) title \(a.title ?? "-") subtitle \(a.subtitle ?? "-")")
        } else { lines.append("ticker persistent: none (status \(probe.status ?? "-"))") }
        probe.stop()
        lines.append("after stop: ticker removed \(center.persistent[.stocks] == nil)")
        // 알림 판정 논리 점검 (가격 데이터가 아니라 규칙 확인용 숫자)
        let up = StockAlert(above: true, price: 100), down = StockAlert(above: false, price: 100)
        let cases = [StocksModel.crossed(up, from: 99, to: 100), !StocksModel.crossed(up, from: 101, to: 102), !StocksModel.crossed(up, from: 100, to: 101),
                     StocksModel.crossed(down, from: 101, to: 99.5), !StocksModel.crossed(down, from: 99, to: 98)]
        lines.append("alert crossing rule check: \(cases.allSatisfy { $0 } ? "pass" : "FAIL") (\(cases.filter { $0 }.count)/\(cases.count))")
        return lines
    }
}

struct StockAlert: Codable, Identifiable, Equatable {
    var id = UUID()
    var above: Bool
    var price: Double
    var lastFired: Date?
}

struct StockItem: Codable, Identifiable, Equatable {
    var id: String { symbol }
    var symbol: String
    var name: String
    var exchange: String
    var monitored = true
    var pinned = false
    var alerts: [StockAlert] = []
}

final class StocksModel: ObservableObject {
    @Published var items: [StockItem] = []
    @Published var quotes: [String: StockQuote] = [:]
    @Published var lastUpdate: Date?
    @Published var status: String?
    @Published var results: [StockSearchResult] = []
    @Published var searching = false
    @Published var selected: String?
    @Published var tabVisible = false { didSet { schedule(); if tabVisible { refresh() } } }

    let defaults: ModuleDefaults
    private(set) var context: ModuleContext?
    private var tabID = "stocks"
    private var refreshTimer: Timer?
    private var tickerTimer: Timer?
    private var tickerIndex = 0
    private var tasks: [URLSessionDataTask] = []
    private var searchTask: URLSessionDataTask?
    private var lastPrice: [String: Double] = [:]
    private var running = false

    var showTicker: Bool { defaults.bool("ticker", default: true) }
    var tickerSeconds: Double { defaults.double("tickerSeconds", default: 5) }
    var refreshMinutes: Double { defaults.double("refreshMinutes", default: 1) }

    init(defaults: ModuleDefaults) {
        self.defaults = defaults
        load()
    }

    // MARK: 저장

    private func load() {
        if let data = defaults.data("watchlist"), let list = try? JSONDecoder().decode([StockItem].self, from: data) { items = list }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, "watchlist") }
    }

    // MARK: 시작·정지

    func start(context: ModuleContext, tab: String) {
        self.context = context
        tabID = tab
        running = true
        load()
        schedule()
        if needsNetwork { refresh() }
    }

    func stop() {
        running = false
        refreshTimer?.invalidate(); refreshTimer = nil
        tickerTimer?.invalidate(); tickerTimer = nil
        tasks.forEach { $0.cancel() }; tasks.removeAll()
        searchTask?.cancel(); searchTask = nil
        context?.center.removePersistent(.stocks)
        context = nil
    }

    func reloadSettings() {
        load()
        schedule()
        updateTicker()
    }

    /// 탭이 보이거나, 노치 티커에 고정 종목이 있거나, 가격 알림이 걸려 있을 때만 시세를 받는다
    private var needsNetwork: Bool {
        guard running else { return false }
        if tabVisible { return !items.isEmpty }
        let watched = items.filter(\.monitored)
        return (showTicker && watched.contains { $0.pinned }) || watched.contains { !$0.alerts.isEmpty }
    }

    private func schedule() {
        guard running, needsNetwork else {
            refreshTimer?.invalidate(); refreshTimer = nil
            updateTicker()
            return
        }
        if refreshTimer == nil {
            let t = Timer(timeInterval: max(60, refreshMinutes * 60), repeats: true) { [weak self] _ in self?.timerFired() }
            t.tolerance = 10
            RunLoop.main.add(t, forMode: .common)
            refreshTimer = t
        }
        updateTicker()
    }

    private func timerFired() {
        // 장이 모두 닫혀 있고 탭도 안 보이면 15분에 한 번만
        let allClosed = !quotes.isEmpty && quotes.values.allSatisfy { $0.session == .closed }
        if allClosed, !tabVisible, let last = lastUpdate, Date().timeIntervalSince(last) < 15 * 60 { return }
        refresh()
    }

    func refresh() {
        guard running else { return }
        var symbols = items.filter(\.monitored).map(\.symbol)
        if tabVisible, let s = selected, !symbols.contains(s) { symbols.append(s) }
        guard !symbols.isEmpty else { return }
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        var pending = symbols.count
        var failed = 0
        for s in symbols {
            if let t = StocksAPI.chart(s, completion: { [weak self] r in
                guard let self, self.running else { return }
                switch r {
                case .success(let q): self.accept(q, for: s)
                case .failure: failed += 1
                }
                pending -= 1
                if pending == 0 {
                    if failed == symbols.count {
                        self.status = T("시세를 받을 수 없음 (인터넷 연결 또는 Yahoo Finance 응답 확인)", "Market data unavailable (check the connection or Yahoo Finance)")
                    } else {
                        self.status = failed > 0 ? T("일부 종목 시세를 받지 못함", "Some quotes could not be loaded") : nil
                        self.lastUpdate = Date()
                    }
                    self.updateTicker()
                }
            }) { tasks.append(t) }
        }
    }

    private func accept(_ q: StockQuote, for symbol: String) {
        quotes[symbol] = q
        checkAlerts(symbol, q)
        lastPrice[symbol] = q.price
    }

    // MARK: 가격 알림 (선을 넘을 때만, 같은 알림은 30분에 한 번)

    private func checkAlerts(_ symbol: String, _ q: StockQuote) {
        guard let prev = lastPrice[symbol], let i = items.firstIndex(where: { $0.symbol == symbol }), items[i].monitored else { return }
        var changed = false
        for (j, a) in items[i].alerts.enumerated() {
            guard Self.crossed(a, from: prev, to: q.price) else { continue }
            if let f = a.lastFired, Date().timeIntervalSince(f) < 1800 { continue }
            items[i].alerts[j].lastFired = Date()
            changed = true
            context?.center.post(NotchActivity(
                kind: .stocks, priority: ActivityPriority.info, presentation: .detail, duration: 6,
                symbol: a.above ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill", tint: a.above ? .green : .red,
                value: .text(q.priceText()),
                title: a.above ? T("\(symbol) \(q.priceText(a.price)) 넘음", "\(symbol) rose above \(q.priceText(a.price))")
                               : T("\(symbol) \(q.priceText(a.price)) 아래로", "\(symbol) fell below \(q.priceText(a.price))"),
                subtitle: "\(q.name) · \(q.priceText()) (\(q.changeText))",
                valueTint: a.above ? .green : .red, moduleTab: tabID))
        }
        if changed { save() }
    }

    /// 이전 가격에서 새 가격으로 가며 알림 선을 실제로 넘었는지
    static func crossed(_ a: StockAlert, from prev: Double, to new: Double) -> Bool {
        a.above ? (prev < a.price && new >= a.price) : (prev > a.price && new <= a.price)
    }

    // MARK: 노치 티커

    private func updateTicker() {
        let pinned = items.filter { $0.pinned && $0.monitored }
        guard running, showTicker, !pinned.isEmpty else {
            tickerTimer?.invalidate(); tickerTimer = nil
            context?.center.removePersistent(.stocks)
            return
        }
        postTicker()
        if pinned.count > 1, tickerTimer == nil {
            let t = Timer(timeInterval: max(3, tickerSeconds), repeats: true) { [weak self] _ in
                self?.tickerIndex += 1
                self?.postTicker()
            }
            t.tolerance = 0.5
            RunLoop.main.add(t, forMode: .common)
            tickerTimer = t
        } else if pinned.count <= 1 {
            tickerTimer?.invalidate(); tickerTimer = nil
        }
    }

    private func postTicker() {
        let pinned = items.filter { $0.pinned && $0.monitored }
        guard !pinned.isEmpty, let context else { return }
        let item = pinned[tickerIndex % pinned.count]
        guard let q = quotes[item.symbol] else {
            context.center.setPersistent(NotchActivity(kind: .stocks, priority: ActivityPriority.pinned, symbol: "chart.line.uptrend.xyaxis",
                                                       value: .labeledText(label: item.symbol, text: "…"), title: item.name,
                                                       subtitle: status ?? T("시세 받는 중", "Loading quote"), moduleTab: tabID))
            return
        }
        let open = q.session != .closed
        let color: Color = !open ? .white.opacity(0.6) : (q.isUp ? .green : .red)
        context.center.setPersistent(NotchActivity(
            kind: .stocks, priority: ActivityPriority.pinned,
            symbol: q.isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill", tint: color,
            value: .labeledText(label: item.symbol, text: q.changeText),
            title: "\(q.name) · \(item.symbol)",
            subtitle: "\(q.priceText()) \(q.isUp ? "▲" : "▼") \(q.changeText) · \(q.session.label)",
            detailValue: .text(q.priceText()), valueTint: color, moduleTab: tabID))
    }

    // MARK: 관심 목록

    func search(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespaces)
        searchTask?.cancel()
        guard running, q.count >= 1 else { results = []; searching = false; return }
        searching = true
        searchTask = StocksAPI.search(q) { [weak self] r in
            self?.searching = false
            switch r {
            case .success(let list): self?.results = list; self?.status = list.isEmpty ? T("검색 결과 없음", "No results") : nil
            case .failure: self?.results = []; self?.status = T("검색할 수 없음 (인터넷 연결 확인)", "Search unavailable (check the connection)")
            }
        }
    }

    func add(_ r: StockSearchResult) {
        guard !items.contains(where: { $0.symbol == r.symbol }) else { selected = r.symbol; return }
        items.append(StockItem(symbol: r.symbol, name: r.name, exchange: r.exchange))
        selected = r.symbol
        results = []
        save()
        schedule()
        refresh()
    }

    func remove(_ symbol: String) {
        items.removeAll { $0.symbol == symbol }
        quotes[symbol] = nil
        lastPrice[symbol] = nil
        if selected == symbol { selected = items.first?.symbol }
        save()
        schedule()
    }

    func update(_ symbol: String, _ change: (inout StockItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.symbol == symbol }) else { return }
        change(&items[i])
        save()
        schedule()
    }

    /// 자체 검사용: 저장하지 않고 이 목록으로 시세를 받아 티커를 만든다
    func selfTestUse(_ list: [StockItem]) {
        items = list
        schedule()
        refresh()
    }

    func addAlert(_ symbol: String, above: Bool, price: Double) {
        update(symbol) { $0.alerts.append(StockAlert(above: above, price: price)) }
        if let q = quotes[symbol] { lastPrice[symbol] = q.price }
        refresh()
    }
}

// MARK: - 탭

private struct StocksTab: View {
    @ObservedObject var model: StocksModel
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            listColumn.frame(width: 236)
            detailColumn
        }
        .foregroundStyle(.white)
        .onAppear {
            if model.selected == nil { model.selected = model.items.first?.symbol }
            model.tabVisible = true
            if model.items.isEmpty { model.context?.focusInput(); focused = true }
        }
        .onDisappear { model.tabVisible = false }
    }

    private var listColumn: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                TextField(T("회사명·티커 (예: Apple, BTC-USD)", "Company or ticker (e.g. Apple, BTC-USD)"), text: $query)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .focused($focused)
                    .onSubmit { model.search(query) }
                    .simultaneousGesture(TapGesture().onEnded { model.context?.focusInput(); focused = true })
                if model.searching { ProgressView().controlSize(.mini) }
                if !query.isEmpty {
                    Button { query = ""; model.results = [] } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5)).help(T("지우기", "Clear"))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
            ScrollView {
                VStack(spacing: 2) {
                    if !model.results.isEmpty {
                        ForEach(model.results) { r in
                            Button { model.add(r); query = "" } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(r.symbol).font(.system(size: 12, weight: .semibold))
                                        Text(r.name).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                                    }
                                    Spacer()
                                    Text("\(r.exchange) · \(r.type)").font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                                    Image(systemName: "plus.circle").font(.system(size: 12))
                                }
                                .padding(6).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(T("관심 목록에 추가", "Add to watchlist"))
                        }
                    } else if model.items.isEmpty {
                        Text(T("검색해서 관심 종목을 추가하세요. 해외 종목·지수·ETF·암호화폐를 지원합니다.", "Search to add stocks. Stocks, indices, ETFs and crypto are supported."))
                            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).padding(.top, 10)
                    } else {
                        ForEach(model.items) { item in row(item) }
                    }
                }
            }
            if let s = model.status {
                Text(s).font(.system(size: 9.5)).foregroundStyle(.orange.opacity(0.9)).lineLimit(2)
            }
        }
    }

    private func row(_ item: StockItem) -> some View {
        let q = model.quotes[item.symbol]
        let sel = model.selected == item.symbol
        return Button { model.selected = item.symbol } label: {
            HStack(spacing: 6) {
                StockLetterTile(symbol: item.symbol).frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(item.symbol).font(.system(size: 11.5, weight: .semibold))
                        if item.pinned { Image(systemName: "pin.fill").font(.system(size: 7)).foregroundStyle(.white.opacity(0.5)) }
                        if !item.monitored { Image(systemName: "pause.fill").font(.system(size: 7)).foregroundStyle(.white.opacity(0.5)) }
                    }
                    Text(item.name).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 2)
                if let q {
                    StockSparkline(quote: q).frame(width: 34, height: 18)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(q.priceText()).font(.system(size: 11, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        Text(q.changeText).font(.system(size: 9.5, design: .rounded)).monospacedDigit()
                            .foregroundStyle(StockColors.tint(q))
                    }
                } else {
                    Text("–").foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(sel ? 0.12 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let sym = model.selected, let item = model.items.first(where: { $0.symbol == sym }) {
            StockDetail(model: model, item: item, quote: model.quotes[sym])
        } else {
            SysCard {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 26)).foregroundStyle(.white.opacity(0.3))
                    Text(T("종목을 고르면 당일 차트를 보여 줍니다", "Pick a stock to see today's chart"))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    Text(T("시세: Yahoo Finance", "Quotes: Yahoo Finance")).font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

enum StockColors {
    /// 장외 시간에는 중립색
    static func tint(_ q: StockQuote) -> Color {
        q.session == .closed ? .white.opacity(0.6) : (q.isUp ? .green : .red)
    }
}

/// 회사 로고 대신 이 Mac에서 그리는 글자 타일 (로고 서비스 미사용)
private struct StockLetterTile: View {
    let symbol: String
    var body: some View {
        let hue = Double(symbol.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 360 }) / 360   // 실행마다 같은 색
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(hue: hue, saturation: 0.45, brightness: 0.55))
            .overlay(Text(String(symbol.prefix(1))).font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
            .accessibilityHidden(true)
    }
}

private struct StockSparkline: View {
    let quote: StockQuote
    var body: some View {
        StockChartShape(values: quote.closes, baseline: quote.previousClose)
            .stroke(StockColors.tint(quote), lineWidth: 1.2)
    }
}

/// 당일 선 (기준선을 함께 넣어 범위를 정한다)
private struct StockChartShape: Shape {
    let values: [Double]
    let baseline: Double

    static func range(_ values: [Double], _ baseline: Double) -> (Double, Double) {
        let lo = min(values.min() ?? baseline, baseline), hi = max(values.max() ?? baseline, baseline)
        return hi - lo < 1e-9 ? (lo - 1, hi + 1) : (lo, hi)
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard values.count > 1 else { return p }
        let (lo, hi) = Self.range(values, baseline)
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1),
                             y: rect.maxY - rect.height * CGFloat((v - lo) / (hi - lo)))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

private struct StockDetail: View {
    @ObservedObject var model: StocksModel
    let item: StockItem
    let quote: StockQuote?
    @State private var alertAbove = true
    @State private var alertPrice = ""
    @State private var confirmRemove = false

    var body: some View {
        SysCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(quote?.name ?? item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text([item.symbol, quote?.exchange ?? item.exchange, quote?.currency].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    }
                    Spacer()
                    if let q = quote {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(q.priceText()).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text("\(q.isUp ? "▲" : "▼") \(q.priceText(abs(q.change))) (\(q.changeText))")
                                .font(.system(size: 10, design: .rounded)).monospacedDigit().foregroundStyle(StockColors.tint(q))
                        }
                    }
                }
                chart.frame(height: 116)
                HStack(spacing: 6) {
                    if let q = quote {
                        Text(q.session.label).font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(q.session == .regular ? Color.green.opacity(0.25) : Color.white.opacity(0.12)))
                    }
                    if let u = model.lastUpdate {
                        Text(T("갱신 \(SysFmt.time(u))", "Updated \(SysFmt.time(u))")).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    SysPillButton(title: item.pinned ? T("노치 고정됨", "Pinned") : T("노치에 고정", "Pin to notch"),
                                  symbol: item.pinned ? "pin.fill" : "pin") { model.update(item.symbol) { $0.pinned.toggle() } }
                    SysPillButton(title: item.monitored ? T("감시 중", "Watching") : T("감시 멈춤", "Paused"),
                                  symbol: item.monitored ? "eye" : "eye.slash",
                                  help: T("끄면 종목과 알림은 남기고 시세 받기만 멈춥니다", "Off keeps the stock and alerts but stops fetching")) {
                        model.update(item.symbol) { $0.monitored.toggle() }
                    }
                    if confirmRemove {
                        SysPillButton(title: T("삭제", "Remove"), tint: .red, prominent: true) { model.remove(item.symbol); confirmRemove = false }
                        SysPillButton(title: T("취소", "Cancel")) { confirmRemove = false }
                    } else {
                        SysPillButton(title: "", symbol: "trash", help: T("종목과 알림 삭제", "Remove stock and alerts")) { confirmRemove = true }
                    }
                }
                alertsRow
            }
        }
        .onChange(of: item.symbol) { _ in confirmRemove = false; alertPrice = "" }
    }

    @ViewBuilder
    private var chart: some View {
        if let q = quote, q.closes.count > 1 {
            GeometryReader { geo in
                let (lo, hi) = StockChartShape.range(q.closes, q.previousClose)
                let by = geo.size.height - geo.size.height * CGFloat((q.previousClose - lo) / (hi - lo))
                let last = q.closes.last ?? q.price
                let ly = geo.size.height - geo.size.height * CGFloat((last - lo) / (hi - lo))
                // 정규장 전체(6.5시간 = 78칸) 기준으로 지금까지 그린 폭
                let frac = q.session == .regular ? min(1, CGFloat(q.closes.count) / 78) : 1
                ZStack(alignment: .topLeading) {
                    Path { p in p.move(to: CGPoint(x: 0, y: by)); p.addLine(to: CGPoint(x: geo.size.width, y: by)) }
                        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    StockChartShape(values: q.closes, baseline: q.previousClose)
                        .stroke(StockColors.tint(q), lineWidth: 1.6)
                        .frame(width: geo.size.width * frac)
                    Circle().fill(StockColors.tint(q)).frame(width: 6, height: 6)
                        .position(x: geo.size.width * frac, y: ly)
                }
                .overlay(alignment: .topLeading) {
                    Text(T("┄ 전일 종가 \(q.priceText(q.previousClose))", "┄ Prev close \(q.priceText(q.previousClose))"))
                        .font(.system(size: 8.5)).foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                }
            }
            .accessibilityLabel(T("당일 가격 차트", "Intraday price chart"))
        } else {
            Text(quote == nil ? (model.status ?? T("시세 받는 중…", "Loading…")) : T("오늘 거래 데이터 없음", "No trades today"))
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var alertsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "bell").font(.system(size: 10))
                Text(T("가격이", "Alert when price is")).font(.system(size: 10.5))
                Picker("", selection: $alertAbove) {
                    Text(T("이상", "above")).tag(true)
                    Text(T("이하", "below")).tag(false)
                }
                .labelsHidden().pickerStyle(.segmented).controlSize(.mini).frame(width: 90)
                TextField(quote.map { $0.priceText() } ?? "0.00", text: $alertPrice)
                    .textFieldStyle(.plain).font(.system(size: 11)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.1)))
                    .frame(width: 80)
                    .simultaneousGesture(TapGesture().onEnded { model.context?.focusInput() })
                    .onSubmit(addAlert)
                SysPillButton(title: T("추가", "Add"), symbol: "plus") { addAlert() }
                Spacer()
            }
            if !item.alerts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(item.alerts) { a in
                            HStack(spacing: 3) {
                                Text((a.above ? "≥ " : "≤ ") + (quote?.priceText(a.price) ?? String(format: "%.2f", a.price)))
                                    .font(.system(size: 10, design: .rounded)).monospacedDigit()
                                Button { model.update(item.symbol) { $0.alerts.removeAll { $0.id == a.id } } } label: {
                                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                                }
                                .buttonStyle(.plain).help(T("알림 지우기", "Delete alert"))
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                    }
                }
            }
        }
    }

    private func addAlert() {
        // 통화 기호·쉼표는 빼고 숫자와 소수점만
        let text = String(alertPrice.filter { $0.isNumber || $0 == "." })
        guard let v = Double(text), v > 0 else { return }
        model.addAlert(item.symbol, above: alertAbove, price: v)
        alertPrice = ""
    }
}

private struct StocksSettings: View {
    @ObservedObject var model: StocksModel
    @State private var ticker = true
    @State private var seconds = 5.0
    @State private var minutes = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(T("노치 티커: 고정한 종목을 접힌 노치에서 순환", "Notch ticker: cycle pinned stocks in the collapsed notch"), isOn: $ticker)
                .onChange(of: ticker) { model.defaults.set($0, "ticker") }
            HStack {
                Text(T("순환 간격", "Cycle every"))
                Slider(value: $seconds, in: 3...15, step: 1).frame(width: 160)
                    .onChange(of: seconds) { model.defaults.set($0, "tickerSeconds") }
                Text("\(Int(seconds))s").monospacedDigit()
            }
            Picker(T("시세 갱신", "Refresh quotes"), selection: $minutes) {
                Text(T("1분", "1 min")).tag(1.0); Text(T("2분", "2 min")).tag(2.0); Text(T("5분", "5 min")).tag(5.0)
            }
            .frame(width: 240)
            .onChange(of: minutes) { model.defaults.set($0, "refreshMinutes") }
            SysUnsupported(title: T("회사 로고: 보류", "Company logos: deferred"),
                           reason: T("로고를 받을 회사 웹사이트 주소를 얻을 공개 출처가 없습니다(Yahoo 회사 정보는 세션 쿠키가 필요). 그래서 이 Mac에서 그린 글자 타일을 씁니다.",
                                     "There is no public source for each company's website (Yahoo's profile endpoint needs a session cookie), so letter tiles drawn on this Mac are used."),
                           symbol: "building.2")
            Text(T("시세 출처: Yahoo Finance (query1.finance.yahoo.com). 종목 기호만 보내고 계정은 필요 없습니다. 탭이 보이거나, 노치에 고정한 종목·가격 알림이 있을 때만 시세를 받으며, 장이 모두 닫히면 15분에 한 번으로 줄입니다.",
                   "Quotes from Yahoo Finance (query1.finance.yahoo.com). Only ticker symbols are sent and no account is needed. Quotes are fetched only while the tab is visible or a pinned stock or price alert exists, and every 15 minutes when all markets are closed."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            ticker = model.showTicker
            seconds = model.tickerSeconds
            minutes = model.refreshMinutes
        }
    }
}

import Foundation

/// 시세 출처: Yahoo Finance 공개 엔드포인트 (계정 불필요, 공식 API 아님).
///   검색  https://query1.finance.yahoo.com/v1/finance/search?q=<검색어>
///   차트  https://query1.finance.yahoo.com/v8/finance/chart/<종목>?interval=5m&range=1d
/// 요청 머리에는 이 앱 이름을 그대로 쓴다. 종목 기호 외에 사용자 정보는 보내지 않는다.

struct StockSearchResult: Identifiable, Equatable {
    var id: String { symbol }
    var symbol: String
    var name: String
    var exchange: String
    var type: String
}

enum MarketSession: String {
    case pre, regular, post, closed

    var label: String {
        switch self {
        case .pre: return T("장전", "Pre-market")
        case .regular: return T("정규장", "Market open")
        case .post: return T("장후", "After hours")
        case .closed: return T("휴장", "Closed")
        }
    }
}

struct StockQuote: Equatable {
    var symbol: String
    var name: String
    var currency: String
    var exchange: String
    var price: Double
    var previousClose: Double
    var marketTime: Date
    var session: MarketSession
    var times: [Date]
    var closes: [Double]

    var change: Double { price - previousClose }
    var changePercent: Double { previousClose != 0 ? change / previousClose * 100 : 0 }
    var isUp: Bool { change >= 0 }

    func priceText(_ value: Double? = nil) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        let v = value ?? price
        // 통화별 기본 소수 자리(USD 2, KRW·JPY 0)를 따르고, 2보다 작은 값(암호화폐 등)만 4자리
        if v < 2 { f.maximumFractionDigits = 4 }
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    var changeText: String {
        String(format: "%@%.2f%%", change >= 0 ? "+" : "−", abs(changePercent))
    }
}

enum StocksAPI {
    enum Failure: Error { case network, badResponse(Int), noData }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCache = nil
        return URLSession(configuration: c)
    }()

    private static var userAgent: String {
        "DynamicNotch/" + ((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1")
    }

    private static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return r
    }

    @discardableResult
    static func search(_ query: String, completion: @escaping (Result<[StockSearchResult], Failure>) -> Void) -> URLSessionDataTask? {
        var c = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")!
        c.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "quotesCount", value: "8"),
                        URLQueryItem(name: "newsCount", value: "0"), URLQueryItem(name: "listsCount", value: "0")]
        guard let url = c.url else { return nil }
        let task = session.dataTask(with: request(url)) { data, response, error in
            let result: Result<[StockSearchResult], Failure>
            if error != nil { result = .failure(.network) }
            else if let code = (response as? HTTPURLResponse)?.statusCode, code != 200 { result = .failure(.badResponse(code)) }
            else if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let quotes = json["quotes"] as? [[String: Any]] {
                result = .success(quotes.compactMap { q in
                    guard let s = q["symbol"] as? String else { return nil }
                    return StockSearchResult(symbol: s, name: (q["longname"] as? String) ?? (q["shortname"] as? String) ?? s,
                                             exchange: (q["exchDisp"] as? String) ?? (q["exchange"] as? String) ?? "",
                                             type: (q["typeDisp"] as? String) ?? (q["quoteType"] as? String) ?? "")
                })
            } else { result = .failure(.noData) }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
        return task
    }

    @discardableResult
    static func chart(_ symbol: String, completion: @escaping (Result<StockQuote, Failure>) -> Void) -> URLSessionDataTask? {
        let enc = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?interval=5m&range=1d") else { return nil }
        let task = session.dataTask(with: request(url)) { data, response, error in
            let result: Result<StockQuote, Failure>
            if error != nil { result = .failure(.network) }
            else if let code = (response as? HTTPURLResponse)?.statusCode, code != 200 { result = .failure(.badResponse(code)) }
            else if let data, let q = parseChart(data, symbol: symbol) { result = .success(q) }
            else { result = .failure(.noData) }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
        return task
    }

    static func parseChart(_ data: Data, symbol: String, now: Date = Date()) -> StockQuote? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = json["chart"] as? [String: Any],
              let r = (chart["result"] as? [[String: Any]])?.first,
              let meta = r["meta"] as? [String: Any],
              let price = (meta["regularMarketPrice"] as? NSNumber)?.doubleValue else { return nil }
        let prev = (meta["chartPreviousClose"] as? NSNumber)?.doubleValue ?? (meta["previousClose"] as? NSNumber)?.doubleValue ?? price
        let stamps = (r["timestamp"] as? [NSNumber]) ?? []
        let quote = ((r["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first
        let rawCloses = (quote?["close"] as? [Any]) ?? []
        var times: [Date] = [], closes: [Double] = []
        for (i, t) in stamps.enumerated() where i < rawCloses.count {
            guard let c = (rawCloses[i] as? NSNumber)?.doubleValue else { continue }   // 빈 칸(null)은 건너뜀
            times.append(Date(timeIntervalSince1970: t.doubleValue))
            closes.append(c)
        }
        let marketTime = Date(timeIntervalSince1970: (meta["regularMarketTime"] as? NSNumber)?.doubleValue ?? now.timeIntervalSince1970)
        let type = (meta["instrumentType"] as? String) ?? ""
        return StockQuote(symbol: (meta["symbol"] as? String) ?? symbol,
                          name: (meta["longName"] as? String) ?? (meta["shortName"] as? String) ?? symbol,
                          currency: (meta["currency"] as? String) ?? "USD",
                          exchange: (meta["fullExchangeName"] as? String) ?? (meta["exchangeName"] as? String) ?? "",
                          price: price, previousClose: prev, marketTime: marketTime,
                          session: type == "CRYPTOCURRENCY" ? .regular : session(meta, now: now),
                          times: times, closes: closes)
    }

    /// currentTradingPeriod(pre·regular·post)의 시작·끝으로 지금 장 구분을 정한다
    private static func session(_ meta: [String: Any], now: Date) -> MarketSession {
        guard let p = meta["currentTradingPeriod"] as? [String: Any] else { return .closed }
        let t = now.timeIntervalSince1970
        func inside(_ key: String) -> Bool {
            guard let d = p[key] as? [String: Any], let s = (d["start"] as? NSNumber)?.doubleValue,
                  let e = (d["end"] as? NSNumber)?.doubleValue else { return false }
            return t >= s && t < e
        }
        if inside("regular") { return .regular }
        if inside("pre") { return .pre }
        if inside("post") { return .post }
        return .closed
    }
}

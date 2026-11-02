import Foundation

/// "90 f to c", "5 km in mi", "50 usd in eur" 같은 변환식을 해석한다.
/// 숫자 부분은 계산기를 먼저 거친다 (괄호·퍼센트·함수·ans 사용 가능).
enum UnitConvert {
    struct Query: Equatable {
        let amount: Double
        let from: String    // 단위 키 또는 통화 코드
        let to: String
        let isCurrency: Bool
    }

    struct UnitInfo {
        let category: String
        let unit: Dimension
        let symbol: String
    }

    /// 구분자: to, in, ->, →, =, 에서 ~로 (예: "10km 마일로" 는 지원 안 함, "10 km to mi" 형태)
    static func parse(_ text: String, ans: Double? = nil) -> Query? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.count <= 120 else { return nil }
        let lower = t.lowercased()
        let separators = [" to ", " in ", " -> ", " → ", " = ", " into "]
        for sep in separators {
            guard let r = lower.range(of: sep, options: .backwards) else { continue }
            let left = String(lower[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(lower[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard let target = normalize(right) else { continue }
            guard let (amount, source) = splitAmount(left, ans: ans) else { continue }
            if let fromCur = currencyCode(source), let toCur = currencyCode(target) {
                return Query(amount: amount, from: fromCur, to: toCur, isCurrency: true)
            }
            if let a = units[source], let b = units[target], a.category == b.category {
                return Query(amount: amount, from: source, to: target, isCurrency: false)
            }
        }
        return nil
    }

    /// 단위 변환 결과 (통화 제외)
    static func convert(_ q: Query) -> Double? {
        guard !q.isCurrency, let a = units[q.from], let b = units[q.to], a.category == b.category else { return nil }
        let base = a.unit.converter.baseUnitValue(fromValue: q.amount)
        let v = b.unit.converter.value(fromBaseUnitValue: base)
        return v.isFinite ? v : nil
    }

    static func symbol(_ key: String) -> String { units[key]?.symbol ?? key.uppercased() }

    // MARK: 내부

    /// 왼쪽을 "숫자식 + 단위"로 나눈다. 단위는 끝의 낱말(공백 또는 숫자 뒤 붙여 쓴 글자).
    private static func splitAmount(_ left: String, ans: Double?) -> (Double, String)? {
        // 끝에서부터 단위로 해석되는 가장 긴 꼬리를 찾는다 ("100 sq m", "5km", "$50" 등)
        if let first = left.first, let code = currencySymbolPrefix[first] {
            let rest = String(left.dropFirst()).trimmingCharacters(in: .whitespaces)
            if let v = CalcEngine.evaluate(rest, ans: ans) { return (v, code.lowercased()) }
        }
        let words = left.split(separator: " ").map(String.init)
        for take in stride(from: min(3, words.count - 1), through: 1, by: -1) {
            let unitPart = words.suffix(take).joined(separator: " ")
            let numPart = words.dropLast(take).joined(separator: " ")
            if let key = normalize(unitPart), let v = CalcEngine.evaluate(numPart, ans: ans) { return (v, key) }
        }
        // 붙여 쓴 경우: "5km", "90f", "50usd"
        var idx = left.endIndex
        while idx > left.startIndex {
            let prev = left.index(before: idx)
            if left[prev].isLetter || "°′″$€£¥₩²³/".contains(left[prev]) { idx = prev } else { break }
        }
        guard idx > left.startIndex, idx < left.endIndex else { return nil }
        let num = String(left[..<idx]).trimmingCharacters(in: .whitespaces)
        let unit = String(left[idx...])
        if let key = normalize(unit), let v = CalcEngine.evaluate(num, ans: ans) { return (v, key) }
        return nil
    }

    /// 단위 별칭 → 표 키 (통화면 소문자 코드)
    private static func normalize(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        if units[s] != nil { return s }
        if let k = aliases[s] { return k }
        if let c = currencyCode(s) { return c.lowercased() }
        // 복수형 s 떼기
        if s.hasSuffix("s"), let k = aliases[String(s.dropLast())] ?? (units[String(s.dropLast())] != nil ? String(s.dropLast()) : nil) { return k }
        return nil
    }

    // MARK: 통화

    static let currencyCodes: Set<String> = [
        "AUD", "BGN", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD", "HUF", "IDR", "ILS", "INR", "ISK",
        "JPY", "KRW", "MXN", "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR",
    ]
    private static let currencyAliases: [String: String] = [
        "$": "USD", "dollar": "USD", "dollars": "USD", "달러": "USD", "불": "USD",
        "€": "EUR", "euro": "EUR", "euros": "EUR", "유로": "EUR",
        "£": "GBP", "pound": "GBP", "pounds": "GBP", "파운드": "GBP",
        "¥": "JPY", "yen": "JPY", "엔": "JPY", "엔화": "JPY",
        "₩": "KRW", "won": "KRW", "원": "KRW", "원화": "KRW",
        "yuan": "CNY", "rmb": "CNY", "위안": "CNY", "위안화": "CNY",
        "franc": "CHF", "francs": "CHF", "프랑": "CHF",
    ]
    private static let currencySymbolPrefix: [Character: String] = ["$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₩": "KRW"]

    static func currencyCode(_ s: String) -> String? {
        let u = s.uppercased()
        if currencyCodes.contains(u) { return u }
        return currencyAliases[s.lowercased()]
    }

    // MARK: 단위 표

    private static let units: [String: UnitInfo] = {
        var m: [String: UnitInfo] = [:]
        func add(_ key: String, _ cat: String, _ unit: Dimension, _ symbol: String) { m[key] = UnitInfo(category: cat, unit: unit, symbol: symbol) }
        // 길이
        add("m", "length", UnitLength.meters, "m"); add("km", "length", UnitLength.kilometers, "km")
        add("cm", "length", UnitLength.centimeters, "cm"); add("mm", "length", UnitLength.millimeters, "mm")
        add("um", "length", UnitLength.micrometers, "µm"); add("nm", "length", UnitLength.nanometers, "nm")
        add("mi", "length", UnitLength.miles, "mi"); add("yd", "length", UnitLength.yards, "yd")
        add("ft", "length", UnitLength.feet, "ft"); add("in", "length", UnitLength.inches, "in")
        add("nmi", "length", UnitLength.nauticalMiles, "nmi"); add("ly", "length", UnitLength.lightyears, "ly")
        // 질량
        add("kg", "mass", UnitMass.kilograms, "kg"); add("g", "mass", UnitMass.grams, "g")
        add("mg", "mass", UnitMass.milligrams, "mg"); add("t", "mass", UnitMass.metricTons, "t")
        add("lb", "mass", UnitMass.pounds, "lb"); add("oz", "mass", UnitMass.ounces, "oz")
        add("st", "mass", UnitMass.stones, "st"); add("ct", "mass", UnitMass.carats, "ct")
        // 온도
        add("c", "temp", UnitTemperature.celsius, "°C"); add("f", "temp", UnitTemperature.fahrenheit, "°F")
        add("k", "temp", UnitTemperature.kelvin, "K")
        // 부피
        add("l", "volume", UnitVolume.liters, "L"); add("ml", "volume", UnitVolume.milliliters, "mL")
        add("gal", "volume", UnitVolume.gallons, "gal"); add("qt", "volume", UnitVolume.quarts, "qt")
        add("pt", "volume", UnitVolume.pints, "pt"); add("cup", "volume", UnitVolume.cups, "cup")
        add("floz", "volume", UnitVolume.fluidOunces, "fl oz"); add("tbsp", "volume", UnitVolume.tablespoons, "tbsp")
        add("tsp", "volume", UnitVolume.teaspoons, "tsp"); add("m3", "volume", UnitVolume.cubicMeters, "m³")
        // 넓이
        add("m2", "area", UnitArea.squareMeters, "m²"); add("km2", "area", UnitArea.squareKilometers, "km²")
        add("ft2", "area", UnitArea.squareFeet, "ft²"); add("acre", "area", UnitArea.acres, "ac")
        add("ha", "area", UnitArea.hectares, "ha"); add("mi2", "area", UnitArea.squareMiles, "mi²")
        add("pyeong", "area", UnitArea(symbol: "평", converter: UnitConverterLinear(coefficient: 400.0 / 121.0)), "평")
        // 속도
        add("kmh", "speed", UnitSpeed.kilometersPerHour, "km/h"); add("mph", "speed", UnitSpeed.milesPerHour, "mph")
        add("mps", "speed", UnitSpeed.metersPerSecond, "m/s"); add("kn", "speed", UnitSpeed.knots, "kn")
        // 시간
        add("msec", "time", UnitDuration.milliseconds, "ms"); add("sec", "time", UnitDuration.seconds, "s"); add("min", "time", UnitDuration.minutes, "min")
        add("h", "time", UnitDuration.hours, "h")
        add("day", "time", UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86400)), "d")
        add("week", "time", UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604800)), "wk")
        // 데이터
        add("b", "data", UnitInformationStorage.bytes, "B"); add("kb", "data", UnitInformationStorage.kilobytes, "KB")
        add("mb", "data", UnitInformationStorage.megabytes, "MB"); add("gb", "data", UnitInformationStorage.gigabytes, "GB")
        add("tb", "data", UnitInformationStorage.terabytes, "TB"); add("kib", "data", UnitInformationStorage.kibibytes, "KiB")
        add("mib", "data", UnitInformationStorage.mebibytes, "MiB"); add("gib", "data", UnitInformationStorage.gibibytes, "GiB")
        add("bit", "data", UnitInformationStorage.bits, "bit")
        // 에너지
        add("j", "energy", UnitEnergy.joules, "J"); add("kj", "energy", UnitEnergy.kilojoules, "kJ")
        add("cal", "energy", UnitEnergy.calories, "cal"); add("kcal", "energy", UnitEnergy.kilocalories, "kcal")
        add("kwh", "energy", UnitEnergy.kilowattHours, "kWh")
        // 압력
        add("pa", "pressure", UnitPressure.newtonsPerMetersSquared, "Pa"); add("kpa", "pressure", UnitPressure.kilopascals, "kPa")
        add("bar", "pressure", UnitPressure.bars, "bar"); add("psi", "pressure", UnitPressure.poundsForcePerSquareInch, "psi")
        add("atm", "pressure", UnitPressure(symbol: "atm", converter: UnitConverterLinear(coefficient: 101325)), "atm")
        add("mmhg", "pressure", UnitPressure.millimetersOfMercury, "mmHg"); add("hpa", "pressure", UnitPressure.hectopascals, "hPa")
        // 각도
        add("deg", "angle", UnitAngle.degrees, "°"); add("rad", "angle", UnitAngle.radians, "rad")
        add("grad", "angle", UnitAngle.gradians, "grad"); add("rev", "angle", UnitAngle.revolutions, "rev")
        return m
    }()

    private static let aliases: [String: String] = [
        "meter": "m", "metre": "m", "미터": "m", "kilometer": "km", "kilometre": "km", "킬로미터": "km", "키로": "km",
        "centimeter": "cm", "센티": "cm", "센티미터": "cm", "millimeter": "mm", "밀리": "mm", "밀리미터": "mm",
        "µm": "um", "micrometer": "um", "nanometer": "nm",
        "mile": "mi", "마일": "mi", "yard": "yd", "야드": "yd", "foot": "ft", "feet": "ft", "피트": "ft",
        "inch": "in", "inches": "in", "인치": "in", "\"": "in", "'": "ft", "lightyear": "ly",
        "kilogram": "kg", "kilo": "kg", "킬로그램": "kg", "gram": "g", "그램": "g", "milligram": "mg",
        "ton": "t", "tonne": "t", "톤": "t", "pound": "lb", "lbs": "lb", "파운드": "lb", "ounce": "oz", "온스": "oz",
        "stone": "st", "carat": "ct", "캐럿": "ct",
        "°c": "c", "celsius": "c", "섭씨": "c", "°f": "f", "fahrenheit": "f", "화씨": "f", "kelvin": "k", "켈빈": "k",
        "liter": "l", "litre": "l", "리터": "l", "milliliter": "ml", "millilitre": "ml", "gallon": "gal", "갤런": "gal",
        "quart": "qt", "pint": "pt", "cups": "cup", "컵": "cup", "fl oz": "floz", "fluid ounce": "floz",
        "tablespoon": "tbsp", "teaspoon": "tsp", "m³": "m3", "cubic meter": "m3",
        "m²": "m2", "sqm": "m2", "sq m": "m2", "square meter": "m2", "제곱미터": "m2", "km²": "km2", "sq km": "km2",
        "ft²": "ft2", "sqft": "ft2", "sq ft": "ft2", "square feet": "ft2", "acres": "acre", "에이커": "acre",
        "hectare": "ha", "헥타르": "ha", "mi²": "mi2", "sq mi": "mi2", "평": "pyeong",
        "km/h": "kmh", "kph": "kmh", "m/s": "mps", "ms": "msec", "millisecond": "msec", "milliseconds": "msec", "knot": "kn", "knots": "kn", "노트": "kn", "시속": "kmh",
        "s": "sec", "second": "sec", "seconds": "sec", "초": "sec", "minute": "min", "minutes": "min", "mins": "min", "분": "min",
        "hour": "h", "hours": "h", "hr": "h", "hrs": "h", "시간": "h", "days": "day", "d": "day", "일": "day",
        "weeks": "week", "wk": "week", "주": "week",
        "byte": "b", "bytes": "b", "kilobyte": "kb", "megabyte": "mb", "gigabyte": "gb", "terabyte": "tb", "bits": "bit",
        "joule": "j", "joules": "j", "calorie": "cal", "calories": "cal", "kilocalorie": "kcal", "칼로리": "kcal",
        "pascal": "pa", "atmosphere": "atm", "기압": "atm",
        "degree": "deg", "degrees": "deg", "°": "deg", "도": "deg", "radian": "rad", "radians": "rad",
    ]
}

/// 공개 환율(frankfurter.app, 유럽중앙은행 기준값). 통화 변환식을 입력했을 때만 받고 12시간 보관한다.
final class CurrencyRates {
    static let shared = CurrencyRates()
    static let endpoint = URL(string: "https://api.frankfurter.app/latest")!
    static let maxAge: TimeInterval = 12 * 3600

    private let defaults = ModuleDefaults(module: "calculator")
    private(set) var rates: [String: Double] = [:]   // EUR 기준
    private(set) var sourceDate: String?
    private(set) var fetchedAt: Date?
    private(set) var lastError: String?
    private(set) var loading = false
    private var task: URLSessionDataTask?
    private var waiters: [() -> Void] = []
    private var lastAttempt: Date?

    private init() { loadCache() }

    var isFresh: Bool { fetchedAt.map { Date().timeIntervalSince($0) < Self.maxAge } ?? false }

    /// 금액 변환. 환율이 없으면 nil.
    func convert(_ amount: Double, from: String, to: String) -> Double? {
        let r = rates.merging(["EUR": 1]) { a, _ in a }
        guard let a = r[from], let b = r[to], a > 0 else { return nil }
        return amount / a * b
    }

    /// 오래됐거나 없으면 받는다. 끝나면 done(메인 스레드).
    func refreshIfNeeded(done: (() -> Void)? = nil) {
        if isFresh { done?(); return }
        // 실패 직후 1분은 다시 받지 않는다 (화면이 다시 그려질 때마다 요청하지 않게)
        if !loading, lastError != nil, let t = lastAttempt, Date().timeIntervalSince(t) < 60 { return }
        if let done { waiters.append(done) }
        guard !loading else { return }
        loading = true
        lastAttempt = Date()
        lastError = nil
        let session = URLSession(configuration: .ephemeral, delegate: RedirectGuard(), delegateQueue: nil)
        var req = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        task = session.dataTask(with: req) { [weak self] data, response, error in
            let parsed = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                self.task = nil
                if let parsed, let r = parsed["rates"] as? [String: Double], !r.isEmpty {
                    self.rates = r
                    self.sourceDate = parsed["date"] as? String
                    self.fetchedAt = Date()
                    self.saveCache()
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode
                    self.lastError = error?.localizedDescription ?? T("응답을 읽을 수 없음", "Unreadable response") + (code.map { " (\($0))" } ?? "")
                }
                let w = self.waiters
                self.waiters = []
                w.forEach { $0() }
            }
            session.finishTasksAndInvalidate()
        }
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        loading = false
        waiters = []
    }

    /// "2026-10-30 기준 · 3시간 전 받음"
    var statusText: String {
        if loading { return T("환율 받는 중…", "Fetching rates…") }
        if let lastError, rates.isEmpty { return T("환율을 받지 못함: ", "Could not fetch rates: ") + lastError }
        guard let fetchedAt else { return T("환율 없음", "No rates yet") }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        let ago = f.localizedString(for: fetchedAt, relativeTo: Date())
        let stale = isFresh ? "" : T(" · 오래됨", " · stale")
        return T("ECB 환율 \(sourceDate ?? "?") 기준 · \(ago) 받음", "ECB rates of \(sourceDate ?? "?") · fetched \(ago)") + stale
            + (lastError != nil ? T(" · 갱신 실패", " · refresh failed") : "")
    }

    private func loadCache() {
        guard let d = defaults.data("rates"),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let r = obj["rates"] as? [String: Double], let t = obj["fetchedAt"] as? Double else { return }
        rates = r
        sourceDate = obj["date"] as? String
        fetchedAt = Date(timeIntervalSince1970: t)
    }

    private func saveCache() {
        let obj: [String: Any] = ["rates": rates, "date": sourceDate ?? "", "fetchedAt": fetchedAt?.timeIntervalSince1970 ?? 0]
        if let d = try? JSONSerialization.data(withJSONObject: obj) {
            UserDefaults.standard.set(d, forKey: "module.calculator.rates")   // 알림 없이 저장 (설정 변경 아님)
        }
    }

    /// frankfurter.app → frankfurter.dev 이동만 따라간다
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            let host = request.url?.host?.lowercased() ?? ""
            let ok = request.url?.scheme == "https" && (host.hasSuffix("frankfurter.app") || host.hasSuffix("frankfurter.dev"))
            completionHandler(ok ? request : nil)
        }
    }
}

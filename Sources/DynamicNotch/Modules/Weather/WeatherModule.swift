import AppKit
import CoreLocation
import SwiftUI

/// 날씨 (Open-Meteo, 계정·키 불필요): 현재 기온·상태, 시간별, 7일 최고·최저·자외선·강수.
/// 도시를 직접 고르면 위치 권한 없이 쓰고, '현재 위치'를 고를 때만 위치 권한을 묻는다.
/// 켜져 있는 동안 최대 30분에 한 번만 받아 온다. 네트워크를 써서 처음에는 꺼져 있다.
final class WeatherModule: NotchModule {
    let id = "weather"
    var title: String { T("날씨", "Weather") }
    let symbol = "cloud.sun"
    let enabledByDefault = false

    /// 홈·팔레트가 쓸 수 있는 짧은 요약이 바뀌면 알린다 (object: WxSummary)
    static let summaryChanged = Notification.Name("com.dynamicnotch.module.weather.summaryChanged")
    /// 마지막 요약 (본 앱 프로세스, 기능이 켜져 있을 때만)
    private(set) static var latestSummary: WxSummary?

    let model = WeatherModel()
    private var context: ModuleContext?

    func start(context: ModuleContext) {
        guard self.context == nil else { return }
        self.context = context
        model.onSummary = { s in
            WeatherModule.latestSummary = s
            NotificationCenter.default.post(name: WeatherModule.summaryChanged, object: s)
        }
        model.start(background: !AppSettings.isHelper)
        // 개발용: 화면 그리기 모드에서 DMN_WX_TEST_CITY로 준 도시를 저장하지 않고 쓴다
        if AppSettings.isHelper, let city = ProcessInfo.processInfo.environment["DMN_WX_TEST_CITY"] {
            WxAPI.geocode(city) { [weak self] r in
                if case .success(let list) = r, let p = list.first { self?.model.devPlace = p }
            }
        }
    }

    func stop() {
        model.stop()
        WeatherModule.latestSummary = nil
        NotificationCenter.default.post(name: WeatherModule.summaryChanged, object: nil)
        context = nil
    }

    func settingsChanged() { model.settingsChanged() }

    func tabView() -> AnyView? { AnyView(WeatherTab(model: model)) }

    /// 홈 대시보드 카드 (켜져 있을 때만)
    func homeCard() -> AnyView? {
        guard context != nil else { return nil }
        return AnyView(WeatherHomeCard(model: model))
    }

    /// 잠금 화면 카드용 현재 값. 꺼져 있거나 아직 받지 못했으면 nil.
    func lockCardWeather() -> LCWeather? {
        guard context != nil, let f = model.forecast else { return nil }
        let fahrenheit = model.unit == "f"
        return LCWeather(temperature: fahrenheit ? f.current.temp * 9 / 5 + 32 : f.current.temp,
                         unit: fahrenheit ? "°F" : "°C",
                         symbol: WxCode.symbol(f.current.code, isDay: f.current.isDay),
                         summary: WxCode.text(f.current.code), place: model.placeName, updated: f.fetched)
    }
    var tabContentSize: CGSize { CGSize(width: 600, height: 250) }

    func paletteActions() -> [PaletteAction] {
        guard let s = model.summary else {
            return [PaletteAction(id: "weather.open", title: T("날씨 열기", "Open Weather"), symbol: symbol,
                                  keywords: ["weather", "날씨", "forecast", "예보"]) { [weak self] in self?.context?.openTab("weather") }]
        }
        return [PaletteAction(id: "weather.now", title: T("날씨: \(s.line)", "Weather: \(s.line)"), subtitle: s.detail, symbol: s.symbol,
                              keywords: ["weather", "날씨", "forecast", "예보", "기온", "temperature"]) { [weak self] in
            self?.context?.openTab("weather")
        }]
    }

    func settingsView() -> AnyView? { AnyView(WeatherSettings()) }

    /// 실제 Open-Meteo 요청 (지오코딩 + 예보 한 번씩). 설정·화면은 바꾸지 않는다.
    func selfTest() -> [String] {
        var lines: [String] = []
        var place: WxPlace?
        var finished = false
        WxAPI.geocode("Seoul") { r in
            switch r {
            case .success(let list):
                place = list.first
                lines.append("geocoding 'Seoul': \(list.count) results, first \(list.first.map { "\($0.name), \($0.detail) (\(String(format: "%.2f", $0.lat)), \(String(format: "%.2f", $0.lon)))" } ?? "-")")
            case .failure(let e): lines.append("geocoding failed: \(e.localizedDescription)")
            }
            finished = true
        }
        PIMWait.until(timeout: 20) { finished }
        if let place {
            finished = false
            WxAPI.forecast(lat: place.lat, lon: place.lon) { r in
                switch r {
                case .success(let f):
                    let today = f.daily.first
                    lines.append("forecast: now \(f.current.temp)°C code \(f.current.code) (\(WxCode.text(f.current.code))), feels \(f.current.feels)°C, humidity \(Int(f.current.humidity))%, hourly \(f.hourly.count), daily \(f.daily.count)")
                    lines.append("today: hi \(today?.hi ?? .nan) lo \(today?.lo ?? .nan) uv \(today?.uv ?? .nan) precip \(today?.precip ?? .nan)mm pop \(today?.pop ?? -1)%, tz \(f.timezone)")
                case .failure(let e): lines.append("forecast failed: \(e.localizedDescription)")
                }
                finished = true
            }
            PIMWait.until(timeout: 20) { finished }
        }
        lines.append("configured mode: \(model.mode), place: \(model.place?.name ?? "none"), unit: \(model.unit)")
        lines.append("location permission (not asking): \(WxLocator.statusText(CLLocationManager().authorizationStatus))")
        lines.append("°F conversion 20°C → \(WeatherModel.format(20, unit: "f"))")
        return lines
    }
}

/// 홈·팔레트용 짧은 요약
struct WxSummary: Equatable {
    var place: String
    var temperature: String
    var condition: String
    var symbol: String
    var high: String
    var low: String
    var line: String { "\(place) \(temperature) \(condition)" }
    var detail: String { T("최고 \(high) · 최저 \(low)", "High \(high) · Low \(low)") }
}

struct WxPlace: Codable, Equatable {
    var name: String
    var detail: String
    var lat: Double
    var lon: Double
}

struct WxForecast: Codable, Equatable {
    struct Current: Codable, Equatable {
        var temp: Double
        var feels: Double
        var code: Int
        var isDay: Bool
        var wind: Double
        var humidity: Double
        var precip: Double
    }
    struct Hour: Codable, Equatable {
        var time: Date
        var temp: Double
        var code: Int
        var pop: Int?
        var isDay: Bool
    }
    struct Day: Codable, Equatable {
        var date: Date
        var code: Int
        var hi: Double
        var lo: Double
        var uv: Double?
        var precip: Double?
        var pop: Int?
    }
    var fetched: Date
    var lat: Double
    var lon: Double
    var timezone: String
    var current: Current
    var hourly: [Hour]
    var daily: [Day]
}

// MARK: - Open-Meteo

enum WxAPI {
    static func geocode(_ name: String, completion: @escaping (Result<[WxPlace], Error>) -> Void) {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "count", value: "8"),
                        URLQueryItem(name: "language", value: L10n.isEnglish ? "en" : "ko"), URLQueryItem(name: "format", value: "json")]
        get(c.url!) { r in
            completion(r.flatMap { data in
                struct Res: Decodable {
                    struct Item: Decodable { var name: String; var latitude: Double; var longitude: Double; var country: String?; var admin1: String? }
                    var results: [Item]?
                }
                guard let res = try? JSONDecoder().decode(Res.self, from: data) else { return .failure(URLError(.cannotParseResponse)) }
                return .success((res.results ?? []).map { i in
                    WxPlace(name: i.name, detail: [i.admin1, i.country].compactMap { $0 }.filter { $0 != i.name }.joined(separator: ", "),
                            lat: i.latitude, lon: i.longitude)
                })
            })
        }
    }

    @discardableResult
    static func forecast(lat: Double, lon: Double, completion: @escaping (Result<WxForecast, Error>) -> Void) -> URLSessionTask? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", lon)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m,precipitation"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,uv_index_max,precipitation_sum,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "forecast_hours", value: "24"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        return get(c.url!) { r in
            completion(r.flatMap { data in
                guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return .failure(URLError(.cannotParseResponse)) }
                return .success(raw.forecast(lat: lat, lon: lon))
            })
        }
    }

    @discardableResult
    private static func get(_ url: URL, completion: @escaping (Result<Data, Error>) -> Void) -> URLSessionTask {
        let task = URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 20)) { data, resp, error in
            let result: Result<Data, Error>
            if let error { result = .failure(error) }
            else if let code = (resp as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) { result = .failure(URLError(.badServerResponse)) }
            else { result = .success(data ?? Data()) }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
        return task
    }

    private struct Raw: Decodable {
        struct Current: Decodable {
            var temperature_2m: Double
            var apparent_temperature: Double?
            var weather_code: Int
            var is_day: Int?
            var wind_speed_10m: Double?
            var relative_humidity_2m: Double?
            var precipitation: Double?
        }
        struct Hourly: Decodable {
            var time: [Double]
            var temperature_2m: [Double?]
            var weather_code: [Int?]
            var precipitation_probability: [Int?]?
            var is_day: [Int?]?
        }
        struct Daily: Decodable {
            var time: [Double]
            var weather_code: [Int?]
            var temperature_2m_max: [Double?]
            var temperature_2m_min: [Double?]
            var uv_index_max: [Double?]?
            var precipitation_sum: [Double?]?
            var precipitation_probability_max: [Int?]?
        }
        var timezone: String?
        var current: Current
        var hourly: Hourly
        var daily: Daily

        func forecast(lat: Double, lon: Double) -> WxForecast {
            let cur = WxForecast.Current(temp: current.temperature_2m, feels: current.apparent_temperature ?? current.temperature_2m,
                                         code: current.weather_code, isDay: (current.is_day ?? 1) == 1,
                                         wind: current.wind_speed_10m ?? 0, humidity: current.relative_humidity_2m ?? 0,
                                         precip: current.precipitation ?? 0)
            var hours: [WxForecast.Hour] = []
            for (i, t) in hourly.time.enumerated() {
                guard let temp = hourly.temperature_2m.wxAt(i) ?? nil, let code = hourly.weather_code.wxAt(i) ?? nil else { continue }
                hours.append(WxForecast.Hour(time: Date(timeIntervalSince1970: t), temp: temp, code: code,
                                             pop: hourly.precipitation_probability?.wxAt(i) ?? nil,
                                             isDay: ((hourly.is_day?.wxAt(i) ?? nil) ?? 1) == 1))
            }
            var days: [WxForecast.Day] = []
            for (i, t) in daily.time.enumerated() {
                guard let hi = daily.temperature_2m_max.wxAt(i) ?? nil, let lo = daily.temperature_2m_min.wxAt(i) ?? nil else { continue }
                days.append(WxForecast.Day(date: Date(timeIntervalSince1970: t), code: (daily.weather_code.wxAt(i) ?? nil) ?? 0,
                                           hi: hi, lo: lo, uv: daily.uv_index_max?.wxAt(i) ?? nil,
                                           precip: daily.precipitation_sum?.wxAt(i) ?? nil,
                                           pop: daily.precipitation_probability_max?.wxAt(i) ?? nil))
            }
            return WxForecast(fetched: Date(), lat: lat, lon: lon, timezone: timezone ?? TimeZone.current.identifier,
                              current: cur, hourly: hours, daily: days)
        }
    }
}

private extension Array {
    func wxAt(_ i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - 날씨 코드 (WMO)

enum WxCode {
    static func text(_ code: Int) -> String {
        switch code {
        case 0: return T("맑음", "Clear")
        case 1: return T("대체로 맑음", "Mostly Clear")
        case 2: return T("구름 조금", "Partly Cloudy")
        case 3: return T("흐림", "Overcast")
        case 45, 48: return T("안개", "Fog")
        case 51, 53, 55: return T("이슬비", "Drizzle")
        case 56, 57: return T("어는 이슬비", "Freezing Drizzle")
        case 61, 63: return T("비", "Rain")
        case 65: return T("강한 비", "Heavy Rain")
        case 66, 67: return T("어는 비", "Freezing Rain")
        case 71, 73: return T("눈", "Snow")
        case 75: return T("폭설", "Heavy Snow")
        case 77: return T("싸락눈", "Snow Grains")
        case 80, 81: return T("소나기", "Showers")
        case 82: return T("강한 소나기", "Heavy Showers")
        case 85, 86: return T("눈 소나기", "Snow Showers")
        case 95: return T("뇌우", "Thunderstorm")
        case 96, 99: return T("우박 뇌우", "Thunderstorm with Hail")
        default: return T("알 수 없음", "Unknown")
        }
    }

    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: return isDay ? "sun.max.fill" : "moon.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57, 66, 67: return "cloud.sleet.fill"
        case 61, 63: return "cloud.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    /// 하늘 배경색 (위 → 아래)
    static func sky(_ code: Int, isDay: Bool) -> [Color] {
        func c(_ hex: String) -> Color { PIMColor.color(hex: hex) }
        switch code {
        case 0, 1: return isDay ? [c("#2F80ED"), c("#56CCF2")] : [c("#0B1026"), c("#2B3A67")]
        case 2: return isDay ? [c("#3A7BD5"), c("#8FB3D9")] : [c("#141E30"), c("#35445C")]
        case 3, 45, 48: return isDay ? [c("#5D6D7E"), c("#8E9BA8")] : [c("#1C2331"), c("#3B4A5A")]
        case 71...77, 85, 86: return isDay ? [c("#7F8C9D"), c("#B8C2CC")] : [c("#2C3440"), c("#56606C")]
        case 95...99: return [c("#232526"), c("#414345")]
        default: return isDay ? [c("#34495E"), c("#5D6D7E")] : [c("#141A22"), c("#2E3A46")]
        }
    }
}

// MARK: - 현재 위치 (고를 때만)

final class WxLocator: NSObject, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    var onLocation: ((CLLocation) -> Void)?
    var onStatus: ((CLAuthorizationStatus) -> Void)?
    var onError: ((String) -> Void)?

    var status: CLAuthorizationStatus { manager?.authorizationStatus ?? CLLocationManager().authorizationStatus }

    static func isAuthorized(_ s: CLAuthorizationStatus) -> Bool {
        s != .notDetermined && s != .denied && s != .restricted
    }

    static func statusText(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        default: return "authorized"
        }
    }

    /// ask가 true일 때만(사용자가 '현재 위치'를 고르거나 허용을 누를 때) 권한을 묻는다
    func locate(ask: Bool) {
        if manager == nil {
            let m = CLLocationManager()
            m.desiredAccuracy = kCLLocationAccuracyKilometer
            m.delegate = self
            manager = m
        }
        guard let m = manager else { return }
        switch m.authorizationStatus {
        case .notDetermined: if ask { m.requestWhenInUseAuthorization() }
        case .denied, .restricted: onStatus?(m.authorizationStatus)
        default: m.requestLocation()
        }
    }

    func stop() {
        manager?.stopUpdatingLocation()
        manager?.delegate = nil
        manager = nil
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        onStatus?(m.authorizationStatus)
        if Self.isAuthorized(m.authorizationStatus) { m.requestLocation() }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let l = locations.last { onLocation?(l) }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        onError?(error.localizedDescription)
    }
}

// MARK: - 모델

final class WeatherModel: ObservableObject {
    @Published private(set) var forecast: WxForecast?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    var onSummary: ((WxSummary?) -> Void)?

    let defaults = ModuleDefaults(module: "weather")
    private var timer: Timer?
    private var task: URLSessionTask?
    private var locator: WxLocator?
    private var wakeObserver: NSObjectProtocol?
    private var running = false
    private var currentCoord: (lat: Double, lon: Double)?

    var mode: String { defaults.string("mode", default: "city") }
    var unit: String { defaults.string("unit", default: L10n.isEnglish && Locale.current.measurementSystem == .us ? "f" : "c") }
    var sky: Bool { defaults.bool("sky", default: true) }
    var place: WxPlace? { devPlace ?? defaults.data("place").flatMap { try? JSONDecoder().decode(WxPlace.self, from: $0) } }
    /// 개발용 (저장하지 않는 도시)
    var devPlace: WxPlace? {
        didSet { objectWillChange.send(); fetchIfStale() }
    }

    var placeName: String {
        mode == "current" ? T("현재 위치", "Current Location") : (place?.name ?? "")
    }

    /// 지금 쓸 좌표 (현재 위치는 받아 온 뒤에만)
    private var coordinate: (lat: Double, lon: Double)? {
        if mode == "current" { return currentCoord }
        return place.map { ($0.lat, $0.lon) }
    }

    var summary: WxSummary? {
        guard let f = forecast else { return nil }
        let today = f.daily.first
        return WxSummary(place: placeName, temperature: Self.format(f.current.temp, unit: unit), condition: WxCode.text(f.current.code),
                         symbol: WxCode.symbol(f.current.code, isDay: f.current.isDay),
                         high: today.map { Self.format($0.hi, unit: unit) } ?? "–", low: today.map { Self.format($0.lo, unit: unit) } ?? "–")
    }

    static func format(_ celsius: Double, unit: String) -> String {
        let v = unit == "f" ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(v.rounded()))°"
    }

    func start(background: Bool) {
        guard !running else { return }
        running = true
        // 같은 곳을 30분 안에 받았으면 저장본을 쓴다
        if let cached = PIMFiles.read(WxForecast.self, "weather.json") { forecast = cached }
        if mode == "current" {
            if mode == "current", let f = forecast { currentCoord = (f.lat, f.lon) }
            startLocator(ask: false)
        }
        fetchIfStale()
        publishSummary()
        guard background else { return }
        let t = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in self?.refreshTick() }
        t.tolerance = 120
        RunLoop.main.add(t, forMode: .common)
        timer = t
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshTick()
        }
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
        locator?.stop()
        locator = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        loading = false
    }

    func settingsChanged() {
        guard running else { return }
        if mode == "current" {
            // 사용자가 방금 '현재 위치'를 골랐다면 이때 권한을 묻는다
            startLocator(ask: defaults.double("locationAsk", default: 0) > Date().timeIntervalSince1970 - 30)
        } else {
            locator?.stop()
            locator = nil
            currentCoord = nil
        }
        fetchIfStale()
        publishSummary()
        objectWillChange.send()
    }

    private func refreshTick() {
        if mode == "current" { locator?.locate(ask: false) }
        fetchIfStale()
    }

    private func startLocator(ask: Bool) {
        if locator == nil {
            let l = WxLocator()
            l.onLocation = { [weak self] loc in
                guard let self else { return }
                // 개인정보: 소수 둘째 자리(약 1km)로 줄여서 보낸다
                let lat = (loc.coordinate.latitude * 100).rounded() / 100
                let lon = (loc.coordinate.longitude * 100).rounded() / 100
                let moved = self.currentCoord.map { abs($0.lat - lat) > 0.05 || abs($0.lon - lon) > 0.05 } ?? true
                self.currentCoord = (lat, lon)
                if moved { self.fetchIfStale() }
            }
            l.onStatus = { [weak self] s in self?.locationStatus = s }
            l.onError = { [weak self] e in if self?.forecast == nil { self?.error = e } }
            locator = l
        }
        locationStatus = locator?.status ?? .notDetermined
        locator?.locate(ask: ask)
    }

    /// 탭의 '위치 허용' 버튼
    func requestLocation() {
        startLocator(ask: true)
        if locationStatus == .denied || locationStatus == .restricted { PIMPrivacy.open("Privacy_LocationServices") }
    }

    /// 좌표가 바뀌었거나 30분이 지났을 때만 받는다
    func fetchIfStale() {
        guard running, let c = coordinate else { return }
        if let f = forecast, abs(f.lat - c.lat) < 0.05, abs(f.lon - c.lon) < 0.05, Date().timeIntervalSince(f.fetched) < 30 * 60 { return }
        guard task == nil else { return }
        loading = true
        task = WxAPI.forecast(lat: c.lat, lon: c.lon) { [weak self] r in
            guard let self else { return }
            self.task = nil
            self.loading = false
            switch r {
            case .success(let f):
                self.forecast = f
                self.error = nil
                PIMFiles.write(f, "weather.json")
            case .failure(let e):
                self.error = e.localizedDescription
            }
            self.publishSummary()
        }
    }

    private func publishSummary() { onSummary?(summary) }

    /// 지금 보이는 예보가 고른 곳의 것인지
    var forecastMatches: Bool {
        guard let f = forecast, let c = coordinate else { return false }
        return abs(f.lat - c.lat) < 0.05 && abs(f.lon - c.lon) < 0.05
    }
}

// MARK: - 탭

/// 홈 대시보드의 날씨 카드: 현재 기온·상태·최고/최저. 아직 받지 못했으면 빈 상태.
private struct WeatherHomeCard: View {
    @ObservedObject var model: WeatherModel

    var body: some View {
        if let s = model.summary {
            HStack(spacing: 10) {
                Image(systemName: s.symbol).symbolRenderingMode(.multicolor)
                    .font(.island(.title1, .regular)).frame(width: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(s.temperature) \(s.condition)").font(.island(.subhead, .semibold)).lineLimit(1)
                    Text("\(s.place) · \(s.detail)").font(.island(.footnote)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label(T("날씨", "Weather"), systemImage: "cloud.sun")
                    .font(.island(.footnote, .semibold)).foregroundStyle(.white.opacity(0.6))
                Text(model.place == nil && model.mode == "city" ? T("설정에서 도시를 고르세요", "Pick a city in Settings")
                                                                 : (model.loading ? T("불러오는 중…", "Loading…") : T("아직 정보 없음", "No data yet")))
                    .font(.island(.subhead)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
        }
    }
}

private struct WeatherTab: View {
    @ObservedObject var model: WeatherModel

    var body: some View {
        Group {
            if model.mode == "city" && model.place == nil {
                PIMEmptyState(symbol: "cloud.sun", title: T("날씨를 볼 도시를 정하세요", "Choose a city for the weather"),
                              detail: T("설정 → 날씨에서 도시를 입력하면 위치 권한 없이 씁니다. '현재 위치'를 고르면 위치 권한을 묻습니다.",
                                        "Enter a city in Settings → Weather to use it without location access. Choosing Current Location asks for permission."))
            } else if model.mode == "current" && !WxLocator.isAuthorized(model.locationStatus) && !model.forecastMatches {
                PIMEmptyState(symbol: "location", title: model.locationStatus == .notDetermined ? T("위치 권한이 필요함", "Location access needed") : T("위치 권한이 거부됨", "Location access denied"),
                              detail: T("또는 설정에서 도시를 직접 고르면 위치 권한 없이 씁니다", "Or pick a city in Settings to skip location access"),
                              buttonTitle: model.locationStatus == .notDetermined ? T("위치 허용", "Allow Location") : T("시스템 설정 열기", "Open System Settings")) {
                    model.requestLocation()
                }
            } else if let f = model.forecast, model.forecastMatches {
                content(f)
            } else if model.loading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PIMEmptyState(symbol: "exclamationmark.icloud", title: T("날씨를 받아 오지 못함", "Couldn't load the weather"),
                              detail: model.error, buttonTitle: T("다시 시도", "Try Again")) { model.fetchIfStale() }
            }
        }
        .foregroundStyle(.white)
        .onAppear { model.fetchIfStale() }
    }

    private func content(_ f: WxForecast) -> some View {
        let unit = model.unit
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.placeName).font(.island(.subhead, .semibold)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                HStack(alignment: .center, spacing: 8) {
                    Text(WeatherModel.format(f.current.temp, unit: unit))
                        .font(.system(size: 50, weight: .light, design: .rounded)).monospacedDigit()
                    Image(systemName: WxCode.symbol(f.current.code, isDay: f.current.isDay))
                        .symbolRenderingMode(.multicolor).font(.island(.largeTitle, .regular))
                }
                Text(WxCode.text(f.current.code)).font(.island(.subhead, .semibold))
                Text(T("체감 \(WeatherModel.format(f.current.feels, unit: unit)) · 습도 \(Int(f.current.humidity))%",
                       "Feels \(WeatherModel.format(f.current.feels, unit: unit)) · Humidity \(Int(f.current.humidity))%"))
                    .font(.island(.caption)).foregroundStyle(.white.opacity(0.7))
                if let d = f.daily.first {
                    Text(T("최고 \(WeatherModel.format(d.hi, unit: unit)) · 최저 \(WeatherModel.format(d.lo, unit: unit))",
                           "High \(WeatherModel.format(d.hi, unit: unit)) · Low \(WeatherModel.format(d.lo, unit: unit))"))
                        .font(.island(.caption)).foregroundStyle(.white.opacity(0.7))
                    Text(T("자외선 \(d.uv.map { String(format: "%.0f", $0) } ?? "–") \(uvLevel(d.uv)) · 강수 \(d.precip.map { String(format: "%.1f", $0) } ?? "0") mm",
                           "UV \(d.uv.map { String(format: "%.0f", $0) } ?? "–") \(uvLevel(d.uv)) · Precip \(d.precip.map { String(format: "%.1f", $0) } ?? "0") mm"))
                        .font(.island(.caption)).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                Text(T("업데이트 \(PIMFormat.time(f.fetched)) · Open-Meteo", "Updated \(PIMFormat.time(f.fetched)) · Open-Meteo"))
                    .font(.island(.caption2)).foregroundStyle(.white.opacity(0.45))
            }
            .frame(width: 178, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                hourly(f, unit: unit)
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                daily(f, unit: unit)
            }
        }
        .padding(model.sky ? 12 : 0)
        .background {
            if model.sky {
                ZStack {
                    LinearGradient(colors: WxCode.sky(f.current.code, isDay: f.current.isDay), startPoint: .top, endPoint: .bottom)
                    Color.black.opacity(0.18)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func uvLevel(_ uv: Double?) -> String {
        guard let uv else { return "" }
        switch uv {
        case ..<3: return T("(낮음)", "(Low)")
        case ..<6: return T("(보통)", "(Moderate)")
        case ..<8: return T("(높음)", "(High)")
        case ..<11: return T("(매우 높음)", "(Very High)")
        default: return T("(위험)", "(Extreme)")
        }
    }

    private func hourly(_ f: WxForecast, unit: String) -> some View {
        let hours = Array(f.hourly.filter { $0.time > Date().addingTimeInterval(-3600) }.prefix(12))
        let tz = TimeZone(identifier: f.timezone) ?? .current
        return HStack(spacing: 0) {
            ForEach(Array(hours.enumerated()), id: \.offset) { i, h in
                VStack(spacing: 3) {
                    Text(i == 0 ? T("지금", "Now") : hourText(h.time, tz: tz)).font(.island(.caption2)).foregroundStyle(.white.opacity(0.65))
                    Image(systemName: WxCode.symbol(h.code, isDay: h.isDay)).symbolRenderingMode(.multicolor).font(.island(.subhead)).frame(height: 16)
                    Text(WeatherModel.format(h.temp, unit: unit)).font(.island(.footnote, design: .rounded)).monospacedDigit()
                    Text((h.pop ?? 0) >= 20 ? "\(h.pop!)%" : " ").font(.island(.caption2)).foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func hourText(_ d: Date, tz: TimeZone) -> String {
        let fmt = DateFormatter()
        fmt.timeZone = tz
        fmt.locale = L10n.isEnglish ? Locale(identifier: "en_US") : Locale(identifier: "ko_KR")
        fmt.setLocalizedDateFormatFromTemplate(L10n.isEnglish ? "j" : "H")
        return fmt.string(from: d)
    }

    private func daily(_ f: WxForecast, unit: String) -> some View {
        let lo = f.daily.map(\.lo).min() ?? 0
        let hi = f.daily.map(\.hi).max() ?? 1
        let span = max(1, hi - lo)
        let tz = TimeZone(identifier: f.timezone) ?? .current
        return VStack(spacing: 1) {
            ForEach(Array(f.daily.prefix(7).enumerated()), id: \.offset) { i, d in
                HStack(spacing: 6) {
                    Text(i == 0 ? T("오늘", "Today") : weekday(d.date, tz: tz)).font(.island(.footnote)).frame(width: 34, alignment: .leading)
                    Image(systemName: WxCode.symbol(d.code)).symbolRenderingMode(.multicolor).font(.island(.subhead)).frame(width: 20)
                    Text((d.pop ?? 0) >= 20 ? "\(d.pop!)%" : "").font(.island(.caption2)).foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1))
                        .frame(width: 30, alignment: .leading)
                    Text(WeatherModel.format(d.lo, unit: unit)).font(.island(.footnote, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6)).frame(width: 30, alignment: .trailing)
                    GeometryReader { g in
                        let x0 = CGFloat((d.lo - lo) / span) * g.size.width
                        let x1 = CGFloat((d.hi - lo) / span) * g.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(LinearGradient(colors: [Color(red: 0.4, green: 0.75, blue: 1), Color(red: 1, green: 0.75, blue: 0.3)],
                                                          startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, x1 - x0)).offset(x: x0)
                        }
                    }
                    .frame(height: 4)
                    Text(WeatherModel.format(d.hi, unit: unit)).font(.island(.footnote, design: .rounded)).monospacedDigit().frame(width: 30, alignment: .leading)
                    Text(d.uv.map { "UV \(Int($0.rounded()))" } ?? "").font(.island(.caption2)).foregroundStyle(.white.opacity(0.5)).frame(width: 34, alignment: .trailing)
                }
                .frame(height: 17)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func weekday(_ d: Date, tz: TimeZone) -> String {
        let fmt = DateFormatter()
        fmt.timeZone = tz
        fmt.locale = L10n.isEnglish ? Locale(identifier: "en_US") : Locale(identifier: "ko_KR")
        fmt.setLocalizedDateFormatFromTemplate("EEE")
        return fmt.string(from: d)
    }
}

// MARK: - 설정

private struct WeatherSettings: View {
    private let d = ModuleDefaults(module: "weather")
    // 처음 값은 init에서 읽는다 (onAppear에서 바꾸면 onChange가 불려 위치 권한 요청이 잘못 나갈 수 있음)
    @State private var mode: String
    @State private var unit: String
    @State private var sky: Bool
    @State private var place: WxPlace?

    init() {
        let d = ModuleDefaults(module: "weather")
        _mode = State(initialValue: d.string("mode", default: "city"))
        _unit = State(initialValue: d.string("unit", default: L10n.isEnglish && Locale.current.measurementSystem == .us ? "f" : "c"))
        _sky = State(initialValue: d.bool("sky", default: true))
        _place = State(initialValue: d.data("place").flatMap { try? JSONDecoder().decode(WxPlace.self, from: $0) })
    }
    @State private var query = ""
    @State private var results: [WxPlace] = []
    @State private var searching = false
    @State private var status: String?
    @State private var searchWork: DispatchWorkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PIMSettingsGroup(title: T("위치", "Location")) {
                Picker(T("위치", "Location"), selection: $mode) {
                    Text(T("도시 직접 지정 (위치 권한 불필요)", "City (no location access)")).tag("city")
                    Text(T("현재 위치 (위치 권한 필요)", "Current Location (needs location access)")).tag("current")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: mode) { _, v in
                    if v == "current" { d.set(Date().timeIntervalSince1970, "locationAsk") }
                    d.set(v, "mode")
                }
                if mode == "city" {
                    Text(T("지금 도시: ", "Current city: ") + (place.map { "\($0.name)\($0.detail.isEmpty ? "" : ", " + $0.detail)" } ?? T("없음", "None")))
                    TextField(T("도시 검색 (예: Seoul, 부산, Paris)", "Search a city (e.g. Seoul, Paris)"), text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: query) { _, q in scheduleSearch(q) }
                    if searching { ProgressView().controlSize(.small) }
                    ForEach(Array(results.enumerated()), id: \.offset) { _, p in
                        Button("\(p.name)\(p.detail.isEmpty ? "" : " — " + p.detail)") {
                            place = p
                            d.set(try? JSONEncoder().encode(p), "place")
                            results = []
                            query = ""
                        }
                        .buttonStyle(.link)
                    }
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                } else {
                    Text(T("현재 위치를 고르면 macOS가 위치 권한을 묻습니다. 좌표는 약 1km 단위로 줄여 Open-Meteo에 보냅니다.",
                           "Choosing Current Location makes macOS ask for location access. Coordinates are rounded to about 1 km before being sent to Open-Meteo."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            PIMSettingsGroup(title: T("표시", "Display")) {
                Picker(T("온도 단위", "Temperature Unit"), selection: $unit) {
                    Text("°C").tag("c")
                    Text("°F").tag("f")
                }
                .pickerStyle(.segmented)
                .onChange(of: unit) { _, v in d.set(v, "unit") }
                Toggle(T("하늘 배경", "Sky Background"), isOn: $sky)
                    .onChange(of: sky) { _, v in d.set(v, "sky") }
            }
            Text(T("날씨 출처: Open-Meteo (계정·API 키 불필요). 기능이 켜져 있는 동안 최대 30분에 한 번 받아 옵니다. 도시 검색은 입력할 때 Open-Meteo 지오코딩을 씁니다.",
                   "Source: Open-Meteo (no account or API key). Fetched at most every 30 minutes while enabled. City search uses Open-Meteo geocoding as you type."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func scheduleSearch(_ q: String) {
        searchWork?.cancel()
        let text = q.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { results = []; return }
        let work = DispatchWorkItem {
            searching = true
            WxAPI.geocode(text) { r in
                searching = false
                switch r {
                case .success(let list):
                    results = list
                    status = list.isEmpty ? T("결과 없음", "No results") : nil
                case .failure(let e):
                    status = e.localizedDescription
                }
            }
        }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}

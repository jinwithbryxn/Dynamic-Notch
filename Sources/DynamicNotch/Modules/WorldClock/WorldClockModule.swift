import SwiftUI

/// 세계 시계: 고른 도시들의 현재 시각과 이 Mac과의 시차를 보여 준다.
/// 화면이 보이는 동안에만 TimelineView가 1분마다 다시 그리며, 배경 타이머는 없다.
final class WorldClockModule: NotchModule {
    let id = "worldclock"
    var title: String { T("세계 시계", "World Clock") }
    let symbol = "globe"

    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }
    static let defaultZones = ["America/New_York", "Europe/London", "Asia/Tokyo"]

    /// 표시할 시간대 (IANA 이름)
    var zones: [String] {
        defaults.strings("zones", default: Self.defaultZones).filter { TimeZone(identifier: $0) != nil }
    }

    func start(context: ModuleContext) {}
    func stop() {}

    func tabView() -> AnyView? { AnyView(WorldClockTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 420, height: CGFloat(max(1, zones.count)) * 44 + 8) }

    func paletteActions() -> [PaletteAction] {
        zones.compactMap { TimeZone(identifier: $0) }.map { zone in
            PaletteAction(id: "worldclock.\(zone.identifier)",
                          title: "\(Self.city(zone)) \(Self.time(Date(), zone))",
                          subtitle: Self.offsetText(zone, from: .current),
                          symbol: symbol, keywords: ["world clock", "세계 시계", "시간", "time"], run: {})
        }
    }

    func settingsView() -> AnyView? { AnyView(WorldClockSettings(module: self)) }

    func selfTest() -> [String] {
        let now = Date()
        return zones.compactMap { TimeZone(identifier: $0) }.map {
            "\($0.identifier): \(Self.time(now, $0)) (\(Self.offsetText($0, from: .current)))"
        } + ["zone count \(TimeZone.knownTimeZoneIdentifiers.count)"]
    }

    func setZones(_ list: [String]) { defaults.set(list, "zones") }

    // MARK: 표시 도우미

    static func city(_ zone: TimeZone) -> String {
        let raw = zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier
        return raw.replacingOccurrences(of: "_", with: " ")
    }

    static func time(_ date: Date, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = zone
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: date)
    }

    /// "오늘 · 14시간 늦음" 형태
    static func offsetText(_ zone: TimeZone, from local: TimeZone, at date: Date = Date()) -> String {
        let diff = zone.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)
        var cal = Calendar.current
        cal.timeZone = local
        var other = Calendar.current
        other.timeZone = zone
        let localDay = cal.dateComponents([.year, .month, .day], from: date)
        let otherDay = other.dateComponents([.year, .month, .day], from: date)
        let day: String
        if localDay == otherDay { day = T("오늘", "Today") }
        else if diff > 0 { day = T("내일", "Tomorrow") }
        else { day = T("어제", "Yesterday") }
        if diff == 0 { return day }
        let hours = Double(abs(diff)) / 3600
        let h = hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
        return day + " · " + (diff > 0 ? T("\(h)시간 빠름", "+\(h)h") : T("\(h)시간 늦음", "−\(h)h"))
    }
}

private struct WorldClockTab: View {
    let module: WorldClockModule

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 0) {
                ForEach(module.zones, id: \.self) { id in
                    if let zone = TimeZone(identifier: id) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(WorldClockModule.city(zone))
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                Text(WorldClockModule.offsetText(zone, from: .current, at: context.date))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(WorldClockModule.time(context.date, zone))
                                .font(.system(size: 26, weight: .regular, design: .rounded))
                                .monospacedDigit()
                        }
                        .frame(height: 44)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }
}

private struct WorldClockSettings: View {
    let module: WorldClockModule
    @State private var zones: [String] = []
    @State private var query = ""

    private var matches: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2 else { return [] }
        return TimeZone.knownTimeZoneIdentifiers.filter { $0.lowercased().contains(q) && !zones.contains($0) }.prefix(8).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(zones, id: \.self) { id in
                HStack {
                    Text(id.replacingOccurrences(of: "_", with: " "))
                    Spacer()
                    Button(T("빼기", "Remove")) { zones.removeAll { $0 == id }; module.setZones(zones) }
                }
            }
            TextField(T("도시 검색 (예: Paris, Seoul)", "Search a city (e.g. Paris, Seoul)"), text: $query)
            ForEach(matches, id: \.self) { id in
                Button(id.replacingOccurrences(of: "_", with: " ")) {
                    zones.append(id); module.setZones(zones); query = ""
                }
                .buttonStyle(.link)
            }
        }
        .onAppear { zones = module.zones }
    }
}

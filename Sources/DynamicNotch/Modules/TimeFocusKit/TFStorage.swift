import AppKit
import SwiftUI

/// 시간·집중 모듈들이 함께 쓰는 로컬 JSON 저장소.
/// 설치본은 "Application Support/DynamicNotch/Modules/<모듈>/", 검토용 등 다른 번들은 번들 ID 폴더를 써서 기록이 섞이지 않게 한다.
enum TFStorage {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundle = Bundle.main.bundleIdentifier ?? "com.dynamicnotch.app"
        let name = bundle == "com.dynamicnotch.app" ? "DynamicNotch" : bundle
        return base.appendingPathComponent(name, isDirectory: true).appendingPathComponent("Modules", isDirectory: true)
    }

    static func url(_ module: String, _ file: String) -> URL {
        root.appendingPathComponent(module, isDirectory: true).appendingPathComponent(file)
    }

    static func load<T: Decodable>(_ type: T.Type, _ module: String, _ file: String) -> T? {
        guard let data = try? Data(contentsOf: url(module, file)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(T.self, from: data)
    }

    @discardableResult
    static func save<T: Encodable>(_ value: T, _ module: String, _ file: String) -> Bool {
        let target = url(module, file)
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            try encoder.encode(value).write(to: target, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 실행 상태 파일(사용자 기록 아님)을 지운다.
    static func removeState(_ module: String, _ file: String) {
        try? FileManager.default.removeItem(at: url(module, file))
    }

    /// 기록 지우기: 영구 삭제하지 않고 휴지통으로 보낸다.
    @discardableResult
    static func trash(_ module: String, _ file: String) -> Bool {
        let target = url(module, file)
        guard FileManager.default.fileExists(atPath: target.path) else { return true }
        return (try? FileManager.default.trashItem(at: target, resultingItemURL: nil)) != nil
    }
}

/// 날짜 키("2026-11-02", 이 Mac의 달력·시간대 기준)
enum TFDay {
    static func key(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(_ key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// 오늘까지 n일 (오래된 날 → 오늘)
    static func lastDays(_ n: Int, from date: Date = Date()) -> [String] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)
        return (0..<n).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.map { key($0) }
    }

    /// 요일 한 글자 (월·Mon)
    static func weekdayShort(_ key: String) -> String {
        guard let d = date(key) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isEnglish ? "en_US" : "ko_KR")
        f.dateFormat = L10n.isEnglish ? "EEEEE" : "E"
        return f.string(from: d)
    }

    /// 키가 해당 연·월인지
    static func isIn(_ key: String, year: Int, month: Int? = nil) -> Bool {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, p[0] == year else { return false }
        return month == nil || p[1] == month
    }
}

/// 시간 표시
enum TFFormat {
    /// 카운트다운 "24:12" / "1:02:03" (남은 시간은 올림)
    static func clock(_ t: TimeInterval, roundUp: Bool = true) -> String {
        let s = max(0, Int(roundUp ? t.rounded(.up) : t.rounded(.down)))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "1시간 23분" / "1h 23m", 1분 미만은 초
    static func duration(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        if s == 0 { return T("0분", "0m") }
        if s < 60 { return T("\(s)초", "\(s)s") }
        let h = s / 3600, m = s / 60 % 60
        if h == 0 { return T("\(m)분", "\(m)m") }
        if m == 0 { return T("\(h)시간", "\(h)h") }
        return T("\(h)시간 \(m)분", "\(h)h \(m)m")
    }

    /// 짧은 표시 "1.5h" / "45m" (차트 축)
    static func short(_ t: TimeInterval) -> String {
        if t >= 3600 { return String(format: t >= 36000 ? "%.0fh" : "%.1fh", t / 3600) }
        return "\(Int(t / 60))m"
    }

    static func number(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// "오후 3:05" 같은 시각
    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: date)
    }
}

/// 설정 화면(도우미 프로세스)에서 ModuleDefaults를 SwiftUI 바인딩으로 쓰기 위한 작은 저장소.
/// 값을 바꾸면 화면을 다시 그리고 본 앱에 알린다.
final class TFPrefs: ObservableObject {
    let defaults: ModuleDefaults
    init(module: String) { defaults = ModuleDefaults(module: module) }

    func bool(_ name: String, _ value: Bool) -> Binding<Bool> {
        Binding(get: { self.defaults.bool(name, default: value) },
                set: { self.objectWillChange.send(); self.defaults.set($0, name) })
    }
    func int(_ name: String, _ value: Int) -> Binding<Int> {
        Binding(get: { self.defaults.int(name, default: value) },
                set: { self.objectWillChange.send(); self.defaults.set($0, name) })
    }
    func double(_ name: String, _ value: Double) -> Binding<Double> {
        Binding(get: { self.defaults.double(name, default: value) },
                set: { self.objectWillChange.send(); self.defaults.set($0, name) })
    }
    func string(_ name: String, _ value: String) -> Binding<String> {
        Binding(get: { self.defaults.string(name, default: value) },
                set: { self.objectWillChange.send(); self.defaults.set($0, name) })
    }
    func strings(_ name: String) -> [String] { defaults.strings(name, default: []) }
    func setStrings(_ list: [String], _ name: String) {
        objectWillChange.send()
        defaults.set(list, name)
    }
}

// MARK: - 노치 탭 공용 모양

/// 작은 캡슐 버튼 (탭 안 조작)
struct TFPillButton: View {
    var title: String
    var symbol: String? = nil
    var tint: Color = .white
    var prominent = false
    var help: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
                if !title.isEmpty { Text(title).font(.system(size: 11.5, weight: .semibold)) }
            }
            .lineLimit(1)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .padding(.horizontal, title.isEmpty ? 8 : 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(prominent ? tint : tint.opacity(0.18)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help ?? title)
        .accessibilityLabel(help ?? title)
    }
}

/// 둥근 원 아이콘 버튼 (시작·일시정지 등)
struct TFRoundButton: View {
    var symbol: String
    var tint: Color = .white
    var size: CGFloat = 34
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(tint.opacity(0.32)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 탭 위쪽 작은 구역 선택 (포모도로 | 반복 | 기록 등)
struct TFSegment<Value: Hashable>: View {
    var items: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                Button { selection = item.0 } label: {
                    Text(item.1)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selection == item.0 ? Color.black : Color.white.opacity(0.75))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(selection == item.0 ? Color.white.opacity(0.9) : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.1)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

/// 지원 안 됨 / 권한 필요 안내 상자 (이유 + 대안)
struct TFUnsupportedBox: View {
    var title: String
    var reason: String
    var alternative: String?
    var buttonTitle: String? = nil
    var buttonAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11.5, weight: .semibold))
                Text(reason).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                if let alternative {
                    Text(alternative).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let buttonTitle, let buttonAction {
                TFPillButton(title: buttonTitle, tint: .yellow, action: buttonAction)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }
}

/// 설정 화면 안내 문구 (보조 글자)
struct TFSettingsNote: View {
    var text: String
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

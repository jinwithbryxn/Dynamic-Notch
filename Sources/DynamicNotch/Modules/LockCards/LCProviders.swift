import AppKit
import EventKit
import Intents
import IOKit
import IOKit.ps
import SwiftUI

/// 잠금 화면 카드 종류
enum LCCard: String, CaseIterable, Identifiable {
    case clock, weather, battery, devices, timer, event, reminders, focus
    var id: String { rawValue }
    var label: String {
        switch self {
        case .clock: return T("시계", "Clock")
        case .weather: return T("날씨", "Weather")
        case .battery: return T("Mac 배터리", "Mac battery")
        case .devices: return T("주변기기 배터리", "Device batteries")
        case .timer: return T("타이머", "Timer")
        case .event: return T("다음 일정", "Up next")
        case .reminders: return T("미리 알림", "Reminders")
        case .focus: return T("집중 모드", "Focus")
        }
    }
    static let defaults: [LCCard] = [.clock, .battery, .devices, .timer, .event, .focus]
}

/// 날씨 값 (날씨 모듈이 `LockCardHooks.weather`로 넘겨 준다)
struct LCWeather: Equatable {
    var temperature: Double
    var unit: String          // "°C" / "°F"
    var symbol: String        // SF Symbol
    var summary: String
    var place: String?
    var updated: Date
}

/// 본 앱(통합 담당)이 다른 기능의 값을 연결하는 자리. 연결되지 않으면 카드는 '연결 안 됨'으로 보인다.
enum LockCardHooks {
    /// 날씨 모듈(M-D-017)의 현재 값
    static var weather: (() -> LCWeather?)?
}

enum LCAccess: Equatable {
    case granted, notDetermined, denied
    case unavailable(String)
}

struct LCDevice: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var level: Int
    var detail: String?
    var symbol: String
}

struct LCTimer: Identifiable, Equatable {
    var id: String
    var title: String
    var text: String
    var symbol: String
}

struct LCEvent: Equatable {
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
}

struct LCReminder: Equatable {
    var title: String
    var due: Date?
}

struct LCFocus: Equatable {
    var name: String
    var symbol: String
    var tint: Color
}

struct LCSnapshot: Equatable {
    var battery: BatteryMonitor.Snapshot?
    var devices: [LCDevice] = []
    var timers: [LCTimer] = []
    var event: LCEvent?
    var calendarAccess: LCAccess = .notDetermined
    var reminders: [LCReminder] = []
    var remindersAccess: LCAccess = .notDetermined
    /// nil = 꺼짐 (권한이 있을 때) / 모름 (권한이 없을 때)
    var focus: LCFocus?
    var focusAccess: LCAccess = .notDetermined
    var weather: LCWeather?
}

/// 카드 값 모음. 잠금 중이거나 탭이 보일 때만 `refresh`한다 (배경 타이머 없음).
final class LCDataModel: ObservableObject {
    @Published private(set) var snapshot = LCSnapshot()
    private var store: EKEventStore?

    func refresh(center: ActivityCenter?) {
        var s = LCSnapshot()
        s.battery = BatteryMonitor.read()
        s.devices = Self.accessories()
        s.timers = Self.timers(center)
        s.calendarAccess = Self.access(EKEventStore.authorizationStatus(for: .event))
        if s.calendarAccess == .granted { s.event = nextEvent() }
        s.remindersAccess = Self.remindersAccess()
        (s.focus, s.focusAccess) = Self.focus()
        s.weather = LockCardHooks.weather?()
        s.reminders = snapshot.reminders
        if snapshot != s { snapshot = s }
        if s.remindersAccess == .granted { loadReminders() }
    }

    // MARK: 캘린더·미리 알림 (EventKit, 권한이 있을 때만 읽음)

    static func access(_ status: EKAuthorizationStatus) -> LCAccess {
        switch status {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        case .writeOnly: return .unavailable(T("쓰기 전용 권한이라 읽을 수 없음", "Write-only access cannot read"))
        default: return .denied
        }
    }

    /// 앱 정보(Info.plist)에 미리 알림 설명이 없으면 요청 자체를 할 수 없다.
    static var remindersUsageDeclared: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSRemindersFullAccessUsageDescription") != nil
    }

    static func remindersAccess() -> LCAccess {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .fullAccess { return .granted }
        if !remindersUsageDeclared {
            return .unavailable(T("앱 정보(Info.plist)에 미리 알림 사용 설명이 없어 권한을 요청할 수 없음",
                                  "The app's Info.plist has no Reminders usage description, so access cannot be requested"))
        }
        return access(status)
    }

    private func eventStore() -> EKEventStore {
        if let store { return store }
        let s = EKEventStore()
        store = s
        return s
    }

    /// 지금부터 24시간 안의 다음 일정 (진행 중인 것 포함, 종일 일정은 뒤로)
    private func nextEvent() -> LCEvent? {
        let store = eventStore()
        let now = Date()
        let pred = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(86_400), calendars: nil)
        let events = store.events(matching: pred).filter { $0.endDate > now && $0.status != .canceled }
        let pick = events.filter { !$0.isAllDay }.sorted { $0.startDate < $1.startDate }.first
            ?? events.sorted { $0.startDate < $1.startDate }.first
        return pick.map { LCEvent(title: $0.title ?? "", start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay) }
    }

    private func loadReminders() {
        let store = eventStore()
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: Date().addingTimeInterval(86_400), calendars: nil)
        store.fetchReminders(matching: pred) { [weak self] list in
            let items = (list ?? []).map { r in
                LCReminder(title: r.title ?? "", due: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) })
            }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            DispatchQueue.main.async {
                guard let self, self.snapshot.reminders != items else { return }
                self.snapshot.reminders = items
            }
        }
    }

    /// 사용자가 누를 때만: 캘린더 전체 접근 요청
    static func requestCalendar(_ done: @escaping () -> Void) {
        EKEventStore().requestFullAccessToEvents { _, _ in DispatchQueue.main.async(execute: done) }
    }

    // MARK: 집중 모드

    /// 전체 디스크 접근이 있으면 모드 이름·아이콘, 없으면 집중 모드 상태 권한으로 켜짐 여부만.
    static func focus() -> (LCFocus?, LCAccess) {
        if PermissionsManager.hasFullDiskAccess() {
            let mode = FocusMonitor.readActiveMode()
            return (mode.map { LCFocus(name: $0.name, symbol: $0.symbol, tint: $0.tint) }, .granted)
        }
        let center = INFocusStatusCenter.default
        switch center.authorizationStatus {
        case .authorized:
            let on = center.focusStatus.isFocused == true
            return (on ? LCFocus(name: T("집중 모드", "Focus"), symbol: "moon.fill", tint: .indigo) : nil, .granted)
        case .notDetermined: return (nil, .notDetermined)
        default: return (nil, .denied)
        }
    }

    // MARK: 타이머 (본 앱 노치의 상시 표시에서 읽음)

    static let timerKinds: [ActivityKind] = [.timer, .stopwatch, .pomodoro]

    static func timers(_ center: ActivityCenter?) -> [LCTimer] {
        guard let center else { return [] }
        return timerKinds.compactMap { kind in
            guard let a = center.persistent[kind] else { return nil }
            let text: String
            switch a.value {
            case .text(let t): text = t
            case .labeledText(_, let t): text = t
            case .elapsed(let d): text = TimerController.format(Date().timeIntervalSince(d))
            case .percent(let p), .ring(let p), .ringPercent(let p), .bar(let p): text = "\(Int((p * 100).rounded()))%"
            default:
                if let d = a.startDate { text = TimerController.format(Date().timeIntervalSince(d)) }
                else { text = a.subtitle ?? "" }
            }
            return LCTimer(id: kind.rawValue, title: a.title ?? kind.rawValue, text: text, symbol: a.symbol)
        }
    }

    // MARK: 주변기기 배터리

    /// macOS 배터리 위젯이 쓰는 액세서리 전원 목록(비공개 IOPSCopyPowerSourcesByType, dlsym으로 격리)과
    /// Magic 액세서리의 HID BatteryPercent(공개 IOKit)를 합친다. 없으면 빈 목록.
    static func accessories() -> [LCDevice] {
        struct Parts { var main: Int?; var left: Int?; var right: Int?; var caseLevel: Int? }
        var byName: [String: Parts] = [:]
        var order: [String] = []
        func touch(_ name: String) { if byName[name] == nil { byName[name] = Parts(); order.append(name) } }

        typealias ByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
        if let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
           let p = dlsym(handle, "IOPSCopyPowerSourcesByType"),
           let info = unsafeBitCast(p, to: ByType.self)(4)?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                      let name = d["Name"] as? String else { continue }
                let level = d["Current Capacity"] as? Int
                switch d["Part Identifier"] as? String {
                case "Left": touch(name); byName[name]?.left = level
                case "Right": touch(name); byName[name]?.right = level
                case "Case":
                    // 케이스는 "이름 Case"처럼 따로 올 수 있다 → 앞부분이 같은 기기에 붙인다
                    let owner = order.first { name.hasPrefix($0) } ?? name
                    touch(owner); byName[owner]?.caseLevel = level
                case "Combined":
                    touch(name)
                    for part in (d["Combined Parts"] as? [[String: Any]]) ?? [] {
                        switch part["Part Identifier"] as? String {
                        case "Left": byName[name]?.left = part["Current Capacity"] as? Int
                        case "Right": byName[name]?.right = part["Current Capacity"] as? Int
                        default: break
                        }
                    }
                    if byName[name]?.left == nil, byName[name]?.right == nil { byName[name]?.main = level }
                default: touch(name); byName[name]?.main = level
                }
            }
        }
        // Magic 키보드·마우스·트랙패드
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                func prop(_ key: String) -> Any? {
                    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                }
                if let percent = prop("BatteryPercent") as? Int, let product = prop("Product") as? String, !product.isEmpty,
                   byName[product] == nil {
                    touch(product); byName[product]?.main = percent
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        return order.compactMap { name in
            guard let p = byName[name] else { return nil }
            let buds = [p.left, p.right].compactMap { $0 }
            guard let level = p.main ?? buds.min() else { return nil }
            var parts: [String] = []
            if let l = p.left { parts.append(T("왼쪽 \(l)%", "L \(l)%")) }
            if let r = p.right { parts.append(T("오른쪽 \(r)%", "R \(r)%")) }
            if let c = p.caseLevel { parts.append(T("케이스 \(c)%", "Case \(c)%")) }
            let symbol = BluetoothMonitor.nameSymbol(name.lowercased()) ?? "battery.75percent"
            return LCDevice(name: name, level: level, detail: parts.isEmpty ? nil : parts.joined(separator: " · "), symbol: symbol)
        }
    }
}

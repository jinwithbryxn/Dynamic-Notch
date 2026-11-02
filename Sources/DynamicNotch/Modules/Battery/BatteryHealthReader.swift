import Foundation
import IOKit
import IOKit.ps

/// 배터리 상태 읽기 (IOKit 전원 소스 + AppleSmartBattery 레지스트리). 읽기만 한다.
struct BatteryHealthReading: Equatable {
    var present = false
    var percent = 0
    var isCharging = false
    var onAC = false
    var isCharged = false
    /// 분. nil이면 계산 중이거나 해당 없음
    var minutesToEmpty: Int?
    var minutesToFull: Int?
    var lowPowerMode = false
    var cycleCount: Int?
    var designCycleCount: Int?
    var designCapacity: Int?      // mAh
    var fullChargeCapacity: Int?  // mAh (NominalChargeCapacity)
    var temperature: Double?      // °C
    var voltage: Double?          // V
    var amperage: Double?         // mA (음수 = 방전)
    var adapterWatts: Int?
    var adapterName: String?
    /// 충전 안 하는 이유 코드 (ChargerData.NotChargingReason, 0 = 없음)
    var notChargingReason: Int?

    /// 설계 용량 대비 % (시스템 정보 값을 못 읽을 때 대신 씀)
    var estimatedMaxCapacity: Double? {
        guard let d = designCapacity, d > 0, let f = fullChargeCapacity else { return nil }
        return Double(f) / Double(d)
    }

    /// 현재 소비·충전 전력 (W, 양수 = 충전)
    var watts: Double? {
        guard let v = voltage, let a = amperage else { return nil }
        return v * a / 1000
    }

    static func read() -> BatteryHealthReading {
        var r = BatteryHealthReading()
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                      d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                r.present = true
                let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
                let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
                r.percent = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
                r.isCharging = d[kIOPSIsChargingKey] as? Bool ?? false
                r.onAC = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
                r.isCharged = d[kIOPSIsChargedKey] as? Bool ?? false
                if let t = d[kIOPSTimeToEmptyKey] as? Int, t > 0, !r.onAC { r.minutesToEmpty = t }
                if let t = d[kIOPSTimeToFullChargeKey] as? Int, t > 0, r.isCharging { r.minutesToFull = t }
                r.lowPowerMode = (d["LPM Active"] as? Bool) ?? ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
        if !r.present { r.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return r }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return r }
        func int(_ k: String) -> Int? { (d[k] as? NSNumber)?.intValue }
        r.cycleCount = int("CycleCount")
        r.designCycleCount = int("DesignCycleCount9C")
        r.designCapacity = int("DesignCapacity")
        r.fullChargeCapacity = int("NominalChargeCapacity") ?? int("AppleRawMaxCapacity")
        if let t = int("Temperature") { r.temperature = Double(t) / 100 }
        if let v = int("Voltage") { r.voltage = Double(v) / 1000 }
        if let a = d["Amperage"] as? NSNumber { r.amperage = Double(Int64(truncatingIfNeeded: a.int64Value)) }
        if let ad = d["AdapterDetails"] as? [String: Any] {
            r.adapterWatts = (ad["Watts"] as? NSNumber)?.intValue
            r.adapterName = (ad["Name"] as? String) ?? (ad["Description"] as? String)
        }
        if let cd = d["ChargerData"] as? [String: Any] { r.notChargingReason = (cd["NotChargingReason"] as? NSNumber)?.intValue }
        return r
    }
}

/// 시스템 설정과 같은 배터리 성능 상태·최대 용량 (system_profiler, 탭을 열 때 한 번)
struct BatteryProfilerHealth: Equatable {
    var condition: String?        // Good, Fair, Poor, Service Recommended…
    var maximumCapacity: String?  // "89%"

    var conditionText: String? {
        guard let c = condition else { return nil }
        switch c.lowercased() {
        case "good", "normal": return T("정상", "Normal")
        default: return T("서비스 권장", "Service Recommended") + " (\(c))"
        }
    }

    /// 백그라운드 큐에서 부른다 (약 0.2초)
    static func read() -> BatteryProfilerHealth? {
        guard let r = SysCommand.run("/usr/sbin/system_profiler", ["SPPowerDataType", "-json"], timeout: 10),
              r.status == 0, let data = r.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["SPPowerDataType"] as? [[String: Any]] else { return nil }
        for item in items {
            if let h = item["sppower_battery_health_info"] as? [String: Any] {
                return BatteryProfilerHealth(condition: h["sppower_battery_health"] as? String,
                                             maximumCapacity: h["sppower_battery_health_maximum_capacity"] as? String)
            }
        }
        return nil
    }
}

/// 충전 제어·팬 하드웨어 감지 (SMC 읽기만)
struct BatteryHardwareSupport: Equatable {
    var smcAvailable = false
    /// Apple silicon 충전 차단 키(CHTE)나 Intel 충전 한도 키(BCLM)가 있는지
    var chargeControlKeys: [String] = []
    var fans: [SysSMC.Fan] = []

    static func read() -> BatteryHardwareSupport {
        let smc = SysSMC.shared
        var s = BatteryHardwareSupport()
        s.smcAvailable = smc.available
        guard s.smcAvailable else { return s }
        s.chargeControlKeys = ["CHTE", "CHIE", "CH0B", "CH0C", "BCLM"].filter { smc.has($0) }
        s.fans = smc.fans()
        return s
    }
}

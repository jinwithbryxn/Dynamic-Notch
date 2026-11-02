import AppKit
import CoreGraphics
import IOKit

// 화면 제어 어댑터.
//   - SysDisplays: 연결된 화면 목록과 주사율(공개 CoreGraphics 디스플레이 모드)
//   - SysGamma: Extra Dim (감마 표를 원래 값의 비율로 낮춤, 끄거나 앱이 끝나면 ColorSync 설정으로 복원)
//   - SysDDC: 외장 모니터 DDC/CI (Apple silicon 비공개 IOAVService, dlsym으로 격리)

struct SysDisplay: Identifiable, Equatable {
    var id: CGDirectDisplayID
    var name: String
    var isBuiltin: Bool
    var isMain: Bool
    var currentRefresh: Double
    /// 현재 해상도에서 고를 수 있는 주사율 (높은 순)
    var refreshOptions: [Double]
    /// 화면이 낼 수 있는 최대 EDR 배율 (1이면 HDR/XDR 아님)
    var maxEDR: Double
}

enum SysDisplays {
    static func onlineIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
    }

    static func all() -> [SysDisplay] {
        onlineIDs().filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }.map { id in
            let screen = screen(for: id)
            let builtin = CGDisplayIsBuiltin(id) != 0
            let current = CGDisplayCopyDisplayMode(id)
            return SysDisplay(
                id: id,
                name: screen?.localizedName ?? (builtin ? T("내장 화면", "Built-in Display") : T("외장 화면", "External Display")),
                isBuiltin: builtin, isMain: CGDisplayIsMain(id) != 0,
                currentRefresh: current?.refreshRate ?? 0,
                refreshOptions: refreshModes(id).map(\.rate),
                maxEDR: Double(screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1))
        }
    }

    /// 현재 해상도·배율이 같은 모드 중 주사율별 하나씩
    static func refreshModes(_ id: CGDirectDisplayID) -> [(rate: Double, mode: CGDisplayMode)] {
        guard let cur = CGDisplayCopyDisplayMode(id) else { return [] }
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode]) ?? []
        var seen: [Double: CGDisplayMode] = [:]
        for m in modes where m.width == cur.width && m.height == cur.height && m.pixelWidth == cur.pixelWidth
            && m.pixelHeight == cur.pixelHeight && m.isUsableForDesktopGUI() && m.refreshRate > 0 {
            let r = (m.refreshRate * 100).rounded() / 100
            if seen[r] == nil { seen[r] = m }
        }
        return seen.sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }

    /// 사용자가 고른 주사율로 바꾼다 (재부팅 후에도 유지)
    @discardableResult
    static func setRefresh(_ id: CGDirectDisplayID, _ rate: Double) -> Bool {
        guard let mode = refreshModes(id).first(where: { abs($0.rate - rate) < 0.01 })?.mode else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        guard CGConfigureDisplayWithDisplayMode(config, id, mode, nil) == .success else {
            CGCancelDisplayConfiguration(config); return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    static func rateText(_ r: Double) -> String {
        r == r.rounded() ? "\(Int(r)) Hz" : String(format: "%.2f Hz", r)
    }
}

/// Extra Dim: 감마 표를 낮춰 최소 밝기보다 더 어둡게. 바꾼 화면은 기억했다가 되돌린다.
final class SysGamma {
    static let shared = SysGamma()
    private struct Table { var r: [CGGammaValue]; var g: [CGGammaValue]; var b: [CGGammaValue] }
    private var originals: [CGDirectDisplayID: Table] = [:]
    private(set) var levels: [CGDirectDisplayID: Double] = [:]
    private var callbackInstalled = false
    private var quitObserver: NSObjectProtocol?

    var isActive: Bool { levels.values.contains { $0 > 0 } }

    /// level 0…0.9 (0 = 원래대로)
    func set(_ id: CGDirectDisplayID, _ level: Double) {
        let level = min(0.9, max(0, level))
        if level <= 0.001 {
            levels[id] = nil
            if let t = originals.removeValue(forKey: id) {
                CGSetDisplayTransferByTable(id, UInt32(t.r.count), t.r, t.g, t.b)
            }
            if levels.isEmpty { restoreAll() }
            return
        }
        if originals[id] == nil, let t = Self.read(id) { originals[id] = t }
        guard let t = originals[id] else { return }
        levels[id] = level
        apply(id, t, level)
        installObservers()
    }

    private func apply(_ id: CGDirectDisplayID, _ t: Table, _ level: Double) {
        let f = CGGammaValue(1 - level)
        CGSetDisplayTransferByTable(id, UInt32(t.r.count), t.r.map { $0 * f }, t.g.map { $0 * f }, t.b.map { $0 * f })
    }

    private static func read(_ id: CGDirectDisplayID) -> Table? {
        let cap: UInt32 = 1024
        var r = [CGGammaValue](repeating: 0, count: Int(cap))
        var g = r, b = r
        var n: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, cap, &r, &g, &b, &n) == .success, n > 0 else { return nil }
        return Table(r: Array(r.prefix(Int(n))), g: Array(g.prefix(Int(n))), b: Array(b.prefix(Int(n))))
    }

    /// 모든 화면을 ColorSync 설정으로 되돌린다 (끄기·정지·앱 종료)
    func restoreAll() {
        let had = !originals.isEmpty || !levels.isEmpty
        levels.removeAll()
        originals.removeAll()
        if had { CGDisplayRestoreColorSyncSettings() }
        removeObservers()
    }

    private func installObservers() {
        if !callbackInstalled {
            CGDisplayRegisterReconfigurationCallback(SysGamma.reconfigured, nil)
            callbackInstalled = true
        }
        if quitObserver == nil {
            quitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                SysGamma.shared.restoreAll()
            }
        }
    }

    private func removeObservers() {
        if callbackInstalled {
            CGDisplayRemoveReconfigurationCallback(SysGamma.reconfigured, nil)
            callbackInstalled = false
        }
        if let quitObserver { NotificationCenter.default.removeObserver(quitObserver) }
        quitObserver = nil
    }

    /// 화면 구성이 바뀌면 (연결·해제·모드 변경) 감마가 초기화되므로 다시 적용한다
    private static let reconfigured: CGDisplayReconfigurationCallBack = { id, flags, _ in
        guard !flags.contains(.beginConfigurationFlag) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let g = SysGamma.shared
            guard let level = g.levels[id] else { return }
            if flags.contains(.removeFlag) { g.levels[id] = nil; g.originals[id] = nil; return }
            if let t = SysGamma.read(id) { g.originals[id] = t; g.apply(id, t, level) }
        }
    }
}

/// 외장 모니터 DDC/CI (Apple silicon IOAVService). 쓰기는 사용자가 조절할 때만.
final class SysDDC {
    static let shared = SysDDC()

    private typealias CreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<AnyObject>?
    private typealias I2CFn = @convention(c) (AnyObject, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private let create: CreateWithService?
    private let readI2C: I2CFn?
    private let writeI2C: I2CFn?
    private let lock = NSLock()

    enum VCP: UInt8 { case brightness = 0x10, contrast = 0x12, colorPreset = 0x14, input = 0x60 }

    private init() {
        let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        func sym<T>(_ n: String, _ t: T.Type) -> T? { h.flatMap { dlsym($0, n) }.map { unsafeBitCast($0, to: t) } }
        create = sym("IOAVServiceCreateWithService", CreateWithService.self)
        readI2C = sym("IOAVServiceReadI2C", I2CFn.self)
        writeI2C = sym("IOAVServiceWriteI2C", I2CFn.self)
    }

    var apiAvailable: Bool {
        #if arch(arm64)
        return create != nil && readI2C != nil && writeI2C != nil
        #else
        return false
        #endif
    }

    /// 외장 연결(DCPAVServiceProxy, Location = External)마다 AV 서비스 하나 (레지스트리 순서)
    func externalServices() -> [AnyObject] {
        guard apiAvailable, let create else { return [] }
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &it) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(it) }
        var list: [AnyObject] = []
        while case let s = IOIteratorNext(it), s != 0 {
            defer { IOObjectRelease(s) }
            let loc = IORegistryEntryCreateCFProperty(s, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            guard loc == "External", let av = create(kCFAllocatorDefault, s)?.takeRetainedValue() else { continue }
            list.append(av)
        }
        return list
    }

    /// 자체 검사용: AV 프록시 위치 목록 (I2C 통신 없음)
    func proxyLocations() -> [String] {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &it) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(it) }
        var out: [String] = []
        while case let s = IOIteratorNext(it), s != 0 {
            out.append(IORegistryEntryCreateCFProperty(s, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String ?? "?")
            IOObjectRelease(s)
        }
        return out
    }

    /// VCP 값 읽기 → (현재, 최대). 모니터가 답하지 않으면 nil. 백그라운드 큐에서 부른다.
    func read(_ service: AnyObject, _ vcp: VCP) -> (current: Int, max: Int)? {
        guard let readI2C, let writeI2C else { return nil }
        lock.lock(); defer { lock.unlock() }
        for _ in 0..<3 {
            var req: [UInt8] = [0x82, 0x01, vcp.rawValue, 0]
            req[3] = 0x6E ^ req[0] ^ req[1] ^ req[2]
            guard writeI2C(service, 0x37, 0x51, &req, UInt32(req.count)) == kIOReturnSuccess else { usleep(20_000); continue }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 11)
            guard readI2C(service, 0x37, 0x51, &reply, UInt32(reply.count)) == kIOReturnSuccess else { usleep(20_000); continue }
            // [0x6E, 0x88, 0x02, 결과, vcp, 형식, 최대H, 최대L, 현재H, 현재L, 검사합]
            guard reply[2] == 0x02, reply[3] == 0x00, reply[4] == vcp.rawValue else { usleep(20_000); continue }
            return (Int(reply[8]) << 8 | Int(reply[9]), Int(reply[6]) << 8 | Int(reply[7]))
        }
        return nil
    }

    /// VCP 값 쓰기 (사용자 조작에서만)
    @discardableResult
    func write(_ service: AnyObject, _ vcp: VCP, _ value: Int) -> Bool {
        guard let writeI2C else { return false }
        lock.lock(); defer { lock.unlock() }
        let hi = UInt8((value >> 8) & 0xff), lo = UInt8(value & 0xff)
        var pkt: [UInt8] = [0x84, 0x03, vcp.rawValue, hi, lo, 0]
        pkt[5] = 0x6E ^ 0x51 ^ pkt[0] ^ pkt[1] ^ pkt[2] ^ pkt[3] ^ pkt[4]
        for _ in 0..<2 {
            if writeI2C(service, 0x37, 0x51, &pkt, UInt32(pkt.count)) == kIOReturnSuccess { return true }
            usleep(20_000)
        }
        return false
    }
}

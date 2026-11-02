import CoreLocation
import CoreWLAN
import Darwin
import Foundation
import IOKit
import IOKit.usb

/// 현재 Wi-Fi 연결 정보 (CoreWLAN). SSID·BSSID는 위치 권한이 없으면 macOS가 가린다.
struct WiFiCardInfo: Equatable {
    var interfaceName: String?
    var powerOn = false
    var ssid: String?
    var associated = false
    var rssi = 0
    var noise = 0
    var txRate = 0.0
    var channel: Int?
    var band: String?
    var width: String?
    var security = ""
    var phy = ""
    var ipv4: String?

    /// RSSI → 막대 0…4
    var bars: Int {
        guard associated else { return 0 }
        switch rssi {
        case (-55)...: return 4
        case (-67)...: return 3
        case (-75)...: return 2
        case (-85)...: return 1
        default: return 0
        }
    }

    static func read() -> WiFiCardInfo {
        var w = WiFiCardInfo()
        guard let i = CWWiFiClient.shared().interface() else { return w }
        w.interfaceName = i.interfaceName
        w.powerOn = i.powerOn()
        w.ssid = i.ssid()
        w.rssi = i.rssiValue()
        w.noise = i.noiseMeasurement()
        w.txRate = i.transmitRate()
        w.associated = w.powerOn && (w.rssi != 0 || w.txRate > 0)
        if let ch = i.wlanChannel() {
            w.channel = ch.channelNumber
            switch ch.channelBand.rawValue {
            case 1: w.band = "2.4 GHz"
            case 2: w.band = "5 GHz"
            case 3: w.band = "6 GHz"
            default: w.band = nil
            }
            switch ch.channelWidth.rawValue {
            case 1: w.width = "20 MHz"
            case 2: w.width = "40 MHz"
            case 3: w.width = "80 MHz"
            case 4: w.width = "160 MHz"
            default: w.width = nil
            }
        }
        w.security = securityName(i.security())
        switch i.activePHYMode().rawValue {
        case 1: w.phy = "802.11a"
        case 2: w.phy = "802.11b"
        case 3: w.phy = "802.11g"
        case 4: w.phy = "Wi-Fi 4 (802.11n)"
        case 5: w.phy = "Wi-Fi 5 (802.11ac)"
        case 6: w.phy = "Wi-Fi 6 (802.11ax)"
        case 7: w.phy = "Wi-Fi 7 (802.11be)"
        default: w.phy = ""
        }
        if let name = i.interfaceName { w.ipv4 = ipv4(of: name) }
        return w
    }

    private static func securityName(_ s: CWSecurity) -> String {
        switch s.rawValue {
        case 0: return T("없음(개방)", "None (open)")
        case 1: return "WEP"
        case 2: return "WPA Personal"
        case 3: return "WPA/WPA2 Personal"
        case 4: return "WPA2 Personal"
        case 5: return "Personal"
        case 6: return "Dynamic WEP"
        case 7: return "WPA Enterprise"
        case 8: return "WPA/WPA2 Enterprise"
        case 9: return "WPA2 Enterprise"
        case 10: return "Enterprise"
        case 11: return "WPA3 Personal"
        case 12: return "WPA3 Enterprise"
        case 13: return "WPA2/WPA3 Personal"
        case 14: return "OWE"
        case 15: return "OWE Transition"
        default: return T("알 수 없음", "Unknown")
        }
    }

    static func ipv4(of interface: String) -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            let ifa = cur.pointee
            if String(cString: ifa.ifa_name) == interface, let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            p = ifa.ifa_next
        }
        return nil
    }

    /// 위치 권한 상태 (요청하지 않고 읽기만)
    static func locationStatus() -> CLAuthorizationStatus { CLLocationManager().authorizationStatus }

    static func locationStatusText(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return T("아직 묻지 않음", "not requested yet")
        case .restricted: return T("제한됨", "restricted")
        case .denied: return T("거부됨", "denied")
        case .authorizedAlways: return T("허용됨", "allowed")
        @unknown default: return T("허용됨", "allowed")
        }
    }
}

/// USB 장치 (IOUSBHostDevice). 허브는 빼고 빠른 순·이름순으로 정렬한다.
struct USBDeviceInfo: Identifiable, Equatable {
    var id: UInt64
    var name: String
    var vendor: String?
    /// 초당 비트 (협상 속도)
    var speed: Double?

    var speedText: String {
        guard let s = speed else { return T("속도 모름", "Unknown speed") }
        if s >= 1e9 { return String(format: s.truncatingRemainder(dividingBy: 1e9) == 0 ? "%.0f Gb/s" : "%.1f Gb/s", s / 1e9) }
        if s >= 1e6 { return String(format: s >= 1e7 ? "%.0f Mb/s" : "%.1f Mb/s", s / 1e6) }
        return String(format: "%.0f kb/s", s / 1e3)
    }

    var speedClass: String {
        guard let s = speed else { return "" }
        switch s {
        case 20e9...: return "USB 3.2 Gen 2x2 / USB4"
        case 10e9...: return "USB 3.2 Gen 2"
        case 5e9...: return "USB 3.2 Gen 1"
        case 480e6...: return "USB 2.0 High Speed"
        case 12e6...: return "USB Full Speed"
        default: return "USB Low Speed"
        }
    }

    static func readAll() -> [USBDeviceInfo] {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &it) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(it) }
        var list: [USBDeviceInfo] = []
        while case let s = IOIteratorNext(it), s != 0 {
            defer { IOObjectRelease(s) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(s, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let d = props?.takeRetainedValue() as? [String: Any] else { continue }
            if (d["bDeviceClass"] as? NSNumber)?.intValue == 9 { continue }   // 허브
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(s, &entryID)
            var nameBuf = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(s, &nameBuf)
            let name = (d["USB Product Name"] as? String) ?? (d["kUSBProductString"] as? String) ?? String(cString: nameBuf)
            let vendor = (d["USB Vendor Name"] as? String) ?? (d["kUSBVendorString"] as? String)
            var speed: Double?
            if let link = (d["UsbLinkSpeed"] as? NSNumber)?.doubleValue, link > 0 {
                speed = link
            } else if let code = (d["Device Speed"] as? NSNumber)?.intValue {
                speed = [0: 1.5e6, 1: 12e6, 2: 480e6, 3: 5e9, 4: 10e9, 5: 20e9][code]
            }
            list.append(USBDeviceInfo(id: entryID, name: name, vendor: vendor, speed: speed))
        }
        return list.sorted { ($0.speed ?? 0, $1.name) > ($1.speed ?? 0, $0.name) }
    }
}

/// USB 연결·해제 알림 (탭이 보이는 동안만)
final class USBWatcher {
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var onChange: (() -> Void)?

    func start(_ onChange: @escaping () -> Void) {
        guard port == nil else { return }
        self.onChange = onChange
        guard let p = IONotificationPortCreate(kIOMainPortDefault) else { return }
        port = p
        IONotificationPortSetDispatchQueue(p, .main)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var it: io_iterator_t = 0
            let r = IOServiceAddMatchingNotification(p, type, IOServiceMatching("IOUSBHostDevice"), { refcon, iterator in
                USBWatcher.drain(iterator)
                guard let refcon else { return }
                Unmanaged<USBWatcher>.fromOpaque(refcon).takeUnretainedValue().onChange?()
            }, ctx, &it)
            if r == KERN_SUCCESS {
                USBWatcher.drain(it)   // 처음 목록을 비워야 다음 알림이 온다
                iterators.append(it)
            }
        }
    }

    func stop() {
        iterators.forEach { IOObjectRelease($0) }
        iterators.removeAll()
        if let port { IONotificationPortDestroy(port) }
        port = nil
        onChange = nil
    }

    private static func drain(_ it: io_iterator_t) {
        while case let s = IOIteratorNext(it), s != 0 { IOObjectRelease(s) }
    }
}

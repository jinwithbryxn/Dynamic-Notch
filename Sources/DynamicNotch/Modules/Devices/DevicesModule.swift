import AppKit
import CoreLocation
import SwiftUI

/// 기기: Wi-Fi 신호 카드(RSSI·속도·채널·보안·로컬 IP, 요청할 때만 공인 IP·암호)와 USB 장치(협상 속도·제품명·제조사).
/// 탭이 보이는 동안만 Wi-Fi를 2초마다 읽고 USB 연결·해제 알림을 받는다.
final class DevicesModule: NotchModule {
    let id = "devices"
    var title: String { T("기기", "Devices") }
    let symbol = "cable.connector"
    var enabledByDefault: Bool { false }

    let model = DevicesModel()
    private var context: ModuleContext?

    func start(context: ModuleContext) { self.context = context }

    func stop() {
        model.stopLive()
        model.forgetSecrets()
        context = nil
    }

    func tabView() -> AnyView? { AnyView(DevicesTab(model: model)) }
    var tabContentSize: CGSize { CGSize(width: 580, height: 270) }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "devices.open", title: T("Wi-Fi 신호와 USB 장치", "Wi-Fi signal and USB devices"),
                       subtitle: T("RSSI·속도·채널, USB 협상 속도", "RSSI, rate, channel, USB link speed"),
                       symbol: "wifi", keywords: ["wifi", "usb", "와이파이", "신호", "signal", "ip"]) { [weak self] in
            guard let self else { return }
            self.context?.openTab(self.id)
        }]
    }

    func selfTest() -> [String] {
        let w = WiFiCardInfo.read()
        var lines: [String] = []
        lines.append("wifi interface \(w.interfaceName ?? "-") power \(w.powerOn) associated \(w.associated) ssid \(w.ssid == nil ? "hidden/none" : "present (not printed)")")
        lines.append("rssi \(w.rssi) dBm noise \(w.noise) dBm bars \(w.bars) tx \(w.txRate) Mbps channel \(w.channel.map(String.init) ?? "-") \(w.band ?? "-") \(w.width ?? "-") security \(w.security) phy \(w.phy) ipv4 \(w.ipv4 ?? "-")")
        lines.append("location authorization: \(WiFiCardInfo.locationStatusText(WiFiCardInfo.locationStatus())) usage string present: \(DevicesModel.hasLocationUsageString)")
        let usb = USBDeviceInfo.readAll()
        lines.append("usb devices (hubs excluded): \(usb.count)")
        for d in usb { lines.append("  \(d.name) · \(d.vendor ?? "-") · \(d.speedText)") }
        return lines
    }
}

final class DevicesModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var wifi = WiFiCardInfo()
    @Published var usb: [USBDeviceInfo] = []
    @Published var location: CLAuthorizationStatus = .notDetermined
    @Published var publicIP: String?
    @Published var publicIPState: String?
    @Published var password: String?
    @Published var passwordState: String?
    @Published var passwordBusy = false

    private var timer: Timer?
    private let watcher = USBWatcher()
    private var locationManager: CLLocationManager?
    private let queue = DispatchQueue(label: "com.dynamicnotch.devices", qos: .utility)
    private var ipTask: URLSessionDataTask?

    static var hasLocationUsageString: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSLocationUsageDescription") != nil
            || Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil
    }

    func startLive() {
        refreshWiFi()
        usb = USBDeviceInfo.readAll()
        location = WiFiCardInfo.locationStatus()
        if timer == nil {
            let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refreshWiFi() }
            t.tolerance = 0.5
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        watcher.start { [weak self] in
            // 연결 직후 이름·속도가 채워지도록 잠깐 뒤에 읽는다
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.usb = USBDeviceInfo.readAll() }
        }
    }

    func stopLive() {
        timer?.invalidate(); timer = nil
        watcher.stop()
        ipTask?.cancel(); ipTask = nil
    }

    /// 카드를 닫으면 암호를 메모리에서 지운다
    func forgetSecrets() {
        password = nil
        passwordState = nil
    }

    private func refreshWiFi() {
        queue.async { [weak self] in
            let w = WiFiCardInfo.read()
            DispatchQueue.main.async { self?.wifi = w }
        }
    }

    // MARK: 위치 권한 (SSID 표시용, 사용자가 누를 때만)

    func requestLocation() {
        let m = CLLocationManager()
        m.delegate = self
        locationManager = m
        m.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.location = manager.authorizationStatus
            self.refreshWiFi()
        }
    }

    static func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: 공인 IP (누를 때만 api.ipify.org 한 번)

    func lookUpPublicIP() {
        guard let url = URL(string: "https://api.ipify.org") else { return }
        publicIPState = T("조회 중…", "Looking up…")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        req.setValue("DynamicNotch", forHTTPHeaderField: "User-Agent")
        ipTask = URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            let text = data.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200 && (text?.isEmpty == false)
            DispatchQueue.main.async {
                self?.publicIP = ok ? text : nil
                self?.publicIPState = ok ? nil : T("조회 실패", "Lookup failed")
            }
        }
        ipTask?.resume()
    }

    // MARK: Wi-Fi 암호 (누를 때만, macOS 인증 창을 거침, 저장·로그 없음)

    func revealPassword() {
        guard let ssid = wifi.ssid, !ssid.isEmpty else {
            passwordState = T("네트워크 이름(SSID)이 가려져 있어 키체인 항목을 찾을 수 없음. 위치 권한을 허용하세요.",
                              "The network name (SSID) is hidden, so the keychain item cannot be found. Allow Location access.")
            return
        }
        passwordBusy = true
        passwordState = T("macOS 인증 창을 확인하세요", "Check the macOS authentication dialog")
        queue.async { [weak self] in
            // 시스템 키체인의 이 네트워크 항목만 읽는다. macOS가 관리자 인증 창을 띄운다.
            let r = SysCommand.run("/usr/bin/security", ["find-generic-password", "-wa", ssid], timeout: 120)
            let value = r?.output.trimmingCharacters(in: .newlines)
            DispatchQueue.main.async {
                guard let self else { return }
                self.passwordBusy = false
                if let r, r.status == 0, let value, !value.isEmpty {
                    self.password = value
                    self.passwordState = nil
                } else {
                    self.password = nil
                    self.passwordState = T("보여 주지 못함 (취소했거나 항목이 없음)", "Not shown (cancelled or no keychain item)")
                }
            }
        }
    }

    func copyPassword() {
        guard let password else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(password, forType: .string)
        // 클립보드 기록 앱이 저장하지 않도록 표시
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    }
}

// MARK: - 탭

private struct DevicesTab: View {
    @ObservedObject var model: DevicesModel

    var body: some View {
        HStack(spacing: 8) {
            wifiCard.frame(width: 300)
            usbCard
        }
        .foregroundStyle(.white)
        .onAppear { model.startLive() }
        .onDisappear { model.stopLive(); model.forgetSecrets() }
    }

    private var wifiCard: some View {
        let w = model.wifi
        return SysCard {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    WiFiBars(bars: w.bars, active: w.associated)
                        .frame(width: 22, height: 16)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title(w)).font(.island(.subhead, .semibold)).lineLimit(1)
                        Text(w.interfaceName.map { "\($0) · \(w.phy)" } ?? T("Wi-Fi 없음", "No Wi-Fi"))
                            .font(.island(.caption2)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    }
                    Spacer()
                }
                if w.associated {
                    row(T("신호", "Signal"), "\(w.rssi) dBm", hint: T("잡음 \(w.noise)", "noise \(w.noise)"))
                    row(T("연결 속도", "Link rate"), String(format: "%.0f Mbps", w.txRate))
                    row(T("채널", "Channel"), [w.channel.map(String.init), w.band, w.width].compactMap { $0 }.joined(separator: " · "))
                    row(T("보안", "Security"), w.security)
                    row(T("로컬 IP", "Local IP"), w.ipv4 ?? "–")
                    HStack {
                        Text(T("공인 IP", "Public IP")).font(.island(.footnote)).foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        if let ip = model.publicIP {
                            Text(ip).font(.island(.footnote, design: .rounded)).textSelection(.enabled)
                        } else {
                            if let s = model.publicIPState { Text(s).font(.island(.caption)).foregroundStyle(.white.opacity(0.5)) }
                            SysPillButton(title: T("조회", "Look up"),
                                          help: T("api.ipify.org에 한 번 요청합니다", "Sends one request to api.ipify.org")) { model.lookUpPublicIP() }
                        }
                    }
                    passwordRow
                } else {
                    Text(w.powerOn ? T("연결된 네트워크 없음", "Not connected") : T("Wi-Fi 꺼짐", "Wi-Fi is off"))
                        .font(.island(.footnote)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                if w.associated, w.ssid == nil { locationNote }
            }
        }
    }

    private func title(_ w: WiFiCardInfo) -> String {
        if !w.powerOn { return T("Wi-Fi 꺼짐", "Wi-Fi Off") }
        if !w.associated { return "Wi-Fi" }
        return w.ssid ?? T("이름 가려짐", "Name hidden")
    }

    private var passwordRow: some View {
        HStack(spacing: 6) {
            Text(T("암호", "Password")).font(.island(.footnote)).foregroundStyle(.white.opacity(0.65))
            Spacer()
            if let pw = model.password {
                Text(pw).font(.island(.footnote, .medium, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                SysPillButton(title: T("복사", "Copy"), symbol: "doc.on.doc") { model.copyPassword() }
                SysPillButton(title: T("가리기", "Hide"), symbol: "eye.slash") { model.forgetSecrets() }
            } else if model.passwordBusy {
                ProgressView().controlSize(.mini)
            } else {
                if let s = model.passwordState {
                    Text(s).font(.island(.caption2)).foregroundStyle(.white.opacity(0.5)).lineLimit(2).frame(maxWidth: 150, alignment: .trailing)
                }
                SysPillButton(title: T("보기", "Show"), symbol: "key",
                              help: T("현재 네트워크의 키체인 항목을 macOS 인증 후 한 번 읽습니다. 저장하지 않습니다.",
                                      "Reads this network's keychain item once after macOS authentication. Nothing is stored.")) { model.revealPassword() }
            }
        }
    }

    private var locationNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(T("macOS가 네트워크 이름을 가림: 위치 권한 \(WiFiCardInfo.locationStatusText(model.location))",
                   "macOS hides the network name: Location access \(WiFiCardInfo.locationStatusText(model.location))"))
                .font(.island(.caption2)).foregroundStyle(.yellow.opacity(0.85))
            if model.location == .notDetermined, DevicesModel.hasLocationUsageString {
                SysPillButton(title: T("위치 권한 요청", "Allow Location"), symbol: "location") { model.requestLocation() }
            } else {
                SysPillButton(title: T("위치 서비스 설정", "Location Settings"), symbol: "gearshape") { DevicesModel.openLocationSettings() }
            }
        }
    }

    private func row(_ title: String, _ value: String, hint: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.island(.footnote)).foregroundStyle(.white.opacity(0.65))
            Spacer()
            if let hint { Text(hint).font(.island(.caption2)).foregroundStyle(.white.opacity(0.4)) }
            Text(value).font(.island(.footnote, design: .rounded)).monospacedDigit().lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var usbCard: some View {
        SysCard {
            VStack(alignment: .leading, spacing: 6) {
                SysHeader(text: T("USB 장치 · 빠른 순", "USB devices · fastest first"))
                if model.usb.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "cable.connector.slash").font(.island(.title1, .regular)).foregroundStyle(.white.opacity(0.35))
                        Text(T("연결된 USB 장치 없음", "No USB devices connected")).font(.island(.footnote)).foregroundStyle(.white.opacity(0.55))
                        Text(T("내장 키보드·트랙패드·허브는 목록에서 뺍니다", "Built-in keyboard, trackpad and hubs are not listed"))
                            .font(.island(.caption2)).foregroundStyle(.white.opacity(0.4)).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(model.usb) { d in
                                HStack(spacing: 8) {
                                    Image(systemName: "cable.connector").font(.island(.subhead)).foregroundStyle(.white.opacity(0.7))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(d.name).font(.island(.footnote)).lineLimit(1)
                                        Text(d.vendor ?? "–").font(.island(.caption2)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(d.speedText).font(.island(.footnote, design: .rounded)).monospacedDigit()
                                        Text(d.speedClass).font(.island(.caption2)).foregroundStyle(.white.opacity(0.45))
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Wi-Fi 막대 (RSSI 기준 4칸)
private struct WiFiBars: View {
    let bars: Int
    let active: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(active && i < bars ? Color.white : Color.white.opacity(0.2))
                    .frame(width: 4, height: CGFloat(4 + i * 4))
            }
        }
        .accessibilityLabel(T("신호 \(bars)칸", "\(bars) bars"))
    }
}

import AppKit
import CoreBluetooth
import IOBluetooth
import IOKit.ps
import SwiftUI

/// 기기 배터리: 페어링된 블루투스 기기와 배터리(AirPods 좌·우·케이스 따로), 연결 안 된 오디오 기기 연결 버튼,
/// 블루투스 설정 열기, 배터리 부족 알림(기본 10%, 한 번 알리고 10%p 충전 전엔 다시 안 알림, 10분 주기).
/// 목록은 system_profiler(권한 불필요)와 액세서리 전원 목록(비공개 IOPS, dlsym)에서 읽고 IOBluetooth 등록은 하지 않는다.
final class BluetoothBatteryModule: NotchModule {
    let id = "btbattery"
    var title: String { T("기기 배터리", "Device Batteries") }
    let symbol = "battery.75percent"
    /// 10분마다 배터리를 읽으므로 기본 꺼짐
    let enabledByDefault = false

    let model = MBBatteryModel(module: "btbattery")

    func start(context: ModuleContext) { model.start(context: context) }
    func stop() { model.stop() }
    func settingsChanged() { model.objectWillChange.send() }

    func tabView() -> AnyView? { AnyView(BatteryTab(model: model)) }
    var tabContentSize: CGSize { CGSize(width: 460, height: 260) }

    func settingsView() -> AnyView? { AnyView(BatterySettings(module: id)) }

    func selfTest() -> [String] {
        var lines: [String] = []
        let started = Date()
        let devices = MBBatteryModel.readDevices()
        lines.append(String(format: "system_profiler read in %.1fs: %d paired devices", Date().timeIntervalSince(started), devices.count))
        for d in devices {
            lines.append("  \(d.connected ? "●" : "○") \(d.name) [\(d.symbol)] \(MBBatteryModel.batteryText(d.battery) ?? "no battery reported")")
        }
        let acc = MBBatteryModel.accessoryLevels()
        lines.append("accessory power sources (IOPS): \(acc.isEmpty ? "none" : acc.map { "\($0.key) \($0.value)%" }.joined(separator: ", "))")
        lines.append("bluetooth permission (read only): \(CBManager.authorization == .allowedAlways ? "allowed" : "not allowed") → connect buttons \(CBManager.authorization == .allowedAlways ? "shown" : "hidden")")
        return lines
    }
}

struct MBBTDevice: Identifiable, Equatable {
    var id: String { address.isEmpty ? name : address }
    var name: String
    var address: String
    var connected: Bool
    var symbol: String
    var minorType: String
    var battery: BluetoothMonitor.Battery?

    var isAudio: Bool { ["headphones", "headset", "speaker", "loudspeaker", "headphone"].contains(minorType.lowercased()) || symbol.hasPrefix("airpods") || symbol.hasPrefix("beats") }
}

final class MBBatteryModel: ObservableObject {
    @Published private(set) var devices: [MBBTDevice] = []
    @Published private(set) var loading = false
    @Published private(set) var updated: Date?
    @Published private(set) var connecting: String?

    private let defaults: ModuleDefaults
    private var context: ModuleContext?
    private var timer: Timer?
    private var running = false
    /// 경고를 보낸 기기와 그때 값 (UserDefaults: 다시 켜도 같은 경고를 반복하지 않게)
    private var warned: [String: Int] {
        get { (UserDefaults.standard.dictionary(forKey: "module.btbattery.warned") as? [String: Int]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "module.btbattery.warned") }
    }
    private var connectTarget: MBConnectTarget?

    init(module: String) { defaults = ModuleDefaults(module: module) }

    var threshold: Int { defaults.int("threshold", default: 10) }

    func start(context: ModuleContext) {
        guard !running else { return }
        running = true
        self.context = context
        guard !MBAudio.isDevTool else { return }
        let t = Timer(timeInterval: 600, repeats: true) { [weak self] _ in self?.checkLow() }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.checkLow() }
    }

    func stop() {
        guard running else { return }
        running = false
        timer?.invalidate()
        timer = nil
        connectTarget = nil
        context = nil
    }

    // MARK: 목록

    func refresh() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let list = Self.readDevices()
            DispatchQueue.main.async {
                self?.devices = list
                self?.loading = false
                self?.updated = Date()
            }
        }
    }

    /// system_profiler(느림, 백그라운드) + 액세서리 전원 목록(더 새 값)으로 기기 목록을 만든다
    static func readDevices() -> [MBBTDevice] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = json["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var out: [MBBTDevice] = []
        for section in sections {
            for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
                for entry in section[key] as? [[String: Any]] ?? [] {
                    for (name, raw) in entry {
                        guard let info = raw as? [String: Any] else { continue }
                        func level(_ k: String) -> Int? {
                            (info[k] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
                        }
                        var b = BluetoothMonitor.Battery(main: level("device_batteryLevelMain") ?? level("device_batteryLevel"),
                                                         left: level("device_batteryLevelLeft"), right: level("device_batteryLevelRight"),
                                                         caseLevel: level("device_batteryLevelCase"))
                        if connected, let fresh = BluetoothMonitor.accessoryBattery(name: name) {
                            b = BluetoothMonitor.Battery(main: fresh.main ?? b.main, left: fresh.left ?? b.left, right: fresh.right ?? b.right,
                                                         caseLevel: fresh.caseLevel ?? b.caseLevel)
                        }
                        let address = info["device_address"] as? String ?? ""
                        if connected, b.primary == nil, let hid = BluetoothMonitor.hidBattery(name: name, address: address) { b = hid }
                        let minor = info["device_minorType"] as? String ?? ""
                        let symbol = BluetoothMonitor.appleSymbol(vendor: info["device_vendorID"] as? String, product: info["device_productID"] as? String)
                            ?? BluetoothMonitor.minorTypeSymbol(minor) ?? BluetoothMonitor.nameSymbol(name.lowercased())
                            ?? (name.lowercased().contains("watch") ? "applewatch" : "dot.radiowaves.left.and.right")
                        out.append(MBBTDevice(name: name, address: address, connected: connected, symbol: symbol, minorType: minor,
                                              battery: b.primary == nil && b.caseLevel == nil ? nil : b))
                    }
                }
            }
        }
        return out.sorted { ($0.connected ? 0 : 1, $0.name) < ($1.connected ? 0 : 1, $1.name) }
    }

    static func batteryText(_ b: BluetoothMonitor.Battery?) -> String? {
        guard let b else { return nil }
        if let buds = b.budsSummary { return buds }
        var parts: [String] = []
        if let m = b.main { parts.append("\(m)%") }
        if let c = b.caseLevel { parts.append(T("케이스 \(c)%", "Case \(c)%")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 액세서리 전원 목록 전체 (이름 → 가장 낮은 값). 비공개 IOPSCopyPowerSourcesByType(4)
    static func accessoryLevels() -> [String: Int] {
        var out: [String: Int] = [:]
        for d in PowerSources.accessories() {
            guard let name = d["Name"] as? String else { continue }
            // 케이스는 경고 대상이 아니다
            if (d["Part Identifier"] as? String) == "Case" { continue }
            var levels: [Int] = []
            if let parts = d["Combined Parts"] as? [[String: Any]] { levels = parts.compactMap { $0["Current Capacity"] as? Int } }
            if levels.isEmpty, let l = d["Current Capacity"] as? Int { levels = [l] }
            if let low = levels.min() { out[name] = min(out[name] ?? 100, low) }
        }
        return out
    }

    // MARK: 배터리 부족 알림

    private func checkLow() {
        guard running else { return }
        let limit = threshold
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let levels = Self.accessoryLevels()
            DispatchQueue.main.async {
                guard let self, self.running else { return }
                var w = self.warned
                for (name, level) in levels {
                    if let prev = w[name] {
                        // 10%p 넘게 충전되면 다시 알릴 수 있게
                        if level >= prev + 10 { w[name] = nil }
                        continue
                    }
                    if level <= limit {
                        w[name] = level
                        self.context?.notice(T("\(name) 배터리 \(level)%", "\(name) battery \(level)%"), T("충전이 필요합니다", "Needs charging"),
                                             symbol: "battery.25percent", tint: .red, tab: "btbattery")
                    }
                }
                self.warned = w
            }
        }
    }

    // MARK: 연결 (사용자가 눌렀을 때만, 블루투스 권한이 이미 있을 때)

    var canConnect: Bool { CBManager.authorization == .allowedAlways }

    func connect(_ d: MBBTDevice) {
        guard canConnect, let dev = IOBluetoothDevice(addressString: d.address) else { return }
        connecting = d.id
        let target = MBConnectTarget { [weak self] in
            DispatchQueue.main.async {
                self?.connecting = nil
                self?.refresh()
            }
        }
        connectTarget = target
        if dev.openConnection(target) != kIOReturnSuccess {
            connecting = nil
        }
    }

    static func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") { NSWorkspace.shared.open(url) }
    }
}

/// IOBluetooth 비동기 연결 완료 콜백
final class MBConnectTarget: NSObject {
    let done: () -> Void
    init(done: @escaping () -> Void) { self.done = done }
    @objc func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) { done() }
}

// MARK: - 화면

private struct BatteryTab: View {
    @ObservedObject var model: MBBatteryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(T("블루투스 기기", "Bluetooth devices")).font(.island(.subhead, .semibold))
                if model.loading { ProgressView().controlSize(.small).scaleEffect(0.7) }
                Spacer()
                MBPillButton(title: T("새로 고침", "Refresh"), symbol: "arrow.clockwise") { model.refresh() }
                MBPillButton(title: T("블루투스 설정", "Bluetooth Settings"), symbol: "gearshape") { MBBatteryModel.openBluetoothSettings() }
            }
            if model.devices.isEmpty {
                Spacer()
                Text(model.loading ? T("기기 정보를 읽는 중…", "Reading devices…") : T("페어링된 블루투스 기기가 없습니다", "No paired Bluetooth devices"))
                    .font(.island(.footnote)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(model.devices) { d in row(d) }
                    }
                }
            }
            Text(model.canConnect ? T("배터리 부족 알림: \(model.threshold)% 이하일 때 한 번 (10분마다 확인)", "Low battery alert at \(model.threshold)% or less, once (checked every 10 min)")
                                  : T("연결 버튼은 블루투스 권한이 허용된 뒤에 보입니다. 배터리 부족 알림: \(model.threshold)% 이하", "Connect buttons appear once Bluetooth access is allowed. Low battery alert at \(model.threshold)%"))
                .font(.island(.caption2)).foregroundStyle(.white.opacity(0.4))
        }
        .foregroundStyle(.white)
        .onAppear { model.refresh() }
    }

    private func row(_ d: MBBTDevice) -> some View {
        HStack(spacing: 8) {
            Image(systemName: d.symbol).font(.island(.subhead)).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(d.name).font(.island(.footnote)).lineLimit(1)
                Text(d.connected ? (detailText(d) ?? T("연결됨 · 배터리 정보 없음", "Connected · no battery info")) : T("연결 안 됨", "Not connected"))
                    .font(.island(.caption)).foregroundStyle(lowColor(d)).lineLimit(1)
            }
            Spacer()
            if let p = d.battery?.primary, d.connected {
                BatteryBar(level: p, warn: p <= model.threshold)
            } else if !d.connected, d.isAudio, model.canConnect {
                MBPillButton(title: model.connecting == d.id ? T("연결 중…", "Connecting…") : T("연결", "Connect"), symbol: "link") { model.connect(d) }
                    .disabled(model.connecting != nil)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(d.connected ? 0.08 : 0.04)))
        .opacity(d.connected ? 1 : 0.75)
    }

    /// 좌·우·케이스가 있으면 그 값, 하나뿐이면 오른쪽 막대에 있으니 '연결됨'
    private func detailText(_ d: MBBTDevice) -> String? {
        guard let b = d.battery else { return nil }
        if let buds = b.budsSummary { return buds }
        if let c = b.caseLevel { return T("연결됨 · 케이스 \(c)%", "Connected · Case \(c)%") }
        return T("연결됨", "Connected")
    }

    private func lowColor(_ d: MBBTDevice) -> Color {
        if let p = d.battery?.primary, d.connected, p <= model.threshold { return .red }
        return .white.opacity(0.55)
    }
}

private struct BatteryBar: View {
    let level: Int
    let warn: Bool
    var body: some View {
        HStack(spacing: 4) {
            Text("\(level)%").font(.island(.footnote)).monospacedDigit()
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).stroke(Color.white.opacity(0.5), lineWidth: 1).frame(width: 22, height: 10)
                RoundedRectangle(cornerRadius: 1).fill(warn ? Color.red : Color.green)
                    .frame(width: max(2, 20 * CGFloat(level) / 100), height: 8).padding(.leading, 1)
            }
        }
        .accessibilityLabel(T("배터리 \(level)%", "Battery \(level)%"))
    }
}

private struct BatterySettings: View {
    let module: String
    @State private var threshold = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper(T("배터리 부족 알림: \(threshold)% 이하", "Low battery alert: \(threshold)% or less"), value: $threshold, in: 5...30, step: 5)
                .onChange(of: threshold) { _, newValue in ModuleDefaults(module: module).set(newValue, "threshold") }
            Text(T("마우스·키보드·이어폰 등 배터리를 알려 주는 액세서리를 10분마다 확인하고, 한 번 알린 기기는 10%p 넘게 충전될 때까지 다시 알리지 않습니다. iPhone·iPad 배터리는 공개 경로가 없어 빠집니다.",
                   "Accessories that report a battery are checked every 10 minutes. A device is alerted once and not again until it charges 10 points. iPhone and iPad batteries aren't included (no public path)."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { threshold = ModuleDefaults(module: module).int("threshold", default: 10) }
    }
}

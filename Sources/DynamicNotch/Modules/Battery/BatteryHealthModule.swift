import AppKit
import IOKit.ps
import SwiftUI

/// 배터리 상태·알림: 성능 상태·사이클·온도, 부족(소리)·연결·분리·완충 기준 알림, 저전력 모드 켜짐, 비정상 소모 경고.
/// 충전 한도·Sailing·자동 방전·일회성 완충·팬 제어·저전력 모드 전환은 관리자 헬퍼(SMC 쓰기, pmset)가 필요해 보류하고
/// 하드웨어 지원 여부와 팬 회전수만 읽어서 보여 준다.
final class BatteryHealthModule: NotchModule {
    let id = "batteryhealth"
    var title: String { T("배터리", "Battery") }
    let symbol = "battery.100percent"
    var enabledByDefault: Bool { false }

    let model = BatteryHealthModel()
    private var context: ModuleContext?
    private var source: CFRunLoopSource?
    private var lpmObserver: NSObjectProtocol?
    private var last: BatteryHealthReading?
    private var lowArmed = true
    private var lastACChange = Date.distantPast

    // 비정상 소모 감시
    private var drainTimer: Timer?
    private let drainReader = SysProcReader()
    private var highSince: [pid_t: Date] = [:]
    private var lastWarned: [String: Date] = [:]
    private let drainQueue = DispatchQueue(label: "com.dynamicnotch.battery.drain", qos: .utility)

    var defaults: ModuleDefaults { ModuleDefaults(module: id) }

    func start(context: ModuleContext) {
        self.context = context
        guard source == nil else { return }
        last = BatteryHealthReading.read()
        model.reading = last ?? BatteryHealthReading()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ c in
            guard let c else { return }
            Unmanaged<BatteryHealthModule>.fromOpaque(c).takeUnretainedValue().powerChanged()
        }, ctx)?.takeRetainedValue() {
            source = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        lpmObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.lowPowerChanged()
        }
        updateDrainWatch()
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
        if let lpmObserver { NotificationCenter.default.removeObserver(lpmObserver) }
        lpmObserver = nil
        drainTimer?.invalidate(); drainTimer = nil
        highSince.removeAll()
        model.stopLive()
        SysScreenGlow.dismiss()
        context = nil
    }

    func settingsChanged() { updateDrainWatch() }

    // MARK: 설정

    var lowAlert: Bool { defaults.bool("lowAlert", default: true) }
    var lowThreshold: Int { defaults.int("lowThreshold", default: 20) }
    var lowSound: String { defaults.string("lowSound", default: "Basso") }
    var plugAlert: Bool { defaults.bool("plugAlert", default: false) }
    var plugSound: String { defaults.string("plugSound", default: "") }
    var unplugAlert: Bool { defaults.bool("unplugAlert", default: true) }
    var unplugSound: String { defaults.string("unplugSound", default: "") }
    var fullAlert: Bool { defaults.bool("fullAlert", default: false) }
    var fullLevel: Int { defaults.int("fullLevel", default: 80) }
    var fullSound: String { defaults.string("fullSound", default: "") }
    var lpmAlert: Bool { defaults.bool("lpmAlert", default: true) }
    var drainAlert: Bool { defaults.bool("drainAlert", default: true) }
    var drainMinutes: Int { defaults.int("drainMinutes", default: 3) }
    var glow: Bool { defaults.bool("glow", default: false) }

    // MARK: 전원 변화

    enum PowerEvent: Equatable { case plugged, unplugged, low, full }

    /// 이전·새 상태로 알릴 일을 고른다 (무장 상태만 바꾸고 화면·소리는 없음, 자체 검사에서도 씀)
    func evaluate(old: BatteryHealthReading, new: BatteryHealthReading, now: Date = Date()) -> [PowerEvent] {
        var events: [PowerEvent] = []
        if new.onAC != old.onAC {
            let quick = now.timeIntervalSince(lastACChange) < 2   // 빠르게 뺐다 꽂으면 무시
            lastACChange = now
            if !quick {
                if new.onAC, plugAlert { events.append(.plugged) }
                if !new.onAC, unplugAlert { events.append(.unplugged) }
            }
        }
        // 부족: 기준을 아래로 지날 때 한 번. 충전기를 꽂거나 기준 +5%를 넘으면 다시 무장.
        if new.onAC || new.percent >= lowThreshold + 5 { lowArmed = true }
        if lowAlert, lowArmed, !new.onAC, new.percent <= lowThreshold, old.percent > new.percent || old.onAC {
            lowArmed = false
            events.append(.low)
        }
        // 완충 기준: 충전 중 기준을 위로 지날 때
        if fullAlert, new.onAC, old.percent < fullLevel, new.percent >= fullLevel { events.append(.full) }
        return events
    }

    private func powerChanged() {
        let new = BatteryHealthReading.read()
        model.reading = new
        defer { last = new; updateDrainWatch() }
        guard let old = last, new.present else { return }
        for e in evaluate(old: old, new: new) {
            switch e {
            case .plugged: postPlug(new); SysSounds.play(plugSound)
            case .unplugged: postUnplug(new); SysSounds.play(unplugSound)
            case .low:
                postLow(new); SysSounds.play(lowSound)
                if glow { SysScreenGlow.flash(.systemRed) }
            case .full:
                postFull(new); SysSounds.play(fullSound)
                if glow { SysScreenGlow.flash(.systemGreen) }
            }
        }
    }

    private func lowPowerChanged() {
        let on = ProcessInfo.processInfo.isLowPowerModeEnabled
        model.reading.lowPowerMode = on
        guard on, lpmAlert, let context else { return }
        context.center.post(NotchActivity(
            kind: .battery, presentation: .compact, symbol: "battery.100percent", tint: .yellow,
            value: .text(T("저전력", "Low Power")), title: T("저전력 모드 켜짐", "Low Power Mode On"),
            subtitle: T("성능을 낮춰 배터리를 아낍니다", "Performance is reduced to save battery"),
            valueTint: .yellow, moduleTab: id))
    }

    static func levelColor(_ percent: Int) -> Color { percent <= 10 ? .red : percent <= 20 ? .orange : .green }

    private func glyph(_ r: BatteryHealthReading, charging: Bool) -> BatteryGlyphInfo {
        BatteryGlyphInfo(level: Double(r.percent) / 100, charging: charging)
    }

    private func postPlug(_ r: BatteryHealthReading) {
        var sub = T("충전 중", "Charging")
        if let m = r.minutesToFull { sub = T("완충까지 \(SysFmt.minutes(m))", "\(SysFmt.minutes(m)) until full") }
        context?.center.post(NotchActivity(
            kind: .battery, presentation: .compact, symbol: "bolt.fill", tint: .green, value: .text("\(r.percent)%"),
            title: T("충전기 연결됨", "Charger Connected"), subtitle: sub, detailValue: .percent(Double(r.percent) / 100),
            wing: 56, valueTint: Self.levelColor(r.percent), battery: glyph(r, charging: true), moduleTab: id))
    }

    private func postUnplug(_ r: BatteryHealthReading) {
        let sub = r.minutesToEmpty.map { T("약 \(SysFmt.minutes($0)) 남음", "About \(SysFmt.minutes($0)) left") }
            ?? T("남은 시간 계산 중", "Estimating time remaining")
        context?.center.post(NotchActivity(
            kind: .battery, presentation: .compact, symbol: BatteryMonitor.symbol(for: r.percent), tint: Self.levelColor(r.percent),
            value: .text("\(r.percent)%"), title: T("전원 분리됨", "Unplugged"), subtitle: sub,
            detailValue: .percent(Double(r.percent) / 100), wing: 56, valueTint: Self.levelColor(r.percent),
            battery: glyph(r, charging: false), moduleTab: id))
    }

    private func postLow(_ r: BatteryHealthReading) {
        context?.center.post(NotchActivity(
            kind: .battery, priority: ActivityPriority.batteryLow, presentation: .detail, duration: 5,
            symbol: BatteryMonitor.symbol(for: r.percent), tint: .red, value: .text("\(r.percent)%"),
            title: T("배터리 부족", "Low Battery"),
            subtitle: r.minutesToEmpty.map { T("약 \(SysFmt.minutes($0)) 남음 · 충전기를 연결하세요", "About \(SysFmt.minutes($0)) left · connect a charger") }
                ?? T("충전기를 연결하세요", "Connect a charger"),
            detailValue: .percent(Double(r.percent) / 100), wing: 56, valueTint: .red,
            battery: glyph(r, charging: false), moduleTab: id))
    }

    private func postFull(_ r: BatteryHealthReading) {
        context?.center.post(NotchActivity(
            kind: .battery, presentation: .detail, symbol: "battery.100percent.bolt", tint: .green,
            value: .text("\(r.percent)%"), title: T("\(fullLevel)% 충전됨", "Charged to \(fullLevel)%"),
            subtitle: T("충전기를 빼도 좋습니다", "You can unplug the charger"),
            detailValue: .percent(Double(r.percent) / 100), wing: 56, valueTint: .green,
            battery: glyph(r, charging: true), moduleTab: id))
    }

    // MARK: 비정상 소모 (배터리 사용 중 다른 앱이 CPU 80% 이상을 N분 이어 쓰면)

    private func updateDrainWatch() {
        let onBattery = model.reading.present && !model.reading.onAC
        if drainAlert, onBattery, context != nil {
            guard drainTimer == nil else { return }
            highSince.removeAll()
            drainQueue.async { [drainReader] in _ = drainReader.sample() }   // 기준
            let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.drainTick() }
            t.tolerance = 5
            RunLoop.main.add(t, forMode: .common)
            drainTimer = t
        } else {
            drainTimer?.invalidate(); drainTimer = nil
            highSince.removeAll()
        }
    }

    private func drainTick() {
        let minutes = Double(drainMinutes)
        drainQueue.async { [weak self] in
            guard let self else { return }
            let me = getpid()
            let heavy = self.drainReader.sample().filter { $0.cpu >= 80 && $0.pid != me }
                .map { p -> SysProcInfo in var p = p; p.path = SysProcReader.path(p.pid); return p }
                .filter { !SysProcReader.isSystem(path: $0.path) }
            DispatchQueue.main.async {
                let now = Date()
                let ids = Set(heavy.map(\.pid))
                self.highSince = self.highSince.filter { ids.contains($0.key) }
                for p in heavy {
                    let since = self.highSince[p.pid] ?? now
                    self.highSince[p.pid] = since
                    guard now.timeIntervalSince(since) >= minutes * 60 - 1 else { continue }
                    if let w = self.lastWarned[p.path], now.timeIntervalSince(w) < 3600 { continue }
                    self.lastWarned[p.path] = now
                    self.postDrain(name: SysProcReader.name(p.pid, path: p.path), cpu: p.cpu)
                }
            }
        }
    }

    private func postDrain(name: String, cpu: Double) {
        let open = ActivityAction(id: "battery.activitymonitor", title: T("활성 상태 보기", "Activity Monitor")) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
        context?.center.post(NotchActivity(
            kind: .battery, priority: ActivityPriority.info, presentation: .detail, duration: 8,
            symbol: "bolt.trianglebadge.exclamationmark", tint: .orange, value: .text("\(Int(cpu))%"),
            title: T("\(name)이(가) 배터리를 많이 씀", "\(name) is draining the battery"),
            subtitle: T("배터리 사용 중 CPU \(Int(cpu))%를 \(drainMinutes)분 넘게 사용", "CPU \(Int(cpu))% for over \(drainMinutes) min on battery"),
            valueTint: .orange, moduleTab: id, actions: [open]))
    }

    // MARK: 화면

    func tabView() -> AnyView? { AnyView(BatteryHealthTab(module: self, model: model)) }
    var tabContentSize: CGSize { CGSize(width: 560, height: 256) }

    func paletteActions() -> [PaletteAction] {
        let r = model.reading.present ? model.reading : BatteryHealthReading.read()
        guard r.present else { return [] }
        return [
            PaletteAction(id: "battery.health", title: T("배터리 상태", "Battery health"),
                          subtitle: "\(r.percent)% · " + T("사이클 \(r.cycleCount ?? 0)", "\(r.cycleCount ?? 0) cycles"),
                          symbol: "battery.100percent", keywords: ["battery", "배터리", "health", "cycle", "사이클"]) { [weak self] in
                guard let self else { return }
                self.context?.openTab(self.id)
            },
            PaletteAction(id: "battery.lpmsettings", title: T("저전력 모드 설정 열기", "Open Low Power Mode settings"),
                          subtitle: T("전환은 시스템 설정에서 (관리자 권한 필요)", "Toggle in System Settings (needs admin rights)"),
                          symbol: "leaf", keywords: ["low power", "저전력"]) { BatteryHealthModel.openBatterySettings() },
        ]
    }

    func settingsView() -> AnyView? { AnyView(BatteryHealthSettings(module: self)) }

    func selfTest() -> [String] {
        let r = BatteryHealthReading.read()
        var lines: [String] = []
        guard r.present else { return ["no internal battery"] }
        lines.append("charge \(r.percent)% charging \(r.isCharging) ac \(r.onAC) charged \(r.isCharged) toEmpty \(r.minutesToEmpty.map(String.init) ?? "-") toFull \(r.minutesToFull.map(String.init) ?? "-") lowPower \(r.lowPowerMode)")
        lines.append("cycles \(r.cycleCount ?? -1)/\(r.designCycleCount ?? -1) design \(r.designCapacity ?? -1) mAh full \(r.fullChargeCapacity ?? -1) mAh est max \(r.estimatedMaxCapacity.map { SysFmt.percent($0) } ?? "-")")
        lines.append(String(format: "temperature %.1f °C voltage %.2f V amperage %.0f mA power %@ adapter %@ %@W notChargingReason %@",
                            r.temperature ?? -1, r.voltage ?? -1, r.amperage ?? 0, r.watts.map { String(format: "%.1f W", $0) } ?? "-",
                            r.adapterName ?? "-", r.adapterWatts.map(String.init) ?? "-", r.notChargingReason.map(String.init) ?? "-"))
        if let h = BatteryProfilerHealth.read() {
            lines.append("system profiler condition \(h.condition ?? "-") maximum capacity \(h.maximumCapacity ?? "-")")
        } else { lines.append("system profiler health unavailable") }
        let hw = BatteryHardwareSupport.read()
        lines.append("smc readable \(hw.smcAvailable) charge-control keys [\(hw.chargeControlKeys.joined(separator: ","))]")
        for f in hw.fans { lines.append("fan \(f.id + 1): \(Int(f.rpm)) rpm (min \(Int(f.min)), max \(Int(f.max)))") }
        if hw.fans.isEmpty { lines.append("fans: none reported") }
        SysSMC.shared.close()
        // 알림 판정 규칙 점검 (가상의 전원 변화, 화면·소리 없음)
        let probe = BatteryHealthModule()
        var a = BatteryHealthReading(); a.present = true; a.percent = 22; a.onAC = false
        var b = a; b.percent = probe.lowThreshold
        var c = b; c.percent = probe.lowThreshold - 1
        var d = c; d.onAC = true
        let t0 = Date(timeIntervalSinceNow: -100)
        let e1 = probe.evaluate(old: a, new: b, now: t0)
        let e2 = probe.evaluate(old: b, new: c, now: t0.addingTimeInterval(60))
        let e3 = probe.evaluate(old: c, new: d, now: t0.addingTimeInterval(70))
        let e4 = probe.evaluate(old: d, new: c, now: t0.addingTimeInterval(80))
        lines.append("alert rule check (defaults: low on at \(probe.lowThreshold)%, unplug on, plug off): crossing → \(e1.map { "\($0)" }), lower again → \(e2.map { "\($0)" }), plug in → \(e3.map { "\($0)" }), unplug → \(e4.map { "\($0)" })")
        return lines
    }
}

/// 탭 화면용 상태 (탭이 보이는 동안 팬 회전수를 3초마다 읽는다)
final class BatteryHealthModel: ObservableObject {
    @Published var reading = BatteryHealthReading()
    @Published var profiler: BatteryProfilerHealth?
    @Published var hardware = BatteryHardwareSupport()
    private var fanTimer: Timer?
    private let queue = DispatchQueue(label: "com.dynamicnotch.battery.live", qos: .utility)

    func startLive() {
        reading = BatteryHealthReading.read()
        queue.async { [weak self] in
            let p = BatteryProfilerHealth.read()
            let hw = BatteryHardwareSupport.read()
            DispatchQueue.main.async { self?.profiler = p; self?.hardware = hw }
        }
        guard fanTimer == nil else { return }
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                let fans = SysSMC.shared.fans()
                let r = BatteryHealthReading.read()
                DispatchQueue.main.async { self.hardware.fans = fans; self.reading = r }
            }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        fanTimer = t
    }

    func stopLive() {
        fanTimer?.invalidate(); fanTimer = nil
        queue.async { SysSMC.shared.close() }
    }

    static func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") { NSWorkspace.shared.open(url) }
    }
}

// MARK: - 탭

private struct BatteryHealthTab: View {
    let module: BatteryHealthModule
    @ObservedObject var model: BatteryHealthModel
    @State private var page = 0

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(T("배터리", "Battery")).font(.island(.callout, .semibold))
                Spacer()
                Picker("", selection: $page) {
                    Text(T("상태", "Status")).tag(0)
                    Text(T("충전·팬 제어", "Charging & fans")).tag(1)
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 200)
            }
            if !model.reading.present {
                SysUnsupported(title: T("내장 배터리 없음", "No internal battery"),
                               reason: T("이 Mac은 배터리를 보고하지 않습니다.", "This Mac reports no internal battery."))
                Spacer()
            } else if page == 0 {
                status
            } else {
                controls
            }
        }
        .foregroundStyle(.white)
        .onAppear { model.startLive() }
        .onDisappear { model.stopLive() }
    }

    private var stateText: String {
        let r = model.reading
        if r.isCharging { return r.minutesToFull.map { T("충전 중 · 완충까지 \(SysFmt.minutes($0))", "Charging · \(SysFmt.minutes($0)) to full") } ?? T("충전 중", "Charging") }
        if r.onAC { return r.isCharged ? T("충전 완료 · 전원 연결됨", "Charged · on power") : T("전원 연결됨 · 충전 대기", "On power · not charging") }
        return r.minutesToEmpty.map { T("배터리 사용 중 · 약 \(SysFmt.minutes($0)) 남음", "On battery · about \(SysFmt.minutes($0)) left") } ?? T("배터리 사용 중", "On battery")
    }

    private var status: some View {
        let r = model.reading
        return HStack(spacing: 8) {
            SysCard {
                VStack(spacing: 6) {
                    ZStack {
                        SysRing(value: Double(r.percent) / 100, tint: BatteryHealthModule.levelColor(r.percent), lineWidth: 7)
                        VStack(spacing: 0) {
                            Text("\(r.percent)%").font(.island(.title1, .semibold)).monospacedDigit()
                            if r.isCharging { Image(systemName: "bolt.fill").font(.island(.footnote)).foregroundStyle(.green) }
                        }
                    }
                    .frame(width: 92, height: 92)
                    Text(stateText).font(.island(.caption)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    if r.onAC, let adapter = r.adapterName ?? r.adapterWatts.map({ "\($0)W" }) {
                        Text(adapter).font(.island(.caption2)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                    }
                    if r.lowPowerMode {
                        Label(T("저전력 모드", "Low Power Mode"), systemImage: "leaf.fill").font(.island(.caption)).foregroundStyle(.yellow)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(width: 170)
            .accessibilityElement(children: .combine)
            VStack(spacing: 8) {
                SysCard {
                    VStack(alignment: .leading, spacing: 5) {
                        SysHeader(text: T("성능 상태", "Health"))
                        row(T("상태", "Condition"), model.profiler?.conditionText ?? T("읽는 중…", "Reading…"))
                        row(T("최대 용량", "Maximum capacity"),
                            model.profiler?.maximumCapacity ?? r.estimatedMaxCapacity.map { "≈" + SysFmt.percent($0) } ?? "–",
                            hint: r.designCapacity.map { T("설계 \($0) mAh", "design \($0) mAh") })
                        row(T("충전 사이클", "Cycle count"), r.cycleCount.map { c in r.designCycleCount.map { "\(c) / \($0)" } ?? "\(c)" } ?? "–")
                        row(T("온도", "Temperature"), r.temperature.map { String(format: "%.1f°C", $0) } ?? "–")
                        row(T("전력", "Power"), r.watts.map { String(format: "%@%.1f W", $0 > 0 ? "+" : "", $0) } ?? "–",
                            hint: r.voltage.map { String(format: "%.2f V", $0) })
                    }
                }
                fansCard
            }
        }
    }

    private func row(_ title: String, _ value: String, hint: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.island(.footnote)).foregroundStyle(.white.opacity(0.65))
            Spacer()
            if let hint { Text(hint).font(.island(.caption2)).foregroundStyle(.white.opacity(0.4)) }
            Text(value).font(.island(.footnote)).monospacedDigit()
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var fansCard: some View {
        SysCard {
            VStack(alignment: .leading, spacing: 4) {
                SysHeader(text: T("팬 (읽기 전용 · 펌웨어 자동 제어)", "Fans (read-only · firmware automatic)"))
                if model.hardware.fans.isEmpty {
                    Text(model.hardware.smcAvailable ? T("팬 없음 또는 보고 안 함", "No fans reported") : T("읽는 중…", "Reading…"))
                        .font(.island(.footnote)).foregroundStyle(.white.opacity(0.55))
                }
                HStack(spacing: 14) {
                    ForEach(model.hardware.fans) { f in
                        HStack(spacing: 5) {
                            Image(systemName: "fan").font(.island(.footnote))
                            Text(f.rpm < 1 ? T("멈춤", "Off") : "\(Int(f.rpm)) rpm").font(.island(.footnote)).monospacedDigit()
                            Text(verbatim: "\(Int(f.min))–\(Int(f.max))").font(.island(.caption2)).foregroundStyle(.white.opacity(0.4)).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .frame(height: 52)
    }

    private var controls: some View {
        let hw = model.hardware
        return VStack(alignment: .leading, spacing: 8) {
            SysCard {
                HStack(spacing: 8) {
                    Image(systemName: model.reading.lowPowerMode ? "leaf.fill" : "leaf").foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(T("저전력 모드: ", "Low Power Mode: ") + (model.reading.lowPowerMode ? T("켜짐", "On") : T("꺼짐", "Off")))
                            .font(.island(.subhead, .semibold))
                        Text(T("전환은 pmset 관리자 권한이 필요해 보류. 시스템 설정에서 바꾸세요.",
                               "Toggling needs admin rights (pmset), so it is deferred. Change it in System Settings."))
                            .font(.island(.caption)).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    SysPillButton(title: T("배터리 설정", "Battery Settings"), symbol: "gearshape") { BatteryHealthModel.openBatterySettings() }
                }
            }
            .frame(height: 50)
            SysCard {
                VStack(alignment: .leading, spacing: 5) {
                    SysUnsupported(
                        title: T("충전 한도 · Sailing · 자동 방전 · 100% 일회 충전: 보류", "Charge limit · Sailing · Discharge · Top up: deferred"),
                        reason: T("SMC 충전 제어 키를 쓰려면 root 권한 헬퍼가 필요한데, 이 앱은 관리자 도우미를 설치하지 않습니다.",
                                  "Writing the SMC charge-control keys needs a root helper, and this app installs no privileged helper."),
                        alternative: T("대안: 시스템 설정 › 배터리 › 충전의 '최적화된 배터리 충전'. ", "Alternative: System Settings › Battery › Charging › Optimized Battery Charging. ")
                            + (hw.chargeControlKeys.isEmpty ? T("이 Mac에서 충전 제어 키를 찾지 못함.", "No charge-control keys found on this Mac.")
                               : T("이 Mac은 충전 제어 키(\(hw.chargeControlKeys.joined(separator: ", ")))를 가지고 있음.", "This Mac exposes charge-control keys (\(hw.chargeControlKeys.joined(separator: ", "))).")))
                    SysUnsupported(
                        title: T("팬 제어: 보류", "Fan control: deferred"),
                        reason: T("팬 속도 쓰기도 같은 root 헬퍼가 필요합니다. 팬 \(hw.fans.count)개는 읽기만 하고 늘 펌웨어 자동 제어입니다.",
                                  "Writing fan speeds needs the same root helper. The \(hw.fans.count) fan(s) are read only and always under firmware control."),
                        alternative: T("복구: 이 앱은 SMC에 값을 쓰지 않으므로 되돌릴 것이 없습니다. 다른 도구가 충전을 막아 두었다면 그 도구의 제거 기능을 쓰세요.",
                                       "Recovery: this app never writes SMC values, so there is nothing to restore. If another tool left charging inhibited, use its uninstaller."),
                        symbol: "fan")
                }
            }
        }
    }
}

// MARK: - 설정

private struct BatteryHealthSettings: View {
    let module: BatteryHealthModule
    @State private var v: [String: Any] = [:]

    private func bind(_ key: String, _ def: Bool) -> Binding<Bool> {
        Binding(get: { v[key] as? Bool ?? module.defaults.bool(key, default: def) },
                set: { v[key] = $0; module.defaults.set($0, key) })
    }
    private func bindInt(_ key: String, _ def: Int) -> Binding<Int> {
        Binding(get: { v[key] as? Int ?? module.defaults.int(key, default: def) },
                set: { v[key] = $0; module.defaults.set($0, key) })
    }
    private func bindSound(_ key: String, _ def: String) -> Binding<String> {
        Binding(get: { v[key] as? String ?? module.defaults.string(key, default: def) },
                set: { v[key] = $0; module.defaults.set($0, key); SysSounds.play($0) })
    }

    private func soundPicker(_ key: String, _ def: String) -> some View {
        Picker(T("소리", "Sound"), selection: bindSound(key, def)) {
            Text(T("없음", "None")).tag("")
            ForEach(SysSounds.names, id: \.self) { Text($0).tag($0) }
        }
        .frame(width: 180)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(T("배터리 부족 알림", "Low battery alert"), isOn: bind("lowAlert", true))
                Stepper(T("기준 \(bindInt("lowThreshold", 20).wrappedValue)%", "At \(bindInt("lowThreshold", 20).wrappedValue)%"),
                        value: bindInt("lowThreshold", 20), in: 5...50, step: 5)
                soundPicker("lowSound", "Basso")
            }
            HStack {
                Toggle(T("충전기 연결 알림", "Charger connected alert"), isOn: bind("plugAlert", false))
                soundPicker("plugSound", "")
            }
            HStack {
                Toggle(T("전원 분리 알림 (남은 시간)", "Unplugged alert (time left)"), isOn: bind("unplugAlert", true))
                soundPicker("unplugSound", "")
            }
            HStack {
                Toggle(T("완충 기준 알림", "Full charge alert"), isOn: bind("fullAlert", false))
                Stepper(T("기준 \(bindInt("fullLevel", 80).wrappedValue)%", "At \(bindInt("fullLevel", 80).wrappedValue)%"),
                        value: bindInt("fullLevel", 80), in: 50...100, step: 5)
                soundPicker("fullSound", "")
            }
            Toggle(T("부족·완충 알림 때 화면 테두리 빛", "Screen glow on low and full alerts"), isOn: bind("glow", false))
            Toggle(T("저전력 모드가 켜지면 알림", "Alert when Low Power Mode turns on"), isOn: bind("lpmAlert", true))
            HStack {
                Toggle(T("비정상 소모 경고 (배터리 사용 중 앱이 CPU 80% 이상)", "Battery drain warning (an app above 80% CPU on battery)"), isOn: bind("drainAlert", true))
                Stepper(T("\(bindInt("drainMinutes", 3).wrappedValue)분 지속", "for \(bindInt("drainMinutes", 3).wrappedValue) min"),
                        value: bindInt("drainMinutes", 3), in: 1...15)
            }
            Text(T("기본 배터리 알림(충전기 연결·부족·80% 완충)과 함께 켜면 같은 순간에 두 번 뜰 수 있습니다. 비정상 소모 감시는 배터리로 동작할 때만 20초마다 돌고, 시스템 프로세스는 빼며, 같은 앱은 1시간에 한 번만 알립니다.",
                   "If the built-in battery alerts (charger, low, 80% full) are also on, the same moment may alert twice. Drain checks run every 20 s only on battery, skip system processes, and warn once per app per hour."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

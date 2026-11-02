import AppKit
import SwiftUI

/// 화면: 주사율 전환, Extra Dim(감마), 외장 모니터 DDC 밝기·명암·색 프리셋·입력. XDR 추가 밝기는 보류(이유 표시).
/// 모든 변경은 사용자가 조절할 때만 하고, 기능을 끄거나 앱이 끝나면 Extra Dim을 되돌린다.
final class DisplaysModule: NotchModule {
    let id = "displays"
    var title: String { T("화면", "Displays") }
    let symbol = "display"
    var enabledByDefault: Bool { false }

    let model = DisplaysModel()
    private var context: ModuleContext?

    func start(context: ModuleContext) { self.context = context }

    func stop() {
        SysGamma.shared.restoreAll()
        model.reset()
        context = nil
    }

    func tabView() -> AnyView? { AnyView(DisplaysTab(model: model)) }
    var tabContentSize: CGSize { CGSize(width: 560, height: 220) }

    func paletteActions() -> [PaletteAction] {
        var list: [PaletteAction] = []
        for d in SysDisplays.all() where d.refreshOptions.count > 1 {
            for r in d.refreshOptions where abs(r - d.currentRefresh) > 0.01 {
                list.append(PaletteAction(id: "displays.rate.\(d.id).\(r)", title: T("\(d.name) 주사율 \(SysDisplays.rateText(r))", "\(d.name) refresh rate \(SysDisplays.rateText(r))"),
                                          subtitle: T("지금 \(SysDisplays.rateText(d.currentRefresh))", "Now \(SysDisplays.rateText(d.currentRefresh))"),
                                          symbol: "display", keywords: ["refresh", "hz", "주사율"]) { [weak self] in
                    SysDisplays.setRefresh(d.id, r)
                    self?.model.reload()
                })
            }
        }
        list.append(PaletteAction(id: "displays.extradim.off", title: T("Extra Dim 끄기", "Turn off Extra Dim"), symbol: "sun.min",
                                  keywords: ["dim", "extra dim", "어둡게"]) { [weak self] in
            SysGamma.shared.restoreAll(); self?.model.reload()
        })
        return list
    }

    func settingsView() -> AnyView? {
        AnyView(Text(T("Extra Dim은 감마 표로 화면을 더 어둡게 하며, 이 기능을 끄거나 앱이 끝나면 macOS 색 설정으로 되돌립니다. 외장 모니터 DDC는 Apple silicon의 비공개 IOAVService를 쓰고, 모니터가 응답한 항목만 조절 막대로 보입니다. 밝기 키로 외장 모니터를 조절하는 기능은 HUD 본체 연결이 필요합니다.",
                       "Extra Dim lowers the gamma table and restores macOS colour settings when turned off or when the app quits. External DDC uses the private IOAVService on Apple silicon and shows only the controls the monitor answers. Brightness keys for external displays need a hook in the HUD core."))
            .font(.callout))
    }

    func selfTest() -> [String] {
        var lines: [String] = []
        for d in SysDisplays.all() {
            lines.append("display \(d.id) \(d.name) builtin \(d.isBuiltin) main \(d.isMain) refresh \(SysDisplays.rateText(d.currentRefresh)) options [\(d.refreshOptions.map(SysDisplays.rateText).joined(separator: ", "))] maxEDR \(String(format: "%.1f", d.maxEDR))")
            if let t = CGDisplayCopyDisplayMode(d.id) { lines.append("  mode \(t.width)x\(t.height) pixels \(t.pixelWidth)x\(t.pixelHeight)") }
        }
        let ddc = SysDDC.shared
        lines.append("ddc api (IOAVService) available \(ddc.apiAvailable) · AV proxies [\(ddc.proxyLocations().joined(separator: ", "))] · external services \(ddc.externalServices().count) (no I2C traffic in self test)")
        lines.append("extra dim active \(SysGamma.shared.isActive) (self test does not change gamma)")
        return lines
    }
}

/// 외장 모니터 한 대의 DDC 상태
struct DDCState: Equatable {
    var responded = false
    var checked = false
    var brightness: (Int, Int)?
    var contrast: (Int, Int)?
    var preset: Int?
    var input: Int?

    static func == (a: DDCState, b: DDCState) -> Bool {
        a.responded == b.responded && a.checked == b.checked && a.brightness?.0 == b.brightness?.0 && a.brightness?.1 == b.brightness?.1
            && a.contrast?.0 == b.contrast?.0 && a.contrast?.1 == b.contrast?.1 && a.preset == b.preset && a.input == b.input
    }
}

final class DisplaysModel: ObservableObject {
    @Published var displays: [SysDisplay] = []
    @Published var dim: [CGDirectDisplayID: Double] = [:]
    @Published var ddc: [CGDirectDisplayID: DDCState] = [:]
    @Published var pairedByOrder = false
    private var services: [CGDirectDisplayID: AnyObject] = [:]
    private let queue = DispatchQueue(label: "com.dynamicnotch.displays.ddc", qos: .userInitiated)
    private var writeWork: [String: DispatchWorkItem] = [:]

    func reload() {
        displays = SysDisplays.all()
        dim = SysGamma.shared.levels
    }

    func reset() {
        writeWork.values.forEach { $0.cancel() }
        writeWork.removeAll()
        services.removeAll()
        ddc.removeAll()
        dim.removeAll()
    }

    /// 탭이 열릴 때: 외장 화면과 AV 서비스를 연결 순서로 짝짓고, 지원 항목을 한 번 읽는다
    func probeDDC() {
        let externals = displays.filter { !$0.isBuiltin }.map(\.id).sorted()
        guard !externals.isEmpty, SysDDC.shared.apiAvailable else { return }
        queue.async { [weak self] in
            let avs = SysDDC.shared.externalServices()
            var found: [CGDirectDisplayID: AnyObject] = [:]
            for (i, id) in externals.enumerated() where i < avs.count { found[id] = avs[i] }
            var states: [CGDirectDisplayID: DDCState] = [:]
            for (id, s) in found {
                var st = DDCState(checked: true)
                st.brightness = SysDDC.shared.read(s, .brightness).map { ($0.current, $0.max) }
                st.contrast = SysDDC.shared.read(s, .contrast).map { ($0.current, $0.max) }
                st.preset = SysDDC.shared.read(s, .colorPreset)?.current
                st.input = SysDDC.shared.read(s, .input).map { $0.current & 0xff }
                st.responded = st.brightness != nil || st.contrast != nil || st.preset != nil || st.input != nil
                states[id] = st
            }
            for id in externals where found[id] == nil { states[id] = DDCState(checked: true) }
            DispatchQueue.main.async {
                self?.services = found
                self?.ddc = states
                self?.pairedByOrder = externals.count > 1
            }
        }
    }

    /// 조절 막대를 끄는 동안 너무 자주 쓰지 않도록 0.15초 모아서 쓴다
    func writeDDC(_ id: CGDirectDisplayID, _ vcp: SysDDC.VCP, _ value: Int) {
        guard let s = services[id] else { return }
        let key = "\(id).\(vcp.rawValue)"
        writeWork[key]?.cancel()
        let work = DispatchWorkItem { SysDDC.shared.write(s, vcp, value) }
        writeWork[key] = work
        queue.asyncAfter(deadline: .now() + 0.15, execute: work)
        switch vcp {
        case .brightness: ddc[id]?.brightness?.0 = value
        case .contrast: ddc[id]?.contrast?.0 = value
        case .colorPreset: ddc[id]?.preset = value
        case .input: ddc[id]?.input = value
        }
    }

    func setDim(_ id: CGDirectDisplayID, _ level: Double) {
        SysGamma.shared.set(id, level)
        dim = SysGamma.shared.levels
    }

    func setRefresh(_ id: CGDirectDisplayID, _ rate: Double) {
        SysDisplays.setRefresh(id, rate)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.reload() }
    }
}

// MARK: - 탭

private struct DisplaysTab: View {
    @ObservedObject var model: DisplaysModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach(model.displays) { d in card(d) }
                if !model.displays.isEmpty, !model.displays.contains(where: { !$0.isBuiltin }) {
                    SysCard {
                        SysUnsupported(title: T("외장 모니터 없음", "No external display"),
                                       reason: T("외장 모니터를 연결하면 DDC/CI로 밝기·명암·색 프리셋·입력 소스를 조절합니다 (Apple silicon, DDC를 지원하는 모니터).",
                                                 "Connect a monitor to control brightness, contrast, colour preset and input over DDC/CI (Apple silicon and a DDC-capable monitor)."),
                                       symbol: "display.2")
                    }
                }
                if model.displays.isEmpty {
                    Text(T("화면을 읽는 중…", "Reading displays…")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear { model.reload(); model.probeDDC() }
    }

    private func card(_ d: SysDisplay) -> some View {
        SysCard {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: d.isBuiltin ? "laptopcomputer" : "display").font(.system(size: 13))
                    Text(d.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if d.isMain { Text(T("주 화면", "Main")).font(.system(size: 9)).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.15))) }
                    Spacer()
                    refreshControl(d)
                }
                dimRow(d)
                if d.isBuiltin {
                    if d.maxEDR > 1.01 {
                        note(T("XDR 추가 밝기: 보류", "XDR extra brightness: deferred"),
                             T("이 화면은 EDR 최대 \(String(format: "%.0f", d.maxEDR))배를 지원합니다. 평소보다 밝게 하려면 화면 전체 EDR 오버레이(금속 레이어 곱하기 합성)가 필요하고 배터리·발열이 커서 아직 넣지 않았습니다. 대안: 시스템 설정 › 디스플레이의 기본 밝기.",
                               "This display supports up to \(String(format: "%.0f", d.maxEDR))× EDR. Going above normal brightness needs a full-screen EDR overlay (Metal multiply compositing) with notable battery and heat cost, so it is not included yet. Alternative: System Settings › Displays brightness."))
                    }
                } else {
                    ddcSection(d)
                }
            }
        }
    }

    @ViewBuilder
    private func refreshControl(_ d: SysDisplay) -> some View {
        if d.refreshOptions.count > 1 {
            Menu {
                ForEach(d.refreshOptions, id: \.self) { r in
                    Button((abs(r - d.currentRefresh) < 0.01 ? "✓ " : "") + SysDisplays.rateText(r)) { model.setRefresh(d.id, r) }
                }
            } label: {
                Text(SysDisplays.rateText(d.currentRefresh)).font(.system(size: 11, weight: .medium)).monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(T("주사율 바꾸기 (현재 해상도에서 가능한 값만)", "Change refresh rate (only rates available at this resolution)"))
        } else if d.currentRefresh > 0 {
            Text(SysDisplays.rateText(d.currentRefresh)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
        }
    }

    private func dimRow(_ d: SysDisplay) -> some View {
        let level = model.dim[d.id] ?? 0
        return HStack(spacing: 8) {
            Text("Extra Dim").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).frame(width: 74, alignment: .leading)
            // 사용자가 끌 때만 감마를 바꾼다
            Slider(value: Binding(get: { level }, set: { model.setDim(d.id, $0) }), in: 0...0.8)
                .controlSize(.small)
                .accessibilityLabel(T("\(d.name) 추가로 어둡게", "\(d.name) extra dim"))
            Text(level > 0 ? "−\(Int(level * 100))%" : T("꺼짐", "Off")).font(.system(size: 10.5)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.6)).frame(width: 40, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func ddcSection(_ d: SysDisplay) -> some View {
        let st = model.ddc[d.id]
        if !SysDDC.shared.apiAvailable {
            note(T("DDC 지원 안 됨", "DDC unsupported"),
                 T("이 Mac(또는 macOS)에서 IOAVService를 찾지 못했습니다. Apple silicon이 필요합니다. 대안: 위 Extra Dim(소프트웨어 감광).",
                   "IOAVService is not available on this Mac or macOS; Apple silicon is required. Alternative: Extra Dim above (software dimming)."))
        } else if st == nil || st?.checked == false {
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text(T("DDC 응답 확인 중…", "Checking DDC…")).font(.system(size: 10.5)) }
        } else if st?.responded != true {
            note(T("모니터가 DDC에 응답하지 않음", "Monitor did not answer DDC"),
                 T("DDC/CI가 꺼져 있거나, 일부 허브·KVM·Mac 내장 HDMI 포트는 DDC를 전달하지 않습니다. 대안: Extra Dim(소프트웨어 감광), 모니터 OSD 메뉴.",
                   "DDC/CI may be off in the monitor menu, or a hub, KVM or the Mac's built-in HDMI port does not pass DDC. Alternatives: Extra Dim (software dimming) or the monitor's OSD."))
        } else if let st {
            if let b = st.brightness { vcpSlider(T("밝기", "Brightness"), d.id, .brightness, b) }
            if let c = st.contrast { vcpSlider(T("명암", "Contrast"), d.id, .contrast, c) }
            HStack(spacing: 10) {
                if st.preset != nil {
                    Picker(T("색", "Colour"), selection: Binding(get: { st.preset ?? 2 }, set: { model.writeDDC(d.id, .colorPreset, $0) })) {
                        Text("Native").tag(2); Text("sRGB").tag(1); Text("5000K").tag(4); Text("6500K").tag(5); Text("7500K").tag(6); Text("9300K").tag(8)
                    }
                    .frame(width: 150).controlSize(.small)
                }
                if st.input != nil {
                    Picker(T("입력", "Input"), selection: Binding(get: { st.input ?? 0 }, set: { model.writeDDC(d.id, .input, $0) })) {
                        Text("DisplayPort 1").tag(0x0F); Text("DisplayPort 2").tag(0x10); Text("HDMI 1").tag(0x11); Text("HDMI 2").tag(0x12)
                        Text("USB-C").tag(0x1B)
                        if let i = st.input, ![0x0F, 0x10, 0x11, 0x12, 0x1B].contains(i) { Text(String(format: "0x%02X", i)).tag(i) }
                    }
                    .frame(width: 170).controlSize(.small)
                }
            }
            if model.pairedByOrder {
                Text(T("외장 화면이 여러 대라 연결 순서로 짝지었습니다.", "Several external displays: matched by connection order."))
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private func vcpSlider(_ title: String, _ id: CGDirectDisplayID, _ vcp: SysDDC.VCP, _ v: (Int, Int)) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).frame(width: 74, alignment: .leading)
            Slider(value: Binding(get: { Double(v.0) }, set: { model.writeDDC(id, vcp, Int($0.rounded())) }), in: 0...Double(max(1, v.1)))
                .controlSize(.small)
            Text(verbatim: "\(v.0)").font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.white.opacity(0.6)).frame(width: 40, alignment: .trailing)
        }
    }

    private func note(_ title: String, _ text: String) -> some View {
        SysUnsupported(title: title, reason: text, symbol: "info.circle")
    }
}

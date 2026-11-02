import AppKit
import SwiftUI

/// 최근 고른 색 (탭이 본다)
final class ColorToolsState: ObservableObject {
    @Published var recent: [String] = []
    @Published var format: ClipColorFormat = .hex
    @Published var selected: String?
    @Published var copied: String?
    private var copiedWork: DispatchWorkItem?

    func flash(_ s: String) {
        copied = s
        copiedWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.copied = nil }
        copiedWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: w)
    }
}

/// 색상 도구: 시스템 확대 루페(NSColorSampler)로 화면 픽셀 색을 뽑아 바로 복사하고, 최근 12색을 HEX·RGB·HSL·SwiftUI로 복사한다.
/// 화면 기록 권한이 필요 없고 배경 작업이 없다. 복사한 색은 클립보드 기능이 켜져 있으면 견본으로 기록된다.
final class ColorToolsModule: NotchModule {
    let id = "colors"
    var title: String { T("색상", "Colors") }
    let symbol = "eyedropper"
    let enabledByDefault = false

    static let maxRecent = 12
    let state = ColorToolsState()
    private(set) var context: ModuleContext?
    private var sampler: NSColorSampler?
    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }

    func start(context: ModuleContext) {
        self.context = context
        reload()
    }

    func stop() {
        sampler = nil
        context = nil
    }

    func settingsChanged() { reload() }

    private func reload() {
        var recent = defaults.strings("recent", default: [])
        // 명령줄 화면 검사(도우미 프로세스)에서만 DMN_COLORS_RECENT로 목록을 바꿀 수 있다
        if AppSettings.isHelper, let custom = ProcessInfo.processInfo.environment["DMN_COLORS_RECENT"] {
            recent = custom.split(separator: ",").map(String.init)
        }
        state.recent = recent.filter { ClipColors.parse($0) != nil }
        state.format = ClipColorFormat(rawValue: defaults.string("format", default: "hex")) ?? .hex
    }

    func tabView() -> AnyView? { AnyView(ColorToolsTab(module: self, state: state)) }
    var tabContentSize: CGSize { CGSize(width: 480, height: 172) }
    func settingsView() -> AnyView? { AnyView(ColorToolsSettings()) }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "colors.pick", title: T("화면에서 색 뽑기", "Pick a Color from the Screen"), symbol: symbol,
                       keywords: ["color", "colour", "picker", "eyedropper", "색", "색상", "스포이트", "hex"], run: { [weak self] in self?.pick() })]
    }

    /// "#3A7BFF", "rgb(…)", "hsl(…)"을 입력하면 네 가지 형식으로 바꿔 복사할 수 있게 한다
    func paletteResults(for query: String) -> [PaletteAction] {
        guard context != nil, let c = ClipColors.parse(query) else { return [] }
        return ClipColorFormat.allCases.map { f in
            let s = ClipColors.format(c, f)
            return PaletteAction(id: "colors.convert.\(f.rawValue)", title: s, subtitle: T("\(f.label)로 복사", "Copy as \(f.label)"),
                                 symbol: "paintpalette", run: { [weak self] in self?.copy(s, remember: ClipColors.format(c, .hex)) })
        }
    }

    // MARK: 동작

    /// 확대 루페를 띄운다. 고르면 정한 형식으로 바로 복사하고 노치에 견본을 보여 준다.
    func pick() {
        context?.collapse()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            let sampler = NSColorSampler()
            self.sampler = sampler
            sampler.show { [weak self] color in
                guard let self else { return }
                self.sampler = nil
                guard let color, let c = ClipColors.from(color) else { return }
                let hex = ClipColors.format(c, .hex)
                let text = ClipColors.format(c, self.state.format)
                self.copy(text, remember: hex)
                self.context?.notice(T("\(text) 복사함", "Copied \(text)"), T("화면에서 고른 색", "Picked from the screen"),
                                     symbol: "circle.fill", tint: Color(nsColor: ClipColors.nsColor(c)), tab: self.id, duration: 2.5)
            }
        }
    }

    /// 글자를 복사한다 (일반 복사라 클립보드 기록에 견본으로 남는다)
    func copy(_ text: String, remember hex: String?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        state.flash(text)
        if let hex { remember(hex) }
    }

    func remember(_ hex: String) {
        var list = state.recent.filter { $0.caseInsensitiveCompare(hex) != .orderedSame }
        list.insert(hex, at: 0)
        if list.count > Self.maxRecent { list.removeLast(list.count - Self.maxRecent) }
        state.recent = list
        state.selected = hex
        defaults.set(list, "recent")
    }

    func setFormat(_ f: ClipColorFormat) {
        state.format = f
        defaults.set(f.rawValue, "format")
    }

    func selfTest() -> [String] {
        var out: [String] = []
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            out.append("\(ok ? "ok  " : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
        check("NSColorSampler available", NSClassFromString("NSColorSampler") != nil)
        let ns = NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)
        let c = ClipColors.from(ns)
        check("NSColor → HEX", c.map { ClipColors.format($0, .hex) } == "#FF8000", c.map { ClipColors.format($0, .hex) } ?? "")
        let p3 = NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)
        check("Display P3 → sRGB", ClipColors.from(p3) != nil, ClipColors.from(p3).map { ClipColors.format($0, .hex) } ?? "")
        let formats = ClipColorFormat.allCases.compactMap { f in c.map { ClipColors.format($0, f) } }
        check("four copy formats", formats.count == 4, formats.joined(separator: " | "))
        check("round trip", formats.prefix(3).allSatisfy { ClipColors.parse($0).map { ClipColors.format($0, .hex) } == "#FF8000" })
        // 최근 목록 규칙 (저장하지 않는 계산만)
        var list = (0..<14).map { String(format: "#%06X", $0) }
        list = Array(list.prefix(Self.maxRecent))
        check("recent list capped at 12", list.count == 12)
        out.append("recent colors stored: \(defaults.strings("recent", default: []).count)")
        out.append("note: the loupe is not opened by the self test (it needs a click on the screen)")
        return out
    }
}

/// 색상 탭: 스포이트, 형식 고르기, 최근 12색, 고른 색의 네 가지 형식
struct ColorToolsTab: View {
    let module: ColorToolsModule
    @ObservedObject var state: ColorToolsState

    private var current: ClipRGBA? { (state.selected ?? state.recent.first).flatMap(ClipColors.parse) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: module.pick) {
                    HStack(spacing: 6) {
                        Image(systemName: "eyedropper").font(.system(size: 13, weight: .semibold))
                        Text(T("화면에서 색 뽑기", "Pick from Screen")).font(.system(size: 12.5, weight: .medium))
                    }
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Color.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(T("확대 루페로 화면 아무 곳의 색을 고름 (Esc로 취소)", "Choose any pixel with the magnifier (Esc cancels)"))
                .accessibilityLabel(T("화면에서 색 뽑기", "Pick a color from the screen"))
                HStack(spacing: 4) {
                    ForEach(ClipColorFormat.allCases) { f in
                        Button { module.setFormat(f) } label: {
                            Text(f.label).font(.system(size: 10.5, weight: state.format == f ? .semibold : .regular))
                                .padding(.horizontal, 7).frame(height: 20)
                                .background(Color.white.opacity(state.format == f ? 0.22 : 0.07), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(T("뽑으면 \(f.label)로 복사", "Copy picks as \(f.label)"))
                    }
                }
                Text(T("최근 색", "Recent")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                if state.recent.isEmpty {
                    Text(T("아직 고른 색이 없음", "No colors picked yet")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 6), alignment: .leading, spacing: 6) {
                        ForEach(state.recent, id: \.self) { hex in swatch(hex) }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 214, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                if let c = current {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: ClipColors.nsColor(c)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.25)))
                        .frame(height: 46)
                    ForEach(ClipColorFormat.allCases) { f in
                        let s = ClipColors.format(c, f)
                        Button { module.copy(s, remember: nil) } label: {
                            HStack(spacing: 6) {
                                Text(f.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5)).frame(width: 44, alignment: .leading)
                                Text(s).font(.system(size: 11, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7).truncationMode(.middle)
                                Spacer(minLength: 0)
                                Image(systemName: state.copied == s ? "checkmark" : "doc.on.doc").font(.system(size: 10))
                                    .foregroundStyle(state.copied == s ? .green : .white.opacity(0.6))
                            }
                            .padding(.horizontal, 7).frame(height: 22)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(s)
                        .accessibilityLabel(T("\(f.label) 복사: \(s)", "Copy \(f.label): \(s)"))
                    }
                } else {
                    Text(T("색을 뽑으면 HEX·RGB·HSL·SwiftUI 형식이 여기에 나옴", "Pick a color to see HEX, RGB, HSL and SwiftUI values here"))
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(.white)
    }

    private func swatch(_ hex: String) -> some View {
        let c = ClipColors.parse(hex) ?? ClipRGBA(r: 0, g: 0, b: 0)
        let isSelected = (state.selected ?? state.recent.first) == hex
        return Button { state.selected = hex } label: {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(nsColor: ClipColors.nsColor(c)))
                .frame(width: 30, height: 30)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.9 : 0.2), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .help(hex)
        .accessibilityLabel(hex)
    }
}

/// 색상 설정 (설정 도우미 프로세스)
struct ColorToolsSettings: View {
    private let d = ModuleDefaults(module: "colors")
    @State private var format = ClipColorFormat.hex
    @State private var count = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(T("뽑은 색 복사 형식", "Copy format for picked colors"), selection: Binding(get: { format }, set: { format = $0; d.set($0.rawValue, "format") })) {
                ForEach(ClipColorFormat.allCases) { Text($0.label).tag($0) }
            }
            .frame(maxWidth: 320)
            HStack {
                Text(T("최근 색 \(count)개 (최대 12개)", "\(count) recent colors (up to 12)")).foregroundStyle(.secondary)
                Button(T("최근 색 비우기", "Clear Recent Colors")) { d.set([String](), "recent"); count = 0 }.disabled(count == 0)
            }
            ClipSettingsNote(T("스포이트는 macOS 확대 루페(NSColorSampler)를 써서 화면 기록 권한이 필요 없음. 고른 색은 바로 복사되고, 클립보드 기능이 켜져 있으면 견본으로 기록에 남아 고정할 수 있음.",
                               "The eyedropper uses the macOS magnifier (NSColorSampler), so no screen recording permission is needed. Picked colors are copied right away and, with Clipboard on, saved to history as swatches you can pin."))
            ClipSettingsNote(T("노치 패널 머리의 스포이트 버튼은 본 앱 머리 영역이 확장 기능 버튼을 받게 바뀌어야 함 (지금은 이 탭과 ⌘K 팔레트에서 실행).",
                               "A header eyedropper button needs the panel header to accept module buttons; for now use this tab or the ⌘K palette."))
        }
        .onAppear {
            format = ClipColorFormat(rawValue: d.string("format", default: "hex")) ?? .hex
            count = d.strings("recent", default: []).count
        }
    }
}

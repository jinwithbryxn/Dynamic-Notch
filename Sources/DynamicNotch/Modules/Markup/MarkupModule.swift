import AppKit
import SwiftUI

/// 마크업·워터마크 (M-G-004, M-G-005). 사용자가 고른 이미지(클립보드·파일)에만 동작한다.
/// 권한·백그라운드 작업이 없는 탭이라 기본으로 켠다.
final class MarkupModule: NotchModule {
    static let moduleID = "markup"
    let id = MarkupModule.moduleID
    var title: String { T("마크업", "Markup") }
    let symbol = "pencil.tip.crop.circle"
    var enabledByDefault: Bool { true }

    final class State: ObservableObject {
        @Published var status: String?
    }
    let state = State()
    private var context: ModuleContext?

    func start(context: ModuleContext) { self.context = context }
    func stop() {
        context = nil
    }

    func tabView() -> AnyView? { AnyView(MarkupTab(module: self, state: state)) }
    var tabContentSize: CGSize { CGSize(width: 460, height: 130) }

    func paletteActions() -> [PaletteAction] {
        [
            PaletteAction(id: "markup.clipboard", title: T("클립보드 이미지에 주석 달기", "Annotate Clipboard Image"),
                          symbol: "pencil.tip.crop.circle", keywords: ["annotate", "markup", "주석", "마크업", "편집"]) { [weak self] in self?.editClipboard() },
            PaletteAction(id: "markup.watermark", title: T("이미지에 워터마크", "Watermark an Image"),
                          symbol: "seal", keywords: ["watermark", "워터마크"]) { [weak self] in self?.watermarkPick() },
        ]
    }

    func editClipboard() {
        guard let img = CPImageIO.clipboardImage() else {
            state.status = T("클립보드에 이미지가 없음", "No image on the clipboard")
            return
        }
        context?.collapse()
        MarkupEditor.open(image: img, sourceURL: nil)
        state.status = nil
    }

    func editFile() {
        context?.collapse()
        guard let url = CPImageIO.pickImage(message: T("주석을 달 이미지를 고른다", "Choose an image to annotate")) else { return }
        guard let img = CPImageIO.load(url) else { state.status = T("이미지를 열지 못함", "Could not open the image"); return }
        MarkupEditor.open(image: img, sourceURL: url)
    }

    func watermarkPick() {
        context?.collapse()
        guard let url = CPImageIO.pickImage(message: T("워터마크를 넣을 이미지를 고른다", "Choose an image to watermark")) else { return }
        guard let img = CPImageIO.load(url) else { state.status = T("이미지를 열지 못함", "Could not open the image"); return }
        WatermarkEditor.open(image: img, sourceURL: url)
    }

    func watermarkClipboard() {
        guard let img = CPImageIO.clipboardImage() else {
            state.status = T("클립보드에 이미지가 없음", "No image on the clipboard")
            return
        }
        context?.collapse()
        WatermarkEditor.open(image: img, sourceURL: nil)
    }

    // MARK: 자체 검사: 만든 이미지에 도형·워터마크를 합성하고 픽셀을 확인한다

    func selfTest() -> [String] {
        var lines: [String] = []
        guard let base = CPTestImages.checker(width: 400, height: 300, cell: 10) else { return ["checker failed"] }
        let red: [CGFloat] = [1, 0, 0, 1]
        let shapes = [
            MarkupShape(tool: .rect, rgba: red, width: 6, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 120, y: 90)),
            MarkupShape(tool: .redact, rgba: [0, 0, 0, 1], width: 6, start: CGPoint(x: 200, y: 20), end: CGPoint(x: 260, y: 60)),
            MarkupShape(tool: .pixelate, rgba: red, width: 6, start: CGPoint(x: 280, y: 150), end: CGPoint(x: 390, y: 290)),
            MarkupShape(tool: .arrow, rgba: [0.04, 0.52, 1, 1], width: 6, start: CGPoint(x: 30, y: 250), end: CGPoint(x: 200, y: 160)),
            MarkupShape(tool: .text, rgba: red, width: 6, start: CGPoint(x: 150, y: 100), end: CGPoint(x: 150, y: 100),
                        text: "Notch", fontSize: 36),
            MarkupShape(tool: .highlight, rgba: [1, 0.84, 0.04, 1], width: 6, start: .zero, end: .zero,
                        points: [CGPoint(x: 20, y: 140), CGPoint(x: 140, y: 140)]),
        ]
        guard let out = MarkupRenderer.render(base: base, shapes: shapes) else { return ["render failed"] }
        CPTestImages.write(out, "markup-render.png").map { lines.append("wrote \($0)") }
        func px(_ x: Int, _ y: Int) -> String {
            guard let p = CPTestImages.pixel(out, x: x, y: y) else { return "?" }
            return "(\(p.r),\(p.g),\(p.b))"
        }
        let edge = CPTestImages.pixel(out, x: 20, y: 50)
        lines.append("rect edge (20,50) red: \(edge.map { $0.r > 200 && $0.g < 60 } ?? false) \(px(20, 50))")
        let black = CPTestImages.pixel(out, x: 230, y: 40)
        lines.append("redact (230,40) black: \(black.map { $0.r < 10 && $0.g < 10 && $0.b < 10 } ?? false)")
        // 모자이크: 원래 10px 격자가 큰 블록으로 바뀌어 이웃 픽셀이 같아진다
        let a = CPTestImages.pixel(out, x: 288, y: 170), b = CPTestImages.pixel(out, x: 290, y: 170)
        let origA = CPTestImages.pixel(base, x: 288, y: 170), origB = CPTestImages.pixel(base, x: 290, y: 170)
        lines.append("pixelate block uniform: \(a.map { "\($0)" } == b.map { "\($0)" }) (orig differ: \(origA.map { "\($0)" } != origB.map { "\($0)" }))")
        lines.append("arrow head (196,162): \(px(196, 162)) highlight (80,140): \(px(80, 140))")
        let textChanged = (150...240).contains { x in
            guard let p = CPTestImages.pixel(out, x: x, y: 122), let o = CPTestImages.pixel(base, x: x, y: 122) else { return false }
            return p.r > 200 && p.g < 80 && !(o.r > 200 && o.g < 80)
        }
        lines.append("text drawn: \(textChanged)")

        var wm = WatermarkOptions()
        wm.text = "SAMPLE"
        wm.colorHex = "#FF0000"
        wm.size = 0.12
        wm.opacity = 1
        wm.position = .bottomRight
        if let w = WatermarkRenderer.render(base: base, options: wm, markImage: nil) {
            CPTestImages.write(w, "watermark-text.png").map { lines.append("wrote \($0)") }
            let redCount = stride(from: 200, to: 400, by: 2).reduce(0) { n, x in
                n + stride(from: 240, to: 300, by: 2).filter { y in
                    guard let p = CPTestImages.pixel(w, x: x, y: y) else { return false }
                    return p.r > 200 && p.g < 80 && p.b < 80
                }.count
            }
            let topRed = stride(from: 0, to: 200, by: 4).filter { x in
                guard let p = CPTestImages.pixel(w, x: x, y: 20) else { return false }
                return p.r > 200 && p.g < 80 && p.b < 80
            }.count
            lines.append("text watermark bottom-right red samples: \(redCount), top-left: \(topRed)")
        }
        var im = WatermarkOptions()
        im.kind = .image
        im.position = .tile
        im.size = 0.2
        im.opacity = 0.6
        im.rotation = 30
        if let w = WatermarkRenderer.render(base: base, options: im, markImage: CPTestImages.qr("dmn")) {
            CPTestImages.write(w, "watermark-image-tile.png").map { lines.append("wrote \($0)") }
            lines.append("image watermark tile rendered \(w.width)x\(w.height)")
        }
        return lines
    }
}

private struct MarkupTab: View {
    let module: MarkupModule
    @ObservedObject var state: MarkupModule.State

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                CPTile(symbol: "doc.on.clipboard", title: T("클립보드 이미지", "Clipboard Image"),
                       help: T("클립보드의 이미지에 주석을 단다", "Annotate the image on the clipboard")) { module.editClipboard() }
                CPTile(symbol: "photo", title: T("이미지 파일…", "Image File…")) { module.editFile() }
                CPTile(symbol: "seal", title: T("워터마크…", "Watermark…"),
                       help: T("이미지 파일을 골라 글자·이미지 워터마크를 넣은 사본을 만든다", "Pick an image and save a watermarked copy")) { module.watermarkPick() }
                CPTile(symbol: "seal.fill", title: T("클립보드 워터마크", "Watermark Clipboard")) { module.watermarkClipboard() }
            }
            Text(T("화살표·사각형·타원·직선·형광펜·글자·모자이크·가림, 7색·3굵기, ⌘Z 실행 취소. 저장하면 원본 옆에 'annotated' 사본이 생기고 원본은 그대로다. 캡처 직후 편집은 '화면 캡처' 탭의 '캡처 후 편집'.",
                   "Arrow, rectangle, ellipse, line, highlighter, text, pixelate and redact; 7 colors, 3 widths, ⌘Z undo. Saving writes an 'annotated' copy next to the original. To edit right after capturing, use Capture & Mark Up in Screen Capture."))
                .font(.island(.caption)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            if let s = state.status {
                Text(s).font(.island(.footnote)).foregroundStyle(.orange)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - 워터마크 창

enum WatermarkEditor {
    static func open(image: CGImage, sourceURL: URL?) {
        let model = WatermarkModel(image: image, sourceURL: sourceURL)
        let window = CPEditorWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = T("워터마크", "Watermark") + (sourceURL.map { " — " + $0.lastPathComponent } ?? "")
        window.contentView = NSHostingView(rootView: WatermarkView(model: model))
        window.contentMinSize = CGSize(width: 760, height: 460)
        window.center()
        CPWindowKeeper.shared.show(window)
    }
}

final class WatermarkModel: ObservableObject {
    let image: CGImage
    let sourceURL: URL?
    let preview: CGImage
    @Published var options: WatermarkOptions { didSet { save(); refresh() } }
    @Published private(set) var rendered: CGImage?
    @Published var status: String?
    @Published var savedURL: URL?
    private var markImage: CGImage?
    private var defaults: ModuleDefaults { ModuleDefaults(module: MarkupModule.moduleID) }

    init(image: CGImage, sourceURL: URL?) {
        self.image = image
        self.sourceURL = sourceURL
        preview = MarkupRenderer.downscale(image, maxSide: 1400).0
        let stored = ModuleDefaults(module: MarkupModule.moduleID).string("watermark", default: "")
        options = (try? JSONDecoder().decode(WatermarkOptions.self, from: Data(stored.utf8))) ?? WatermarkOptions()
        loadMark()
        refresh()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(options), let s = String(data: data, encoding: .utf8) { defaults.set(s, "watermark") }
    }

    private func loadMark() {
        markImage = options.imagePath.isEmpty ? nil : CPImageIO.load(URL(fileURLWithPath: options.imagePath))
    }

    private func refresh() {
        // 크기는 짧은 변 비율이라 줄인 미리보기에 그대로 그려도 비율이 같다
        rendered = WatermarkRenderer.render(base: preview, options: options, markImage: markImage) ?? preview
    }

    func chooseMark() {
        guard let url = CPImageIO.pickImage(message: T("워터마크로 쓸 이미지(로고 등)", "Image to use as the watermark (logo)")) else { return }
        options.imagePath = url.path
        options.kind = .image
        loadMark()
        refresh()
    }

    func copy() {
        guard let img = WatermarkRenderer.render(base: image, options: options, markImage: markImage) else { return }
        CPImageIO.copy(img)
        status = T("클립보드에 복사함", "Copied to clipboard")
    }

    func saveCopy() {
        guard let img = WatermarkRenderer.render(base: image, options: options, markImage: markImage) else { return }
        let url = CPImageIO.siblingURL(for: sourceURL, suffix: "watermark")
        if CPImageIO.savePNG(img, to: url) {
            savedURL = url
            status = T("저장함: ", "Saved: ") + url.lastPathComponent
        } else {
            status = T("저장 실패", "Save failed")
        }
    }
}

private struct WatermarkView: View {
    @ObservedObject var model: WatermarkModel

    private var color: Binding<Color> {
        Binding(get: { Color(nsColor: WatermarkRenderer.color(model.options.colorHex)) },
                set: { c in
                    if let ns = NSColor(c).usingColorSpace(.sRGB) { model.options.colorHex = CaptureToolsModule.hex(ns) }
                })
    }

    private static let grid: [[WatermarkOptions.Position]] = [
        [.topLeft, .top, .topRight], [.left, .center, .right], [.bottomLeft, .bottom, .bottomRight],
    ]

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                if let img = model.rendered {
                    Image(decorative: img, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(12)
                }
            }
            Divider()
            Form {
                Picker(T("종류", "Type"), selection: $model.options.kind) {
                    Text(T("글자", "Text")).tag(WatermarkOptions.Kind.text)
                    Text(T("이미지", "Image")).tag(WatermarkOptions.Kind.image)
                }
                .pickerStyle(.segmented)
                if model.options.kind == .text {
                    TextField(T("글자", "Text"), text: $model.options.text)
                    ColorPicker(T("색", "Color"), selection: color, supportsOpacity: false)
                } else {
                    HStack {
                        Text(model.options.imagePath.isEmpty ? T("이미지 없음", "No image")
                             : URL(fileURLWithPath: model.options.imagePath).lastPathComponent)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(T("고르기…", "Choose…")) { model.chooseMark() }
                    }
                }
                LabeledContent(T("위치", "Position")) {
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(0..<3, id: \.self) { r in
                            HStack(spacing: 4) {
                                ForEach(Self.grid[r], id: \.self) { p in
                                    Button { model.options.position = p } label: {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(model.options.position == p ? Color.accentColor : Color.gray.opacity(0.3))
                                            .frame(width: 22, height: 16)
                                    }
                                    .buttonStyle(.borderless)
                                    .help(p.rawValue)
                                    .accessibilityLabel(p.rawValue)
                                }
                            }
                        }
                        Toggle(T("바둑판 반복", "Tile"), isOn: Binding(get: { model.options.position == .tile },
                                                                    set: { model.options.position = $0 ? .tile : .bottomRight }))
                    }
                }
                LabeledContent(T("크기 \(Int(model.options.size * 100))%", "Size \(Int(model.options.size * 100))%")) {
                    Slider(value: $model.options.size, in: 0.02...0.6)
                }
                .help(T("짧은 변에 대한 비율 (글자는 글자 크기, 이미지는 폭)", "Share of the short side (text: font size, image: width)"))
                LabeledContent(T("불투명도 \(Int(model.options.opacity * 100))%", "Opacity \(Int(model.options.opacity * 100))%")) {
                    Slider(value: $model.options.opacity, in: 0.1...1)
                }
                LabeledContent(T("회전 \(Int(model.options.rotation))°", "Rotation \(Int(model.options.rotation))°")) {
                    Slider(value: $model.options.rotation, in: -90...90, step: 5)
                }
                HStack {
                    Button(T("복사", "Copy")) { model.copy() }
                    Button(T("사본 저장", "Save Copy")) { model.saveCopy() }.keyboardShortcut("s", modifiers: .command)
                }
                if let s = model.status {
                    Text(s).font(.caption).foregroundStyle(.secondary)
                }
                if let url = model.savedURL {
                    Button(T("Finder에서 보기", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
            .formStyle(.grouped)
            .frame(width: 320)
        }
    }
}

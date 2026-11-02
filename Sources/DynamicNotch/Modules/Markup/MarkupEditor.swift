import AppKit
import SwiftUI

/// 마크업 편집기 창 (M-G-004). 도형은 데이터로 들고 있다가 저장·복사할 때 원본 해상도로 합성한다.
/// 저장은 원본 옆에 "annotated" 사본을 만들고 원본은 그대로 둔다.
enum MarkupEditor {
    static func open(image: CGImage, sourceURL: URL?) {
        let doc = MarkupDoc(image: image, sourceURL: sourceURL)
        let screen = NSScreen.cpUnderMouse?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        // 화면의 80% 안에 원본 비율로 맞춘다 (위 도구 막대 높이 포함)
        let toolbar: CGFloat = 92
        let maxW = screen.width * 0.8, maxH = screen.height * 0.8 - toolbar
        let iw = CGFloat(image.width) / (NSScreen.cpUnderMouse?.backingScaleFactor ?? 2)
        let ih = CGFloat(image.height) / (NSScreen.cpUnderMouse?.backingScaleFactor ?? 2)
        let k = min(1, maxW / max(1, iw), maxH / max(1, ih))
        let size = CGSize(width: max(720, iw * k), height: max(320, ih * k) + toolbar)
        let window = CPEditorWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = T("마크업", "Markup") + (sourceURL.map { " — " + $0.lastPathComponent } ?? "")
        window.contentView = NSHostingView(rootView: MarkupEditorView(doc: doc))
        window.contentMinSize = CGSize(width: 640, height: 360)
        window.center()
        CPWindowKeeper.shared.show(window)
    }
}

final class MarkupDoc: ObservableObject {
    let image: CGImage
    let sourceURL: URL?
    let preview: CGImage
    let previewScale: CGFloat

    @Published var shapes: [MarkupShape] = [] { didSet { refresh() } }
    @Published var drawing: MarkupShape? { didSet { refresh() } }
    @Published private(set) var rendered: CGImage?
    @Published var tool: MarkupTool = .arrow
    @Published var colorIndex = 0
    @Published var widthIndex = 1
    @Published var text = ""
    @Published var status: String?
    @Published var savedURL: URL?
    private var redoStack: [MarkupShape] = []

    static let palette: [[CGFloat]] = [
        [0.96, 0.23, 0.21, 1], [1.0, 0.58, 0.0, 1], [1.0, 0.84, 0.04, 1], [0.2, 0.78, 0.35, 1],
        [0.04, 0.52, 1.0, 1], [0.0, 0.0, 0.0, 1], [1, 1, 1, 1],
    ]
    static let widths: [CGFloat] = [3, 6, 12]

    init(image: CGImage, sourceURL: URL?) {
        self.image = image
        self.sourceURL = sourceURL
        (preview, previewScale) = MarkupRenderer.downscale(image, maxSide: 1800)
        rendered = preview
    }

    /// 굵기(픽셀): 큰 이미지일수록 비례해서 굵게
    var strokeWidth: CGFloat {
        Self.widths[widthIndex] * max(1, CGFloat(min(image.width, image.height)) / 900)
    }

    var canUndo: Bool { !shapes.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func newShape(at p: CGPoint) -> MarkupShape {
        var rgba = Self.palette[colorIndex]
        if tool == .redact && colorIndex == 6 { rgba = [0, 0, 0, 1] }   // 흰 가림은 의미가 없어 검정
        return MarkupShape(tool: tool, rgba: rgba, width: strokeWidth, start: p, end: p, points: [p],
                           text: text, fontSize: strokeWidth * 6)
    }

    func commit(_ s: MarkupShape) {
        let tiny = s.rect.width < 3 && s.rect.height < 3
        if s.tool != .text && s.tool != .highlight && tiny { drawing = nil; return }
        if s.tool == .text && s.text.isEmpty {
            status = T("위 칸에 글자를 먼저 입력해 줘", "Type the text in the field first")
            drawing = nil
            return
        }
        redoStack.removeAll()
        drawing = nil
        shapes.append(s)
    }

    func undo() {
        guard let last = shapes.popLast() else { return }
        redoStack.append(last)
    }

    func redo() {
        guard let s = redoStack.popLast() else { return }
        shapes.append(s)
    }

    private func refresh() {
        let list = shapes + (drawing.map { [$0] } ?? [])
        rendered = MarkupRenderer.render(base: preview, shapes: list, scale: previewScale) ?? preview
    }

    func full() -> CGImage? { MarkupRenderer.render(base: image, shapes: shapes, scale: 1) }

    func copy() {
        guard let img = full() else { status = T("합성 실패", "Render failed"); return }
        CPImageIO.copy(img)
        status = T("클립보드에 복사함", "Copied to clipboard")
    }

    func save() {
        guard let img = full() else { status = T("합성 실패", "Render failed"); return }
        let url = CPImageIO.siblingURL(for: sourceURL, suffix: "annotated")
        if CPImageIO.savePNG(img, to: url) {
            savedURL = url
            status = T("저장함: ", "Saved: ") + url.lastPathComponent
        } else {
            status = T("저장 실패: ", "Save failed: ") + url.deletingLastPathComponent().path
        }
    }
}

struct MarkupEditorView: View {
    @ObservedObject var doc: MarkupDoc

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
        }
        .frame(minWidth: 640, minHeight: 360)
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(MarkupTool.allCases) { t in
                    Button { doc.tool = t } label: {
                        Image(systemName: t.symbol).frame(width: 26, height: 22)
                            .background(doc.tool == t ? Color.accentColor.opacity(0.3) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.borderless)
                    .help(t.title)
                    .accessibilityLabel(t.title)
                }
                Divider().frame(height: 18)
                ForEach(MarkupDoc.palette.indices, id: \.self) { i in
                    let c = MarkupDoc.palette[i]
                    Button { doc.colorIndex = i } label: {
                        Circle().fill(Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: 1))
                            .overlay(Circle().stroke(doc.colorIndex == i ? Color.accentColor : Color.gray.opacity(0.5),
                                                     lineWidth: doc.colorIndex == i ? 2.5 : 1))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.borderless)
                    .help(T("색 \(i + 1)", "Color \(i + 1)"))
                    .accessibilityLabel(T("색 \(i + 1)", "Color \(i + 1)"))
                }
                Divider().frame(height: 18)
                Picker("", selection: $doc.widthIndex) {
                    Text(T("가늘게", "Thin")).tag(0)
                    Text(T("보통", "Medium")).tag(1)
                    Text(T("굵게", "Thick")).tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .help(T("굵기", "Stroke width"))
                Spacer()
            }
            HStack(spacing: 8) {
                if doc.tool == .text {
                    TextField(T("넣을 글자를 쓰고 그림을 누른다", "Type text, then click the image"), text: $doc.text)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }
                Button { doc.undo() } label: { Label(T("실행 취소", "Undo"), systemImage: "arrow.uturn.backward") }
                    .keyboardShortcut("z", modifiers: .command).disabled(!doc.canUndo)
                Button { doc.redo() } label: { Label(T("다시 실행", "Redo"), systemImage: "arrow.uturn.forward") }
                    .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!doc.canRedo)
                Spacer()
                if let s = doc.status {
                    Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                if let url = doc.savedURL {
                    Button(T("Finder에서 보기", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Button { doc.copy() } label: { Label(T("복사", "Copy"), systemImage: "doc.on.doc") }
                    .keyboardShortcut("c", modifiers: .command)
                Button { doc.save() } label: { Label(T("사본 저장", "Save Copy"), systemImage: "square.and.arrow.down") }
                    .keyboardShortcut("s", modifiers: .command)
                    .help(T("원본은 그대로 두고 'annotated' 사본을 저장", "Saves an 'annotated' copy and keeps the original"))
            }
        }
        .padding(10)
    }

    private var canvas: some View {
        GeometryReader { geo in
            let iw = CGFloat(doc.image.width), ih = CGFloat(doc.image.height)
            let k = min(geo.size.width / iw, geo.size.height / ih)
            let size = CGSize(width: iw * k, height: ih * k)
            let origin = CGPoint(x: (geo.size.width - size.width) / 2, y: (geo.size.height - size.height) / 2)
            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor)
                if let img = doc.rendered {
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width, height: size.height)
                        .offset(x: origin.x, y: origin.y)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in
                        let p = toImage(v.location, origin: origin, k: k)
                        if var d = doc.drawing {
                            d.end = p
                            if d.tool == .highlight { d.points.append(p) }
                            if d.tool == .text { d.start = p; d.end = p }
                            doc.drawing = d
                        } else {
                            doc.drawing = doc.newShape(at: toImage(v.startLocation, origin: origin, k: k))
                        }
                    }
                    .onEnded { _ in
                        if let d = doc.drawing { doc.commit(d) }
                    }
            )
        }
    }

    private func toImage(_ p: CGPoint, origin: CGPoint, k: CGFloat) -> CGPoint {
        let x = (p.x - origin.x) / k, y = (p.y - origin.y) / k
        return CGPoint(x: min(max(0, x), CGFloat(doc.image.width)), y: min(max(0, y), CGFloat(doc.image.height)))
    }
}

import AppKit
import CoreImage
import ScreenCaptureKit
import SwiftUI

/// 창 지켜보기 (M-G-018): 고른 창(또는 그 일부)을 ScreenCaptureKit으로 초당 2장만 받아 작은 실시간 썸네일로 보여 주고,
/// 내용이 바뀌면 알린다. 화면 기록 권한은 사용자가 '창 목록 불러오기'를 누를 때만 요청한다. 끄면(stop) 캡처를 멈춘다.
final class WindowWatchModule: NotchModule {
    let id = "windowwatch"
    var title: String { T("창 지켜보기", "Window Watch") }
    let symbol = "eye"
    /// 화면 캡처를 쓰므로 기본 꺼짐
    var enabledByDefault: Bool { false }

    let model = WatchModel()
    private var context: ModuleContext?

    func start(context: ModuleContext) {
        self.context = context
        model.onChange = { [weak self] title in
            guard let self else { return }
            CPSounds.play(.windowChanged)
            self.context?.notice(T("지켜보는 창이 바뀜", "Watched window changed"), title, symbol: "eye", tint: .yellow, tab: self.id)
        }
    }

    func stop() {
        model.stopWatching()
        model.onChange = nil
        context = nil
    }

    func tabView() -> AnyView? { AnyView(WatchTab(model: model)) }
    var tabContentSize: CGSize { CGSize(width: 600, height: 270) }

    func selfTest() -> [String] {
        // ScreenCaptureKit 목록 조회는 권한 창을 띄울 수 있어 부르지 않는다
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let normal = list.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
        return [
            "screen recording permission (preflight, no prompt): \(CPPermission.screenRecording.granted)",
            "on-screen normal windows (CGWindowList, no titles): \(normal.count)",
            "ScreenCaptureKit available: \(NSClassFromString("SCStream") != nil)",
            "watching now: \(model.running)",
        ]
    }
}

final class WatchModel: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    struct Item: Identifiable, Hashable {
        let id: CGWindowID
        let title: String
        let app: String
        let size: CGSize
    }

    private let d = ModuleDefaults(module: "windowwatch")
    @Published var items: [Item] = []
    @Published var selected: Item?
    @Published private(set) var image: CGImage?
    /// 지켜볼 부분 (0–1, 위쪽 원점). nil이면 창 전체.
    @Published var crop: CGRect?
    @Published private(set) var running = false
    @Published var status: String?
    @Published var notify: Bool { didSet { d.set(notify, "notify") } }
    @Published var floating: Bool { didSet { d.set(floating, "floating"); updateFloating() } }
    @Published var granted = CPPermission.screenRecording.granted

    var onChange: ((String) -> Void)?
    private var windows: [CGWindowID: SCWindow] = [:]
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "windowwatch.frames", qos: .utility)
    private let ci = CIContext(options: [.cacheIntermediates: false])
    private var lastSignature: [UInt8]?
    private var lastNotice = Date.distantPast
    private var panel: CPOverlayPanel?

    override init() {
        notify = d.bool("notify", default: true)
        floating = d.bool("floating", default: false)
        super.init()
    }

    /// 사용자 동작: 창 목록을 불러온다 (권한이 없으면 요청하고 멈춘다)
    func loadWindows() {
        granted = CPPermission.screenRecording.granted
        guard granted else {
            CPPermission.screenRecording.request()
            status = T("화면 기록 권한이 필요함. 허용한 뒤 앱을 다시 시작해 줘.", "Screen Recording permission is needed. Allow it, then relaunch the app.")
            return
        }
        status = T("창 목록을 불러오는 중…", "Loading windows…")
        let me = Bundle.main.bundleIdentifier
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let content else {
                    self.status = T("창 목록 실패: ", "Could not list windows: ") + (error?.localizedDescription ?? "")
                    return
                }
                let list = content.windows.filter {
                    $0.windowLayer == 0 && $0.frame.width >= 80 && $0.frame.height >= 60
                        && $0.owningApplication != nil && $0.owningApplication?.bundleIdentifier != me
                }
                self.windows = Dictionary(uniqueKeysWithValues: list.map { ($0.windowID, $0) })
                self.items = list.map {
                    Item(id: $0.windowID, title: ($0.title?.isEmpty == false ? $0.title! : T("(제목 없음)", "(untitled)")),
                         app: $0.owningApplication?.applicationName ?? "?", size: $0.frame.size)
                }
                self.status = T("창 \(list.count)개", "\(list.count) windows")
            }
        }
    }

    func select(_ item: Item) {
        selected = item
        crop = nil
        if running { restart() }
    }

    func startWatching() {
        guard let item = selected, let w = windows[item.id] else {
            status = T("먼저 창을 골라 줘", "Pick a window first")
            return
        }
        stopWatching(keepImage: true)
        let filter = SCContentFilter(desktopIndependentWindow: w)
        let config = SCStreamConfiguration()
        var source = CGRect(origin: .zero, size: w.frame.size)
        if let c = crop {
            source = CGRect(x: c.minX * w.frame.width, y: c.minY * w.frame.height, width: c.width * w.frame.width, height: c.height * w.frame.height)
            config.sourceRect = source
        }
        // 썸네일 크기: 긴 변 480픽셀
        let k = 480 / max(source.width, source.height, 1)
        config.width = max(32, Int(source.width * k))
        config.height = max(32, Int(source.height * k))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 2)
        config.showsCursor = false
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        let s = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        } catch {
            status = T("캡처를 준비하지 못함: ", "Could not prepare capture: ") + error.localizedDescription
            return
        }
        stream = s
        lastSignature = nil
        s.startCapture { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.stream = nil
                    self.running = false
                    self.status = T("캡처 시작 실패: ", "Capture failed: ") + error.localizedDescription
                } else {
                    self.running = true
                    self.status = T("지켜보는 중 · ", "Watching · ") + item.app
                    self.updateFloating()
                }
            }
        }
    }

    func stopWatching(keepImage: Bool = false) {
        if let s = stream {
            s.stopCapture { _ in }
            try? s.removeStreamOutput(self, type: .screen)
        }
        stream = nil
        running = false
        if !keepImage { image = nil }
        closeFloating()
    }

    private func restart() { startWatching() }

    /// 미리보기에서 끌어 고른 부분을 지켜본다 (현재 부분 안에서 다시 고르면 겹쳐 계산)
    func setCrop(_ r: CGRect) {
        guard r.width > 0.03, r.height > 0.03 else { return }
        let base = crop ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        crop = CGRect(x: base.minX + r.minX * base.width, y: base.minY + r.minY * base.height,
                      width: r.width * base.width, height: r.height * base.height)
        if running { restart() }
    }

    func clearCrop() {
        crop = nil
        if running { restart() }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pixels = sampleBuffer.imageBuffer else { return }
        let ciImage = CIImage(cvPixelBuffer: pixels)
        guard let cg = ci.createCGImage(ciImage, from: ciImage.extent) else { return }
        let sig = Self.signature(cg)
        let changed: Bool
        if let last = lastSignature, let sig {
            changed = Self.difference(last, sig) > 6
        } else {
            changed = false
        }
        if let sig { lastSignature = sig }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.image = cg
            if changed, self.notify, Date().timeIntervalSince(self.lastNotice) > 5 {
                self.lastNotice = Date()
                self.onChange?(self.selected.map { "\($0.app) — \($0.title)" } ?? "")
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil
            self.running = false
            self.closeFloating()
            self.status = T("캡처가 멈춤 (창이 닫혔을 수 있음): ", "Capture stopped (the window may be closed): ") + error.localizedDescription
        }
    }

    /// 16×16 회색 축소본 (바뀜 비교용)
    static func signature(_ image: CGImage) -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: 256)
        guard let ctx = CGContext(data: &buf, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 16,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        return buf
    }

    /// 평균 밝기 차이 (0–255)
    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        return Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(a.count)
    }

    // MARK: 떠 있는 썸네일 (캡처에서 숨기기 시도)

    private func updateFloating() {
        guard floating, running else { closeFloating(); return }
        guard panel == nil, let screen = NSScreen.main else { return }
        let size = CGSize(width: 260, height: 180)
        let frame = CGRect(x: screen.visibleFrame.maxX - size.width - 16, y: screen.visibleFrame.maxY - size.height - 16,
                           width: size.width, height: size.height)
        let p = CPOverlayPanel(frame: frame, level: .floating, clickThrough: false, hideFromCapture: true)
        p.isMovable = true
        p.isMovableByWindowBackground = true
        p.contentView = CPHostingView(rootView: WatchFloatingView(model: self))
        p.orderFrontRegardless()
        panel = p
    }

    private func closeFloating() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    func hideFloating() { floating = false }
}

private struct WatchFloatingView: View {
    @ObservedObject var model: WatchModel
    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.85))
            if let img = model.image {
                Image(decorative: img, scale: 1).resizable().aspectRatio(contentMode: .fit).padding(6)
            }
            Button { model.hideFloating() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white.opacity(0.8)).padding(6)
            }
            .buttonStyle(.plain)
            .help(T("썸네일 닫기", "Close thumbnail"))
            .accessibilityLabel(T("썸네일 닫기", "Close thumbnail"))
        }
    }
}

private struct WatchTab: View {
    @ObservedObject var model: WatchModel
    @State private var dragStart: CGPoint?
    @State private var dragRect: CGRect?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    CPPill(symbol: "arrow.clockwise", title: T("창 목록 불러오기", "Load Windows")) { model.loadWindows() }
                    if model.running {
                        CPPill(symbol: "stop.fill", title: T("멈추기", "Stop"), tint: .red) { model.stopWatching() }
                    } else {
                        CPPill(symbol: "eye.fill", title: T("지켜보기", "Watch"), tint: .green, disabled: model.selected == nil) { model.startWatching() }
                    }
                }
                Menu {
                    ForEach(model.items) { item in
                        Button("\(item.app) — \(item.title)") { model.select(item) }
                    }
                } label: {
                    Text(model.selected.map { "\($0.app) — \($0.title)" } ?? T("창 고르기", "Choose a window"))
                        .font(.system(size: 11)).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .disabled(model.items.isEmpty)
                .frame(maxWidth: 270, alignment: .leading)
                HStack(spacing: 6) {
                    Text(model.crop == nil ? T("부분: 창 전체", "Region: whole window") : T("부분: 고른 영역", "Region: selection"))
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                    if model.crop != nil {
                        CPPill(symbol: "arrow.up.left.and.arrow.down.right", title: T("전체로", "Whole")) { model.clearCrop() }
                    }
                }
                Toggle(T("바뀌면 알림", "Notify on change"), isOn: $model.notify)
                Toggle(T("떠 있는 썸네일 (캡처에서 숨기기 시도)", "Floating thumbnail (tries to hide from capture)"), isOn: $model.floating)
                CPPermissionLine(permission: .screenRecording, granted: model.granted)
                if let s = model.status {
                    Text(s).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            .frame(width: 290)
            preview
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { model.granted = CPPermission.screenRecording.granted }
    }

    private var preview: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06))
                if let img = model.image {
                    let fit = fitted(CGSize(width: img.width, height: img.height), in: geo.size)
                    Image(decorative: img, scale: 1).resizable().frame(width: fit.width, height: fit.height)
                        .overlay(alignment: .topLeading) {
                            if let r = dragRect {
                                Rectangle().stroke(Color.yellow, lineWidth: 1.5)
                                    .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                            }
                        }
                        .gesture(DragGesture(minimumDistance: 4)
                            .onChanged { v in
                                let a = clamp(v.startLocation, fit), b = clamp(v.location, fit)
                                dragRect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                            }
                            .onEnded { _ in
                                if let r = dragRect {
                                    model.setCrop(CGRect(x: r.minX / fit.width, y: r.minY / fit.height, width: r.width / fit.width, height: r.height / fit.height))
                                }
                                dragRect = nil
                            })
                        .help(T("끌어서 지켜볼 부분을 고른다", "Drag to choose the region to watch"))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "macwindow").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                        Text(T("창을 고르고 '지켜보기'를 누르면\n여기에 실시간 썸네일이 나온다. 끌어서 부분 지정.",
                               "Pick a window and press Watch\nto see a live thumbnail. Drag to pick a region."))
                            .font(.system(size: 10.5)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
    }

    private func fitted(_ size: CGSize, in box: CGSize) -> CGSize {
        let k = min(box.width / max(1, size.width), box.height / max(1, size.height))
        return CGSize(width: size.width * k, height: size.height * k)
    }

    private func clamp(_ p: CGPoint, _ s: CGSize) -> CGPoint {
        CGPoint(x: min(max(0, p.x), s.width), y: min(max(0, p.y), s.height))
    }
}

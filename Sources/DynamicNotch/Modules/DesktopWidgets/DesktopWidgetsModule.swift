import AppKit
import ImageIO
import SwiftUI

/// 사진 위젯 설정 (사진 한 장 또는 폴더 순환)
struct PhotoWidgetConfig: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var path: String
    /// 폴더일 때 다음 사진으로 바꾸는 간격(분)
    var intervalMinutes = 10
}

/// 배경화면 위(모든 창 아래)에 놓는 위젯 창: 시계·세계 시계·타이머·활동·사진(최대 6개).
/// 끌어서 옮기면 위치를 위젯마다 저장하고, 오른쪽 클릭으로 크기·닫기를 고른다. 기능을 끄면 창을 모두 닫는다.
/// WidgetKit 위젯(M-L-009)은 서명된 앱 확장이 필요해 이 창으로 대신한다.
final class DesktopWidgetsModule: NotchModule, ObservableObject {
    let id = "desktopwidgets"
    var title: String { T("데스크톱 위젯", "Desktop Widgets") }
    let symbol = "rectangle.3.group"
    var enabledByDefault: Bool { false }

    static let maxPhotos = 6
    static let fixedKinds = ["clock", "worldclock", "timers", "activity"]

    private var windows: [String: NSPanel] = [:]
    private var delegates: [String: DesktopWidgetWindowDelegate] = [:]
    private var photoModels: [String: PhotoWidgetModel] = [:]
    private var photoTimer: Timer?
    private var started = false
    private var seenResetAt: Double = 0
    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }

    // MARK: 설정

    var enabledWidgets: [String] {
        let photos = Set(photoConfigs.map { "photo:" + $0.id })
        return defaults.strings("widgets", default: ["clock"]).filter { Self.fixedKinds.contains($0) || photos.contains($0) }
    }

    var photoConfigs: [PhotoWidgetConfig] {
        guard let d = defaults.data("photos"), let list = try? JSONDecoder().decode([PhotoWidgetConfig].self, from: d) else { return [] }
        return Array(list.prefix(Self.maxPhotos))
    }

    var glass: Bool { defaults.bool("glass", default: true) }

    func scale(_ wid: String) -> CGFloat {
        switch defaults.string("size.\(wid)", default: "m") {
        case "s": return 0.8
        case "l": return 1.3
        default: return 1
        }
    }

    func setEnabled(_ wid: String, _ on: Bool) {
        var list = defaults.strings("widgets", default: ["clock"])
        list.removeAll { $0 == wid }
        if on { list.append(wid) }
        defaults.set(list, "widgets")
        objectWillChange.send()
    }

    // MARK: 수명

    func start(context: ModuleContext) {
        guard !started else { return }
        started = true
        seenResetAt = defaults.double("resetAt", default: 0)
        // 검사·그림 모드(도우미 프로세스)에서는 화면에 창을 띄우지 않는다
        guard !AppSettings.isHelper else { return }
        sync()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.rotatePhotos() }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        photoTimer = t
    }

    func stop() {
        started = false
        photoTimer?.invalidate()
        photoTimer = nil
        for w in windows.values { w.orderOut(nil); w.close() }
        windows = [:]
        delegates = [:]
        photoModels = [:]
    }

    func settingsChanged() {
        objectWillChange.send()
        let reset = defaults.double("resetAt", default: 0)
        if reset > seenResetAt {
            seenResetAt = reset
            for wid in windows.keys { UserDefaults.standard.removeObject(forKey: Self.positionKey(wid)) }
            for w in windows.values { w.close() }
            windows = [:]
            delegates = [:]
        }
        guard started, !AppSettings.isHelper else { return }
        sync()
    }

    /// 켜진 위젯과 열린 창을 맞춘다
    private func sync() {
        let wanted = enabledWidgets
        for (wid, w) in windows where !wanted.contains(wid) {
            w.close()
            windows[wid] = nil
            delegates[wid] = nil
            photoModels[wid] = nil
        }
        let configs = Dictionary(uniqueKeysWithValues: photoConfigs.map { ("photo:" + $0.id, $0) })
        for (i, wid) in wanted.enumerated() {
            if let cfg = configs[wid] {
                let model = photoModels[wid] ?? PhotoWidgetModel(id: wid)
                model.config = cfg
                model.reload()
                photoModels[wid] = model
            }
            let size = Self.baseSize(wid).applying(CGAffineTransform(scaleX: scale(wid), y: scale(wid)))
            if let w = windows[wid] {
                if w.frame.size != size { w.setContentSize(size) }
                (w.contentView as? DesktopWidgetHost)?.rootView = view(for: wid)
                continue
            }
            open(wid, size: size, index: i)
        }
    }

    private func view(for wid: String) -> AnyView {
        AnyView(DesktopWidgetContent(kind: wid, scale: scale(wid), glass: glass, photo: photoModels[wid]))
    }

    private func open(_ wid: String, size: CGSize, index: Int) {
        let origin = Self.savedOrigin(wid, size: size) ?? Self.defaultOrigin(index: index, size: size)
        let panel = NSPanel(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        // 바탕화면 아이콘 바로 위, 일반 창 아래
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let host = DesktopWidgetHost(rootView: view(for: wid))
        host.onRightClick = { [weak self] event, v in self?.showMenu(wid, event: event, view: v) }
        panel.contentView = host
        let d = DesktopWidgetWindowDelegate(id: wid)
        panel.delegate = d
        delegates[wid] = d
        windows[wid] = panel
        panel.orderFrontRegardless()
    }

    private func showMenu(_ wid: String, event: NSEvent, view: NSView) {
        let menu = NSMenu()
        let current = defaults.string("size.\(wid)", default: "m")
        for (key, label) in [("s", T("작게", "Small")), ("m", T("보통", "Medium")), ("l", T("크게", "Large"))] {
            let item = TFMenuItem(title: label) { [weak self] in self?.defaults.set(key, "size.\(wid)") }
            item.state = current == key ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let glassItem = TFMenuItem(title: T("유리 효과", "Glass")) { [weak self] in
            guard let self else { return }
            self.defaults.set(!self.glass, "glass")
        }
        glassItem.state = glass ? .on : .off
        menu.addItem(glassItem)
        menu.addItem(.separator())
        menu.addItem(TFMenuItem(title: T("위젯 닫기", "Remove Widget")) { [weak self] in self?.setEnabled(wid, false) })
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func rotatePhotos() {
        for m in photoModels.values { m.advanceIfDue() }
    }

    // MARK: 위치·크기

    static func positionKey(_ wid: String) -> String { "module.desktopwidgets.pos.\(wid)" }

    static func baseSize(_ wid: String) -> CGSize {
        switch wid {
        case "clock": return CGSize(width: 210, height: 112)
        case "worldclock": return CGSize(width: 250, height: CGFloat(max(1, WorldClockModule().zones.count)) * 40 + 30)
        case "timers": return CGSize(width: 230, height: 128)
        case "activity": return CGSize(width: 260, height: 120)
        default: return CGSize(width: 220, height: 220)   // 사진
        }
    }

    static func savedOrigin(_ wid: String, size: CGSize) -> CGPoint? {
        guard let a = UserDefaults.standard.array(forKey: positionKey(wid)) as? [Double], a.count == 2 else { return nil }
        let p = CGPoint(x: a[0], y: a[1])
        // 화면 밖이면(모니터를 뺐을 때) 기본 자리로
        let rect = CGRect(origin: p, size: size)
        return NSScreen.screens.contains { $0.frame.intersects(rect) } ? p : nil
    }

    static func defaultOrigin(index: Int, size: CGSize) -> CGPoint {
        let vf = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let col = index / 3, row = index % 3
        return CGPoint(x: vf.minX + 40 + CGFloat(col) * 270, y: vf.maxY - 40 - size.height - CGFloat(row) * 240)
    }

    // MARK: 탭·설정

    func tabView() -> AnyView? { AnyView(DesktopWidgetsTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 620, height: 236) }
    func settingsView() -> AnyView? { AnyView(DesktopWidgetsSettings()) }

    func selfTest() -> [String] {
        let level = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        let photos = photoConfigs.map { cfg -> String in
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: cfg.path, isDirectory: &isDir)
            let count = isDir.boolValue ? PhotoWidgetModel.images(in: cfg.path).count : (exists ? 1 : 0)
            return "\((cfg.path as NSString).lastPathComponent): \(exists ? (isDir.boolValue ? "folder \(count) images" : "file") : "missing")"
        }
        return [
            "window level \(level) (desktop icon + 1, normal is 0), behaviors canJoinAllSpaces+stationary+ignoresCycle",
            "enabled widgets: \(enabledWidgets)",
            "photo widgets (\(photoConfigs.count)/\(Self.maxPhotos)): \(photos.isEmpty ? "none" : photos.joined(separator: "; "))",
            "screens: \(NSScreen.screens.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" })",
            "WidgetKit widgets (M-L-009): deferred, needs a signed app extension + app group",
        ]
    }
}

/// 창 위치 저장 (끌기가 끝나면)
final class DesktopWidgetWindowDelegate: NSObject, NSWindowDelegate {
    let id: String
    private var work: DispatchWorkItem?
    init(id: String) { self.id = id }

    func windowDidMove(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        work?.cancel()
        let key = DesktopWidgetsModule.positionKey(id)
        let item = DispatchWorkItem { UserDefaults.standard.set([Double(w.frame.minX), Double(w.frame.minY)], forKey: key) }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }
}

/// 위젯 창 내용: 왼쪽 끌기로 창을 옮기고, 오른쪽 클릭으로 메뉴를 띄운다.
final class DesktopWidgetHost: NSHostingView<AnyView> {
    var onRightClick: ((NSEvent, NSView) -> Void)?

    required init(rootView: AnyView) { super.init(rootView: rootView) }
    required init?(coder: NSCoder) { fatalError("unused") }

    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func rightMouseDown(with event: NSEvent) { onRightClick?(event, self) }
}

/// 클로저로 동작하는 메뉴 항목
final class TFMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("unused") }
    @objc private func fire() { handler() }
}

/// 사진 위젯 모델: 한 장이면 그 사진, 폴더면 간격마다 다음 사진 (크게 읽지 않고 900px로 줄여 읽음)
final class PhotoWidgetModel: ObservableObject {
    let id: String
    var config = PhotoWidgetConfig(path: "")
    @Published private(set) var image: NSImage?
    @Published private(set) var problem: String?
    private var lastChange = Date()

    init(id: String) { self.id = id }

    private var indexKey: String { "module.desktopwidgets.photoIndex.\(id)" }

    static func images(in folder: String) -> [URL] {
        let exts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "webp", "bmp"]
        let url = URL(fileURLWithPath: folder)
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return items.filter { exts.contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func reload() {
        var isDir: ObjCBool = false
        guard !config.path.isEmpty, FileManager.default.fileExists(atPath: config.path, isDirectory: &isDir) else {
            image = nil
            problem = T("사진을 찾을 수 없어요", "Photo not found")
            return
        }
        let url: URL
        if isDir.boolValue {
            let list = Self.images(in: config.path)
            guard !list.isEmpty else { image = nil; problem = T("폴더에 사진이 없어요", "No photos in the folder"); return }
            let i = UserDefaults.standard.integer(forKey: indexKey) % list.count
            url = list[i]
        } else {
            url = URL(fileURLWithPath: config.path)
        }
        image = Self.thumbnail(url, maxPixel: 900)
        problem = image == nil ? T("사진을 읽지 못했어요", "Couldn't read the photo") : nil
    }

    func advanceIfDue() {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: config.path, isDirectory: &isDir), isDir.boolValue,
              Date().timeIntervalSince(lastChange) >= Double(max(1, config.intervalMinutes) * 60) else { return }
        lastChange = Date()
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: indexKey) + 1, forKey: indexKey)
        reload()
    }

    static func thumbnail(_ url: URL, maxPixel: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

// MARK: - 위젯 화면

private struct TFVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct DesktopWidgetContent: View {
    var kind: String
    var scale: CGFloat
    var glass: Bool
    var photo: PhotoWidgetModel?

    var body: some View {
        let base = DesktopWidgetsModule.baseSize(kind)
        ZStack {
            if kind.hasPrefix("photo:") {
                if let photo { PhotoWidgetView(model: photo) } else { Color.black.opacity(0.4) }
            } else {
                Group {
                    switch kind {
                    case "clock": ClockWidgetView()
                    case "worldclock": WorldClockWidgetView()
                    case "timers": TimersWidgetView(pomodoro: PomodoroEngine.shared, stopwatch: StopwatchEngine.shared, awake: KeepAwakeEngine.shared)
                    case "activity": ActivityWidgetView(store: ActivityStore.shared)
                    default: EmptyView()
                    }
                }
                .padding(14)
                .frame(width: base.width, height: base.height, alignment: .topLeading)
            }
        }
        .frame(width: base.width, height: base.height)
        .background {
            if glass { TFVisualEffect() } else { Color(white: 0.11) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: base.width * scale, height: base.height * scale, alignment: .topLeading)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

private struct ClockWidgetView: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: .leading, spacing: 4) {
                Text(ctx.date, format: .dateTime.weekday(.wide).month().day())
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                Text(TFFormat.time(ctx.date))
                    .font(.system(size: 44, weight: .light, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }
}

private struct WorldClockWidgetView: View {
    var body: some View {
        let zones = WorldClockModule().zones.compactMap { TimeZone(identifier: $0) }
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: .leading, spacing: 4) {
                if zones.isEmpty {
                    Text(T("세계 시계 설정에서 도시를 추가하세요", "Add cities in World Clock settings")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
                ForEach(zones, id: \.identifier) { z in
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(WorldClockModule.city(z)).font(.system(size: 13, weight: .semibold))
                            Text(WorldClockModule.offsetText(z, from: .current, at: ctx.date)).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        Text(WorldClockModule.time(ctx.date, z)).font(.system(size: 20, design: .rounded)).monospacedDigit()
                    }
                    .frame(height: 36)
                }
            }
        }
    }
}

private struct TimersWidgetView: View {
    @ObservedObject var pomodoro: PomodoroEngine
    @ObservedObject var stopwatch: StopwatchEngine
    @ObservedObject var awake: KeepAwakeEngine

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 7) {
                Text(T("타이머", "Timers")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                if let s = pomodoro.state {
                    row(s.phase.symbol, s.phase.tint, s.waiting ? T("\(s.phase.title) 준비", "\(s.phase.title) ready") : s.phase.title,
                        TFFormat.clock(pomodoro.remaining))
                }
                if !stopwatch.isIdle {
                    row("stopwatch", .yellow, T("스톱워치", "Stopwatch"), StopwatchEngine.format(stopwatch.elapsed(at: ctx.date), hundredths: false))
                }
                if awake.isActive {
                    row("cup.and.saucer.fill", .orange, T("잠자기 방지", "Keep Awake"),
                        awake.remaining.map { TFFormat.clock($0) } ?? "∞")
                }
                if pomodoro.state == nil && stopwatch.isIdle && !awake.isActive {
                    Text(T("실행 중인 타이머가 없어요", "No timers running")).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                    Text(T("포모도로·스톱워치·잠자기 방지가 돌면 여기 보여요", "Pomodoro, stopwatch and Keep Awake show here"))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func row(_ symbol: String, _ tint: Color, _ label: String, _ value: String) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 18)
            Text(label).font(.system(size: 12.5))
            Spacer()
            Text(value).font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
        }
    }
}

private struct ActivityWidgetView: View {
    @ObservedObject var store: ActivityStore

    var body: some View {
        let running = ModuleRegistry.shared.running.contains(ActivityStore.module)
        let d = store.today
        let hasKeys = TFKeyTap.hasPermission
        let p = ActivityStore.progress(d, keysAvailable: hasKeys)
        HStack(spacing: 14) {
            ActivityRingsGlyph(move: p.move, type: p.type, focus: p.focus, size: 82, typeAvailable: hasKeys)
            VStack(alignment: .leading, spacing: 4) {
                Text(ActivityRingModule.km(d.distanceMM / 1000)).foregroundStyle(ActivityRingsGlyph.moveTint)
                Text(hasKeys ? TFFormat.number(d.keys) + T("회", " keys") : T("키: 권한 필요", "Keys: no access")).foregroundStyle(hasKeys ? ActivityRingsGlyph.typeTint : .gray)
                Text(TFFormat.duration(d.activeSeconds)).foregroundStyle(ActivityRingsGlyph.focusTint)
                if !running {
                    Text(T("활동 링 기능이 꺼져 있어요", "Activity Rings is off")).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .onAppear { store.load() }
    }
}

private struct PhotoWidgetView: View {
    @ObservedObject var model: PhotoWidgetModel

    var body: some View {
        if let img = model.image {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                .accessibilityLabel(T("사진 위젯", "Photo widget"))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "photo").font(.system(size: 28))
                Text(model.problem ?? T("사진 없음", "No photo")).font(.system(size: 11))
            }
            .foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - 탭 (노치 안 관리 화면)

private struct DesktopWidgetsTab: View {
    @ObservedObject var module: DesktopWidgetsModule

    var body: some View {
        let enabled = module.enabledWidgets
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(DesktopWidgetsModule.fixedKinds, id: \.self) { k in
                    TFPillButton(title: label(k), symbol: enabled.contains(k) ? "checkmark" : "plus", prominent: enabled.contains(k),
                                 help: enabled.contains(k) ? T("\(label(k)) 위젯 닫기", "Remove \(label(k))") : T("\(label(k)) 위젯 놓기", "Add \(label(k))")) {
                        module.setEnabled(k, !enabled.contains(k))
                    }
                }
                Text(T("사진 \(module.photoConfigs.count)/\(DesktopWidgetsModule.maxPhotos)", "Photos \(module.photoConfigs.count)/\(DesktopWidgetsModule.maxPhotos)"))
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
                Spacer()
            }
            if enabled.isEmpty {
                Text(T("놓을 위젯을 고르세요. 바탕화면에서 끌어 옮기고, 오른쪽 클릭으로 크기·닫기를 골라요.",
                       "Pick widgets to place. Drag them on the desktop; right-click for size or remove."))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(enabled.filter { !$0.hasPrefix("photo:") }, id: \.self) { k in
                            let size = DesktopWidgetsModule.baseSize(k)
                            DesktopWidgetContent(kind: k, scale: 0.68, glass: false, photo: nil)
                                .frame(width: size.width * 0.68, height: size.height * 0.68, alignment: .topLeading)
                        }
                    }
                }
                .frame(height: 140, alignment: .topLeading)
                Text(T("바탕화면(모든 창 아래)에 떠 있어요 · 끌어 옮기면 위치 저장 · 오른쪽 클릭: 크기·유리·닫기 · 사진 위젯은 설정에서 추가",
                       "On the desktop below all windows · drag to move (saved) · right-click: size, glass, remove · add photo widgets in Settings"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
            }
        }
        .foregroundStyle(.white)
    }

    private func label(_ k: String) -> String {
        switch k {
        case "clock": return T("시계", "Clock")
        case "worldclock": return T("세계 시계", "World Clock")
        case "timers": return T("타이머", "Timers")
        case "activity": return T("활동", "Activity")
        default: return k
        }
    }
}

// MARK: - 설정 (도우미 프로세스)

private struct DesktopWidgetsSettings: View {
    @StateObject private var prefs = TFPrefs(module: "desktopwidgets")
    @State private var photos: [PhotoWidgetConfig] = []

    private var defaults: ModuleDefaults { prefs.defaults }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(DesktopWidgetsModule.fixedKinds, id: \.self) { k in
                Toggle(label(k), isOn: Binding(get: { defaults.strings("widgets", default: ["clock"]).contains(k) },
                                              set: { on in toggle(k, on) }))
            }
            Toggle(T("유리 효과 (끄면 불투명)", "Glass (off = opaque)"), isOn: prefs.bool("glass", true))
            Divider()
            Text(T("사진 위젯 (최대 6개)", "Photo Widgets (up to 6)")).font(.headline)
            ForEach(photos) { p in
                HStack {
                    Image(systemName: isFolder(p.path) ? "folder" : "photo")
                    Text((p.path as NSString).lastPathComponent).lineLimit(1)
                    Spacer()
                    if isFolder(p.path) {
                        Picker("", selection: Binding(get: { p.intervalMinutes }, set: { v in update(p.id) { $0.intervalMinutes = v } })) {
                            ForEach([1, 5, 10, 30, 60, 240], id: \.self) { m in Text(m >= 60 ? T("\(m / 60)시간마다", "Every \(m / 60)h") : T("\(m)분마다", "Every \(m) min")).tag(m) }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                    Button(T("빼기", "Remove")) { remove(p.id) }
                }
            }
            HStack {
                Button(T("사진 추가…", "Add Photo…")) { add(folder: false) }.disabled(photos.count >= DesktopWidgetsModule.maxPhotos)
                Button(T("폴더 추가 (순환)…", "Add Folder (rotate)…")) { add(folder: true) }.disabled(photos.count >= DesktopWidgetsModule.maxPhotos)
            }
            TFSettingsNote(text: T("위젯은 바탕화면(모든 창 아래)에 놓여요. 끌어서 옮기면 위치를 기억하고, 오른쪽 클릭으로 크기·유리 효과·닫기를 골라요.",
                                   "Widgets sit on the desktop below all windows. Drag to move (remembered); right-click for size, glass or remove."))
            Button(T("위치 초기화", "Reset Positions")) { defaults.set(Date().timeIntervalSince1970, "resetAt") }
            Divider()
            TFSettingsNote(text: T("위젯 갤러리·알림 센터용 WidgetKit 위젯은 서명된 앱 확장과 앱 그룹이 필요해 지원하지 않아요. 대신 이 바탕화면 위젯을 써요.",
                                   "WidgetKit widgets for the gallery and Notification Center need a signed app extension and an app group, so they aren't supported. Use these desktop widgets instead."))
        }
        .onAppear { photos = load() }
    }

    private func label(_ k: String) -> String {
        switch k {
        case "clock": return T("시계", "Clock")
        case "worldclock": return T("세계 시계", "World Clock")
        case "timers": return T("타이머·포모도로·스톱워치", "Timers, Pomodoro, Stopwatch")
        case "activity": return T("활동 링", "Activity Rings")
        default: return k
        }
    }

    private func toggle(_ k: String, _ on: Bool) {
        var list = defaults.strings("widgets", default: ["clock"])
        list.removeAll { $0 == k }
        if on { list.append(k) }
        prefs.setStrings(list, "widgets")
    }

    private func isFolder(_ path: String) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &d) && d.boolValue
    }

    private func load() -> [PhotoWidgetConfig] {
        guard let d = defaults.data("photos"), let l = try? JSONDecoder().decode([PhotoWidgetConfig].self, from: d) else { return [] }
        return l
    }

    private func save(_ list: [PhotoWidgetConfig]) {
        photos = list
        defaults.set(try? JSONEncoder().encode(list), "photos")
    }

    private func add(folder: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = folder
        panel.canChooseFiles = !folder
        if !folder { panel.allowedContentTypes = [.image] }
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url, photos.count < DesktopWidgetsModule.maxPhotos else { return }
        let cfg = PhotoWidgetConfig(path: url.path)
        save(photos + [cfg])
        toggle("photo:" + cfg.id, true)
    }

    private func remove(_ id: String) {
        save(photos.filter { $0.id != id })
        toggle("photo:" + id, false)
    }

    private func update(_ id: String, _ f: (inout PhotoWidgetConfig) -> Void) {
        var list = photos
        if let i = list.firstIndex(where: { $0.id == id }) { f(&list[i]) }
        save(list)
    }
}

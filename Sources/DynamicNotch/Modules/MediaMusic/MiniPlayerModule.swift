import AppKit
import SwiftUI

/// 플로팅 플레이어: 창 위에 떠 있는 작은 플레이어. 끌어 옮기면 위치를 기억한다.
/// 크기 3종(⌘1 작게, ⌘2 플레이어, ⌘3 큰 아트워크 — 창을 한 번 누른 뒤). 조작은 Music·Spotify AppleScript, 그 밖은 기존 어댑터 명령.
final class MiniPlayerModule: NotchModule {
    let id = "miniplayer"
    var title: String { T("플로팅 플레이어", "Floating Player") }
    let symbol = "pip"
    let enabledByDefault = false

    let controller = MBMiniPlayerController(module: "miniplayer")

    func start(context: ModuleContext) { controller.start() }
    func stop() { controller.stop() }

    func tabView() -> AnyView? { AnyView(MiniPlayerTab(controller: controller)) }
    var tabContentSize: CGSize { CGSize(width: 420, height: 124) }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "miniplayer.toggle",
                       title: controller.visible ? T("플로팅 플레이어 닫기", "Close Floating Player") : T("플로팅 플레이어 열기", "Open Floating Player"),
                       symbol: "pip", keywords: ["floating", "mini player", "플로팅", "미니"], run: { [weak self] in self?.controller.toggle() })]
    }

    func selfTest() -> [String] {
        let screens = NSScreen.screens.map { "\(Int($0.visibleFrame.width))x\(Int($0.visibleFrame.height))" }.joined(separator: ", ")
        return ["screens (visible frames): \(screens)",
                "saved position: \(controller.savedOrigin.map { "\(Int($0.x)),\(Int($0.y))" } ?? "none (bottom-right default)")",
                "size: \(controller.size.rawValue), visible setting: \(ModuleDefaults(module: id).bool("visible", default: false))",
                "default origin for player size: \(controller.defaultOrigin(for: MBMiniPlayerController.Size.player.frameSize).map { "\(Int($0.x)),\(Int($0.y))" } ?? "no screen")"]
    }
}

/// 떠 있는 패널 (앱을 앞으로 가져오지 않는다)
final class MBPanel: NSPanel {
    var allowKey = false
    var onKey: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { allowKey }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }

    static func make(size: CGSize) -> MBPanel {
        let p = MBPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        return p
    }
}

final class MBMiniPlayerController: NSObject, ObservableObject {
    enum Size: String, CaseIterable {
        case mini, player, artwork
        var frameSize: CGSize {
            switch self {
            case .mini: return CGSize(width: 300, height: 64)
            case .player: return CGSize(width: 320, height: 112)
            case .artwork: return CGSize(width: 240, height: 320)
            }
        }
        var label: String {
            switch self {
            case .mini: return T("작게", "Mini")
            case .player: return T("플레이어", "Player")
            case .artwork: return T("아트워크", "Artwork")
            }
        }
    }

    @Published private(set) var visible = false
    @Published private(set) var size: Size = .player

    private let module: String
    private let defaults: ModuleDefaults
    private var panel: MBPanel?
    private var moveObserver: NSObjectProtocol?
    private var running = false

    init(module: String) {
        self.module = module
        defaults = ModuleDefaults(module: module)
        super.init()
        size = Size(rawValue: defaults.string("size", default: Size.player.rawValue)) ?? .player
    }

    func start() {
        guard !running else { return }
        running = true
        if defaults.bool("visible", default: false), !MBAudio.isDevTool { show() }
    }

    func stop() {
        guard running else { return }
        running = false
        closePanel()
    }

    func toggle() { visible ? hide() : show() }

    func show() {
        guard running, panel == nil, !MBAudio.isDevTool else { return }
        let p = MBPanel.make(size: size.frameSize)
        p.allowKey = true
        p.isMovableByWindowBackground = true
        p.onKey = { [weak self] e in
            guard e.modifierFlags.contains(.command), let c = e.charactersIgnoringModifiers else { return false }
            switch c {
            case "1": self?.setSize(.mini)
            case "2": self?.setSize(.player)
            case "3": self?.setSize(.artwork)
            case "w": self?.hide()
            default: return false
            }
            return true
        }
        p.contentView = MBFirstMouseHostingView(rootView: MiniPlayerView(controller: self).environment(\.colorScheme, .dark))
        p.setFrameOrigin(validOrigin(savedOrigin, size: size.frameSize) ?? defaultOrigin(for: size.frameSize) ?? .zero)
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
            self?.saveOrigin()
        }
        p.orderFrontRegardless()
        panel = p
        MBPlayerFeed.shared.acquire("miniplayer")
        visible = true
        defaults.set(true, "visible")
    }

    func hide() {
        closePanel()
        defaults.set(false, "visible")
    }

    private func closePanel() {
        if let o = moveObserver { NotificationCenter.default.removeObserver(o) }
        moveObserver = nil
        if panel != nil { MBPlayerFeed.shared.release("miniplayer") }
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        visible = false
    }

    func setSize(_ s: Size) {
        size = s
        defaults.set(s.rawValue, "size")
        guard let p = panel else { return }
        // 위쪽 왼쪽 모서리를 고정하고 크기를 바꾼다
        let top = p.frame.maxY
        var frame = CGRect(x: p.frame.minX, y: top - s.frameSize.height, width: s.frameSize.width, height: s.frameSize.height)
        if let o = validOrigin(frame.origin, size: s.frameSize) { frame.origin = o } else if let o = defaultOrigin(for: s.frameSize) { frame.origin = o }
        p.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: "module.\(module).x")
        UserDefaults.standard.removeObject(forKey: "module.\(module).y")
        if let p = panel, let o = defaultOrigin(for: p.frame.size) { p.setFrameOrigin(o) }
    }

    // MARK: 위치 (창을 옮길 때마다 바뀌므로 알림 없이 바로 저장)

    var savedOrigin: CGPoint? {
        let d = UserDefaults.standard
        guard let x = d.object(forKey: "module.\(module).x") as? Double, let y = d.object(forKey: "module.\(module).y") as? Double else { return nil }
        return CGPoint(x: x, y: y)
    }

    private func saveOrigin() {
        guard let o = panel?.frame.origin else { return }
        UserDefaults.standard.set(Double(o.x), forKey: "module.\(module).x")
        UserDefaults.standard.set(Double(o.y), forKey: "module.\(module).y")
    }

    /// 화면 밖이면 nil
    private func validOrigin(_ o: CGPoint?, size: CGSize) -> CGPoint? {
        guard let o else { return nil }
        let rect = CGRect(origin: o, size: size)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(rect.insetBy(dx: size.width * 0.3, dy: size.height * 0.3)) } ? o : nil
    }

    /// 주 화면 오른쪽 아래
    func defaultOrigin(for size: CGSize) -> CGPoint? {
        guard let f = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return nil }
        return CGPoint(x: f.maxX - size.width - 24, y: f.minY + 24)
    }
}

// MARK: - 화면

private struct MiniPlayerView: View {
    @ObservedObject var controller: MBMiniPlayerController
    @ObservedObject private var feed = MBPlayerFeed.shared
    @State private var hover = false

    var body: some View {
        let t = feed.track
        ZStack(alignment: .topTrailing) {
            Group {
                switch controller.size {
                case .mini: miniLayout(t)
                case .player: playerLayout(t)
                case .artwork: artworkLayout(t)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.86)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08)))
            if hover {
                HStack(spacing: 4) {
                    smallButton("rectangle.compress.vertical", T("크기 바꾸기 (⌘1–⌘3)", "Change size (⌘1–⌘3)")) {
                        let all = MBMiniPlayerController.Size.allCases
                        controller.setSize(all[(all.firstIndex(of: controller.size)! + 1) % all.count])
                    }
                    smallButton("xmark", T("닫기", "Close")) { controller.hide() }
                }
                .padding(6)
                .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }

    private func smallButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.island(.caption2, .bold)).frame(width: 16, height: 16)
                .background(Circle().fill(Color.white.opacity(0.18)))
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    private func art(_ side: CGFloat) -> some View {
        Group {
            if let a = feed.artwork { Image(nsImage: a).resizable().aspectRatio(contentMode: .fill) }
            else { Image(systemName: "music.note").font(.system(size: side * 0.35)).foregroundStyle(.white.opacity(0.4)) }
        }
        .frame(width: side, height: side)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: side * 0.14, style: .continuous))
    }

    private func titles(_ t: MBTrack?, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(t?.title ?? T("재생 중인 곡 없음", "Nothing playing")).font(.system(size: size, weight: .semibold)).lineLimit(1)
            Text(t?.artist ?? "").font(.system(size: size - 2)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        }
    }

    private func controls(_ t: MBTrack?, size: CGFloat) -> some View {
        HStack(spacing: size * 0.7) {
            Button { MBPlayer.previous(t) } label: { Image(systemName: "backward.fill") }
                .help(T("이전", "Previous")).accessibilityLabel(T("이전", "Previous"))
            Button { MBPlayer.toggle(t) } label: { Image(systemName: t?.playing == true ? "pause.fill" : "play.fill").frame(width: size * 1.2) }
                .help(T("재생/일시정지", "Play/Pause")).accessibilityLabel(T("재생/일시정지", "Play/Pause"))
            Button { MBPlayer.next(t) } label: { Image(systemName: "forward.fill") }
                .help(T("다음", "Next")).accessibilityLabel(T("다음", "Next"))
        }
        .font(.system(size: size))
        .buttonStyle(.plain)
        .disabled(t == nil)
    }

    private func miniLayout(_ t: MBTrack?) -> some View {
        HStack(spacing: 10) {
            art(44)
            titles(t, size: 12)
            Spacer(minLength: 4)
            controls(t, size: 14)
        }
    }

    private func playerLayout(_ t: MBTrack?) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                art(52)
                titles(t, size: 13)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                progress(t)
                controls(t, size: 14)
            }
        }
    }

    private func artworkLayout(_ t: MBTrack?) -> some View {
        VStack(spacing: 8) {
            art(200)
            titles(t, size: 13).frame(maxWidth: .infinity, alignment: .leading)
            progress(t)
            controls(t, size: 17)
        }
    }

    private func progress(_ t: MBTrack?) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let pos = t?.position(at: ctx.date) ?? 0
            let dur = t?.duration ?? 0
            ScrubBar(fraction: dur > 0 ? pos / dur : 0, enabled: MBPlayer.canSeek(t), spacing: 6, thickness: 3,
                     onScrub: { f in if let t { MBPlayer.seek(t, to: f * t.duration) } }, onEnd: {},
                     leading: { Text(MBStorage.duration(pos)).font(.island(.caption2)).monospacedDigit().foregroundStyle(.white.opacity(0.5)) },
                     trailing: { Text(MBStorage.duration(dur)).font(.island(.caption2)).monospacedDigit().foregroundStyle(.white.opacity(0.5)) })
        }
    }
}

private struct MiniPlayerTab: View {
    @ObservedObject var controller: MBMiniPlayerController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(T("플로팅 플레이어", "Floating Player")).font(.island(.subhead, .semibold))
                    Text(T("모든 창 위에 뜨는 작은 플레이어. 끌어서 옮기면 위치를 기억합니다.", "A small player above all windows. Drag it anywhere; the position is remembered."))
                        .font(.island(.caption)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                MBPillButton(title: controller.visible ? T("닫기", "Close") : T("띄우기", "Show"), symbol: "pip",
                             active: controller.visible, tint: .green) { controller.toggle() }
            }
            HStack(spacing: 6) {
                Text(T("크기", "Size")).font(.island(.footnote)).foregroundStyle(.white.opacity(0.6))
                ForEach(Array(MBMiniPlayerController.Size.allCases.enumerated()), id: \.offset) { i, s in
                    MBPillButton(title: "\(s.label) ⌘\(i + 1)", active: controller.size == s) { controller.setSize(s) }
                }
                Spacer()
                MBPillButton(title: T("위치 초기화", "Reset position"), symbol: "arrow.down.right.square") { controller.resetPosition() }
            }
            Text(T("⌘1–⌘3과 ⌘W는 플레이어를 한 번 누른 뒤에 동작합니다.", "⌘1–⌘3 and ⌘W work after clicking the player once."))
                .font(.island(.caption)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
    }
}

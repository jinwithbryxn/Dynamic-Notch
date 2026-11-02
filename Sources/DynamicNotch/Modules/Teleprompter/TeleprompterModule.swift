import AppKit
import SwiftUI

/// 노치 아래 텔레프롬프터 (M-G-009). 카메라 바로 아래에 대본 띠를 띄워 자동으로 스크롤한다.
/// 띠는 사용자가 '보이기'를 누를 때만 나타나고, 끄면(stop) 바로 닫힌다.
/// 음성 따라가기(M-G-010)는 보류: Info.plist에 마이크·음성 인식 사용 목적 문구가 없다.
final class TeleprompterModule: NotchModule {
    let id = "teleprompter"
    var title: String { T("텔레프롬프터", "Teleprompter") }
    let symbol = "text.aligncenter"
    /// 화면 위 오버레이를 쓰므로 기본 꺼짐
    var enabledByDefault: Bool { false }

    let model: PrompterModel
    private var context: ModuleContext?
    private var panel: CPOverlayPanel?
    private var scrollMonitor: Any?
    private var keyMonitor: Any?
    private var hoverMonitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var endTimer: Timer?

    init() { model = PrompterModel(defaults: ModuleDefaults(module: "teleprompter")) }

    func start(context: ModuleContext) {
        self.context = context
        model.onLayoutChange = { [weak self] in self?.layoutPanel() }
        model.onPlayingChange = { [weak self] playing in self?.updateEndTimer(playing) }
    }

    func stop() {
        hide()
        model.saveNow()
        model.onLayoutChange = nil
        model.onPlayingChange = nil
        context = nil
    }

    func tabView() -> AnyView? { AnyView(PrompterTab(module: self, model: model)) }
    var tabContentSize: CGSize { CGSize(width: 600, height: 300) }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "teleprompter.toggle",
                       title: model.showing ? T("텔레프롬프터 숨기기", "Hide Teleprompter") : T("텔레프롬프터 시작", "Start Teleprompter"),
                       symbol: symbol, keywords: ["teleprompter", "프롬프터", "대본", "script"]) { [weak self] in
            guard let self else { return }
            if self.model.showing { self.hide() } else { self.show(play: true) }
        }]
    }

    func focusInput() { context?.focusInput() }

    // MARK: 띠 창

    func show(play: Bool) {
        model.saveNow()
        if panel == nil {
            let p = CPOverlayPanel(frame: .zero, level: CPLevel.belowNotch, clickThrough: false, hideFromCapture: model.hideFromCapture)
            p.allowsKey = true   // 띠를 누르면 화살표·스페이스로 조작
            p.acceptsMouseMovedEvents = true
            p.contentView = CPHostingView(rootView: PrompterOverlay(model: model, close: { [weak self] in self?.hide() }))
            panel = p
            installMonitors()
        }
        layoutPanel()
        panel?.orderFrontRegardless()
        model.showing = true
        context?.collapse()
        if play { model.play() }
    }

    func hide() {
        model.pause()
        model.showing = false
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        removeMonitors()
        updateEndTimer(false)
    }

    /// 노치 바로 아래 가운데 (노치 없는 화면은 메뉴 막대 아래)
    private func layoutPanel() {
        guard let panel else { return }
        panel.sharingType = model.hideFromCapture ? .none : .readOnly
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        guard let screen else { return }
        let notch = NotchGeometry.notchRect(on: screen)
        let w = CGFloat(model.width), h = CGFloat(model.height)
        let frame = CGRect(x: notch.midX - w / 2, y: notch.minY - 4 - h, width: w, height: h)
        panel.setFrame(frame, display: true)
    }

    private func installMonitors() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self, let panel = self.panel, e.window === panel else { return e }
            let dy = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 12
            self.model.nudge(-dy)
            return nil
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let panel = self.panel, e.window === panel else { return e }
            switch e.keyCode {
            case 126: self.model.nudge(-CGFloat(self.model.fontSize) * 1.4); return nil   // ↑
            case 125: self.model.nudge(CGFloat(self.model.fontSize) * 1.4); return nil    // ↓
            case 49: self.model.toggle(); return nil                                     // 스페이스
            case 53: self.hide(); return nil                                             // Esc
            default: return e
            }
        }
        // 앞에 있지 않은 패널은 SwiftUI 마우스 올림이 안 올 수 있어 마우스 위치로 판단한다
        let hover: () -> Void = { [weak self] in
            guard let self, let panel = self.panel else { return }
            let inside = panel.frame.contains(NSEvent.mouseLocation)
            if inside != self.model.hovering { self.model.setHover(inside) }
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { _ in hover() }) { hoverMonitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { e in hover(); return e }) { hoverMonitors.append(l) }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in self?.layoutPanel() }
    }

    private func removeMonitors() {
        if let m = scrollMonitor { NSEvent.removeMonitor(m) }
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        if let o = screenObserver { NotificationCenter.default.removeObserver(o) }
        hoverMonitors.forEach { NSEvent.removeMonitor($0) }
        hoverMonitors.removeAll()
        scrollMonitor = nil
        keyMonitor = nil
        screenObserver = nil
    }

    /// 재생 중에만 0.5초마다 끝에 닿았는지 본다
    private func updateEndTimer(_ playing: Bool) {
        endTimer?.invalidate()
        endTimer = nil
        guard playing else { return }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.model.checkEnd() }
        RunLoop.main.add(t, forMode: .common)
        endTimer = t
    }

    func selfTest() -> [String] {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        var lines = ["notched screen: \(NSScreen.screens.contains { $0.safeAreaInsets.top > 0 })"]
        if let screen {
            let n = NotchGeometry.notchRect(on: screen)
            lines.append("strip frame would be x=\(Int(n.midX - model.width / 2)) y=\(Int(n.minY - 4 - model.height)) \(Int(model.width))x\(Int(model.height))")
        }
        lines.append("script chars \(model.script.count), speed \(Int(model.speed)) pt/s, font \(Int(model.fontSize))")
        lines.append("markdown parse ok: \(PrompterModel.attributed("**bold** and *italic*").characters.count == 15)")
        // 띠 화면 그리기 확인 (화면에 띄우지 않음, 저장 안 하는 임시 모델)
        let m = PrompterModel(defaults: ModuleDefaults(module: "teleprompter-selftest"))
        m.setHover(true)
        CPTestImages.renderView(PrompterOverlay(model: m, close: {}), size: CGSize(width: 560, height: 130), name: "teleprompter-strip.png")
            .map { lines.append("wrote \($0)") }
        lines.append("speech usage description in Info.plist: \(Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil), microphone: \(Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil)")
        return lines
    }
}

/// 대본과 재생 상태. 스크롤 위치 = 멈춘 위치 + 속도 × 재생 시간.
final class PrompterModel: ObservableObject {
    private let defaults: ModuleDefaults
    @Published var script: String { didSet { scheduleSave() } }
    @Published var speed: Double { didSet { rebase(oldSpeed: oldValue); defaults.set(speed, "speed") } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, "fontSize") } }
    @Published var width: Double { didSet { defaults.set(width, "width"); onLayoutChange?() } }
    @Published var height: Double { didSet { defaults.set(height, "height"); onLayoutChange?() } }
    @Published var mirror: Bool { didSet { defaults.set(mirror, "mirror") } }
    @Published var hideFromCapture: Bool { didSet { defaults.set(hideFromCapture, "hideFromCapture"); onLayoutChange?() } }
    @Published var pauseOnHover: Bool { didSet { defaults.set(pauseOnHover, "pauseOnHover") } }
    @Published private(set) var playing = false { didSet { if playing != oldValue { onPlayingChange?(playing) } } }
    @Published var showing = false
    @Published private(set) var hovering = false

    var onLayoutChange: (() -> Void)?
    var onPlayingChange: ((Bool) -> Void)?
    private var baseOffset: CGFloat = 0
    private var playStart: Date?
    private var hoverPaused = false
    var contentHeight: CGFloat = 0
    private var saveWork: DispatchWorkItem?

    static let sample = T("여기에 대본을 붙여 넣는다.\n\n**굵게**와 *기울임*을 쓸 수 있다.\n마우스를 올리면 멈추고, 휠로 넘긴다.",
                          "Paste your script here.\n\nYou can use **bold** and *italic*.\nHover to pause, scroll to move.")

    init(defaults: ModuleDefaults) {
        self.defaults = defaults
        script = defaults.string("script", default: Self.sample)
        speed = defaults.double("speed", default: 40)
        fontSize = defaults.double("fontSize", default: 24)
        width = defaults.double("width", default: 560)
        height = defaults.double("height", default: 130)
        mirror = defaults.bool("mirror", default: false)
        hideFromCapture = defaults.bool("hideFromCapture", default: true)
        pauseOnHover = defaults.bool("pauseOnHover", default: true)
    }

    static func attributed(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    var attributedScript: AttributedString { Self.attributed(script) }

    func offset(at date: Date) -> CGFloat {
        guard let s = playStart else { return baseOffset }
        return baseOffset + CGFloat(speed) * CGFloat(date.timeIntervalSince(s))
    }

    func play() {
        guard !playing else { return }
        playStart = Date()
        playing = true
    }

    func pause() {
        guard playing else { return }
        baseOffset = offset(at: Date())
        playStart = nil
        playing = false
    }

    func toggle() { playing ? pause() : play() }

    func rewind() {
        baseOffset = 0
        if playing { playStart = Date() }
        objectWillChange.send()
    }

    func nudge(_ dy: CGFloat) {
        let current = offset(at: Date())
        baseOffset = max(0, current + dy)
        if playing { playStart = Date() }
        objectWillChange.send()
    }

    /// 속도를 바꿀 때 위치가 튀지 않게 지금 위치를 기준으로 다시 잡는다
    private func rebase(oldSpeed: Double) {
        guard let s = playStart else { return }
        baseOffset += CGFloat(oldSpeed) * CGFloat(Date().timeIntervalSince(s))
        playStart = Date()
    }

    func setHover(_ on: Bool) {
        hovering = on
        if on, pauseOnHover, playing { pause(); hoverPaused = true }
        if !on, hoverPaused { hoverPaused = false; play() }
    }

    func checkEnd() {
        if contentHeight > 0, offset(at: Date()) > contentHeight + 20 { pause() }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        if defaults.string("script", default: "") != script { defaults.set(script, "script") }
    }
}

private struct PrompterHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// 노치 아래 띠
private struct PrompterOverlay: View {
    @ObservedObject var model: PrompterModel
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.9))
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !model.playing)) { tl in
                GeometryReader { geo in
                    Text(model.attributedScript)
                        .font(.system(size: CGFloat(model.fontSize), weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(CGFloat(model.fontSize) * 0.25)
                        .frame(width: max(40, geo.size.width - 32))
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { g in Color.clear.preference(key: PrompterHeightKey.self, value: g.size.height) })
                        .offset(x: 16, y: geo.size.height * 0.3 - model.offset(at: tl.date))
                }
                .clipped()
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                             .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .scaleEffect(x: model.mirror ? -1 : 1, y: 1)
            }
            .onPreferenceChange(PrompterHeightKey.self) { model.contentHeight = $0 }
            if model.hovering {
                HStack(spacing: 4) {
                    button(model.playing ? "pause.fill" : "play.fill", model.playing ? T("일시정지", "Pause") : T("재생", "Play")) { model.toggle() }
                    button("tortoise.fill", T("느리게", "Slower")) { model.speed = max(10, model.speed - 10) }
                    button("hare.fill", T("빠르게", "Faster")) { model.speed = min(200, model.speed + 10) }
                    button("backward.end.fill", T("처음으로", "Rewind")) { model.rewind() }
                    button("xmark", T("닫기", "Close")) { close() }
                }
                .padding(6)
                .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func button(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Color.white.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct PrompterTab: View {
    let module: TeleprompterModule
    @ObservedObject var model: PrompterModel
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if model.showing {
                    CPPill(symbol: model.playing ? "pause.fill" : "play.fill", title: model.playing ? T("일시정지", "Pause") : T("재생", "Play")) { model.toggle() }
                    CPPill(symbol: "backward.end.fill", title: T("처음으로", "Rewind")) { model.rewind() }
                    CPPill(symbol: "eye.slash", title: T("숨기기", "Hide")) { module.hide() }
                } else {
                    CPPill(symbol: "play.fill", title: T("노치 아래에 띄우고 시작", "Show Below Notch & Start"), tint: .green) { module.show(play: true) }
                }
                Spacer()
                Text(T("속도", "Speed")).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                Slider(value: $model.speed, in: 10...200).frame(width: 90).controlSize(.mini)
                    .help(T("초당 \(Int(model.speed))pt", "\(Int(model.speed)) pt per second"))
                Text(T("글자", "Font")).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                Stepper("\(Int(model.fontSize))", value: $model.fontSize, in: 14...56, step: 2)
                    .font(.system(size: 10.5).monospacedDigit()).controlSize(.mini).fixedSize()
            }
            HStack(spacing: 10) {
                Toggle(T("좌우 반전", "Mirror"), isOn: $model.mirror)
                Toggle(T("올리면 멈춤", "Pause on hover"), isOn: $model.pauseOnHover)
                Toggle(T("캡처에서 숨기기 시도", "Try to hide from capture"), isOn: $model.hideFromCapture)
                    .help(T("일부 화면 공유·녹화에서 빠지도록 창 공유 설정을 끈다. macOS 15부터 일부 캡처 방식은 이 설정을 무시하고, 휴대폰 촬영은 막을 수 없다.",
                            "Turns off window sharing so some screen shares and recordings skip the strip. Some capture paths on macOS 15+ ignore it, and phone cameras cannot be stopped."))
                Spacer()
                Text(T("폭", "W")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                Slider(value: $model.width, in: 300...900).frame(width: 60).controlSize(.mini)
                Text(T("높이", "H")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                Slider(value: $model.height, in: 80...320).frame(width: 60).controlSize(.mini)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 10.5))
            TextEditor(text: $model.script)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .focused($editorFocused)
                .accessibilityLabel(T("대본", "Script"))
            CPUnsupported(title: T("음성 따라가기 보류", "Follow-my-voice deferred"),
                          reason: T("이 앱의 Info.plist에 마이크·음성 인식 사용 목적 문구가 없어 권한을 요청하면 macOS가 앱을 끝낸다.",
                                    "This app's Info.plist has no microphone or speech recognition usage text, so asking for access would make macOS quit the app."),
                          alternative: T("자동 스크롤과 '올리면 멈춤', 휠·↑↓·스페이스로 조절.", "Auto-scroll with pause on hover; adjust with the wheel, ↑↓ and Space."))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { module.focusInput(); editorFocused = true }
        .onDisappear { model.saveNow() }
    }
}

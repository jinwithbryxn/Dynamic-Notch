import AppKit
import SwiftUI

/// 화면 캡처 도구 (M-G-001 영역 스크린샷, M-G-002 캡처 글자 인식, M-G-006 녹화 시작, M-K-014 화면 영역 도구).
/// 모든 캡처는 사용자가 누른 동작에서만 macOS 영역 선택기(`screencapture -i`)를 띄운다. 백그라운드 작업 없음.
/// 스크롤 캡처(M-G-003)는 보류: 이유를 탭에 보여 준다.
final class CaptureToolsModule: NotchModule {
    let id = "capture"
    var title: String { T("화면 캡처", "Screen Capture") }
    let symbol = "camera.viewfinder"
    /// 화면 기록 권한을 쓰는 기능이라 기본 꺼짐
    var enabledByDefault: Bool { false }

    enum Mode: String { case clipboard, file, markup, ocr, qr }

    final class State: ObservableObject {
        @Published var busy = false
        @Published var status: String?
        /// 마지막 글자 인식·QR 결과 (탭에서 다시 보기)
        @Published var resultText: String?
        @Published var resultURL: URL?
        @Published var color: NSColor?
        @Published var screenGranted = CPPermission.screenRecording.granted
    }

    let state = State()
    private var context: ModuleContext?
    private var process: Process?
    /// 색 고르기 돋보기 (고를 때까지 잡아 둔다)
    private var sampler: NSColorSampler?
    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }

    static let screencapture = "/usr/sbin/screencapture"
    static let screenshotApp = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")

    /// 파일로 저장할 폴더 (설정 없으면 macOS 스크린샷 저장 위치)
    var saveFolder: URL {
        let path = defaults.string("saveFolder", default: "")
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path, isDirectory: true) }
        return RecordingMonitor.saveFolder()
    }

    func start(context: ModuleContext) { self.context = context }

    func stop() {
        // 진행 중인 영역 선택이 있으면 취소한다
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        state.busy = false
        context = nil
    }

    func tabView() -> AnyView? { AnyView(CaptureTab(module: self, state: state)) }
    var tabContentSize: CGSize { CGSize(width: 540, height: 250) }

    func paletteActions() -> [PaletteAction] {
        [
            PaletteAction(id: "capture.region", title: T("영역 스크린샷", "Capture Region"), subtitle: T("클립보드로", "To clipboard"),
                          symbol: "crop", keywords: ["screenshot", "스크린샷", "캡처", "capture"]) { [weak self] in self?.capture(.clipboard) },
            PaletteAction(id: "capture.ocr", title: T("화면 글자 인식", "Capture Text (OCR)"), subtitle: T("영역의 글자를 클립보드로", "Copy text from a region"),
                          symbol: "text.viewfinder", keywords: ["ocr", "글자", "텍스트", "text"]) { [weak self] in self?.capture(.ocr) },
            PaletteAction(id: "capture.qr", title: T("화면 QR 코드 읽기", "Read QR Code on Screen"),
                          symbol: "qrcode.viewfinder", keywords: ["qr", "barcode", "바코드"]) { [weak self] in self?.capture(.qr) },
            PaletteAction(id: "capture.color", title: T("화면 색 고르기", "Pick Color on Screen"),
                          symbol: "eyedropper", keywords: ["color", "색", "컬러", "hex"]) { [weak self] in self?.pickColor() },
            PaletteAction(id: "capture.record", title: T("화면 녹화 도구 열기", "Open Screen Recorder"),
                          symbol: "record.circle", keywords: ["record", "녹화", "recording"]) { [weak self] in self?.openRecorder() },
        ]
    }

    func settingsView() -> AnyView? { AnyView(CaptureSettings(module: self)) }

    // MARK: 동작

    /// 영역 선택기를 띄운다. 권한이 없으면 요청만 하고 멈춘다.
    func capture(_ mode: Mode) {
        guard !state.busy else { return }
        state.screenGranted = CPPermission.screenRecording.granted
        guard state.screenGranted else {
            CPPermission.screenRecording.request()
            let msg = T("화면 기록 권한이 필요함. 시스템 설정에서 허용한 뒤 앱을 다시 시작해 줘.",
                        "Screen Recording permission is needed. Allow it in System Settings, then relaunch the app.")
            state.status = msg
            context?.notice(T("화면 기록 권한 필요", "Screen Recording needed"), msg, symbol: "lock.fill", tint: .orange, tab: id)
            return
        }
        state.busy = true
        state.status = T("영역을 고르는 중… (Esc로 취소)", "Select a region… (Esc to cancel)")
        context?.collapse()
        // 노치가 닫힌 뒤 선택기를 띄워 캡처에 노치가 들어가지 않게 한다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.launch(mode) }
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dmn-capture-\(UUID().uuidString).png")
    }

    private func fileName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return T("스크린샷", "Screenshot") + " " + f.string(from: Date())
    }

    private func launch(_ mode: Mode) {
        let pbCount = NSPasteboard.general.changeCount
        var args = ["-i"]
        var target: URL?
        switch mode {
        case .clipboard:
            args.append("-c")
        case .file:
            let url = CPImageIO.uniqueURL(in: saveFolder, base: fileName(), ext: "png")
            target = url
            args.append(url.path)
        case .markup, .ocr, .qr:
            if mode != .markup { args.append("-x") }   // 글자 인식·QR은 셔터 소리 없이
            let url = tempURL()
            target = url
            args.append(url.path)
        }
        process = CPProcess.run(Self.screencapture, args) { [weak self] _ in
            guard let self else { return }
            self.process = nil
            self.state.busy = false
            ModuleServices.captureFinished()
            self.finish(mode, target: target, pasteboardChanged: NSPasteboard.general.changeCount != pbCount)
        }
        if process == nil {
            state.busy = false
            state.status = T("screencapture를 실행하지 못함", "Could not run screencapture")
        }
    }

    private func finish(_ mode: Mode, target: URL?, pasteboardChanged: Bool) {
        let fm = FileManager.default
        switch mode {
        case .clipboard:
            state.status = pasteboardChanged ? T("클립보드에 복사함", "Copied to clipboard") : T("취소함", "Cancelled")
            if pasteboardChanged { CPSounds.play(.captureDone) }
        case .file:
            guard let url = target, fm.fileExists(atPath: url.path) else { state.status = T("취소함", "Cancelled"); return }
            state.status = T("저장함: ", "Saved: ") + url.lastPathComponent
            CPSounds.play(.captureDone)
            // macOS 스크린샷 폴더면 본 앱의 스크린샷 미리보기가 이미 알리므로 겹치지 않게 한다
            if url.deletingLastPathComponent().standardizedFileURL == RecordingMonitor.saveFolder().standardizedFileURL,
               AppSettings.shared.screenshotEnabled, AppSettings.shared.screenshotSource != .clipboard { return }
            context?.notice(T("스크린샷 저장", "Screenshot saved"), url.lastPathComponent, symbol: "photo", tab: id,
                            actions: [ActivityAction(id: "reveal", title: T("Finder에서 보기", "Show in Finder")) {
                                NSWorkspace.shared.activateFileViewerSelecting([url]) }])
        case .markup:
            guard let url = target, let image = CPImageIO.load(url) else { state.status = T("취소함", "Cancelled"); return }
            try? fm.removeItem(at: url)   // 이 앱이 만든 임시 파일
            state.status = T("편집기를 열었음", "Opened the editor")
            MarkupEditor.open(image: image, sourceURL: nil)
        case .ocr, .qr:
            guard let url = target, let image = CPImageIO.load(url) else { state.status = T("취소함", "Cancelled"); return }
            try? fm.removeItem(at: url)
            state.status = T("인식하는 중…", "Recognizing…")
            if mode == .ocr { recognize(image) } else { readCodes(image) }
        }
    }

    private func recognize(_ image: CGImage) {
        CPVision.async({ try CPVision.recognizeText(image) }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let lines) where !lines.isEmpty:
                let text = lines.joined(separator: "\n")
                CPImageIO.copyText(text)
                self.state.resultText = text
                self.state.resultURL = nil
                self.state.status = T("글자 \(lines.count)줄을 클립보드에 복사함", "Copied \(lines.count) lines to the clipboard")
                CPSounds.play(.captureDone)
                self.context?.notice(T("글자 복사함", "Text copied"), String(lines[0].prefix(60)), symbol: "text.viewfinder", tab: self.id)
            case .success:
                self.state.status = T("글자를 찾지 못함", "No text found")
            case .failure(let e):
                self.state.status = T("글자 인식 실패: ", "OCR failed: ") + e.localizedDescription
            }
        }
    }

    private func readCodes(_ image: CGImage) {
        CPVision.async({ try CPVision.detectBarcodes(image) }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let codes) where !codes.isEmpty:
                let text = codes.joined(separator: "\n")
                CPImageIO.copyText(text)
                self.state.resultText = text
                let url = codes.compactMap { URL(string: $0) }.first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
                self.state.resultURL = url
                self.state.status = T("코드 \(codes.count)개를 클립보드에 복사함", "Copied \(codes.count) code(s) to the clipboard")
                CPSounds.play(.captureDone)
                var actions: [ActivityAction] = []
                if let url { actions.append(ActivityAction(id: "open", title: T("링크 열기", "Open Link"), role: .primary) { NSWorkspace.shared.open(url) }) }
                self.context?.notice(T("QR 코드 복사함", "QR code copied"), String(codes[0].prefix(60)), symbol: "qrcode", tab: self.id, actions: actions)
            case .success:
                self.state.status = T("QR·바코드를 찾지 못함", "No QR or barcode found")
            case .failure(let e):
                self.state.status = T("코드 읽기 실패: ", "Code reading failed: ") + e.localizedDescription
            }
        }
    }

    /// macOS 색 고르기 돋보기 (화면 기록 권한 불필요)
    func pickColor() {
        context?.collapse()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            let sampler = NSColorSampler()
            self?.sampler = sampler
            sampler.show { color in
                self?.sampler = nil
                guard let self, let c = color?.usingColorSpace(.sRGB) else { return }
                let hex = Self.hex(c)
                CPImageIO.copyText(hex)
                self.state.color = c
                self.state.status = T("색 \(hex)을 클립보드에 복사함", "Copied \(hex) to the clipboard")
                self.context?.notice(T("색 복사함", "Color copied"), hex, symbol: "eyedropper", tint: Color(nsColor: c), tab: self.id)
            }
        }
    }

    static func hex(_ c: NSColor) -> String {
        let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded()), b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// macOS 스크린샷 도구(⇧⌘5와 같은 막대)를 연다. 녹화는 macOS가 하고, 이 앱의 화면 기록 권한이 필요 없다.
    func openRecorder() {
        context?.collapse()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            let url = FileManager.default.fileExists(atPath: Self.screenshotApp.path) ? Self.screenshotApp
                : NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.screenshot.launcher")
            guard let url else {
                self?.state.status = T("스크린샷 앱을 찾지 못함. ⇧⌘5를 눌러 줘.", "Screenshot app not found. Press ⇧⌘5.")
                return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                DispatchQueue.main.async {
                    self?.state.status = error == nil
                        ? T("아래 막대에서 '선택 부분 기록'이나 '전체 화면 기록'을 고르고 '기록'을 누르면 된다.",
                            "In the bar, pick Record Selected Portion or Record Entire Screen, then click Record.")
                        : T("스크린샷 도구를 열지 못함. ⇧⌘5를 눌러 줘.", "Could not open the Screenshot tool. Press ⇧⌘5.")
                }
            }
        }
    }

    func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { defaults.set(url.path, "saveFolder") }
    }

    func resetSaveFolder() { defaults.set(nil, "saveFolder") }

    // MARK: 자체 검사 (화면을 찍지 않는다)

    func selfTest() -> [String] {
        var lines: [String] = []
        lines.append("screen recording permission (preflight, no prompt): \(CPPermission.screenRecording.granted)")
        lines.append("screencapture executable: \(FileManager.default.isExecutableFile(atPath: Self.screencapture))")
        lines.append("Screenshot.app present: \(FileManager.default.fileExists(atPath: Self.screenshotApp.path))")
        lines.append("save folder: \(saveFolder.path)")
        if let img = CPTestImages.text(["Hello Notch 2026", "안녕하세요 노치"]) {
            CPTestImages.write(img, "ocr-input.png").map { lines.append("wrote \($0)") }
            do {
                let found = try CPVision.recognizeText(img)
                lines.append("OCR on generated image: \(found.joined(separator: " | "))")
            } catch { lines.append("OCR error: \(error.localizedDescription)") }
        }
        if let qr = CPTestImages.qr("https://example.com/dmn-selftest") {
            CPTestImages.write(qr, "qr-input.png").map { lines.append("wrote \($0)") }
            do {
                lines.append("QR on generated image: \(try CPVision.detectBarcodes(qr).joined(separator: ", "))")
            } catch { lines.append("QR error: \(error.localizedDescription)") }
        }
        lines.append("hex(#3366CC): \(Self.hex(NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)))")
        lines.append("color sampler available: \(NSClassFromString("NSColorSampler") != nil)")
        return lines
    }
}

// MARK: - 탭

private struct CaptureTab: View {
    let module: CaptureToolsModule
    @ObservedObject var state: CaptureToolsModule.State

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                CPTile(symbol: "doc.on.clipboard", title: T("영역 → 클립보드", "Region → Clipboard"), disabled: state.busy) { module.capture(.clipboard) }
                CPTile(symbol: "square.and.arrow.down", title: T("영역 → 파일", "Region → File"),
                       help: T("저장 위치: ", "Saves to: ") + module.saveFolder.path, disabled: state.busy) { module.capture(.file) }
                CPTile(symbol: "pencil.tip.crop.circle", title: T("캡처 후 편집", "Capture & Mark Up"), disabled: state.busy) { module.capture(.markup) }
                CPTile(symbol: "record.circle", title: T("녹화 도구", "Recorder"), tint: .red,
                       help: T("macOS 스크린샷 막대(⇧⌘5)를 연다. 정지는 노치의 빨간 점.", "Opens the macOS Screenshot bar (⇧⌘5). Stop from the red dot in the notch.")) { module.openRecorder() }
            }
            HStack(spacing: 6) {
                CPTile(symbol: "text.viewfinder", title: T("글자 인식", "Copy Text"),
                       help: T("영역의 글자를 기기 안에서 인식해 클립보드로", "Recognize text in a region on this Mac and copy it"), disabled: state.busy) { module.capture(.ocr) }
                CPTile(symbol: "qrcode.viewfinder", title: T("QR 읽기", "Read QR"), disabled: state.busy) { module.capture(.qr) }
                CPTile(symbol: "eyedropper", title: T("색 고르기", "Pick Color"),
                       help: T("화면의 한 점 색을 HEX로 복사 (권한 불필요)", "Copy the HEX color of a point (no permission needed)")) { module.pickColor() }
                CPTile(symbol: "scroll", title: T("스크롤 캡처", "Scrolling"), disabled: true) {}
                    .help(T("보류: 아래 설명 참고", "Deferred: see below"))
            }
            CPPermissionLine(permission: .screenRecording, granted: state.screenGranted)
            if let status = state.status {
                HStack(spacing: 6) {
                    if let c = state.color {
                        Circle().fill(Color(nsColor: c)).frame(width: 10, height: 10)
                    }
                    Text(status).font(.island(.footnote)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                    Spacer(minLength: 0)
                    if let url = state.resultURL {
                        CPPill(symbol: "safari", title: T("링크 열기", "Open Link")) { NSWorkspace.shared.open(url) }
                    }
                }
            }
            if let text = state.resultText {
                ScrollView {
                    Text(text).font(.island(.caption, .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 36)
            } else {
                CPUnsupported(title: T("스크롤 캡처 보류", "Scrolling capture deferred"),
                              reason: T("스크롤 이벤트를 보내며 반복 캡처해 이어 붙이는 방식은 고정 머리글·관성 스크롤·늦게 뜨는 내용 때문에 이음새가 자주 틀어져 아직 믿을 만하지 않음.",
                                        "Stitching repeated captures while sending scroll events breaks on sticky headers, inertial scrolling and lazy content, so it is not reliable yet."),
                              alternative: T("브라우저는 개발자 도구의 '전체 크기 스크린샷'을 쓴다.", "In browsers, use the developer tools' full-size screenshot."))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { state.screenGranted = CPPermission.screenRecording.granted }
    }
}

private struct CaptureSettings: View {
    let module: CaptureToolsModule
    @State private var folder = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(T("파일 저장 위치", "Save location"))
                Spacer()
                Text(folder).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            HStack {
                Button(T("폴더 고르기…", "Choose Folder…")) { module.chooseSaveFolder(); folder = module.saveFolder.path }
                Button(T("macOS 기본 위치로", "Use macOS Location")) { module.resetSaveFolder(); folder = module.saveFolder.path }
            }
            Text(T("영역 캡처·글자 인식·QR 읽기는 macOS 영역 선택기를 쓰며 이 앱의 '화면 및 시스템 오디오 녹음' 권한이 필요하다. 글자 인식은 기기 안(Vision)에서만 처리한다. 색 고르기와 녹화 도구 열기는 권한이 필요 없다.",
                   "Region capture, OCR and QR use the macOS selector and need this app's Screen Recording permission. OCR runs on this Mac (Vision). Color picking and opening the recorder need no permission."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { folder = module.saveFolder.path }
    }
}

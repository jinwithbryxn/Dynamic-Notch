import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 파일 도구: 탭에 파일을 놓거나 골라 이미지 변환·압축·크기 줄이기, PDF 합치기, 동영상 GIF, ZIP 압축·해제, QR 읽기.
/// 모두 사용자가 누를 때만 실행하고, 결과는 새 파일(원본 옆 또는 다운로드 폴더)로 만든다. 배경 작업은 없다.
/// 외부 도구(ditto, screencapture)와 화면 기록 권한(QR 화면 영역)을 쓰므로 기본은 꺼짐.
final class FileToolsModule: NotchModule {
    let id = "filetools"
    var title: String { T("파일 도구", "File Tools") }
    let symbol = "wrench.and.screwdriver"
    let enabledByDefault = false

    let store = FTStore(module: "filetools")

    func start(context: ModuleContext) { store.context = context }
    func stop() { store.cancelAll() }

    func tabView() -> AnyView? {
        // 화면 그리기 검사(--render-tab)에서만: 미리 넣을 파일 (작업은 실행하지 않음)
        let env = ProcessInfo.processInfo.environment
        if AppSettings.isHelper, let list = env["DMN_FILETOOLS_PRELOAD"], store.items.isEmpty {
            store.add(list.split(separator: ":").map { URL(fileURLWithPath: String($0)) })
            // 미리 넣은 검사 파일에만 동작 하나를 돌려 결과 화면을 확인한다 (결과는 그 파일 옆에 새 파일로)
            switch env["DMN_FILETOOLS_RUN"] ?? "" {
            case "qr": store.qrFromFiles()
            case "zip": store.zip()
            case "merge": store.merge()
            case "convert": store.convert(.jpeg)
            default: break
            }
        }
        return AnyView(FTTab(store: store))
    }
    var tabContentSize: CGSize { CGSize(width: 600, height: 262) }

    func paletteActions() -> [PaletteAction] {
        let open = { [weak self] in
            guard let self else { return }
            self.store.context?.openTab(self.id)
        }
        return [
            PaletteAction(id: "filetools.open", title: T("파일 도구 열기", "Open File Tools"),
                          subtitle: T("이미지 변환·압축, PDF 합치기, GIF, ZIP", "Convert, compress, merge PDFs, GIF, ZIP"),
                          symbol: symbol, keywords: ["file tools", "파일", "zip", "압축", "unzip", "gif", "pdf", "merge", "합치기"], run: open),
            PaletteAction(id: "filetools.convert", title: T("이미지 변환", "Convert image"),
                          subtitle: T("파일 도구 탭에 이미지를 놓고 형식을 고르기", "Drop images on the File Tools tab and pick a format"),
                          symbol: "photo.on.rectangle.angled",
                          keywords: ["convert", "변환", "heic", "jpeg", "jpg", "png", "tiff", "compress", "resize", "이미지"], run: open),
            PaletteAction(id: "filetools.qr.screen", title: T("화면에서 QR 읽기", "Scan QR code on screen"),
                          subtitle: T("영역을 드래그해 QR·바코드를 읽고 복사", "Drag over a code to read and copy it"),
                          symbol: "qrcode.viewfinder", keywords: ["qr", "barcode", "바코드", "스캔", "scan"],
                          run: { [weak self] in self?.store.qrFromScreen() }),
            PaletteAction(id: "filetools.qr.clipboard", title: T("클립보드 이미지에서 QR 읽기", "Scan QR code from clipboard"),
                          symbol: "doc.on.clipboard", keywords: ["qr", "clipboard", "클립보드", "바코드"],
                          run: { [weak self] in self?.store.qrFromClipboard() }),
        ]
    }

    func settingsView() -> AnyView? { AnyView(FTSettings(defaults: ModuleDefaults(module: id))) }

    func selfTest() -> [String] { FTSelfTest.run(processes: store.processes) }
}

// MARK: - 상태

final class FTStore: ObservableObject {
    struct Item: Identifiable, Equatable {
        let url: URL
        let size: Int64
        let isFolder: Bool
        var id: String { url.path }
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var outputs: [URL] = []
    @Published private(set) var codes: [FTCode] = []
    @Published private(set) var busy: String?
    @Published private(set) var message: String?
    @Published private(set) var messageIsError = false
    @Published var targeted = false

    let processes = FAProcessGroup()
    var context: ModuleContext?
    private let moduleID: String
    private let queue = DispatchQueue(label: "dmn.filetools", qos: .userInitiated)
    private var gifTask: Task<Void, Never>?
    private var generation = 0   // 끄면 진행 중 작업의 결과를 버린다

    init(module: String) { moduleID = module }

    private var defaults: ModuleDefaults { ModuleDefaults(module: moduleID) }
    var outputMode: FTOutputMode { FTOutputMode(rawValue: defaults.string("output", default: FTOutputMode.besideSource.rawValue)) ?? .besideSource }
    var quality: Double { min(1, max(0.5, defaults.double("quality", default: 0.9))) }

    // MARK: 목록

    func add(_ urls: [URL]) {
        for u in urls {
            let url = u.standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path), !items.contains(where: { $0.url == url }) else { continue }
            let dir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            items.append(Item(url: url, size: dir ? 0 : FAKit.fileSize(url), isFolder: dir))
        }
    }

    func remove(_ item: Item) { items.removeAll { $0 == item } }
    func clear() { items.removeAll() }
    func clearResults() { outputs.removeAll(); codes.removeAll(); message = nil }

    func move(_ item: Item, by delta: Int) {
        guard let i = items.firstIndex(of: item) else { return }
        let j = i + delta
        guard items.indices.contains(j) else { return }
        items.swapAt(i, j)
    }

    var images: [URL] { items.filter { !$0.isFolder && FTEngine.isImage($0.url) }.map(\.url) }
    var mergeable: [URL] { items.filter { !$0.isFolder && (FTEngine.isPDF($0.url) || FTEngine.isImage($0.url)) }.map(\.url) }
    var videos: [URL] { items.filter { !$0.isFolder && FTEngine.isVideo($0.url) }.map(\.url) }
    var zips: [URL] { items.filter { !$0.isFolder && FTEngine.isZip($0.url) }.map(\.url) }
    var largestImageBytes: Int64 { items.filter { !$0.isFolder && FTEngine.isImage($0.url) }.map(\.size).max() ?? 0 }
    var largestImagePixels: Int {
        images.compactMap { FTEngine.pixelSize($0) }.map { Int(max($0.width, $0.height)) }.max() ?? 0
    }

    // MARK: 동작

    func convert(_ format: FTImageFormat) {
        let mode = outputMode, q = quality
        runEach(T("\(format.label)로 변환", "Converting to \(format.label)"), images) { try FTEngine.convertImage($0, to: format, quality: q, mode: mode) }
    }

    func compress(_ target: Int) {
        let mode = outputMode
        let inputs = items.filter { !$0.isFolder && FTEngine.isImage($0.url) && $0.size > Int64(target) }.map(\.url)
        runEach(T("\(FAKit.bytes(Int64(target))) 이하로 압축", "Compressing to \(FAKit.bytes(Int64(target)))"), inputs) {
            try FTEngine.compressImage($0, targetBytes: target, mode: mode).url
        }
    }

    func resize(_ longSide: Int) {
        let mode = outputMode, q = quality
        let inputs = images.filter { (FTEngine.pixelSize($0).map { Int(max($0.width, $0.height)) } ?? 0) > longSide }
        runEach(T("긴 변 \(longSide)px로 줄이기", "Resizing to \(longSide) px"), inputs) {
            try FTEngine.resizeImage($0, longSide: longSide, quality: q, mode: mode)
        }
    }

    func merge() {
        let mode = outputMode, inputs = mergeable
        runBatch(T("PDF 합치기", "Merging PDFs"), inputs) { [inputs] in
            let r = try FTEngine.mergePDFs(inputs, mode: mode)
            return ([r.url], T("\(r.pages)쪽", "\(r.pages) pages"))
        }
    }

    func zip() {
        let mode = outputMode, inputs = items.map(\.url), group = processes
        runBatch(T("ZIP 압축", "Zipping"), inputs) { [inputs] in
            ([try FTEngine.zip(inputs, mode: mode, processes: group)], nil)
        }
    }

    func unzip() {
        let mode = outputMode, group = processes
        runEach(T("압축 풀기", "Unzipping"), zips, addResultsToList: true) { try FTEngine.unzip($0, mode: mode, processes: group) }
    }

    func gif() {
        let inputs = videos, mode = outputMode
        guard !inputs.isEmpty, begin(T("GIF 만들기", "Making GIF")) else { return }
        let gen = generation
        // 저장소는 기능과 수명이 같아 강하게 잡아도 된다
        gifTask = Task.detached(priority: .userInitiated) { [self] in
            var made: [URL] = []
            var failure: String?
            for url in inputs {
                do { made.append(try await FTEngine.videoToGIF(url, mode: mode).url) }
                catch is CancellationError { return }
                catch { failure = error.localizedDescription }
            }
            await MainActor.run { [made, failure] in
                self.finish(gen, title: T("GIF 만들기", "Making GIF"), made: made, failure: failure, detail: nil)
            }
        }
    }

    func qrFromFiles() {
        let inputs = images
        guard !inputs.isEmpty, begin(T("QR 읽는 중", "Reading codes")) else { return }
        let gen = generation
        queue.async { [weak self] in
            var found: [FTCode] = []
            var failure: String?
            for url in inputs {
                do { found += try FTEngine.detectCodes(inFile: url) } catch { failure = error.localizedDescription }
            }
            DispatchQueue.main.async { self?.finishCodes(gen, found, failure: failure) }
        }
    }

    func qrFromClipboard() {
        guard begin(T("QR 읽는 중", "Reading codes")) else { return }
        let gen = generation
        guard let image = FTEngine.clipboardImage() else {
            finishCodes(gen, [], failure: T("클립보드에 이미지가 없음", "No image on the clipboard"))
            return
        }
        queue.async { [weak self] in
            let result = Result { try FTEngine.detectCodes(in: image) }
            DispatchQueue.main.async {
                switch result {
                case .success(let codes): self?.finishCodes(gen, codes, failure: nil)
                case .failure(let e): self?.finishCodes(gen, [], failure: e.localizedDescription)
                }
            }
        }
    }

    /// 화면 영역 캡처 → 해독. 화면 기록 권한이 없으면 macOS가 처음에 묻는다.
    func qrFromScreen() {
        guard begin(T("화면에서 영역을 드래그하세요 (esc 취소)", "Drag over the code (esc to cancel)")) else { return }
        let gen = generation, group = processes
        context?.collapse()
        queue.async { [weak self] in
            guard let image = FTEngine.captureRegion(processes: group) else {
                DispatchQueue.main.async { self?.finishCodes(gen, [], failure: nil, cancelled: true) }
                return
            }
            let result = Result { try FTEngine.detectCodes(in: image) }
            DispatchQueue.main.async {
                switch result {
                case .success(let codes): self?.finishCodes(gen, codes, failure: nil, showNotice: true)
                case .failure(let e): self?.finishCodes(gen, [], failure: e.localizedDescription, showNotice: true)
                }
            }
        }
    }

    func copy(_ code: FTCode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code.payload, forType: .string)
        setMessage(T("복사함", "Copied"), error: false)
    }

    func open(_ code: FTCode) {
        if let url = code.openableURL { NSWorkspace.shared.open(url) }
    }

    func addToList(_ url: URL) { add([url]) }

    /// 기능을 끌 때: 외부 도구와 GIF 작업을 멈추고 진행 표시를 지운다
    func cancelAll() {
        generation += 1
        processes.terminateAll()
        gifTask?.cancel()
        gifTask = nil
        busy = nil
    }

    // MARK: 실행 도우미

    private func begin(_ title: String) -> Bool {
        guard busy == nil else { return false }
        busy = title
        message = nil
        return true
    }

    /// 입력마다 새 파일 하나
    private func runEach(_ title: String, _ inputs: [URL], addResultsToList: Bool = false, _ work: @escaping (URL) throws -> URL) {
        guard !inputs.isEmpty else {
            setMessage(T("맞는 파일이 없음", "No matching files"), error: true)
            return
        }
        guard begin(title) else { return }
        let gen = generation
        queue.async { [weak self] in
            var made: [URL] = []
            var failure: String?
            for url in inputs {
                do { made.append(try work(url)) } catch { failure = error.localizedDescription }
            }
            DispatchQueue.main.async {
                self?.finish(gen, title: title, made: made, failure: failure, detail: nil)
                if addResultsToList { self?.add(made) }
            }
        }
    }

    /// 여러 입력으로 결과 하나 (합치기·압축)
    private func runBatch(_ title: String, _ inputs: [URL], _ work: @escaping () throws -> ([URL], String?)) {
        guard !inputs.isEmpty else {
            setMessage(T("맞는 파일이 없음", "No matching files"), error: true)
            return
        }
        guard begin(title) else { return }
        let gen = generation
        queue.async { [weak self] in
            let result = Result { try work() }
            DispatchQueue.main.async {
                switch result {
                case .success(let (made, detail)): self?.finish(gen, title: title, made: made, failure: nil, detail: detail)
                case .failure(let e): self?.finish(gen, title: title, made: [], failure: e.localizedDescription, detail: nil)
                }
            }
        }
    }

    private func finish(_ gen: Int, title: String, made: [URL], failure: String?, detail: String?) {
        guard gen == generation else { return }
        busy = nil
        codes.removeAll()
        outputs = Array((made + outputs).prefix(12))
        MemoryTrim.soon()
        let fellBack = made.contains { $0.path.hasPrefix((try? FTEngine.fallbackFolder().path) ?? "/nonexistent") }
        if let failure, made.isEmpty {
            setMessage(failure, error: true)
            context?.notice(T("파일 도구 실패", "File Tools failed"), failure, symbol: "exclamationmark.triangle.fill",
                            tint: .orange, tab: moduleID)
            return
        }
        var text = made.count == 1 ? made[0].lastPathComponent : T("\(made.count)개 만듦", "\(made.count) files created")
        if let detail { text += " · " + detail }
        if fellBack { text += T(" · 원래 폴더에 쓸 수 없어 임시 폴더에 둠", " · saved to a temporary folder (no write access)") }
        if let failure { text += " · " + T("일부 실패: ", "some failed: ") + failure }
        setMessage(text, error: failure != nil)
        context?.notice(title + T(" 완료", " done"), text, symbol: "checkmark.circle.fill", tint: .green, tab: moduleID,
                        actions: made.isEmpty ? [] : [ActivityAction(id: "ft.reveal", title: T("Finder에서 보기", "Show in Finder"),
                                                                     run: { FAKit.reveal(made) })])
    }

    private func finishCodes(_ gen: Int, _ found: [FTCode], failure: String?, cancelled: Bool = false, showNotice: Bool = false) {
        guard gen == generation else { return }
        busy = nil
        if cancelled { message = nil; return }
        codes = found
        if found.isEmpty {
            let text = failure ?? T("QR·바코드를 찾지 못함", "No QR code or barcode found")
            setMessage(text, error: true)
            if showNotice { context?.notice(T("QR 읽기", "QR scan"), text, symbol: "qrcode.viewfinder", tint: .orange, tab: moduleID) }
            return
        }
        if found.count == 1 {
            // 하나면 바로 복사 (Notchy와 같음)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(found[0].payload, forType: .string)
            setMessage(T("읽어서 복사함", "Read and copied"), error: false)
        } else {
            setMessage(T("코드 \(found.count)개를 찾음", "Found \(found.count) codes"), error: false)
        }
        if showNotice {
            let first = found[0]
            var actions: [ActivityAction] = []
            if found.count == 1, let url = first.openableURL {
                actions.append(ActivityAction(id: "ft.qr.open", title: T("열기", "Open"), role: .primary, run: { NSWorkspace.shared.open(url) }))
            }
            context?.notice(found.count == 1 ? T("QR 복사함", "QR code copied") : T("코드 \(found.count)개", "\(found.count) codes found"),
                            String(first.payload.prefix(80)), symbol: "qrcode", tint: .white, tab: moduleID, actions: actions)
        }
    }

    private func setMessage(_ text: String, error: Bool) {
        message = text
        messageIsError = error
    }
}

// MARK: - 탭 화면

private struct FTTab: View {
    @ObservedObject var store: FTStore

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            fileList.frame(width: 248)
            VStack(spacing: 6) {
                actions
                results
            }
        }
        .foregroundStyle(.white)
        .onDrop(of: [.fileURL], isTargeted: $store.targeted) { providers in
            load(providers)
            return true
        }
    }

    // MARK: 파일 목록 (선반 순서 = 합치기 순서)

    private var fileList: some View {
        FACard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(store.items.isEmpty ? T("파일", "Files") : T("파일 \(store.items.count)개", "\(store.items.count) files"))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button { pick() } label: { Image(systemName: "plus") }
                        .buttonStyle(FAPillStyle())
                        .help(T("파일 고르기", "Choose files"))
                        .accessibilityLabel(T("파일 고르기", "Choose files"))
                    if !store.items.isEmpty {
                        Button { store.clear() } label: { Image(systemName: "xmark") }
                            .buttonStyle(FAPillStyle())
                            .help(T("목록 비우기 (파일은 그대로)", "Clear the list (files stay)"))
                            .accessibilityLabel(T("목록 비우기", "Clear list"))
                    }
                }
                if store.items.isEmpty {
                    dropHint
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(store.items) { row($0) }
                        }
                    }
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.accentColor.opacity(store.targeted ? 0.9 : 0), lineWidth: 2))
    }

    private var dropHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.doc").font(.system(size: 24, weight: .light))
            Text(T("여기에 파일을 끌어다 놓기", "Drop files here")).font(.system(size: 12, weight: .medium))
            Text(T("이미지·PDF·동영상·ZIP·폴더", "Images, PDFs, videos, ZIPs, folders"))
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .contentShape(Rectangle())
        .onTapGesture { pick() }
    }

    private func row(_ item: FTStore.Item) -> some View {
        HStack(spacing: 6) {
            FAFileIcon(url: item.url, size: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.url.lastPathComponent).font(.system(size: 11.5)).lineLimit(1).truncationMode(.middle)
                Text(item.isFolder ? T("폴더", "Folder") : FAKit.bytes(item.size))
                    .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5)).monospacedDigit()
            }
            Spacer(minLength: 2)
            iconButton("chevron.up", T("위로", "Move up")) { store.move(item, by: -1) }
                .disabled(store.items.first == item)
            iconButton("chevron.down", T("아래로", "Move down")) { store.move(item, by: 1) }
                .disabled(store.items.last == item)
            iconButton("minus.circle", T("목록에서 빼기 (파일은 그대로)", "Remove from the list (file stays)")) { store.remove(item) }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.7))
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: 동작 버튼

    private var idle: Bool { store.busy == nil }

    private var actions: some View {
        FACard {
            VStack(alignment: .leading, spacing: 6) {
                actionRow(T("이미지", "Image")) {
                    pill(T("변환", "Convert"), "photo.on.rectangle", enabled: !store.images.isEmpty,
                         help: T("JPEG·PNG·TIFF·PDF·HEIC로 새 파일", "Save a copy as JPEG, PNG, TIFF, PDF or HEIC")) {
                        FAMenu.popUp(FTImageFormat.allCases.map { f in FAMenu.Entry(title: f.label) { store.convert(f) } })
                    }
                    pill(T("용량", "Size"), "arrow.down.right.and.arrow.up.left", enabled: !store.images.isEmpty,
                         help: T("목표 용량 이하로 압축 (원본 보존)", "Compress below a target size (original kept)")) {
                        let biggest = store.largestImageBytes
                        let entries = FTEngine.compressTargets.filter { Int64($0) < biggest }.map { t in
                            FAMenu.Entry(title: FAKit.bytes(Int64(t))) { store.compress(t) }
                        }
                        FAMenu.popUp(entries.isEmpty ? [FAMenu.Entry(title: T("이미 200 KB보다 작음", "Already under 200 KB"), enabled: false) {}] : entries)
                    }
                    pill(T("크기", "Resize"), "arrow.up.left.and.down.right.magnifyingglass", enabled: !store.images.isEmpty,
                         help: T("긴 변 기준으로 줄인 새 파일", "Save a smaller copy by long side")) {
                        let px = store.largestImagePixels
                        let entries = FTEngine.resizeTargets.filter { $0 < px }.map { t in
                            FAMenu.Entry(title: T("긴 변 \(t)px", "Long side \(t) px")) { store.resize(t) }
                        }
                        FAMenu.popUp(entries.isEmpty ? [FAMenu.Entry(title: T("이미 800px보다 작음", "Already under 800 px"), enabled: false) {}] : entries)
                    }
                }
                actionRow(T("문서·영상", "PDF·Video")) {
                    pill(T("PDF 합치기", "Merge PDF"), "doc.on.doc", enabled: store.mergeable.count >= 2,
                         help: T("목록 순서대로 PDF·이미지를 한 PDF로", "Combine PDFs and images in list order")) { store.merge() }
                    pill("GIF", "film", enabled: !store.videos.isEmpty,
                         help: T("앞 8초 · 12fps · 긴 변 480px", "First 8 s · 12 fps · 480 px")) { store.gif() }
                }
                actionRow(T("압축", "Archive")) {
                    pill("ZIP", "doc.zipper", enabled: !store.items.isEmpty,
                         help: T("목록의 파일을 ZIP 하나로 (__MACOSX 없음)", "Zip the listed files (no __MACOSX)")) { store.zip() }
                    pill(T("풀기", "Unzip"), "arrow.up.bin", enabled: !store.zips.isEmpty,
                         help: T("ZIP을 원본 옆 새 폴더에 풀고 목록에 올림", "Extract next to the ZIP and add to the list")) { store.unzip() }
                }
                actionRow("QR") {
                    pill(T("이미지", "Image"), "photo", enabled: !store.images.isEmpty,
                         help: T("목록의 이미지에서 QR·바코드 읽기", "Read codes in the listed images")) { store.qrFromFiles() }
                    pill(T("클립보드", "Clipboard"), "doc.on.clipboard", enabled: true,
                         help: T("클립보드 이미지에서 읽기", "Read the clipboard image")) { store.qrFromClipboard() }
                    pill(T("화면 영역", "Screen"), "qrcode.viewfinder", enabled: true,
                         help: T("영역을 드래그해 읽기 (화면 기록 권한 필요)", "Drag over a code (needs Screen Recording)")) { store.qrFromScreen() }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func actionRow<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                .frame(width: 54, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func pill(_ title: String, _ symbol: String, enabled: Bool, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 10))
                Text(title)
            }
        }
        .buttonStyle(FAPillStyle())
        .disabled(!enabled || !idle)
        .help(help)
        .accessibilityLabel(title)
    }

    // MARK: 결과

    private var results: some View {
        FACard {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let busy = store.busy {
                        ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                        Text(busy).font(.system(size: 11)).lineLimit(1)
                    } else if let msg = store.message {
                        Image(systemName: store.messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 10)).foregroundStyle(store.messageIsError ? .orange : .green)
                        Text(msg).font(.system(size: 11)).lineLimit(2).foregroundStyle(.white.opacity(0.8))
                    } else {
                        Text(T("결과는 새 파일로 만들고 원본은 건드리지 않음", "Results are new files; originals stay untouched"))
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer(minLength: 0)
                    if !store.outputs.isEmpty || !store.codes.isEmpty, store.busy == nil {
                        Button(T("지우기", "Clear")) { store.clearResults() }.buttonStyle(FAPillStyle())
                            .help(T("결과 목록만 지움 (파일은 그대로)", "Clear the result list (files stay)"))
                    }
                }
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.codes) { codeRow($0) }
                        if store.codes.isEmpty { ForEach(store.outputs, id: \.self) { outputRow($0) } }
                    }
                }
            }
        }
    }

    private func outputRow(_ url: URL) -> some View {
        HStack(spacing: 6) {
            FAFileIcon(url: url, size: 16)
            Text(url.lastPathComponent).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 2)
            Text(FAKit.bytes(FAKit.fileSize(url))).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5)).monospacedDigit()
            iconButton("plus.rectangle.on.rectangle", T("목록에 올리기", "Add to the list")) { store.addToList(url) }
            iconButton("magnifyingglass", T("Finder에서 보기", "Show in Finder")) { FAKit.reveal([url]) }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .help(T("끌어서 다른 앱에 놓기", "Drag into another app"))
    }

    private func codeRow(_ code: FTCode) -> some View {
        HStack(spacing: 6) {
            Image(systemName: code.symbology.lowercased().contains("qr") ? "qrcode" : "barcode").font(.system(size: 12))
            VStack(alignment: .leading, spacing: 0) {
                Text(code.payload).font(.system(size: 11)).lineLimit(2).textSelection(.enabled)
                Text(code.symbology).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 2)
            Button(T("복사", "Copy")) { store.copy(code) }.buttonStyle(FAPillStyle())
            if code.openableURL != nil {
                Button(T("열기", "Open")) { store.open(code) }.buttonStyle(FAPillStyle(tone: .primary))
                    .help(T("웹·메일·전화·FaceTime·문자 주소만 연다", "Opens web, mail, phone, FaceTime and SMS links only"))
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: 파일 받기

    private func load(_ providers: [NSItemProvider]) {
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async { store.add([url]) }
            }
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.title = T("파일 도구에 넣을 파일", "Files for File Tools")
        panel.prompt = T("넣기", "Add")
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            if response == .OK { store.add(panel.urls) }
        }
    }
}

// MARK: - 설정 화면 (설정 도우미 프로세스)

private struct FTSettings: View {
    let defaults: ModuleDefaults
    @State private var output = FTOutputMode.besideSource
    @State private var quality = 0.9

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(T("결과 저장 위치", "Save results to"), selection: $output) {
                ForEach(FTOutputMode.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: output) { _, v in defaults.set(v.rawValue, "output") }
            HStack {
                Text(T("JPEG·HEIC 품질", "JPEG/HEIC quality"))
                Slider(value: $quality, in: 0.5...1, step: 0.05)
                    .onChange(of: quality) { _, v in defaults.set(v, "quality") }
                Text("\(Int(quality * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            Text(T("같은 이름이 있으면 '이름 2'처럼 새 이름을 붙이고, 원본이나 기존 파일을 덮어쓰지 않는다. 원래 폴더에 쓸 수 없으면 임시 폴더에 두고 탭에서 끌어낼 수 있다.",
                   "Results never overwrite anything: a name in use becomes 'name 2'. If the folder isn't writable, results go to a temporary folder you can drag them out of."))
                .font(.caption).foregroundStyle(.secondary)
            Text(T("화면 영역 QR 읽기는 macOS 화면 기록 권한이 필요하다. 처음 누를 때 macOS가 묻는다. 찍은 임시 이미지는 읽은 뒤 바로 지운다.",
                   "Scanning a screen area needs Screen Recording permission; macOS asks the first time. The temporary capture is deleted right after reading."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            output = FTOutputMode(rawValue: defaults.string("output", default: FTOutputMode.besideSource.rawValue)) ?? .besideSource
            quality = defaults.double("quality", default: 0.9)
        }
    }
}

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 탭·설정 화면이 보는 클립보드 상태
final class ClipUIState: ObservableObject {
    @Published var prefs = ClipPrefs()
    @Published var axTrusted = AXIsProcessTrusted()
    @Published var ocrRunning: Set<UUID> = []
    /// 방금 복사만 한 항목 (줄에 잠깐 표시)
    @Published var flashID: UUID?
    private var flashWork: DispatchWorkItem?

    func flash(_ id: UUID) {
        flashID = id
        flashWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flashID = nil }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}

/// 탭이 보이는 동안만 켜는 앱 안 키 감시 (권한 불필요). 기능이 꺼지면 모듈이 지운다.
final class ClipKeyMonitor {
    private var token: Any?

    func install(_ handler: @escaping (NSEvent) -> Bool) {
        remove()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in handler(e) ? nil : e }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

/// 항목에 붙는 스마트 동작
struct ClipAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let run: () -> Void
}

/// 클립보드 기록: 복사한 글자·링크·이미지·파일·색상을 이 Mac에만 저장하고, 다시 붙여넣는다.
/// 켜져 있을 때만 0.5초마다 클립보드 변경 번호(changeCount)를 확인한다. 내용은 네트워크로 보내지 않는다.
final class ClipboardModule: NotchModule {
    let id = "clipboard"
    var title: String { T("클립보드", "Clipboard") }
    let symbol = "doc.on.clipboard"
    let enabledByDefault = false

    /// 실행 중인 인스턴스 (다른 기능이 기록을 읽을 때)
    static weak var current: ClipboardModule?

    /// 저장 위치를 바꿀 때만 (자체 검사의 임시 폴더)
    private let storeDirectory: URL?
    private(set) lazy var store = storeDirectory.map { ClipStore(directory: $0, readOnly: false) } ?? ClipStore(readOnly: AppSettings.isHelper)

    init(storeDirectory: URL? = nil) {
        self.storeDirectory = storeDirectory
    }
    let ui = ClipUIState()
    /// 탭 키보드 처리 (탭이 보일 때만)
    let tabKeys = ClipKeyMonitor()
    private(set) var context: ModuleContext?
    private var running = false
    private var generation = 0
    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }

    private var pollTimer: Timer?
    private var lastCount = 0
    private var maintenanceTimer: Timer?
    private var idleTimer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var keyMonitor: Any?
    private var lastCmdC: Date?
    private var lastCapture: (id: UUID, date: Date)?
    private var lastEmptiedCount = -1
    private let captureQueue = DispatchQueue(label: "dmn.clipboard.capture", qos: .userInitiated)
    private var sound: NSSound?

    // MARK: 시작·정지

    func start(context: ModuleContext) {
        guard !running else { return }
        running = true
        generation += 1
        self.context = context
        Self.current = self
        ui.prefs = ClipPrefs.load(defaults)
        store.load()
        store.configure(persist: ui.prefs.keepAfterQuit, limit: ui.prefs.limit)
        // 설정 도우미·명령줄 검사: 저장된 기록을 읽기만 하고 감시·단축키는 켜지 않는다
        guard !AppSettings.isHelper else { return }
        store.reclaimOrphans()
        handleClearRequest()
        applyMaxAge()
        startPolling()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.maintenance() }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        maintenanceTimer = t
        updateIdleTimer()
        observeSleepAndLock()
        registerHotkeys()
        updateKeyMonitor()
    }

    func stop() {
        guard running else { return }
        running = false
        generation += 1
        pollTimer?.invalidate(); pollTimer = nil
        maintenanceTimer?.invalidate(); maintenanceTimer = nil
        idleTimer?.invalidate(); idleTimer = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        HotKeyCenter.shared.unregister("clipboard.open")
        HotKeyCenter.shared.unregister("clipboard.plainPaste")
        tabKeys.remove()
        store.saveNow()
        store.waitForWrites()
        context = nil
        if Self.current === self { Self.current = nil }
    }

    func settingsChanged() {
        ui.prefs = ClipPrefs.load(defaults)
        guard running, !AppSettings.isHelper else { return }
        store.configure(persist: ui.prefs.keepAfterQuit, limit: ui.prefs.limit)
        registerHotkeys()
        updateKeyMonitor()
        updateIdleTimer()
        applyMaxAge()
        handleClearRequest()
    }

    // MARK: 화면

    func tabView() -> AnyView? { AnyView(ClipboardTab(module: self, store: store, ui: ui)) }
    var tabContentSize: CGSize { CGSize(width: 580, height: 300) }
    func settingsView() -> AnyView? { AnyView(ClipboardSettingsView()) }

    func paletteActions() -> [PaletteAction] {
        let paused = ui.prefs.paused
        let p = ui.prefs
        return [
            PaletteAction(id: "clipboard.open", title: T("클립보드 기록 열기", "Open Clipboard History"),
                          subtitle: p.openShortcutOn ? p.openShortcut.display : nil, symbol: symbol,
                          keywords: ["clipboard", "클립보드", "history", "기록", "복사", "copy"], run: { [weak self] in self?.openHistory() }),
            PaletteAction(id: "clipboard.plain", title: T("서식 없이 붙여넣기", "Paste as Plain Text"),
                          subtitle: p.plainShortcutOn ? p.plainShortcut.display : nil, symbol: "textformat",
                          keywords: ["plain", "평문", "서식", "paste", "붙여넣기"], run: { [weak self] in self?.pastePlainText(fromHotkey: false) }),
            PaletteAction(id: "clipboard.pause",
                          title: paused ? T("클립보드 수집 다시 시작", "Resume Clipboard Capture") : T("클립보드 수집 일시정지", "Pause Clipboard Capture"),
                          symbol: paused ? "play.circle" : "pause.circle",
                          keywords: ["pause", "resume", "일시정지", "다시 시작", "clipboard", "클립보드"], run: { [weak self] in self?.setPaused(!paused) }),
        ]
    }

    func paletteResults(for query: String) -> [PaletteAction] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard running, q.count >= 2 else { return [] }
        return store.search(q).prefix(5).map { item in
            PaletteAction(id: "clipboard.item.\(item.id.uuidString)", title: item.displayTitle,
                          subtitle: T("클립보드 기록 · ", "Clipboard history · ") + Self.relative(item.date),
                          symbol: item.kind.symbol, run: { [weak self] in self?.use(item, paste: true) })
        }
    }

    // MARK: 감시

    private func startPolling() {
        // 켜기 전부터 클립보드에 있던 내용은 기록하지 않는다
        lastCount = NSPasteboard.general.changeCount
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    private func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastCount else { return }
        lastCount = count
        guard !ClipPasteboard.isOwn(count) else { return }
        let prefs = ui.prefs
        guard !prefs.paused, ClipPasteboard.skipMarker(pb) == nil else { return }
        let front = NSWorkspace.shared.frontmostApplication
        if let bid = front?.bundleIdentifier, prefs.excluded.contains(bid) { return }
        guard var cap = ClipPasteboard.read(pb) else { return }

        if cap.kind == .link, prefs.linkMode == .auto, let text = cap.text, let cleaned = ClipLinkCleaner.cleanString(text) {
            ClipPasteboard.writeText(cleaned, transient: false, pb: pb)
            lastCount = pb.changeCount
            cap.text = cleaned
            context?.notice(T("링크 추적 요소를 지움", "Removed link trackers"), cleaned, symbol: "link", duration: 2)
        }

        var item = ClipItem(kind: cap.kind)
        item.text = cap.text
        item.paths = cap.paths
        item.appID = front?.bundleIdentifier
        item.appName = front?.localizedName
        let gen = generation
        let raw = cap.rawImage
        let base = item
        // 이미지 변환은 백그라운드에서, 순서는 지킨다
        captureQueue.async {
            var item = base
            var png: Data?
            if let raw {
                guard let norm = ClipPasteboard.normalizeImage(raw) else { return }
                png = norm.png
                item.imageWidth = norm.width
                item.imageHeight = norm.height
                item.digest = ClipStore.digest(norm.png)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running, self.generation == gen else { return }
                self.record(item, imageData: png)
            }
        }
    }

    /// 새 복사 하나를 기록한다 (연속 복사 묶음·같은 내용 올리기 포함)
    func record(_ item: ClipItem, imageData: Data?) {
        let prefs = ui.prefs
        // 연속 복사 묶음: 짧은 간격의 글자 복사를 맨 위 항목에 합친다
        if item.kind.isTextual, prefs.burstSeconds > 0, let newText = item.text, let last = lastCapture,
           item.date.timeIntervalSince(last.date) <= prefs.burstSeconds,
           let top = store.items.first, top.id == last.id, !top.isSaved, top.title == nil,
           top.kind.isTextual || top.kind == .burst {
            var parts = top.kind == .burst ? (top.parts ?? []) : [top.text ?? ""]
            if parts.last != newText {
                parts.append(newText)
                store.update(top.id) { t in
                    t.kind = .burst
                    t.parts = parts
                    t.text = parts.joined(separator: "\n")
                    t.date = item.date
                }
                playSound()
            }
            lastCapture = (top.id, item.date)
            return
        }
        let saved = store.insert(item, imageData: imageData)
        lastCapture = (saved.id, item.date)
        playSound()
        if saved.kind == .image, saved.ocrText == nil, prefs.ocrAuto { runOCR(saved.id) }
    }

    private func playSound() {
        guard ui.prefs.sound else { return }
        if sound?.name != NSSound.Name(ui.prefs.soundName) { sound = NSSound(named: NSSound.Name(ui.prefs.soundName)) }
        sound?.stop()
        sound?.play()
    }

    // MARK: 유지 작업

    private func maintenance() {
        applyMaxAge()
        ui.axTrusted = AXIsProcessTrusted()
        if ui.prefs.copyTwice, keyMonitor == nil { updateKeyMonitor() }
    }

    private func applyMaxAge() {
        let hours = ui.prefs.maxAgeHours
        guard hours > 0 else { return }
        store.prune(olderThan: Date().addingTimeInterval(-Double(hours) * 3600))
    }

    private func handleClearRequest() {
        let request = defaults.double("clearRequest", default: 0)
        let handledKey = "module.clipboard.clearHandled"
        guard request > UserDefaults.standard.double(forKey: handledKey) else { return }
        store.clearHistory()
        store.saveNow()
        UserDefaults.standard.set(request, forKey: handledKey)
    }

    private func observeSleepAndLock() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append((ws, ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleepOrLock(sleep: true)
        }))
        let dn = DistributedNotificationCenter.default()
        observers.append((dn, dn.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.sleepOrLock(sleep: false)
        }))
    }

    private func sleepOrLock(sleep: Bool) {
        let p = ui.prefs
        if sleep ? p.clearOnSleep : p.clearOnLock {
            store.clearHistory()
            store.saveNow()
        }
        if p.emptyOnSleepLock { emptySystemClipboard() }
    }

    private func updateIdleTimer() {
        if ui.prefs.emptyIdle, idleTimer == nil {
            let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.checkIdle() }
            t.tolerance = 5
            RunLoop.main.add(t, forMode: .common)
            idleTimer = t
        } else if !ui.prefs.emptyIdle {
            idleTimer?.invalidate()
            idleTimer = nil
        }
    }

    /// 키보드·마우스 입력이 없었던 시간(초). 권한 없이 읽는다.
    static func idleSeconds() -> Double {
        let types: [CGEventType] = [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .otherMouseDown]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    private func checkIdle() {
        guard Self.idleSeconds() >= Double(ui.prefs.emptyIdleMinutes * 60) else { return }
        emptySystemClipboard()
    }

    /// 지금 붙여넣기 될 내용만 비운다 (기록은 남김)
    private func emptySystemClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastEmptiedCount, !(pb.types ?? []).isEmpty else { return }
        pb.clearContents()
        ClipPasteboard.markOwn(pb)
        lastEmptiedCount = pb.changeCount
    }

    // MARK: 단축키

    private func registerHotkeys() {
        let p = ui.prefs
        var failed: [String] = []
        HotKeyCenter.shared.unregister("clipboard.open")
        if p.openShortcutOn, !HotKeyCenter.shared.register("clipboard.open", p.openShortcut, handler: { [weak self] in self?.openHistory() }) {
            failed.append(p.openShortcut.display)
        }
        HotKeyCenter.shared.unregister("clipboard.plainPaste")
        if p.plainShortcutOn, !HotKeyCenter.shared.register("clipboard.plainPaste", p.plainShortcut, handler: { [weak self] in self?.pastePlainText(fromHotkey: true) }) {
            failed.append(p.plainShortcut.display)
        }
        // 설정 화면이 읽는 상태 (알림을 보내지 않도록 UserDefaults에 직접)
        UserDefaults.standard.set(failed, forKey: "module.clipboard.status.failedShortcuts")
    }

    /// ⌘C 두 번으로 열기: 손쉬운 사용 권한이 있을 때만 전역 키 감시를 켠다
    private func updateKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard ui.prefs.copyTwice, AXIsProcessTrusted() else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.keyCode == UInt16(kVK_ANSI_C), !e.isARepeat,
                  e.modifierFlags.intersection([.command, .option, .control, .shift]) == .command else { return }
            let now = Date()
            if let last = self.lastCmdC, now.timeIntervalSince(last) < 0.45 {
                self.lastCmdC = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.openHistory() }
            } else {
                self.lastCmdC = now
            }
        }
    }

    // MARK: 동작

    func openHistory() {
        context?.openTab(id)
    }

    func setPaused(_ on: Bool) {
        ui.prefs.paused = on
        defaults.set(on, "paused")
    }

    func setPref(_ value: Any?, _ name: String) {
        defaults.set(value, name)
        ui.prefs = ClipPrefs.load(defaults)
    }

    /// 항목을 클립보드에 넣고, paste면 패널을 열기 전 앱에 붙여넣는다.
    func use(_ item: ClipItem, paste: Bool) {
        if item.kind == .image, store.imageData(for: item) == nil { return }
        ClipPasteboard.write(item, imageData: store.imageData(for: item))
        store.bump(item.id)
        guard paste, ui.prefs.pasteOnSelect else { ui.flash(item.id); return }
        context?.collapse()
        if !ModuleServices.pasteCurrentClipboard() {
            ui.axTrusted = false
            noticeCopiedOnly()
        }
    }

    /// 글자만 복사 (스마트 동작 결과·묶음 조각·인식한 글자). 기록에는 새로 넣지 않는다.
    func copyText(_ s: String, flash id: UUID? = nil) {
        ClipPasteboard.writeText(s, transient: false)
        if let id { ui.flash(id) }
    }

    func noticeCopiedOnly() {
        context?.notice(T("클립보드에 복사함", "Copied to the clipboard"),
                        T("손쉬운 사용 권한이 없어 자동으로 붙여넣지 못함 · ⌘V로 붙여넣기", "No Accessibility permission, so it was not pasted · press ⌘V"),
                        symbol: "doc.on.clipboard",
                        actions: [ActivityAction(id: "clipboard.ax", title: T("권한 열기", "Grant access")) { Self.requestAccessibility() }])
    }

    /// 지금 클립보드를 서식 없이 한 번 붙여넣고 원래 내용을 되돌린다.
    func pastePlainText(fromHotkey: Bool) {
        guard let text = ClipPasteboard.plainText() else {
            context?.notice(T("서식 없이 붙여넣을 글자가 없음", "Nothing to paste as plain text"),
                            T("지금 클립보드에 글자가 없음", "The clipboard has no text"), symbol: "textformat", duration: 2)
            return
        }
        if !fromHotkey { context?.collapse() }
        ClipPasteboard.pasteOnce(text, waitForModifiers: fromHotkey) { [weak self] ok in
            guard !ok else { return }
            self?.ui.axTrusted = false
            self?.context?.notice(T("서식 없는 글자를 클립보드에 넣음", "Plain text is on the clipboard"),
                                  T("손쉬운 사용 권한이 없어 ⌘V로 붙여넣기", "No Accessibility permission · press ⌘V"),
                                  symbol: "textformat",
                                  actions: [ActivityAction(id: "clipboard.ax", title: T("권한 열기", "Grant access")) { Self.requestAccessibility() }])
        }
    }

    func runOCR(_ id: UUID) {
        guard let item = store.items.first(where: { $0.id == id }), let data = store.imageData(for: item),
              !ui.ocrRunning.contains(id) else { return }
        ui.ocrRunning.insert(id)
        ClipOCR.recognize(data) { [weak self] text in
            guard let self else { return }
            self.ui.ocrRunning.remove(id)
            if let text { self.store.update(id) { $0.ocrText = text } }
        }
    }

    /// 묶음을 낱개 항목으로 푼다
    func splitBurst(_ item: ClipItem) {
        guard item.kind == .burst, let parts = item.parts, !parts.isEmpty else { return }
        store.remove(item.id)
        for p in parts {
            var it = ClipItem(kind: ClipColors.parse(p) != nil ? .color : (ClipDetect.link(p) != nil ? .link : .text), date: item.date)
            it.text = p
            it.appID = item.appID
            it.appName = item.appName
            store.insert(it, imageData: nil)
        }
        lastCapture = nil
    }

    /// 링크의 추적 요소를 지운 주소로 항목을 바꾸고 클립보드에 넣는다
    func cleanLink(_ item: ClipItem) {
        guard let text = item.text, let cleaned = ClipLinkCleaner.cleanString(text) else { return }
        store.update(item.id) { $0.text = cleaned }
        copyText(cleaned, flash: item.id)
    }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if !AXIsProcessTrustedWithOptions([key: true] as CFDictionary),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 항목 종류·내용에 맞는 스마트 동작
    func smartActions(for item: ClipItem) -> [ClipAction] {
        var a: [ClipAction] = []
        let text = item.text ?? ""
        switch item.kind {
        case .link:
            if let url = ClipDetect.link(text) {
                a.append(ClipAction(id: "open", title: T("열기", "Open"), symbol: "safari") { NSWorkspace.shared.open(url) })
                let trackers = ClipLinkCleaner.trackers(in: url)
                if !trackers.isEmpty, ui.prefs.linkMode != .off {
                    a.append(ClipAction(id: "clean", title: T("추적 요소 \(trackers.count)개 지우기", "Remove \(trackers.count) tracker\(trackers.count == 1 ? "" : "s")"),
                                        symbol: "wand.and.stars") { [weak self] in self?.cleanLink(item) })
                }
            }
        case .color:
            if let c = ClipColors.parse(text) {
                for f in ClipColorFormat.allCases {
                    let s = ClipColors.format(c, f)
                    a.append(ClipAction(id: "color.\(f.rawValue)", title: T("\(f.label) 복사 · \(s)", "Copy \(f.label) · \(s)"), symbol: "doc.on.doc") { [weak self] in
                        self?.copyText(s, flash: item.id)
                    })
                }
            }
        case .text:
            if let mail = ClipDetect.email(text), let url = URL(string: "mailto:\(mail)") {
                a.append(ClipAction(id: "mail", title: T("새 메일", "New Email"), symbol: "envelope") { NSWorkspace.shared.open(url) })
            }
            if let phone = ClipDetect.phone(text) {
                let digits = phone.filter { $0.isNumber || $0 == "+" }
                if let url = URL(string: "tel:\(digits)") {
                    a.append(ClipAction(id: "call", title: T("전화 걸기", "Call"), symbol: "phone") { NSWorkspace.shared.open(url) })
                }
            }
            if let v = ClipDetect.math(text) {
                let s = ClipDetect.formatNumber(v)
                a.append(ClipAction(id: "math", title: "= \(s)", symbol: "equal.circle") { [weak self] in self?.copyText(s, flash: item.id) })
            }
            if let pretty = ClipDetect.prettyJSON(text) {
                a.append(ClipAction(id: "json", title: T("JSON 정리 복사", "Copy Formatted JSON"), symbol: "curlybraces") { [weak self] in
                    self?.copyText(pretty, flash: item.id)
                })
            }
            if let addr = ClipDetect.address(text), var comps = URLComponents(string: "maps://") {
                comps.queryItems = [URLQueryItem(name: "q", value: addr)]
                if let url = comps.url {
                    a.append(ClipAction(id: "map", title: T("지도에서 보기", "Show in Maps"), symbol: "map") { NSWorkspace.shared.open(url) })
                }
            }
        case .file:
            let urls = (item.paths ?? []).map { URL(fileURLWithPath: $0) }
            let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            if !existing.isEmpty {
                a.append(ClipAction(id: "reveal", title: T("Finder에서 보기", "Show in Finder"), symbol: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting(existing)
                })
            }
        case .image:
            if let ocr = item.ocrText, !ocr.isEmpty {
                a.append(ClipAction(id: "ocrcopy", title: T("인식한 글자 복사", "Copy Recognized Text"), symbol: "text.viewfinder") { [weak self] in
                    self?.copyText(ocr, flash: item.id)
                })
            } else if item.ocrText == nil {
                a.append(ClipAction(id: "ocr", title: T("글자 인식", "Recognize Text"), symbol: "text.viewfinder") { [weak self] in self?.runOCR(item.id) })
            }
        case .burst:
            a.append(ClipAction(id: "split", title: T("묶음 풀기", "Split"), symbol: "square.split.1x2") { [weak self] in self?.splitBurst(item) })
        }
        return a
    }

    // MARK: 표시 도우미

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: L10n.isEnglish ? "en_US" : "ko_KR")
        return f
    }()

    static func relative(_ date: Date) -> String {
        let s = -date.timeIntervalSinceNow
        if s < 45 { return T("방금", "just now") }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: 자체 검사

    func selfTest() -> [String] { ClipSelfTest.run() }
}

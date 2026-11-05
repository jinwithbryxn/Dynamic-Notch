import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

/// 클립보드 설정 화면 (설정 도우미 프로세스에서 그려진다).
/// 값은 ModuleDefaults로 저장하고, 기록 지우기 같은 동작은 본 앱에 요청만 보낸다.
struct ClipboardSettingsView: View {
    private let d = ModuleDefaults(module: "clipboard")
    @State private var p = ClipPrefs.load()
    @State private var counts = (total: 0, saved: 0)
    @State private var pendingLimit: Int?
    @State private var confirmClear = false
    @State private var axTrusted = AXIsProcessTrusted()
    @State private var failedShortcuts: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            history
            capture
            privacy
            paste
            links
            limits
        }
        .onAppear(perform: refresh)
        .alert(T("보관 개수를 줄일까?", "Lower the history limit?"), isPresented: Binding(get: { pendingLimit != nil }, set: { if !$0 { pendingLimit = nil } })) {
            Button(T("줄이기", "Lower"), role: .destructive) {
                if let l = pendingLimit { p.limit = l; d.set(l, "limit") }
                pendingLimit = nil
            }
            Button(T("취소", "Cancel"), role: .cancel) { pendingLimit = nil }
        } message: {
            let over = max(0, counts.total - counts.saved - (pendingLimit ?? p.limit))
            Text(T("오래된 항목 \(over)개가 지워짐. 고정·목록 항목은 남음.", "\(over) older items will be removed. Pinned and saved items stay."))
        }
        .alert(T("기록을 지울까?", "Clear clipboard history?"), isPresented: $confirmClear) {
            Button(T("지우기", "Clear"), role: .destructive) {
                d.set(Date().timeIntervalSince1970, "clearRequest")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refresh() }
            }
            Button(T("취소", "Cancel"), role: .cancel) {}
        } message: {
            Text(T("고정한 항목과 저장 목록 항목은 남음.", "Pinned items and items in saved lists stay."))
        }
    }

    private func refresh() {
        p = ClipPrefs.load(d)
        counts = ClipStore.peekCounts()
        axTrusted = AXIsProcessTrusted()
        failedShortcuts = UserDefaults.standard.stringArray(forKey: "module.clipboard.status.failedShortcuts") ?? []
    }

    private func bind<V>(_ key: WritableKeyPath<ClipPrefs, V>, _ name: String, store: @escaping (V) -> Any = { $0 }) -> Binding<V> {
        Binding(get: { p[keyPath: key] }, set: { p[keyPath: key] = $0; d.set(store($0), name) })
    }

    // MARK: 기록

    private var history: some View {
        ClipSettingsSection(T("기록", "History")) {
            Toggle(T("종료 후에도 기록 유지 (이 Mac에만 저장)", "Keep history after quitting (stored on this Mac only)"), isOn: bind(\.keepAfterQuit, "keepAfterQuit"))
            ClipSettingsNote(T("끄면 고정·목록 항목만 저장하고 나머지는 메모리에만 둠.", "When off, only pinned and saved items are written to disk; the rest stays in memory."))
            Picker(T("보관 개수", "History limit"), selection: Binding(get: { p.limit }, set: { new in
                if new < p.limit, counts.total - counts.saved > new { pendingLimit = new } else { p.limit = new; d.set(new, "limit") }
            })) {
                ForEach(ClipPrefs.limits, id: \.self) { Text(T("\($0)개", "\($0) items")).tag($0) }
            }
            .frame(maxWidth: 320)
            HStack(spacing: 8) {
                Text(T("저장된 항목 \(counts.total)개 (고정·목록 \(counts.saved)개)", "\(counts.total) items stored (\(counts.saved) pinned or saved)"))
                    .foregroundStyle(.secondary)
                Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help(T("새로고침", "Refresh")).accessibilityLabel(T("새로고침", "Refresh"))
            }
            Button(T("기록 지우기…", "Clear History…")) { confirmClear = true }
            ClipSettingsNote(T("고정 항목은 보관 개수에서 빠지고 지우기·재시작 뒤에도 남음.", "Pinned items don't count toward the limit and survive clearing and restarts."))
        }
    }

    // MARK: 수집

    private var capture: some View {
        ClipSettingsSection(T("수집", "Capture")) {
            Toggle(T("수집 일시정지", "Pause capture"), isOn: bind(\.paused, "paused"))
            Toggle(T("복사한 이미지 속 글자 자동 인식 (기기 안, 검색에 쓰임)", "Recognize text in copied images automatically (on this Mac, used for search)"), isOn: bind(\.ocrAuto, "ocrAuto"))
            Picker(T("연속 복사 묶음", "Group rapid copies"), selection: bind(\.burstSeconds, "burstSeconds")) {
                ForEach(ClipPrefs.burstChoices, id: \.self) { Text(ClipPrefs.burstLabel($0)).tag($0) }
            }
            .frame(maxWidth: 320)
            ClipSettingsNote(T("짧은 간격으로 복사한 글자를 한 항목으로 묶어 한 번에 붙여넣음 (줄바꿈으로 이어 붙임). 항목 메뉴에서 풀 수 있음.",
                               "Text copied in quick succession becomes one item that pastes all parts joined by new lines. Split it from the item menu."))
            HStack(spacing: 8) {
                Toggle(T("복사 저장 소리", "Capture sound"), isOn: bind(\.sound, "sound"))
                Picker("", selection: bind(\.soundName, "soundName")) {
                    ForEach(ClipPrefs.sounds, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 130).disabled(!p.sound)
                Button { NSSound(named: NSSound.Name(p.soundName))?.play() } label: { Image(systemName: "speaker.wave.2") }
                    .buttonStyle(.borderless).help(T("미리 듣기", "Preview")).accessibilityLabel(T("소리 미리 듣기", "Preview sound"))
            }
        }
    }

    // MARK: 개인정보

    private var privacy: some View {
        ClipSettingsSection(T("개인정보", "Privacy")) {
            ClipSettingsNote(T("비밀번호 관리자 등이 숨김(Concealed)·임시(Transient)·자동 생성(AutoGenerated)으로 표시한 복사는 항상 기록하지 않음. 기록은 네트워크로 보내지 않음.",
                               "Copies marked Concealed, Transient or AutoGenerated (password managers and similar) are never saved. History is never sent over the network."))
            Text(T("기록하지 않을 앱", "Apps to ignore")).font(.system(size: 12, weight: .semibold))
            ClipExcludedApps(list: bind(\.excluded, "excluded"))
            Picker(T("기록 자동 삭제", "Delete history automatically"), selection: bind(\.maxAgeHours, "maxAgeHours")) {
                ForEach(ClipPrefs.maxAgeChoices, id: \.self) { Text(ClipPrefs.maxAgeLabel($0)).tag($0) }
            }
            .frame(maxWidth: 320)
            Toggle(T("잠자기 때 기록 지우기", "Clear history when the Mac sleeps"), isOn: bind(\.clearOnSleep, "clearOnSleep"))
            Toggle(T("화면 잠금 때 기록 지우기", "Clear history when the screen locks"), isOn: bind(\.clearOnLock, "clearOnLock"))
            HStack(spacing: 8) {
                Toggle(T("쓰지 않으면 시스템 클립보드 비우기", "Empty the clipboard when idle"), isOn: bind(\.emptyIdle, "emptyIdle"))
                Picker("", selection: bind(\.emptyIdleMinutes, "emptyIdleMinutes")) {
                    ForEach(ClipPrefs.idleChoices, id: \.self) { Text(T("\($0)분 뒤", "after \($0) min")).tag($0) }
                }
                .labelsHidden().frame(width: 110).disabled(!p.emptyIdle)
            }
            Toggle(T("잠자기·화면 잠금 때 시스템 클립보드 비우기", "Empty the clipboard on sleep or lock"), isOn: bind(\.emptyOnSleepLock, "emptyOnSleepLock"))
            ClipSettingsNote(T("지금 붙여넣기 될 내용만 비우고 기록은 남김. 이 앱의 기록에서 빠지는 것은 고정·목록 항목뿐.",
                               "Only what would be pasted next is emptied; your history stays. Clearing history keeps pinned and saved items."))
        }
    }

    // MARK: 붙여넣기·단축키

    private var paste: some View {
        ClipSettingsSection(T("붙여넣기·단축키", "Paste & Shortcuts")) {
            Toggle(T("항목을 고르면 앞 앱에 바로 붙여넣기", "Paste into the previous app when choosing an item"), isOn: bind(\.pasteOnSelect, "pasteOnSelect"))
            HStack(spacing: 8) {
                Image(systemName: axTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(axTrusted ? .green : .orange)
                Text(axTrusted ? T("손쉬운 사용 권한 있음: ⌘V를 대신 눌러 붙여넣음", "Accessibility allowed: pastes by sending ⌘V")
                               : T("손쉬운 사용 권한 없음: 고르면 클립보드에 복사만 됨 (⌘V로 직접 붙여넣기)", "No Accessibility permission: items are only copied (press ⌘V yourself)"))
                    .foregroundStyle(.secondary)
                if !axTrusted {
                    Button(T("권한 요청", "Grant Access")) { ClipboardModule.requestAccessibility() }
                }
            }
            Toggle(T("기록이 열려 있을 때 숫자 1–9로 붙여넣기 (검색 칸이 비었을 때, ⌘1–9는 언제나)", "Paste with 1–9 while history is open (when search is empty; ⌘1–9 always)"), isOn: bind(\.numberPaste, "numberPaste"))
            Toggle(T("⌘C 두 번으로 기록 열기 (손쉬운 사용 권한 필요)", "Press ⌘C twice to open history (needs Accessibility)"), isOn: bind(\.copyTwice, "copyTwice"))
                .disabled(!axTrusted && !p.copyTwice)
            ClipShortcutRow(title: T("기록 열기 단축키", "Open history shortcut"), on: bind(\.openShortcutOn, "openShortcutOn"),
                            shortcut: $p.openShortcut) { ClipPrefs.saveShortcut($0, "openShortcut", d) }
            ClipShortcutRow(title: T("서식 없이 붙여넣기 단축키", "Paste as plain text shortcut"), on: bind(\.plainShortcutOn, "plainShortcutOn"),
                            shortcut: $p.plainShortcut) { ClipPrefs.saveShortcut($0, "plainShortcut", d) }
            ClipSettingsNote(T("서식 없이 붙여넣기는 한 번만 평문으로 붙여넣고 원래 클립보드를 되돌림 (그 사이 새로 복사하면 새 것을 둠). 임시 평문은 기록에 남지 않음.",
                               "Paste as Plain Text pastes once as plain text, then restores the original clipboard unless you copied something new. The temporary copy is not saved."))
            if !failedShortcuts.isEmpty {
                Label(T("다른 앱이 이미 쓰는 단축키라 등록하지 못함: \(failedShortcuts.joined(separator: ", "))", "Shortcut already used by another app: \(failedShortcuts.joined(separator: ", "))"),
                      systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
    }

    // MARK: 링크

    private var links: some View {
        ClipSettingsSection(T("링크", "Links")) {
            Picker(T("추적 링크", "Tracking links"), selection: bind(\.linkMode, "linkMode", store: { $0.rawValue })) {
                Text(T("그대로 두기", "Leave as is")).tag(ClipPrefs.LinkMode.off)
                Text(T("정리 제안 (기록에서 한 번 눌러 정리)", "Suggest cleaning (one click in history)")).tag(ClipPrefs.LinkMode.suggest)
                Text(T("복사 즉시 정리", "Clean automatically on copy")).tag(ClipPrefs.LinkMode.auto)
            }
            .frame(maxWidth: 420)
            ClipSettingsNote(T("utm_·fbclid·gclid·YouTube si 같은 추적 파라미터만 지우고, 영상 ID·검색어처럼 내용을 바꾸는 파라미터는 남김.",
                               "Removes tracking parameters such as utm_, fbclid, gclid and YouTube si; keeps ones that change the page, like video IDs and search terms."))
        }
    }

    // MARK: 지원 안 됨

    private var limits: some View {
        ClipSettingsSection(T("지원 안 됨", "Not supported")) {
            ClipSettingsNote(T("iCloud로 저장 항목 동기화: 이 앱은 iCloud 권한(CloudKit entitlement)이 있는 서명으로 배포되지 않아 쓸 수 없음. 대안: 스니펫으로 저장해 두기.",
                               "Sync saved items with iCloud: this build isn't signed with an iCloud (CloudKit) entitlement. Alternative: keep reusable text as snippets."))
            ClipSettingsNote(T("서식 있는 글자(RTF·HTML)는 기록에 평문으로만 남음.", "Rich text (RTF/HTML) is kept in history as plain text only."))
        }
    }
}

// MARK: - 설정 부품

struct ClipSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            content
        }
    }
}

struct ClipSettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// 기록하지 않을 앱 목록 (번들 ID)
struct ClipExcludedApps: View {
    @Binding var list: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(list, id: \.self) { id in
                HStack(spacing: 8) {
                    let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                    if let url {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "app.dashed").frame(width: 18, height: 18).foregroundStyle(.secondary)
                    }
                    Text(url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id)
                    Text(url == nil ? T("\(id) · 설치 안 됨", "\(id) · not installed") : id).font(.island(.caption)).foregroundStyle(.secondary)
                    Spacer()
                    Button { list.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help(T("목록에서 빼기", "Remove")).accessibilityLabel(T("\(id) 빼기", "Remove \(id)"))
                }
            }
            HStack(spacing: 8) {
                Button(T("앱 추가…", "Add App…"), action: addApp)
                Button(T("기본 목록 복원", "Restore Defaults")) {
                    list = list + ClipPrefs.defaultExcluded.filter { !list.contains($0) }
                }
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = T("추가", "Add")
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { !list.contains($0) }
        if !ids.isEmpty { list += ids }
    }
}

/// 단축키 켜기 + 기록 버튼
struct ClipShortcutRow: View {
    let title: String
    @Binding var on: Bool
    @Binding var shortcut: HotKeyCenter.Shortcut
    let save: (HotKeyCenter.Shortcut) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle(title, isOn: $on)
            ClipShortcutRecorder(shortcut: $shortcut, save: save).disabled(!on)
        }
    }
}

/// 다음에 누른 키 조합을 단축키로 기록한다 (⌘·⌥·⌃ 중 하나 이상 필요, Esc는 취소)
struct ClipShortcutRecorder: View {
    @Binding var shortcut: HotKeyCenter.Shortcut
    let save: (HotKeyCenter.Shortcut) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? T("키를 누르세요…", "Press keys…") : shortcut.display) { recording ? stop() : start() }
            .frame(minWidth: 90)
            .help(T("눌러서 새 단축키 기록", "Click to record a new shortcut"))
            .onDisappear(perform: stop)
    }

    private func start() {
        stop()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            let flags = e.modifierFlags
            var mods: UInt32 = 0
            if flags.contains(.command) { mods |= UInt32(cmdKey) }
            if flags.contains(.option) { mods |= UInt32(optionKey) }
            if flags.contains(.control) { mods |= UInt32(controlKey) }
            if flags.contains(.shift) { mods |= UInt32(shiftKey) }
            guard mods & UInt32(cmdKey | optionKey | controlKey) != 0,
                  HotKeyCenter.Shortcut.keyNames[UInt32(e.keyCode)] != nil else { NSSound.beep(); return nil }
            let s = HotKeyCenter.Shortcut(keyCode: UInt32(e.keyCode), modifiers: mods)
            shortcut = s
            save(s)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

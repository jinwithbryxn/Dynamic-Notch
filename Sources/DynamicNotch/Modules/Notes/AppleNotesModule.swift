import AppKit
import SwiftUI

/// 적은 내용을 Apple 메모의 고른 폴더에 바로 저장한다 (AppleScript).
/// 처음 저장하거나 폴더 목록을 읽을 때 macOS가 자동화(메모 제어) 권한을 묻는다. 그래서 처음에는 꺼져 있다.
final class AppleNotesModule: NotchModule {
    let id = "applenotes"
    var title: String { T("Apple 메모", "Apple Notes") }
    let symbol = "note.text"
    let enabledByDefault = false

    let model = ANotesModel()
    private var context: ModuleContext?

    func start(context: ModuleContext) { self.context = context }
    func stop() { context = nil }
    func settingsChanged() { model.reloadFromDefaults() }

    func tabView() -> AnyView? { AnyView(ANotesTab(model: model, focusInput: { [weak self] in self?.context?.focusInput() })) }
    var tabContentSize: CGSize { CGSize(width: 460, height: 230) }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "applenotes.open", title: T("Apple 메모에 적기", "Write to Apple Notes"), symbol: symbol,
                       keywords: ["notes", "apple notes", "메모", "노트"]) { [weak self] in self?.context?.openTab("applenotes") }]
    }

    /// "메모 …", "note …" → 바로 Apple 메모에 저장
    func paletteResults(for query: String) -> [PaletteAction] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard let p = ["메모 ", "note "].first(where: { q.lowercased().hasPrefix($0) }) else { return [] }
        let text = String(q.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        return [PaletteAction(id: "applenotes.save", title: T("Apple 메모에 저장: \(text)", "Save to Apple Notes: \(text)"),
                              subtitle: model.folderName, symbol: "square.and.arrow.down") { [weak self] in
            self?.model.save(text) { err in
                if let err { self?.context?.notice(T("저장하지 못함", "Couldn't save"), err, symbol: "exclamationmark.triangle") }
                else { self?.context?.notice(T("Apple 메모에 저장함", "Saved to Apple Notes"), self?.model.folderName, symbol: "note.text") }
            }
        }]
    }

    func settingsView() -> AnyView? { AnyView(ANotesSettings(model: model)) }

    func selfTest() -> [String] {
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ANotesModel.bundleID) != nil
        return ["Notes installed: \(installed)",
                "automation permission (not asking): \(ANotesModel.automationStatus().debug)",
                "Info.plist NSAppleEventsUsageDescription: \(PIMPrivacy.hasUsageKey("NSAppleEventsUsageDescription"))",
                "saved folder: \(model.folderName)",
                "html body: \(ANotesModel.html("Title & <b>\nline \"2\"\n\nend\\"))"]
    }
}

struct ANFolder: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var account: String
}

final class ANotesModel: ObservableObject {
    static let bundleID = "com.apple.Notes"
    @Published var draft = ""
    @Published private(set) var saving = false
    @Published private(set) var folders: [ANFolder] = []
    @Published var status: String?
    @Published var folderID = ""

    let defaults = ModuleDefaults(module: "applenotes")
    /// AppleScript는 응답(권한 대화상자)을 기다리며 멈출 수 있어 전용 줄에서 돌린다
    private let queue = DispatchQueue(label: "dmn.applenotes.script")

    init() { reloadFromDefaults() }

    /// 설정 창에서 폴더 목록·선택을 바꾸면 다시 읽는다
    func reloadFromDefaults() {
        folders = defaults.data("folders").flatMap { try? JSONDecoder().decode([ANFolder].self, from: $0) } ?? []
        folderID = defaults.string("folder", default: "")
    }

    var folderName: String {
        folders.first { $0.id == folderID }.map { "\($0.account) › \($0.name)" } ?? T("기본 폴더", "Default folder")
    }

    func selectFolder(_ id: String) {
        folderID = id
        defaults.set(id, "folder")
    }

    enum Automation {
        case allowed, denied, notDetermined, notRunning, other(Int32)
        var debug: String {
            switch self {
            case .allowed: return "allowed"
            case .denied: return "denied"
            case .notDetermined: return "notDetermined"
            case .notRunning: return "Notes not running (unknown)"
            case .other(let c): return "status \(c)"
            }
        }
        var label: String {
            switch self {
            case .allowed: return T("허용됨", "Allowed")
            case .denied: return T("거부됨 — 시스템 설정 → 개인정보 보호 → 자동화에서 '메모'를 켜세요", "Denied — turn on Notes in System Settings → Privacy → Automation")
            case .notDetermined: return T("처음 저장할 때 macOS가 묻습니다", "macOS will ask the first time you save")
            case .notRunning: return T("메모 앱이 꺼져 있어 확인 못 함 (저장할 때 확인)", "Notes isn't running (checked on save)")
            case .other(let c): return T("확인 안 됨 (\(c))", "Unknown (\(c))")
            }
        }
    }

    /// 묻지 않고 자동화 권한 상태만 읽는다
    static func automationStatus() -> Automation {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
        switch Int(status) {
        case Int(noErr): return .allowed
        case -1743: return .denied
        case -1744: return .notDetermined
        case -600: return .notRunning
        default: return .other(status)
        }
    }

    /// 글을 메모 본문 HTML로 (첫 줄이 메모 제목이 된다)
    static func html(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { line -> String in
            let esc = line.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            return esc.isEmpty ? "<div><br></div>" : "<div>\(esc)</div>"
        }.joined()
    }

    private static func scriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// 사용자가 누른 저장에서만 부른다
    func save(_ text: String? = nil, done: @escaping (String?) -> Void) {
        let body = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { done(T("내용을 적으세요", "Write something first")); return }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) != nil else {
            done(T("메모 앱이 없음", "Notes app not found")); return
        }
        let folder = folders.first { $0.id == folderID }
        let target = folder.map { "folder id \(Self.scriptString($0.id))" }
        let source = """
        tell application id "com.apple.Notes"
            \(target.map { "make new note at \($0) with properties {body:\(Self.scriptString(Self.html(body)))}" }
              ?? "make new note with properties {body:\(Self.scriptString(Self.html(body)))}")
        end tell
        """
        saving = true
        run(source) { [weak self] _, err in
            guard let self else { return }
            self.saving = false
            if let err {
                self.status = err
                done(err)
            } else {
                if text == nil { self.draft = "" }
                self.status = T("저장함 · \(self.folderName)", "Saved · \(self.folderName)")
                done(nil)
            }
        }
    }

    /// 메모의 폴더 목록을 읽는다 (사용자가 누를 때만, 처음이면 자동화 권한을 묻는다)
    func refreshFolders(done: ((String?) -> Void)? = nil) {
        let source = """
        tell application id "com.apple.Notes"
            set out to {}
            repeat with a in accounts
                repeat with f in folders of a
                    set end of out to {id of f as text, name of f as text, name of a as text}
                end repeat
            end repeat
            return out
        end tell
        """
        status = T("폴더 읽는 중…", "Reading folders…")
        run(source) { [weak self] desc, err in
            guard let self else { return }
            if let err { self.status = err; done?(err); return }
            var list: [ANFolder] = []
            if let desc, desc.numberOfItems > 0 {
                for i in 1...desc.numberOfItems {
                    guard let row = desc.atIndex(i), row.numberOfItems >= 3,
                          let id = row.atIndex(1)?.stringValue, let name = row.atIndex(2)?.stringValue,
                          let account = row.atIndex(3)?.stringValue else { continue }
                    if ["Recently Deleted", "최근 삭제된 항목"].contains(name) { continue }
                    list.append(ANFolder(id: id, name: name, account: account))
                }
            }
            self.folders = list
            self.defaults.set(try? JSONEncoder().encode(list), "folders")
            self.status = T("폴더 \(list.count)개", "\(list.count) folders")
            done?(nil)
        }
    }

    private func run(_ source: String, completion: @escaping (NSAppleEventDescriptor?, String?) -> Void) {
        queue.async {
            let (result, error) = AppleScriptQueue.run(source)
            let message: String? = error.map { code, text in
                if code == -1743 { return T("메모 제어 권한이 거부됨 — 시스템 설정 → 개인정보 보호 → 자동화", "Permission to control Notes was denied — System Settings → Privacy → Automation") }
                return text.isEmpty ? T("AppleScript 오류 \(code)", "AppleScript error \(code)") : text
            }
            DispatchQueue.main.async { completion(message == nil ? result : nil, message) }
        }
    }
}

private struct ANotesTab: View {
    @ObservedObject var model: ANotesModel
    let focusInput: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "note.text").foregroundStyle(.yellow)
                Menu {
                    Button(T("기본 폴더", "Default folder")) { model.selectFolder("") }
                    if !model.folders.isEmpty { Divider() }
                    ForEach(model.folders) { f in Button("\(f.account) › \(f.name)") { model.selectFolder(f.id) } }
                    Divider()
                    Button(T("폴더 목록 새로 읽기", "Reload folder list")) { model.refreshFolders() }
                } label: {
                    Text(model.folderName).font(.island(.footnote, .semibold)).lineLimit(1)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help(T("저장할 폴더", "Destination folder"))
                Spacer()
                Button {
                    model.save { _ in }
                } label: {
                    Label(model.saving ? T("저장 중…", "Saving…") : T("메모에 저장", "Save to Notes"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(PIMPillStyle(prominent: true, tint: .yellow))
                .disabled(model.saving || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .help(T("Apple 메모에 저장 (⌘↩)", "Save to Apple Notes (⌘↩)"))
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.draft)
                    .font(.island(.subhead))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .accessibilityLabel(T("메모 내용", "Note text"))
                if model.draft.isEmpty {
                    Text(T("적은 내용은 Apple 메모에 바로 저장됩니다. 첫 줄이 제목이 됩니다.", "Write here and save straight to Apple Notes. The first line becomes the title."))
                        .font(.island(.subhead)).foregroundStyle(.white.opacity(0.35))
                        .padding(.leading, 5).allowsHitTesting(false)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
            if let s = model.status {
                Text(s).font(.island(.caption)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            focusInput()
            DispatchQueue.main.async { focused = true }
        }
    }
}

private struct ANotesSettings: View {
    @ObservedObject var model: ANotesModel
    @State private var status = ANotesModel.automationStatus()

    var body: some View {
        PIMSettingsGroup(title: T("Apple 메모", "Apple Notes")) {
            Text(T("자동화 권한: ", "Automation: ") + status.label).font(.caption).fixedSize(horizontal: false, vertical: true)
            HStack {
                Picker(T("저장할 폴더", "Folder"), selection: Binding(get: { model.folderID }, set: { model.selectFolder($0) })) {
                    Text(T("기본 폴더", "Default folder")).tag("")
                    ForEach(model.folders) { f in Text("\(f.account) › \(f.name)").tag(f.id) }
                }
                Button(T("폴더 목록 읽기", "Load Folders")) {
                    model.refreshFolders { _ in status = ANotesModel.automationStatus() }
                }
            }
            if let s = model.status { Text(s).font(.caption).foregroundStyle(.secondary) }
            if case .denied = status {
                Button(T("시스템 설정 열기", "Open System Settings")) { PIMPrivacy.open("Privacy_Automation") }
            }
            Text(T("폴더 목록을 읽거나 처음 저장할 때 macOS가 '메모' 제어를 허용할지 묻습니다. 내용은 이 Mac의 메모 앱으로만 전달됩니다.",
                   "macOS asks to allow controlling Notes the first time you load folders or save. Text goes only to the Notes app on this Mac."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

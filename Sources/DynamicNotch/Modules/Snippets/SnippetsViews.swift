import AppKit
import SwiftUI

/// 스니펫 탭: 검색, 누르면 직전 앱에 붙여넣기, 추가·편집·삭제(되돌리기)
struct SnippetsTab: View {
    let module: SnippetsModule
    @ObservedObject var store: ClipSnippetStore
    @ObservedObject var undo: SnippetUndo

    @State private var query = ""
    @State private var selection = 0
    @State private var hoverID: UUID?
    @State private var editing: SnippetDraft?
    @State private var axTrusted = AXIsProcessTrusted()
    @FocusState private var searchFocused: Bool

    private var results: [ClipSnippet] { store.search(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let draft = editing {
                SnippetEditor(draft: draft, dark: true) { result in
                    if let result { apply(result) }
                    editing = nil
                    DispatchQueue.main.async { searchFocused = true }
                }
            } else {
                header
                if let last = undo.last {
                    ClipBanner(symbol: "arrow.uturn.backward", text: T("'\(last.snippet.name)' 삭제함", "Deleted '\(last.snippet.name)'"), button: T("되돌리기", "Undo")) {
                        store.restore(last.snippet, at: last.index)
                        undo.clear()
                    }
                } else if !axTrusted {
                    ClipBanner(symbol: "exclamationmark.triangle", text: T("손쉬운 사용 권한이 없어 누르면 복사만 됨 · ⌘V로 붙여넣기", "No Accessibility permission: snippets are only copied · press ⌘V"),
                               button: T("권한 요청", "Grant")) { ClipboardModule.requestAccessibility() }
                }
                list
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            module.context?.focusInput()
            axTrusted = AXIsProcessTrusted()
            DispatchQueue.main.async { searchFocused = true }
            module.tabKeys.install { handleKey($0) }
        }
        .onDisappear { module.tabKeys.remove() }
    }

    /// 검색 칸에 포커스가 있을 때만: ↑↓ 고르기, ↩ 붙여넣기, Esc 검색어 지우기 (편집 중에는 건드리지 않음)
    private func handleKey(_ e: NSEvent) -> Bool {
        guard editing == nil, searchFocused, e.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
        let r = results
        switch e.keyCode {
        case 126:
            guard !r.isEmpty else { return false }
            selection = max(0, min(selection, r.count - 1) - 1)
            return true
        case 125:
            guard !r.isEmpty else { return false }
            selection = min(r.count - 1, selection + 1)
            return true
        case 36, 76:
            guard !r.isEmpty else { return false }
            module.paste(r[min(selection, r.count - 1)])
            return true
        case 53:
            guard !query.isEmpty else { return false }
            query = ""
            return true
        default:
            return false
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.island(.footnote)).foregroundStyle(.secondary)
                TextField(T("스니펫 검색", "Search snippets"), text: $query)
                    .textFieldStyle(.plain).font(.island(.subhead))
                    .focused($searchFocused)
                    .onChange(of: query) { _, _ in selection = 0 }
                    .accessibilityLabel(T("스니펫 검색", "Search snippets"))
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            ClipIconButton(symbol: "doc.on.clipboard", help: T("지금 클립보드를 스니펫으로 저장", "Save the clipboard as a snippet")) { module.saveClipboard() }
            ClipIconButton(symbol: "plus", help: T("새 스니펫", "New snippet")) { editing = SnippetDraft(id: nil, name: "", text: "") }
        }
        .frame(height: 26)
    }

    @ViewBuilder private var list: some View {
        let items = results
        if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: query.isEmpty ? "text.badge.plus" : "magnifyingglass").font(.island(.title1, .regular)).foregroundStyle(.secondary)
                Text(query.isEmpty ? T("저장한 스니펫이 없음\n+로 추가하거나 클립보드 내용을 저장", "No snippets yet\nAdd one with + or save the clipboard")
                                   : T("'\(query)' 검색 결과 없음", "No results for '\(query)'"))
                    .font(.island(.subhead)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, s in
                        row(s, selected: i == min(selection, items.count - 1))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ s: ClipSnippet, selected: Bool) -> some View {
        let hovered = hoverID == s.id
        return HStack(spacing: 8) {
            Image(systemName: "text.quote").font(.island(.subhead)).foregroundStyle(.white.opacity(0.6)).frame(width: 26, height: 26)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(.island(.subhead)).lineLimit(1)
                Text(ClipItem.firstLine(s.text)).font(.island(.caption)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 6)
            if hovered || selected {
                ClipIconButton(symbol: "pencil", help: T("편집", "Edit"), small: true) { editing = SnippetDraft(id: s.id, name: s.name, text: s.text) }
                ClipIconButton(symbol: "trash", help: T("삭제", "Delete"), small: true) {
                    if let (snip, i) = store.delete(s.id) { undo.remember(snip, i) }
                }
            }
        }
        .padding(.horizontal, 8).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(selected ? 0.14 : (hovered ? 0.08 : 0))))
        .contentShape(Rectangle())
        .onTapGesture { module.paste(s) }
        .onHover { inside in hoverID = inside ? s.id : (hoverID == s.id ? nil : hoverID) }
        .accessibilityElement(children: .combine)
        .accessibilityHint(T("눌러서 붙여넣기", "Press to paste"))
    }

    private func apply(_ d: SnippetDraft) {
        let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.isEmpty ? ClipSnippetStore.suggestedName(d.text) : name
        if let id = d.id { store.update(id, name: finalName, text: d.text) } else { store.add(name: finalName, text: d.text) }
    }
}

/// 편집 중인 스니펫
struct SnippetDraft: Equatable {
    var id: UUID?
    var name: String
    var text: String
}

/// 이름 + 내용 편집기. 끝나면 결과(취소면 nil)를 돌려준다.
struct SnippetEditor: View {
    @State var draft: SnippetDraft
    let dark: Bool
    let done: (SnippetDraft?) -> Void
    @FocusState private var nameFocused: Bool

    init(draft: SnippetDraft, dark: Bool, done: @escaping (SnippetDraft?) -> Void) {
        _draft = State(initialValue: draft)
        self.dark = dark
        self.done = done
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(T("이름 (팔레트에서 이 이름으로 찾음)", "Name (find it by this name in the palette)"), text: $draft.name)
                .textFieldStyle(.plain).font(.island(.subhead, .semibold))
                .focused($nameFocused)
                .padding(.horizontal, 8).frame(height: 26)
                .background(fieldBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel(T("스니펫 이름", "Snippet name"))
            TextEditor(text: $draft.text)
                .font(.island(.subhead))
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(fieldBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(minHeight: 80, maxHeight: .infinity)
                .accessibilityLabel(T("스니펫 내용", "Snippet text"))
            HStack(spacing: 6) {
                Spacer()
                if dark {
                    ClipCapsuleButton(title: T("취소", "Cancel"), symbol: nil) { done(nil) }
                    ClipCapsuleButton(title: T("저장", "Save"), symbol: "checkmark") { done(draft) }
                        .disabled(draft.text.isEmpty)
                } else {
                    Button(T("취소", "Cancel")) { done(nil) }
                    Button(T("저장", "Save")) { done(draft) }.disabled(draft.text.isEmpty).keyboardShortcut(.defaultAction)
                }
            }
        }
        .onExitCommand { done(nil) }
        .onAppear { DispatchQueue.main.async { nameFocused = true } }
    }

    private var fieldBackground: Color { dark ? Color.white.opacity(0.08) : Color.primary.opacity(0.06) }
}

/// 스니펫 설정 화면 (설정 도우미 프로세스)
struct SnippetsSettingsView: View {
    @StateObject private var store = ClipSnippetStore()
    @State private var editing: SnippetDraft?
    @State private var lastDeleted: (ClipSnippet, Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ClipSettingsNote(T("⌘K 팔레트에서 이름 몇 글자를 입력하고 Return을 누르면 직전에 쓰던 앱에 붙여넣음. 스니펫 붙여넣기는 클립보드 기록에 남지 않고, 붙여넣은 뒤 원래 클립보드를 되돌림. 이 Mac에만 저장.",
                               "Type a few letters of a name in the ⌘K palette and press Return to paste into the app you were using. Snippet pastes are not saved to clipboard history and the original clipboard is restored. Stored on this Mac only."))
            HStack(spacing: 8) {
                Button(T("새 스니펫", "New Snippet")) { editing = SnippetDraft(id: nil, name: "", text: "") }
                Button(T("지금 클립보드를 스니펫으로 저장", "Save Snippet from Clipboard")) {
                    if let text = ClipPasteboard.plainText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        store.add(name: ClipSnippetStore.suggestedName(text), text: text)
                    } else {
                        NSSound.beep()
                    }
                }
                if let (s, i) = lastDeleted {
                    Button(T("'\(s.name)' 삭제 되돌리기", "Undo deleting '\(s.name)'")) { store.restore(s, at: i); lastDeleted = nil }
                }
            }
            if let draft = editing {
                SnippetEditor(draft: draft, dark: false) { result in
                    if let d = result {
                        let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalName = name.isEmpty ? ClipSnippetStore.suggestedName(d.text) : name
                        if let id = d.id { store.update(id, name: finalName, text: d.text) } else { store.add(name: finalName, text: d.text) }
                    }
                    editing = nil
                }
                .frame(height: 200)
            }
            if store.snippets.isEmpty {
                Text(T("저장한 스니펫이 없음", "No snippets yet")).foregroundStyle(.secondary)
            }
            ForEach(store.snippets) { s in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.name).fontWeight(.medium)
                        Text(ClipItem.firstLine(s.text)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button(T("편집", "Edit")) { editing = SnippetDraft(id: s.id, name: s.name, text: s.text) }
                    Button(T("삭제", "Delete")) { lastDeleted = store.delete(s.id) }
                }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .onAppear { store.load() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: ModuleDefaults.changedNotification)) { note in
            if note.object as? String == "snippets", editing == nil { store.load() }
        }
    }
}

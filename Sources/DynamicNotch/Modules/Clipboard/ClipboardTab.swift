import AppKit
import SwiftUI

/// 기록 목록 거르기
enum ClipFilter: Hashable {
    case all, pinned, kind(ClipKind), list(UUID)
}

/// 클립보드 탭: 검색, 종류 거르기, 목록(번호 1–9), 자세히 보기
struct ClipboardTab: View {
    let module: ClipboardModule
    @ObservedObject var store: ClipStore
    @ObservedObject var ui: ClipUIState

    @State private var query = ""
    @State private var filter: ClipFilter = .all
    @State private var selection = 0
    @State private var detailID: UUID?
    @State private var hoverID: UUID?
    @State private var confirmClear = false
    @State private var newList: (name: String, item: UUID?)?
    @FocusState private var searchFocused: Bool

    private var results: [ClipItem] {
        switch filter {
        case .all: return store.search(query)
        case .pinned: return store.search(query, pinnedOnly: true)
        case .kind(let k): return store.search(query, kind: k)
        case .list(let id): return store.search(query, list: id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let id = detailID, let item = store.items.first(where: { $0.id == id }) {
                ClipDetailView(module: module, store: store, ui: ui, item: item) {
                    detailID = nil
                    DispatchQueue.main.async { searchFocused = true }
                }
            } else {
                header
                filterBar
                banners
                list
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            module.context?.focusInput()
            ui.axTrusted = AXIsProcessTrusted()
            DispatchQueue.main.async { searchFocused = true }
            module.tabKeys.install { handleKey($0) }
        }
        .onDisappear { module.tabKeys.remove() }
    }

    // MARK: 머리

    private var header: some View {
        HStack(spacing: 6) {
            if let draft = newList {
                ClipInlineField(placeholder: T("새 목록 이름", "New list name"), text: Binding(get: { draft.name }, set: { newList?.name = $0 }),
                                confirm: T("만들기", "Create")) {
                    let name = (newList?.name ?? "").trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        let list = store.addList(name)
                        if let item = newList?.item { store.toggle(item, in: list.id) } else { filter = .list(list.id) }
                    }
                    newList = nil
                } cancel: { newList = nil }
            } else if confirmClear {
                let n = store.items.filter { !$0.isSaved }.count
                Image(systemName: "trash").font(.island(.subhead)).foregroundStyle(.secondary)
                Text(T("고정·목록 항목을 빼고 \(n)개를 지울까?", "Clear \(n) items? Pinned and saved items stay."))
                    .font(.island(.subhead)).lineLimit(1)
                Spacer()
                ClipCapsuleButton(title: T("지우기", "Clear"), symbol: nil, tint: .red) { store.clearHistory(); confirmClear = false }
                ClipCapsuleButton(title: T("취소", "Cancel"), symbol: nil) { confirmClear = false }
            } else {
                searchField
                ClipIconButton(symbol: ui.prefs.paused ? "play.fill" : "pause.fill",
                               help: ui.prefs.paused ? T("수집 다시 시작", "Resume capture") : T("수집 일시정지", "Pause capture"),
                               active: ui.prefs.paused) { module.setPaused(!ui.prefs.paused) }
                moreMenu
            }
        }
        .frame(height: 26)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.island(.footnote)).foregroundStyle(.secondary)
            TextField(T("기록 검색 (글자·파일 이름·이미지 속 글자)", "Search history (text, file names, text in images)"), text: $query)
                .textFieldStyle(.plain)
                .font(.island(.subhead))
                .focused($searchFocused)
                .onChange(of: query) { _, _ in selection = 0 }
                .accessibilityLabel(T("클립보드 기록 검색", "Search clipboard history"))
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.island(.footnote)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help(T("검색어 지우기", "Clear search")).accessibilityLabel(T("검색어 지우기", "Clear search"))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var moreMenu: some View {
        Menu {
            Button(T("새 목록…", "New List…")) { newList = ("", nil) }
            if case .list(let id) = filter {
                Button(T("이 목록 삭제 (항목은 기록에 남음)", "Delete This List (items stay in history)")) { store.deleteList(id); filter = .all }
            }
            Divider()
            Button(T("기록 지우기…", "Clear History…")) { confirmClear = true }
                .disabled(!store.items.contains { !$0.isSaved })
        } label: {
            Image(systemName: "ellipsis").font(.island(.subhead, .semibold))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(T("더 보기", "More"))
        .accessibilityLabel(T("더 보기", "More"))
    }

    // MARK: 거르기

    private var filterBar: some View {
        HStack(spacing: 4) {
            chip(T("전체", "All"), .all)
            chip(T("고정", "Pinned"), .pinned)
            ForEach([ClipKind.text, .link, .image, .file, .color], id: \.self) { k in chip(k.label, .kind(k)) }
            listMenu
            Spacer(minLength: 4)
            Text(countText).font(.island(.footnote)).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(height: 20)
    }

    private var countText: String {
        let shown = results.count, total = store.items.count
        return shown == total ? T("\(total)개", "\(total) items") : T("\(shown) / \(total)개", "\(shown) of \(total)")
    }

    private func chip(_ title: String, _ f: ClipFilter) -> some View {
        Button { filter = f; selection = 0 } label: {
            Text(title).font(.system(size: 11, weight: filter == f ? .semibold : .regular))
                .padding(.horizontal, 8).frame(height: 20)
                .background(Color.white.opacity(filter == f ? 0.2 : 0.07), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filter == f ? .isSelected : [])
    }

    private var listMenu: some View {
        let current: ClipList? = { if case .list(let id) = filter { return store.lists.first { $0.id == id } }; return nil }()
        return Menu {
            if store.lists.isEmpty { Text(T("저장 목록이 없음", "No saved lists")) }
            ForEach(store.lists) { list in
                Button(list.name) { filter = .list(list.id); selection = 0 }
            }
            Divider()
            Button(T("새 목록…", "New List…")) { newList = ("", nil) }
        } label: {
            HStack(spacing: 2) {
                Text(current?.name ?? T("목록", "Lists")).lineLimit(1)
                Image(systemName: "chevron.down").font(.island(.caption2, .bold))
            }
            .font(.system(size: 11, weight: current != nil ? .semibold : .regular))
            .padding(.horizontal, 8).frame(height: 20)
            .background(Color.white.opacity(current != nil ? 0.2 : 0.07), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(T("저장 목록", "Saved lists"))
    }

    // MARK: 안내 줄

    @ViewBuilder private var banners: some View {
        if ui.prefs.paused {
            ClipBanner(symbol: "pause.circle", text: T("수집 일시정지 중 · 새 복사는 기록하지 않음", "Capture paused · new copies are not saved"),
                       button: T("다시 시작", "Resume")) { module.setPaused(false) }
        } else if ui.prefs.pasteOnSelect && !ui.axTrusted {
            ClipBanner(symbol: "exclamationmark.triangle",
                       text: T("손쉬운 사용 권한이 없어 고르면 복사만 됨 · ⌘V로 붙여넣기", "No Accessibility permission: choosing an item only copies it · press ⌘V"),
                       button: T("권한 요청", "Grant")) { ClipboardModule.requestAccessibility() }
        }
    }

    // MARK: 목록

    private var list: some View {
        let items = results
        return Group {
            if items.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                                ClipRow(module: module, store: store, ui: ui, item: item,
                                        number: ui.prefs.numberPaste && i < 9 ? i + 1 : nil,
                                        selected: i == min(selection, items.count - 1),
                                        hovered: hoverID == item.id,
                                        openDetail: { detailID = item.id },
                                        newListFor: { newList = ("", item.id) })
                                    .id(item.id)
                                    .onHover { inside in hoverID = inside ? item.id : (hoverID == item.id ? nil : hoverID) }
                            }
                        }
                    }
                    .onChange(of: selection) { _, new in
                        guard new < items.count else { return }
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(items[new].id) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: ui.prefs.paused ? "pause.circle" : (query.isEmpty ? "doc.on.clipboard" : "magnifyingglass"))
                .font(.island(.title1)).foregroundStyle(.secondary)
            Text(emptyText).font(.island(.subhead)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyText: String {
        if !query.isEmpty { return T("'\(query)' 검색 결과 없음", "No results for '\(query)'") }
        if filter != .all { return T("이 분류에 항목이 없음", "Nothing here yet") }
        if ui.prefs.paused { return T("수집이 일시정지되어 있음", "Capture is paused") }
        return T("아직 기록이 없음\n무언가 복사하면 여기에 쌓임", "No history yet\nCopy something and it shows up here")
    }

    // MARK: 키보드

    /// 탭이 보이는 동안 앱 안 키 입력을 먼저 본다. 처리했으면 true (이벤트를 먹음).
    /// 검색 칸에 포커스가 있을 때만 (팔레트 등 다른 입력 칸의 키는 건드리지 않음).
    /// ↑↓ 고르기, ↩ 붙여넣기(⌘↩ 복사만), ⌘I 자세히, ⌘⌫ 삭제(검색어가 빌 때), Esc 검색어 지우기, 1–9(⌘1–9) 붙여넣기
    private func handleKey(_ e: NSEvent) -> Bool {
        guard detailID == nil, newList == nil, searchFocused || confirmClear else { return false }
        let items = results
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let cmd = mods == .command
        if confirmClear {
            if e.keyCode == 53 { confirmClear = false; return true }
            return false
        }
        switch e.keyCode {
        case 126:   // ↑
            selection = max(0, min(selection, items.count - 1) - 1)
            return true
        case 125:   // ↓
            selection = min(max(0, items.count - 1), selection + 1)
            return true
        case 36, 76:   // ↩
            guard mods.isEmpty || cmd, let item = item(at: selection, in: items) else { return false }
            module.use(item, paste: !cmd)
            return true
        case 34:   // ⌘I
            guard cmd, let item = item(at: selection, in: items) else { return false }
            detailID = item.id
            return true
        case 51:   // ⌘⌫ (검색어가 있으면 글자 지우기로 둔다)
            guard cmd, query.isEmpty, let item = item(at: selection, in: items) else { return false }
            store.remove(item.id)
            return true
        case 53:   // Esc
            guard !query.isEmpty else { return false }
            query = ""
            return true
        default:
            break
        }
        // 숫자 1–9: 검색 칸이 비었을 때, ⌘와 함께면 언제나
        guard ui.prefs.numberPaste, mods.isEmpty ? query.isEmpty : cmd,
              let ch = e.charactersIgnoringModifiers, let n = Int(ch), (1...9).contains(n),
              let item = item(at: n - 1, in: items) else { return false }
        module.use(item, paste: true)
        return true
    }

    private func item(at i: Int, in items: [ClipItem]) -> ClipItem? {
        guard !items.isEmpty else { return nil }
        return items[max(0, min(i, items.count - 1))]
    }
}

// MARK: - 한 줄

struct ClipRow: View {
    let module: ClipboardModule
    @ObservedObject var store: ClipStore
    @ObservedObject var ui: ClipUIState
    let item: ClipItem
    let number: Int?
    let selected: Bool
    let hovered: Bool
    let openDetail: () -> Void
    let newListFor: () -> Void

    var body: some View {
        let actions = module.smartActions(for: item)
        HStack(spacing: 8) {
            Text(number.map(String.init) ?? "")
                .font(.island(.caption)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.4)).frame(width: 9)
            ClipThumb(store: store, item: item, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayTitle).font(.island(.subhead)).lineLimit(1).truncationMode(.tail)
                Text(meta).font(.island(.caption)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 6)
            if ui.flashID == item.id {
                Text(T("복사함", "Copied")).font(.island(.caption))
                    .padding(.horizontal, 7).frame(height: 18).background(Color.green.opacity(0.35), in: Capsule())
            }
            if selected || hovered {
                ForEach(actions.prefix(2)) { a in
                    ClipIconButton(symbol: a.symbol, help: a.title, small: true, action: a.run)
                }
                ClipIconButton(symbol: item.isPinned ? "pin.fill" : "pin", help: item.isPinned ? T("고정 해제", "Unpin") : T("고정", "Pin"),
                               small: true, active: item.isPinned) { store.update(item.id) { $0.pinned = !item.isPinned } }
                rowMenu(actions)
            } else if item.isPinned {
                Image(systemName: "pin.fill").font(.island(.caption)).foregroundStyle(.white.opacity(0.6))
                    .accessibilityLabel(T("고정됨", "Pinned"))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.white.opacity(selected ? 0.14 : (hovered ? 0.08 : 0))))
        .contentShape(Rectangle())
        .onTapGesture(count: 1) { module.use(item, paste: true) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.displayTitle)
        .accessibilityHint(ui.prefs.pasteOnSelect ? T("눌러서 붙여넣기", "Press to paste") : T("눌러서 복사", "Press to copy"))
        .contextMenu { menuItems(actions) }
    }

    private var meta: String {
        var parts: [String] = []
        parts.append(item.kind.singular)
        if let app = item.appName { parts.append(app) }
        parts.append(ClipboardModule.relative(item.date))
        if let lists = item.lists, !lists.isEmpty {
            let names = store.lists.filter { lists.contains($0.id) }.map(\.name)
            if !names.isEmpty { parts.append(names.joined(separator: ", ")) }
        }
        if item.kind == .image {
            if ui.ocrRunning.contains(item.id) { parts.append(T("글자 인식 중…", "Recognizing text…")) }
            else if let o = item.ocrText, !o.isEmpty { parts.append(ClipItem.firstLine(o)) }
        }
        if item.kind == .link, let url = ClipDetect.link(item.text ?? ""), !ClipLinkCleaner.trackers(in: url).isEmpty, ui.prefs.linkMode != .off {
            parts.append(T("추적 요소 있음", "Has trackers"))
        }
        return parts.joined(separator: " · ")
    }

    private func rowMenu(_ actions: [ClipAction]) -> some View {
        Menu { menuItems(actions) } label: {
            Image(systemName: "ellipsis").font(.island(.footnote, .semibold))
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.1), in: Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(T("항목 동작", "Item actions"))
        .accessibilityLabel(T("항목 동작", "Item actions"))
    }

    @ViewBuilder private func menuItems(_ actions: [ClipAction]) -> some View {
        Button(ui.prefs.pasteOnSelect ? T("붙여넣기", "Paste") : T("복사", "Copy")) { module.use(item, paste: true) }
        if ui.prefs.pasteOnSelect { Button(T("복사만", "Copy Only")) { module.use(item, paste: false) } }
        if !actions.isEmpty {
            Divider()
            ForEach(actions) { a in Button(a.title, action: a.run) }
        }
        Divider()
        Button(item.isPinned ? T("고정 해제", "Unpin") : T("고정", "Pin")) { store.update(item.id) { $0.pinned = !item.isPinned } }
        Menu(T("목록에 넣기", "Add to List")) {
            ForEach(store.lists) { list in
                Button((item.lists?.contains(list.id) == true ? "✓ " : "") + list.name) { store.toggle(item.id, in: list.id) }
            }
            if !store.lists.isEmpty { Divider() }
            Button(T("새 목록…", "New List…"), action: newListFor)
        }
        Button(T("자세히·제목 붙이기 (⌘I)", "Details & Title (⌘I)")) { openDetail() }
        Divider()
        Button(T("삭제", "Delete")) { store.remove(item.id) }
    }
}

// MARK: - 썸네일

struct ClipThumb: View {
    @ObservedObject var store: ClipStore
    let item: ClipItem
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.08))
            content
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .image:
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo").font(.system(size: size * 0.42)).foregroundStyle(.secondary)
                    .task(id: item.id) { image = store.thumbnail(for: item, maxPixel: Int(size * 2)) }
            }
        case .color:
            if let c = ClipColors.parse(item.text ?? "") {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(nsColor: ClipColors.nsColor(c)))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            }
        case .file:
            if let path = item.paths?.first, FileManager.default.fileExists(atPath: path) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().aspectRatio(contentMode: .fit).padding(2)
            } else {
                Image(systemName: "doc.questionmark").font(.system(size: size * 0.42)).foregroundStyle(.secondary)
            }
        case .burst:
            VStack(spacing: 0) {
                Image(systemName: item.kind.symbol).font(.system(size: size * 0.34))
                Text("\(item.parts?.count ?? 0)").font(.island(.caption2, .semibold))
            }
            .foregroundStyle(.white.opacity(0.75))
        default:
            Image(systemName: item.kind.symbol).font(.system(size: size * 0.4)).foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - 작은 부품

struct ClipIconButton: View {
    let symbol: String
    let help: String
    var small = false
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: small ? 10.5 : 12, weight: .semibold))
                .frame(width: small ? 22 : 26, height: small ? 22 : 26)
                .background(Color.white.opacity(active ? 0.24 : 0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct ClipCapsuleButton: View {
    let title: String
    let symbol: String?
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.island(.caption, .semibold)) }
                Text(title).font(.island(.footnote)).lineLimit(1)
            }
            .padding(.horizontal, 10).frame(height: 24)
            .background(tint == .white ? Color.white.opacity(0.12) : tint.opacity(0.45), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

struct ClipBanner: View {
    let symbol: String
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.island(.footnote)).foregroundStyle(.yellow.opacity(0.85))
            Text(text).font(.island(.footnote)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            Spacer(minLength: 4)
            Button(button, action: action).buttonStyle(.plain).font(.island(.footnote, .semibold))
                .padding(.horizontal, 8).frame(height: 18).background(Color.white.opacity(0.14), in: Capsule())
                .help(button)
        }
        .padding(.horizontal, 8).frame(height: 24)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// 한 줄 입력 + 확인·취소 (목록 이름 등)
struct ClipInlineField: View {
    let placeholder: String
    @Binding var text: String
    let confirm: String
    let onConfirm: () -> Void
    let cancel: () -> Void
    @FocusState private var focused: Bool

    init(placeholder: String, text: Binding<String>, confirm: String, onConfirm: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.placeholder = placeholder
        self._text = text
        self.confirm = confirm
        self.onConfirm = onConfirm
        self.cancel = cancel
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain).font(.island(.subhead))
                .focused($focused)
                .onSubmit(onConfirm)
                .onExitCommand(perform: cancel)
                .padding(.horizontal, 8).frame(height: 26)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            ClipCapsuleButton(title: confirm, symbol: nil, action: onConfirm)
            ClipCapsuleButton(title: T("취소", "Cancel"), symbol: nil, action: cancel)
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

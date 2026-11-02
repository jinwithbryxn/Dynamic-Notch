import AppKit
import SwiftUI

/// 이 Mac에만 저장하는 간단한 할 일 목록.
/// Return으로 추가, 체크한 항목은 하루 뒤 사라짐, 패널을 닫아도 입력 중인 글 유지, 최대 200개.
/// 권한·네트워크·백그라운드 작업이 없어 처음부터 켜져 있다.
final class TodoModule: NotchModule {
    let id = "todo"
    var title: String { T("할 일", "To-Do") }
    let symbol = "checklist.checked"
    let enabledByDefault = true

    let model = TodoModel()
    private var context: ModuleContext?

    func start(context: ModuleContext) {
        self.context = context
        model.load()
    }

    func stop() {
        model.save()
        context = nil
    }

    func tabView() -> AnyView? { AnyView(TodoTab(model: model, focusInput: { [weak self] in self?.context?.focusInput() })) }
    var tabContentSize: CGSize { CGSize(width: 420, height: 240) }

    func paletteActions() -> [PaletteAction] {
        let open = model.items.filter { $0.doneAt == nil }.count
        return [PaletteAction(id: "todo.open", title: T("할 일 열기", "Open To-Do"),
                              subtitle: open > 0 ? T("남은 할 일 \(open)개", "\(open) left") : nil, symbol: symbol,
                              keywords: ["todo", "to-do", "할 일", "할일", "checklist", "tasks"]) { [weak self] in
            self?.context?.openTab("todo")
        }]
    }

    /// "할 일 우유 사기", "todo buy milk"
    func paletteResults(for query: String) -> [PaletteAction] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard let p = ["할 일 ", "할일 ", "todo ", "to-do "].first(where: { q.lowercased().hasPrefix($0) }) else { return [] }
        let text = String(q.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        return [PaletteAction(id: "todo.add", title: T("할 일 추가: \(text)", "Add To-Do: \(text)"), symbol: "plus.circle") { [weak self] in
            if let err = self?.model.add(text) {
                self?.context?.notice(T("추가하지 못함", "Couldn't add"), err, symbol: "exclamationmark.triangle")
            } else {
                self?.context?.notice(T("할 일 추가함", "To-do added"), text, symbol: "checklist.checked", tab: "todo")
            }
        }]
    }

    func settingsView() -> AnyView? { AnyView(TodoSettings()) }

    func selfTest() -> [String] {
        let probe = TodoModel()
        probe.load()
        let now = Date()
        // 정리 규칙 검사 (메모리 안에서만)
        let sample = [TodoEntry(id: UUID(), text: "a", created: now, doneAt: nil),
                      TodoEntry(id: UUID(), text: "b", created: now, doneAt: now.addingTimeInterval(-3600)),
                      TodoEntry(id: UUID(), text: "c", created: now, doneAt: now.addingTimeInterval(-90_000))]
        let kept = TodoModel.pruned(sample, now: now).map(\.text).joined()
        let lines = TodoModel.checklistLines("- [ ] buy milk\n- [x] done\n☐ call mom\n* [ ] email Bob\nplain")
        return ["stored items: \(probe.items.count) (open \(probe.items.filter { $0.doneAt == nil }.count))",
                "store file: \(PIMFiles.folder.appendingPathComponent("todo.json").path)",
                "prune rule (keep open + checked < 24h): \(kept == "ab" ? "ok" : "FAIL \(kept)")",
                "memo checklist capture: \(lines)",
                "memo folder readable: \(FileManager.default.isReadableFile(atPath: MemoStore.folder.path))"]
    }
}

struct TodoEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var text: String
    var created: Date
    var doneAt: Date?
}

final class TodoModel: ObservableObject {
    static let limit = 200
    @Published private(set) var items: [TodoEntry] = []
    /// 입력 중인 글 (패널을 닫아도 유지)
    @Published var draft = ""
    @Published private(set) var removed: TodoEntry?
    @Published var message: String?
    private var undoWork: DispatchWorkItem?
    private var messageWork: DispatchWorkItem?
    private var loaded = false

    func load() {
        items = Self.pruned(PIMFiles.read([TodoEntry].self, "todo.json") ?? [], now: Date())
        loaded = true
    }

    func save() {
        guard loaded else { return }
        PIMFiles.write(items, "todo.json")
    }

    /// 체크한 지 하루가 지난 항목을 뺀다
    static func pruned(_ list: [TodoEntry], now: Date) -> [TodoEntry] {
        list.filter { e in e.doneAt.map { now.timeIntervalSince($0) < 86_400 } ?? true }
    }

    /// 보일 때마다 정리 (타이머 없이)
    func prune() {
        let p = Self.pruned(items, now: Date())
        if p.count != items.count { items = p; save() }
    }

    /// 성공하면 nil, 아니면 이유
    @discardableResult
    func add(_ text: String) -> String? {
        if !loaded { load() }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        prune()
        guard items.count < Self.limit else { return T("최대 \(Self.limit)개까지", "Up to \(Self.limit) items") }
        items.insert(TodoEntry(id: UUID(), text: t, created: Date(), doneAt: nil), at: 0)
        save()
        return nil
    }

    func toggle(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].doneAt = items[i].doneAt == nil ? Date() : nil
        save()
    }

    func delete(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        removed = items.remove(at: i)
        save()
        undoWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.removed = nil }
        undoWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    func undoDelete() {
        guard let r = removed else { return }
        items.insert(r, at: 0)
        removed = nil
        save()
    }

    // MARK: 빠른 메모의 체크 안 된 줄 가져오기 (M-D-014 보완)

    static func checklistLines(_ body: String) -> [String] {
        body.components(separatedBy: .newlines).compactMap { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            for prefix in ["- [ ] ", "* [ ] ", "[ ] ", "☐ ", "□ "] where s.hasPrefix(prefix) {
                let t = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return t.isEmpty ? nil : t
            }
            return nil
        }
    }

    /// 빠른 메모 파일을 읽기만 하고, 체크 안 된 체크리스트 줄을 할 일로 복사한다 (이미 있는 글은 건너뜀).
    func importFromMemos() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: MemoStore.folder, includingPropertiesForKeys: nil)) ?? []
        var found: [String] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url), let memo = try? JSONDecoder().decode(Memo.self, from: data) else { continue }
            found.append(contentsOf: Self.checklistLines(memo.title + "\n" + memo.body))
        }
        let existing = Set(items.map { $0.text })
        var added = 0
        for t in found where !existing.contains(t) && items.count < Self.limit {
            items.insert(TodoEntry(id: UUID(), text: t, created: Date(), doneAt: nil), at: 0)
            added += 1
        }
        if added > 0 { save() }
        flash(found.isEmpty ? T("메모에 체크 안 된 줄(- [ ] …)이 없음", "No unchecked lines (- [ ] …) in memos")
                            : T("\(added)개 가져옴", "Imported \(added)"))
    }

    func flash(_ text: String) {
        message = text
        messageWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.message = nil }
        messageWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}

private struct TodoTab: View {
    @ObservedObject var model: TodoModel
    let focusInput: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                TextField(T("할 일 입력 후 Return", "Type a to-do and press Return"), text: $model.draft)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .focused($focused)
                    .onSubmit {
                        if let err = model.add(model.draft) { model.flash(err) } else { model.draft = "" }
                    }
                    .accessibilityLabel(T("새 할 일", "New to-do"))
                Text("\(model.items.count)/\(TodoModel.limit)").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.35)).monospacedDigit()
                Menu {
                    Button(T("메모의 체크 안 된 줄 가져오기", "Import unchecked lines from Memos")) { model.importFromMemos() }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 12))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(T("더 보기", "More"))
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))

            if let r = model.removed {
                HStack {
                    Text(T("'\(r.text)' 지움", "Deleted '\(r.text)'")).font(.system(size: 10.5)).lineLimit(1)
                    Spacer()
                    Button(T("되돌리기", "Undo")) { model.undoDelete() }.buttonStyle(PIMPillStyle())
                }
            } else if let m = model.message {
                Text(m).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.7))
            }

            if model.items.isEmpty {
                PIMEmptyState(symbol: "checklist", title: T("할 일 없음", "Nothing to do"),
                              detail: T("체크한 항목은 하루 뒤 자동으로 사라짐 · 이 Mac에만 저장", "Checked items disappear after a day · stored only on this Mac"))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.items) { item in
                            HStack(spacing: 8) {
                                Button { model.toggle(item.id) } label: { PIMCheckCircle(checked: item.doneAt != nil) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(item.doneAt == nil ? T("\(item.text) 완료", "Complete \(item.text)") : T("\(item.text) 완료 취소", "Uncheck \(item.text)"))
                                Text(item.text).font(.system(size: 12)).lineLimit(2)
                                    .strikethrough(item.doneAt != nil)
                                    .foregroundStyle(item.doneAt != nil ? Color.white.opacity(0.4) : .white)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button(T("삭제", "Delete")) { model.delete(item.id) }
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            model.prune()
            focusInput()
            DispatchQueue.main.async { focused = true }
        }
    }
}

private struct TodoSettings: View {
    var body: some View {
        PIMSettingsGroup(title: T("할 일", "To-Do")) {
            Text(T("이 Mac에만 저장하고 동기화하지 않습니다. 최대 200개, 체크한 항목은 하루 뒤 자동으로 사라집니다.",
                   "Stored only on this Mac and never synced. Up to 200 items; checked items disappear after a day."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(T("빠른 메모의 '- [ ] 할 일' 줄은 탭의 ⋯ 메뉴에서 가져올 수 있습니다.", "Unchecked '- [ ] item' lines from Quick Notes can be imported from the tab's ⋯ menu."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

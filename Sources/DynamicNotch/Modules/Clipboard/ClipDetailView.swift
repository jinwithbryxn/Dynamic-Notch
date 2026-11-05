import AppKit
import SwiftUI

/// 항목 자세히 보기: 전체 내용(선택·복사 가능), 묶음 조각, 이미지와 인식한 글자, 파일 목록, 제목 붙이기
struct ClipDetailView: View {
    let module: ClipboardModule
    @ObservedObject var store: ClipStore
    @ObservedObject var ui: ClipUIState
    let item: ClipItem
    let back: () -> Void

    @State private var titleDraft = ""
    @State private var preview: NSImage?
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            actionBar
        }
        .onAppear {
            titleDraft = item.title ?? ""
            if item.kind == .image, let data = store.imageData(for: item) { preview = ClipStore.downsample(data, maxPixel: 900) }
        }
        .onExitCommand(perform: back)
    }

    // MARK: 머리

    private var header: some View {
        HStack(spacing: 7) {
            ClipIconButton(symbol: "chevron.left", help: T("목록으로 (Esc)", "Back (Esc)"), action: back)
            ClipThumb(store: store, item: item, size: 24)
            TextField(T("제목 붙이기", "Add a title"), text: $titleDraft)
                .textFieldStyle(.plain).font(.island(.subhead, .semibold))
                .focused($titleFocused)
                .onSubmit(saveTitle)
                .onChange(of: titleFocused) { _, focused in if !focused { saveTitle() } }
                .onExitCommand { saveTitle(); back() }
                .accessibilityLabel(T("항목 제목", "Item title"))
            Spacer(minLength: 4)
            Text(meta).font(.island(.caption)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            ClipIconButton(symbol: item.isPinned ? "pin.fill" : "pin", help: item.isPinned ? T("고정 해제", "Unpin") : T("고정", "Pin"),
                           active: item.isPinned) { store.update(item.id) { $0.pinned = !item.isPinned } }
            ClipIconButton(symbol: "trash", help: T("삭제", "Delete")) { store.remove(item.id); back() }
        }
        .frame(height: 26)
    }

    private var meta: String {
        var parts: [String] = []
        if let app = item.appName { parts.append(app) }
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isEnglish ? "en_US" : "ko_KR")
        f.dateStyle = .short
        f.timeStyle = .short
        parts.append(f.string(from: item.date))
        if let t = item.text, item.kind != .image { parts.append(T("\(t.count)자", "\(t.count) chars")) }
        return parts.joined(separator: " · ")
    }

    private func saveTitle() {
        let t = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let new: String? = t.isEmpty ? nil : t
        if new != item.title { store.update(item.id) { $0.title = new } }
    }

    // MARK: 내용

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .image: imageContent
        case .file: fileContent
        case .burst: burstContent
        case .color: colorContent
        default: textContent(item.text ?? "", mono: item.kind == .link)
        }
    }

    private func textContent(_ text: String, mono: Bool) -> some View {
        ScrollView {
            Text(text.count > 20_000 ? String(text.prefix(20_000)) + "\n…" : text)
                .font(.system(size: 12, design: mono ? .monospaced : .default))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
        }
    }

    private var imageContent: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let preview {
                    Image(nsImage: preview).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo").font(.island(.largeTitle)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 220)
            .frame(maxHeight: .infinity)
            .padding(8)
            VStack(alignment: .leading, spacing: 6) {
                Text(T("이미지 속 글자 (기기 안에서 인식)", "Text in image (recognized on this Mac)"))
                    .font(.island(.footnote, .semibold)).foregroundStyle(.white.opacity(0.6))
                if ui.ocrRunning.contains(item.id) {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text(T("인식 중…", "Recognizing…")).font(.island(.subhead)) }
                } else if let ocr = item.ocrText {
                    if ocr.isEmpty {
                        Text(T("글자를 찾지 못함", "No text found")).font(.island(.subhead)).foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            Text(ocr).font(.island(.subhead)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    ClipCapsuleButton(title: T("글자 인식", "Recognize Text"), symbol: "text.viewfinder") { module.runOCR(item.id) }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8).padding(.trailing, 8)
        }
    }

    private var fileContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(item.paths ?? [], id: \.self) { path in
                    let exists = FileManager.default.fileExists(atPath: path)
                    HStack(spacing: 8) {
                        if exists {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 22, height: 22)
                        } else {
                            Image(systemName: "doc.questionmark").frame(width: 22, height: 22).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text((path as NSString).lastPathComponent).font(.island(.subhead)).lineLimit(1)
                            Text(exists ? path : T("파일이 옮겨졌거나 없음 · \(path)", "Moved or missing · \(path)"))
                                .font(.island(.caption)).foregroundStyle(.white.opacity(0.45)).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if exists {
                            ClipIconButton(symbol: "folder", help: T("Finder에서 보기", "Show in Finder"), small: true) {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            }
                        }
                    }
                }
            }
            .padding(9)
        }
    }

    private var burstContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array((item.parts ?? []).enumerated()), id: \.offset) { i, part in
                    HStack(spacing: 8) {
                        Text("\(i + 1)").font(.island(.caption)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.4)).frame(width: 14)
                        Text(ClipItem.firstLine(part)).font(.island(.subhead)).lineLimit(1).textSelection(.enabled)
                        Spacer()
                        ClipIconButton(symbol: "doc.on.doc", help: T("이 조각 복사", "Copy this part"), small: true) {
                            module.copyText(part, flash: item.id)
                        }
                    }
                    .frame(height: 26)
                }
            }
            .padding(9)
        }
    }

    private var colorContent: some View {
        HStack(alignment: .top, spacing: 12) {
            if let c = ClipColors.parse(item.text ?? "") {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: ClipColors.nsColor(c)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.25)))
                    .frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ClipColorFormat.allCases) { f in
                        let s = ClipColors.format(c, f)
                        HStack(spacing: 8) {
                            Text(f.label).font(.island(.caption, .semibold)).foregroundStyle(.white.opacity(0.5)).frame(width: 52, alignment: .leading)
                            Text(s).font(.island(.subhead, .medium, design: .monospaced)).textSelection(.enabled).lineLimit(1)
                            Spacer()
                            ClipIconButton(symbol: "doc.on.doc", help: T("\(f.label) 복사", "Copy \(f.label)"), small: true) { module.copyText(s, flash: item.id) }
                        }
                    }
                }
            }
        }
        .padding(10)
    }

    // MARK: 동작 줄

    private var actionBar: some View {
        let actions = module.smartActions(for: item).filter { !$0.id.hasPrefix("color.") }
        return HStack(spacing: 6) {
            ClipCapsuleButton(title: item.kind == .burst ? (ui.prefs.pasteOnSelect ? T("모두 붙여넣기", "Paste All") : T("모두 복사", "Copy All"))
                                                         : (ui.prefs.pasteOnSelect ? T("붙여넣기", "Paste") : T("복사", "Copy")), symbol: "arrow.down.doc") {
                module.use(item, paste: true)
            }
            if ui.prefs.pasteOnSelect {
                ClipCapsuleButton(title: T("복사만", "Copy Only"), symbol: "doc.on.doc") { module.use(item, paste: false) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(actions) { a in ClipCapsuleButton(title: a.title, symbol: a.symbol, action: a.run) }
                }
            }
            if ui.flashID == item.id {
                Text(T("복사함", "Copied")).font(.island(.caption))
                    .padding(.horizontal, 7).frame(height: 18).background(Color.green.opacity(0.35), in: Capsule())
            }
        }
        .frame(height: 26)
    }
}

import AppKit
import SwiftUI

/// 동영상 URL 저장: 사용자가 Homebrew 등으로 설치한 yt-dlp가 있을 때만, 링크를 받아 다운로드 폴더에 저장한다.
/// 실행 파일을 내려받지 않는다. 없으면 설치 방법만 안내한다.
final class VideoSaverModule: NotchModule, ObservableObject {
    let id = "videosaver"
    var title: String { T("동영상 저장", "Save Video") }
    let symbol = "arrow.down.circle"
    var enabledByDefault: Bool { false }

    enum Format: String, CaseIterable, Identifiable {
        case best, small, audio
        var id: String { rawValue }
        var title: String {
            switch self {
            case .best: return T("최고 화질", "Best")
            case .small: return T("작은 사본", "Small")
            case .audio: return T("오디오만", "Audio only")
            }
        }
        /// ffmpeg가 있으면 영상·음성을 합치고, 없으면 한 파일로 된 형식만 고른다
        func args(ffmpeg: Bool) -> [String] {
            switch self {
            case .best: return ffmpeg ? ["-f", "bv*+ba/b", "--merge-output-format", "mp4/mkv"] : ["-f", "b"]
            case .small: return ffmpeg ? ["-f", "bv*[height<=480]+ba/b[height<=480]/w", "--merge-output-format", "mp4/mkv"] : ["-f", "b[height<=480]/w"]
            case .audio: return ["-f", "ba[ext=m4a]/ba"]
            }
        }
    }

    @Published var progress: Double?
    @Published var detail = ""
    @Published var running = false
    @Published var lastFile: URL?
    @Published var error: String?

    fileprivate var context: ModuleContext?
    private var process: LaunchProcess?

    var ytdlp: String? { LaunchSystem.findExecutable("yt-dlp") }
    var ffmpeg: String? { LaunchSystem.findExecutable("ffmpeg") }
    var downloads: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads") }

    func start(context: ModuleContext) { self.context = context }
    func stop() {
        cancel()
        context = nil
    }

    func tabView() -> AnyView? { AnyView(VideoSaverTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 480, height: 150) }

    /// yt-dlp 인자 (주소는 "--" 뒤에 둬서 옵션으로 해석되지 않게 한다)
    func arguments(url: URL, format: Format) -> [String] {
        let template = downloads.path + "/%(title).120B [%(id)s].%(ext)s"
        return ["--newline", "--progress", "--no-playlist", "--no-mtime",
                "--progress-template", "download:DMN %(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
                "--print", "after_move:filepath", "-o", template]
            + format.args(ffmpeg: ffmpeg != nil) + ["--", url.absoluteString]
    }

    func download(_ text: String, format: Format) {
        guard let exe = ytdlp else { return }
        guard let url = LaunchSystem.webURL(from: text) else { error = T("http(s) 동영상 링크를 넣기", "Enter an http(s) video link"); return }
        cancel()
        error = nil
        lastFile = nil
        progress = 0
        detail = T("시작하는 중…", "Starting…")
        running = true
        let p = LaunchProcess()
        process = p
        var printedPath: String?
        p.run(exe, arguments(url: url, format: format), onLine: { [weak self] line in
            guard let self else { return }
            if line.hasPrefix("DMN ") {
                let parts = line.dropFirst(4).split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                if let pct = Double(parts.first?.replacingOccurrences(of: "%", with: "") ?? "") { self.progress = pct / 100 }
                self.detail = [parts.count > 1 ? parts[1] : "", parts.count > 2 ? T("남은 시간 ", "ETA ") + parts[2] : ""].filter { !$0.isEmpty }.joined(separator: " · ")
            } else if line.hasPrefix("/") {
                printedPath = line
            }
        }) { [weak self] r in
            guard let self, self.process === p else { return }
            self.process = nil
            self.running = false
            if r.status == 0, let path = printedPath ?? r.out.split(separator: "\n").last.map(String.init), path.hasPrefix("/") {
                let file = URL(fileURLWithPath: path)
                self.lastFile = file
                self.progress = 1
                self.detail = file.lastPathComponent
                self.context?.notice(T("동영상 저장함", "Video saved"), file.lastPathComponent, symbol: "arrow.down.circle.fill", actions: [
                    ActivityAction(id: "reveal", title: T("Finder에서 보기", "Show in Finder"), role: .primary) {
                        NSWorkspace.shared.activateFileViewerSelecting([file])
                    },
                ])
            } else if r.status == 15 || r.status == -15 {
                self.progress = nil
                self.detail = T("취소함", "Cancelled")
            } else {
                self.progress = nil
                let msg = r.err.split(separator: "\n").last { $0.contains("ERROR") }.map(String.init) ?? r.err.split(separator: "\n").last.map(String.init) ?? ""
                self.error = T("저장 실패: ", "Failed: ") + String(msg.prefix(160))
            }
        }
    }

    func cancel() {
        process?.cancel()
        process = nil
        if running { detail = T("취소함", "Cancelled") }
        running = false
    }

    func selfTest() -> [String] {
        var out = ["yt-dlp: \(ytdlp ?? "not found -> tab shows install hint (brew install yt-dlp)")",
                   "ffmpeg: \(ffmpeg ?? "not found -> single-file formats only")"]
        if let exe = ytdlp {
            let r = LaunchProcess.runSync(exe, ["--version"], timeout: 10)
            out.append("yt-dlp --version: \(r.out.trimmingCharacters(in: .whitespacesAndNewlines)) (exit \(r.status))")
        }
        if let u = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ") {
            out.append("args(audio): " + arguments(url: u, format: .audio).suffix(4).joined(separator: " "))
        }
        out.append("rejects non-URL: \(LaunchSystem.webURL(from: "--exec rm") == nil ? "yes" : "NO")")
        out.append("save folder: \(downloads.path)")
        out.append("download started in self test: no")
        return out
    }
}

private struct VideoSaverTab: View {
    @ObservedObject var module: VideoSaverModule
    @State private var text = ""
    @State private var format: VideoSaverModule.Format = .best
    @FocusState private var focused: Bool

    var body: some View {
        if module.ytdlp == nil {
            LaunchUnsupportedView(title: T("yt-dlp가 없음", "yt-dlp not found"),
                                  reason: T("동영상 저장은 직접 설치한 yt-dlp를 씀 (앱이 실행 파일을 내려받지 않음)", "Saving videos uses a yt-dlp you install yourself (the app never downloads executables)"),
                                  alternative: T("터미널에서 brew install yt-dlp ffmpeg 후 이 탭을 다시 열기", "Run brew install yt-dlp ffmpeg in Terminal, then reopen this tab"),
                                  symbol: "arrow.down.circle")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                LaunchField(placeholder: T("동영상 링크 붙여넣기", "Paste a video link"), text: $text, symbol: "link", focus: $focused) {
                    module.download(text, format: format)
                }
                HStack(spacing: 6) {
                    ForEach(VideoSaverModule.Format.allCases) { f in
                        LaunchChip(title: f.title, selected: format == f) { format = f }
                    }
                    Spacer()
                    if module.running {
                        LaunchChip(title: T("취소", "Cancel"), symbol: "xmark") { module.cancel() }
                    } else {
                        LaunchChip(title: T("저장", "Save"), symbol: "arrow.down") { module.download(text, format: format) }
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if let p = module.progress {
                    ProgressView(value: min(max(p, 0), 1)).tint(.white).controlSize(.small)
                }
                Text(module.error ?? (module.detail.isEmpty ? T("다운로드 폴더에 저장 · ffmpeg ", "Saves to Downloads · ffmpeg ") + (module.ffmpeg != nil ? T("있음", "found") : T("없음(합치기 없이 저장)", "missing (no merging)")) : module.detail))
                    .font(.island(.footnote)).foregroundStyle(module.error != nil ? Color.red.opacity(0.85) : LaunchUI.secondary).lineLimit(2)
                if let f = module.lastFile {
                    LaunchChip(title: T("Finder에서 보기", "Show in Finder"), symbol: "folder") { NSWorkspace.shared.activateFileViewerSelecting([f]) }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .onAppear {
                module.context?.focusInput()
                DispatchQueue.main.async { focused = true }
            }
        }
    }
}

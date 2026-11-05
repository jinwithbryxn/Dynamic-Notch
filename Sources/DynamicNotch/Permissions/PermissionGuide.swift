import AppKit
import SwiftUI

/// '차례로 허용' 진행 막대. 권한 화면과 확장 기능 화면 위쪽에 놓는다.
/// 진행 중이면 지금 묻는 권한과 할 일을, 끝난 뒤 다시 시작해야 반영되는 권한이 있으면 다시 시작 버튼을 보여 준다.
struct PermissionWalkthroughBar: View {
    @ObservedObject var manager = PermissionsManager.shared

    var body: some View {
        if let kind = manager.walkthroughCurrent {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol).frame(width: 20).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(T("차례로 허용 \(manager.walkthroughStep)/\(manager.walkthroughTotal) · \(kind.title)",
                           "Allowing \(manager.walkthroughStep)/\(manager.walkthroughTotal) · \(kind.title)"))
                        .font(.callout.weight(.semibold))
                    Text(PermissionGuideText.instruction(for: kind))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(T("건너뛰기", "Skip")) { manager.skipStep() }
                Button(T("그만", "Stop")) { manager.cancelWalkthrough() }
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        } else if !relaunchKinds.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise").frame(width: 20).foregroundStyle(Color.accentColor)
                Text(T("\(relaunchKinds.map(\.title).joined(separator: ", ")) 권한은 앱을 다시 시작해야 반영됩니다.",
                       "\(relaunchKinds.map(\.title).joined(separator: ", ")) takes effect after restarting the app."))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(T("앱 다시 시작", "Restart App")) { manager.relaunch() }
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var relaunchKinds: [PermissionKind] {
        PermissionKind.allCases.filter { $0.needsRelaunch && manager.walkthroughGranted.contains($0) }
    }
}

enum PermissionGuideText {
    /// 이 앱이 시스템 설정 목록에 보이는 이름 (검토용 앱은 이름이 다르다)
    static var appName: String { FileManager.default.displayName(atPath: Bundle.main.bundlePath) }

    static func instruction(for kind: PermissionKind) -> String {
        switch kind {
        case .fullDisk:
            return T("열린 시스템 설정 목록에서 '\(appName)' 스위치를 켜 주세요. 목록에 없으면 + 버튼을 눌러 응용 프로그램 폴더에서 고릅니다. 켜지면 다음으로 넘어갑니다.",
                     "In the System Settings list that opened, turn on '\(appName)'. If it isn't listed, click + and pick it from Applications. It moves on once it's on.")
        case .systemAudio where kind.grantedInSettings || PermissionsManager.shared.status(kind) == .denied:
            return T("열린 화면 아래쪽 '시스템 오디오 녹음만' 목록에서 '\(appName)' 스위치를 켜 주세요. 위쪽 '화면 및 시스템 오디오 녹음' 목록과는 따로 허용합니다.",
                     "Turn on '\(appName)' in the 'System Audio Recording Only' list at the bottom. It is separate from the 'Screen & System Audio Recording' list above it.")
        case .screenRecording, .inputMonitoring:
            return T("열린 시스템 설정 목록에서 '\(appName)' 스위치를 켜 주세요. 목록에 없으면 + 버튼을 눌러 응용 프로그램 폴더에서 고릅니다. 켜지면 다음으로 넘어가고, 앱을 다시 시작해야 반영됩니다.",
                     "In the System Settings list that opened, turn on '\(appName)'. If it isn't listed, click + and pick it from Applications. It moves on once it's on; restart the app for it to take effect.")
        case _ where kind.grantedInSettings:
            return T("열린 시스템 설정 목록에서 '\(appName)' 스위치를 켜 주세요. 켜지면 다음으로 넘어갑니다.",
                     "In the System Settings list that opened, turn on '\(appName)'. It moves on once it's on.")
        case .automation:
            return T("뜬 허용 창에 답해 주세요. Music이나 Spotify가 꺼져 있으면 물을 수 없어 건너뜁니다.",
                     "Answer the prompt that appeared. If Music or Spotify isn't running it can't be asked, so it's skipped.")
        default:
            return T("뜬 허용 창에 답해 주세요. 답하면 다음으로 넘어갑니다. 예전에 거부했다면 열린 시스템 설정에서 켜 주세요.",
                     "Answer the prompt that appeared; it moves on once you answer. If you denied it before, turn it on in the System Settings that opened.")
        }
    }
}

/// 시스템 설정에서 직접 켜야 하는 권한을 기다리는 동안 화면 오른쪽 위에 떠 있는 작은 안내 창.
/// 시스템 설정이 앞으로 와 설정 창이 가려져도 할 일과 건너뛰기가 보이게 한다.
final class PermissionGuidePanel {
    static let shared = PermissionGuidePanel()
    private var panel: NSPanel?
    private var host: NSView?

    /// 차례가 바뀔 때마다 불린다. 지금 권한을 시스템 설정에서 켜야 할 때만 띄운다.
    func update() {
        guard AppSettings.isHelper, PermissionsManager.shared.walkthroughInSettings else {
            panel?.orderOut(nil)
            return
        }
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        if !panel.isVisible { place(panel) }
        panel.orderFrontRegardless()
        // 안내 글 길이가 권한마다 달라, 내용이 바뀐 뒤 오른쪽 위를 기준으로 크기를 맞춘다
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, let host = self.host else { return }
            let top = panel.frame.maxY
            panel.setContentSize(host.fittingSize)
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: top - panel.frame.height))
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
                            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
                            backing: .buffered, defer: true)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: PermissionWalkthroughBar().padding(10).frame(width: 360))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        self.host = host
        return panel
    }

    /// 마우스가 있는 화면 오른쪽 위에 놓는다 (시스템 설정 창은 보통 가운데에 열린다).
    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let v = screen.visibleFrame, size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: v.maxX - size.width - 16, y: v.maxY - size.height - 16))
    }
}

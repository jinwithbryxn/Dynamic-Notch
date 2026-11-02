import AppKit
import SwiftUI

/// 화면 테두리를 잠깐 부드럽게 빛낸다 (배터리 부족·완충 알림). 클릭은 아래로 통과하고 1.8초 뒤 창을 닫는다.
enum SysScreenGlow {
    private static var windows: [NSWindow] = []

    static func flash(_ color: NSColor) {
        dismiss()
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: GlowView(color: Color(nsColor: color), pulses: reduce ? 1 : 2))
            w.alphaValue = 1
            w.orderFrontRegardless()
            windows.append(w)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { dismiss() }
    }

    static func dismiss() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private struct GlowView: View {
        let color: Color
        let pulses: Int
        @State private var on = false

        var body: some View {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(color, lineWidth: 10)
                .blur(radius: 14)
                .opacity(on ? 0.85 : 0)
                .ignoresSafeArea()
                .onAppear {
                    // 켜짐·꺼짐을 번갈아 pulses번 (마지막은 꺼진 상태)
                    for step in 0..<(pulses * 2) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42 * Double(step)) {
                            withAnimation(.easeInOut(duration: 0.4)) { on = step % 2 == 0 }
                        }
                    }
                }
        }
    }
}

import AppKit
import SwiftUI

/// 확장 기능 개발·검증용 명령줄 모드. 앱 창을 띄우지 않고 결과를 출력한 뒤 끝난다.
///
///   --list-modules                         기능 목록
///   --module-selftest=<id|all>             기능 자체 검사 (실제 macOS 기능 호출)
///   --render-tab=<id> --out=<png> [--start] [--wait=<초>] [--size=<폭>x<높이>]
///                                          탭 화면을 노치 모양 배경에 그려 PNG로 저장 (화면 녹화 권한 불필요)
enum ModuleDevTools {
    static func handle(_ arguments: [String]) {
        func value(_ name: String) -> String? {
            arguments.first { $0.hasPrefix("--\(name)=") }.map { String($0.dropFirst(name.count + 3)) }
        }
        if arguments.contains("--list-modules") {
            for m in ModuleCatalog.makeAll() {
                print("\(m.id)\t\(m.title)\tdefault=\(m.enabledByDefault ? "on" : "off")\ttab=\(m.tabView() != nil)\tsize=\(Int(m.tabContentSize.width))x\(Int(m.tabContentSize.height))")
            }
            exit(0)
        }
        if let id = value("module-selftest") {
            AppSettings.isHelper = true
            let modules = ModuleCatalog.makeAll().filter { id == "all" || $0.id == id }
            if modules.isEmpty { print("unknown module: \(id)"); exit(2) }
            for m in modules {
                print("== \(m.id)")
                for line in m.selfTest() { print("  \(line)") }
            }
            exit(0)
        }
        if let id = value("render-tab"), let out = value("out") {
            AppSettings.isHelper = true
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            guard let m = ModuleCatalog.makeAll().first(where: { $0.id == id }), let view = m.tabView() else {
                print("unknown module or no tab: \(id)"); exit(2)
            }
            if arguments.contains("--start") {
                m.start(context: ModuleContext(center: ActivityCenter(), openTab: { _ in }, collapse: {}, focusInput: {}))
            }
            var size = m.tabContentSize
            if let s = value("size"), let x = s.split(separator: "x").map({ Double($0) ?? 0 }) as [Double]?, x.count == 2 {
                size = CGSize(width: x[0], height: x[1])
            }
            let wait = Double(value("wait") ?? "") ?? 1.0
            render(view, contentSize: size, wait: wait, to: URL(fileURLWithPath: out))
            if arguments.contains("--start") { m.stop() }
            exit(0)
        }
    }

    /// 확장 패널과 같은 여백·배경(검은 둥근 사각형, 어두운 화면 모드)으로 그린다.
    private static func render(_ content: AnyView, contentSize: CGSize, wait: TimeInterval, to url: URL) {
        let pad: CGFloat = 30
        let size = CGSize(width: contentSize.width + 2 * pad, height: contentSize.height + 2 * pad)
        let root = content
            .frame(width: contentSize.width, height: contentSize.height)
            .padding(pad)
            .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Color.black))
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: AnyView(root))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        // onAppear·비동기 로딩이 끝나도록 잠깐 돌린다
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("render failed"); exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { print("encode failed"); exit(1) }
        do {
            try png.write(to: url)
            print("rendered \(Int(size.width))x\(Int(size.height)) -> \(url.path)")
        } catch {
            print("write failed: \(error.localizedDescription)"); exit(1)
        }
    }
}

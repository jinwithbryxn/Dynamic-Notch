import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 비공개 CGS 함수로 Space 목록만 읽는다 (dlsym으로 격리, 없으면 지원 안 됨).
enum SpacesReader {
    typealias MainConnection = @convention(c) () -> Int32
    typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    struct Space: Identifiable, Hashable {
        let id: UInt64
        let uuid: String
        let fullscreen: Bool
        let appName: String?
    }
    struct Display: Identifiable { let id: String; let spaces: [Space]; let current: UInt64 }

    private static let handle = dlopen(nil, RTLD_NOW)
    private static let mainConnection: MainConnection? = sym("CGSMainConnectionID")
    private static let copySpaces: CopyDisplaySpaces? = sym("CGSCopyManagedDisplaySpaces")

    private static func sym<T>(_ name: String) -> T? {
        guard let h = handle, let p = dlsym(h, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    static var available: Bool { mainConnection != nil && copySpaces != nil }

    static func displays() -> [Display]? {
        guard let mainConnection, let copySpaces, let arr = copySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]] else { return nil }
        return arr.map { d in
            let current = ((d["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.uint64Value ?? 0
            let spaces = (d["Spaces"] as? [[String: Any]] ?? []).map { s -> Space in
                let id = (s["ManagedSpaceID"] as? NSNumber)?.uint64Value ?? 0
                let type = (s["type"] as? NSNumber)?.intValue ?? 0
                let tiles = ((s["TileLayoutManager"] as? [String: Any])?["TileSpaces"] as? [[String: Any]]) ?? []
                return Space(id: id, uuid: s["uuid"] as? String ?? "\(id)", fullscreen: type == 4, appName: tiles.first?["appName"] as? String)
            }
            return Display(id: d["Display Identifier"] as? String ?? "?", spaces: spaces, current: current)
        }
    }
}

/// Spaces: 현재 화면의 데스크톱 목록과 위치, 이름 붙이기, 눌러서 전환(Mission Control의 ⌃←/⌃→ 단축키를 보냄).
/// 목록은 비공개 CGS 함수로 읽어 격리했고, 전환은 키 입력이라 손쉬운 사용 권한이 필요하다. 기본 꺼짐.
final class SpacesModule: NotchModule, ObservableObject {
    let id = "spaces"
    var title: String { T("데스크톱", "Spaces") }
    let symbol = "square.split.2x1"
    var enabledByDefault: Bool { false }

    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }
    fileprivate var context: ModuleContext?
    private var observer: NSObjectProtocol?
    @Published private(set) var displays: [SpacesReader.Display] = []

    var names: [String: String] {
        guard let d = defaults.data("names"), let m = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        return m
    }
    func setName(_ name: String, for uuid: String) {
        var m = names
        m[uuid] = name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name
        defaults.set(try? JSONEncoder().encode(m), "names")
    }
    var announce: Bool { defaults.bool("announce", default: true) }

    func start(context: ModuleContext) {
        self.context = context
        refresh()
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.refresh()
            if self.announce, let cur = self.currentOnMain() {
                self.context?.notice(self.label(cur.1, index: cur.0), nil, symbol: cur.1.fullscreen ? "arrow.up.left.and.arrow.down.right" : "square.split.2x1", duration: 1.5)
            }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        context = nil
    }

    func refresh() { displays = SpacesReader.displays() ?? [] }

    func tabView() -> AnyView? { AnyView(SpacesTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 480, height: 130) }

    func label(_ s: SpacesReader.Space, index: Int) -> String {
        if let n = names[s.uuid] { return n }
        if s.fullscreen { return s.appName ?? T("전체 화면", "Full screen") }
        return T("데스크톱 \(index + 1)", "Desktop \(index + 1)")
    }

    /// 마우스가 있는 화면의 현재 Space (번호, Space)
    func currentOnMain() -> (Int, SpacesReader.Space)? {
        for d in displays {
            if let i = d.spaces.firstIndex(where: { $0.id == d.current }) { return (i, d.spaces[i]) }
        }
        return nil
    }

    /// 같은 화면의 다른 Space로: ⌃← / ⌃→를 필요한 만큼 보낸다 (사용자가 누른 경우만)
    func switchTo(_ target: SpacesReader.Space, in display: SpacesReader.Display) {
        guard let from = display.spaces.firstIndex(where: { $0.id == display.current }),
              let to = display.spaces.firstIndex(where: { $0.id == target.id }), from != to else { return }
        step(to - from)
    }

    func step(_ delta: Int) {
        guard LaunchSystem.axTrusted else {
            context?.notice(T("손쉬운 사용 권한 필요", "Accessibility permission needed"), T("Space 전환 키를 보내려면 허용", "Allow it to send the Space switching keys"),
                            symbol: "hand.raised", actions: [ActivityAction(id: "ax", title: T("권한 요청", "Request"), role: .primary) { LaunchSystem.requestAX() }])
            return
        }
        context?.collapse()
        let key = CGKeyCode(delta > 0 ? kVK_RightArrow : kVK_LeftArrow)
        for i in 0..<min(abs(delta), 16) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i) * 0.35) {
                let src = CGEventSource(stateID: .hidSystemState)
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
                    e?.flags = [.maskControl, .maskSecondaryFn]
                    e?.post(tap: .cghidEventTap)
                }
            }
        }
    }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "spaces.prev", title: T("이전 데스크톱", "Previous Space"), subtitle: "⌃←", symbol: "arrow.left.square",
                       keywords: ["space", "desktop", "데스크톱", "스페이스"]) { [weak self] in self?.step(-1) },
         PaletteAction(id: "spaces.next", title: T("다음 데스크톱", "Next Space"), subtitle: "⌃→", symbol: "arrow.right.square",
                       keywords: ["space", "desktop", "데스크톱", "스페이스"]) { [weak self] in self?.step(1) }]
    }

    func settingsView() -> AnyView? {
        AnyView(VStack(alignment: .leading, spacing: 6) {
            Toggle(T("Space가 바뀌면 노치에 이름 표시", "Show the Space name in the notch when it changes"), isOn: Binding(
                get: { ModuleDefaults(module: "spaces").bool("announce", default: true) },
                set: { ModuleDefaults(module: "spaces").set($0, "announce") }))
            Text(T("목록은 macOS 비공개 함수로 읽습니다(없으면 지원 안 됨). 전환은 시스템 설정 > 키보드 > 단축키 > Mission Control의 '왼쪽/오른쪽으로 이동' 단축키(⌃←/⌃→)가 켜져 있어야 하고 손쉬운 사용 권한이 필요합니다. 홈 카드와 알약 스와이프 전환은 아직 없습니다.",
                   "The list is read with private macOS functions (unsupported if missing). Switching needs the Mission Control 'Move left/right a space' shortcuts (⌃←/⌃→) and Accessibility access. A Home card and pill swipes are not available yet."))
                .font(.caption).foregroundStyle(.secondary)
        })
    }

    func selfTest() -> [String] {
        var out = ["CGS functions: \(SpacesReader.available ? "found" : "missing -> unsupported")"]
        refresh()
        for d in displays {
            let list = d.spaces.enumerated().map { i, s in (s.id == d.current ? "*" : "") + label(s, index: i) }
            out.append("display \(d.id.prefix(8)): \(list.joined(separator: " | "))")
        }
        out.append("accessibility (needed to switch): \(LaunchSystem.axTrusted)")
        out.append("keys sent in self test: no")
        return out
    }
}

private struct SpacesTab: View {
    @ObservedObject var module: SpacesModule
    @State private var editing: String?
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if !SpacesReader.available {
            LaunchUnsupportedView(title: T("Space 목록을 읽을 수 없음", "Can't read Spaces"),
                                  reason: T("이 macOS에서 비공개 CGS 함수를 찾지 못함", "The private CGS functions are missing on this macOS"),
                                  alternative: T("대안: Mission Control(F3) 또는 ⌃←/⌃→", "Alternative: Mission Control (F3) or ⌃←/⌃→"))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(module.displays) { d in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(d.spaces.enumerated()), id: \.element.id) { i, s in
                                Button { module.switchTo(s, in: d) } label: {
                                    VStack(spacing: 3) {
                                        Image(systemName: s.fullscreen ? "arrow.up.left.and.arrow.down.right" : "rectangle")
                                            .font(.island(.title3))
                                        Text(module.label(s, index: i)).font(.island(.footnote)).lineLimit(1)
                                    }
                                    .frame(width: 86, height: 52)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(s.id == d.current ? Color.white.opacity(0.25) : LaunchUI.fill))
                                }
                                .buttonStyle(.plain)
                                .help(s.id == d.current ? T("지금 Space", "Current Space") : T("이 Space로 전환", "Switch to this Space"))
                                .accessibilityLabel(module.label(s, index: i))
                                .contextMenu {
                                    Button(T("이름 바꾸기", "Rename")) { editing = s.uuid; draft = module.names[s.uuid] ?? "" }
                                    if module.names[s.uuid] != nil { Button(T("이름 지우기", "Clear name")) { module.setName("", for: s.uuid); module.refresh() } }
                                }
                            }
                        }
                    }
                }
                if let uuid = editing {
                    HStack {
                        LaunchField(placeholder: T("Space 이름", "Space name"), text: $draft, symbol: "pencil", focus: $focused) {
                            module.setName(draft, for: uuid); editing = nil; module.refresh()
                        }
                        LaunchChip(title: T("저장", "Save")) { module.setName(draft, for: uuid); editing = nil; module.refresh() }
                    }
                    .onAppear { module.context?.focusInput(); DispatchQueue.main.async { focused = true } }
                } else {
                    Text(T("눌러서 전환 · 오른쪽 클릭으로 이름 바꾸기 · 전환은 ⌃←/⌃→ 단축키를 씀", "Click to switch · right-click to rename · uses the ⌃←/⌃→ shortcuts"))
                        .font(.island(.caption)).foregroundStyle(LaunchUI.secondary)
                }
            }
            .foregroundStyle(.white)
            .onAppear { module.refresh() }
        }
    }
}

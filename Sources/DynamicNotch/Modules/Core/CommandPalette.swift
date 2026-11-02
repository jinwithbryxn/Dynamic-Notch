import SwiftUI

/// 확장 패널 아래에 떠 있는 독: 홈 페이지 점 · 고정한 확장 기능 탭 · 검색(명령 팔레트).
/// 다이나믹 아일랜드처럼 본체와 떨어진 작은 캡슐로 그린다.
struct ExpandedDock: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var registry = ModuleRegistry.shared

    var body: some View {
        HStack(spacing: 0) {
            if !vm.homePages.isEmpty {
                PageDots(vm: vm)
            }
            let tabs = registry.dockTabs
            if !tabs.isEmpty {
                if !vm.homePages.isEmpty {
                    Capsule().fill(Color.white.opacity(0.22)).frame(width: 1, height: 10).padding(.horizontal, 3)
                }
                ForEach(tabs, id: \.id) { m in
                    dockButton(symbol: m.symbol, title: m.title, selected: vm.expandedPage == .module(m.id)) {
                        vm.openModule(m.id)
                    }
                }
            }
            dockButton(symbol: "magnifyingglass", title: T("모든 도구 · 명령", "All Tools · Commands"),
                       selected: vm.expandedPage == .palette) { vm.openPalette() }
        }
        .animation(vm.openSpring, value: vm.expandedPage)
    }

    private func dockButton(symbol: String, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(selected ? 1 : 0.45))
                .frame(width: 22, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// 명령 팔레트: 위에 검색 칸, 비어 있으면 모든 도구 격자 + 늘 있는 동작, 입력하면 기능별 즉석 결과.
/// ↑↓로 고르고 Return으로 실행, Esc로 닫는다.
struct CommandPaletteView: View {
    static let contentSize = CGSize(width: 520, height: 252)

    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var registry = ModuleRegistry.shared
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var results: [PaletteAction] {
        let core = vm.corePaletteActions?(query) ?? []
        return Array((core + registry.paletteResults(for: query)).prefix(60))
    }

    var body: some View {
        let items = results
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                TextField(T("검색하거나 명령 입력 (예: 10분 타이머, 12*7)", "Search or type a command (e.g. timer 10m, 12*7)"),
                          text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .focused($focused)
                    .onSubmit { if items.indices.contains(selection) { run(items[selection]) } }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(T("지우기", "Clear"))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.white.opacity(0.1), in: Capsule())

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        if query.isEmpty, !registry.tabs.isEmpty { toolGrid }
                        LazyVStack(spacing: 1) {
                            ForEach(Array(items.enumerated()), id: \.offset) { index, action in
                                row(action, selected: index == selection)
                                    .id(index)
                                    .onTapGesture { run(action) }
                            }
                        }
                        if items.isEmpty, !query.isEmpty {
                            Text(T("결과 없음", "No results"))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.45))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 20)
                        }
                    }
                }
                .onChange(of: selection) { _, new in withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(new) } }
            }
        }
        .onChange(of: query) { _, _ in selection = 0 }
        .onAppear {
            vm.requestKeyFocus?()
            DispatchQueue.main.async { focused = true }
        }
        .onKeyPress(.downArrow) { selection = min(selection + 1, max(0, results.count - 1)); return .handled }
        .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
        .onKeyPress(.escape) { vm.collapse(); return .handled }
    }

    /// 모든 확장 기능 탭 (독에 없는 것까지)
    private var toolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 6) {
            ForEach(registry.tabs, id: \.id) { m in
                Button { vm.openModule(m.id) } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.1))
                            Image(systemName: m.symbol).font(.system(size: 14, weight: .medium))
                        }
                        .frame(width: 34, height: 34)
                        Text(m.title).font(.system(size: 10)).lineLimit(1).foregroundStyle(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel(m.title)
            }
        }
        .padding(.bottom, 4)
    }

    private func row(_ action: PaletteAction, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: action.symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title).font(.system(size: 13)).lineLimit(1)
                if let sub = action.subtitle, !sub.isEmpty {
                    Text(sub).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "return").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(selected ? 0.14 : 0)))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func run(_ action: PaletteAction) {
        action.run()
        // 동작이 다른 탭을 열지 않았으면 팔레트를 닫는다
        if vm.expandedPage == .palette { vm.collapse() }
    }
}

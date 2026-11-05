import SwiftUI
import Combine

enum NotchState: Int, Equatable {
    case idle, compact, detail, expanded
}

/// 홈의 네 가지 옵션. 한 번에 하나씩 표시하고 점·스와이프로 넘긴다.
enum HomeOption: Int, CaseIterable {
    case camera, timer, usage, memo, calendar, tray, dashboard

    /// 설정·저장에 쓰는 이름 (순서를 바꿔도 변하지 않음)
    var key: String {
        switch self {
        case .camera: return "camera"
        case .timer: return "timer"
        case .usage: return "usage"
        case .memo: return "memo"
        case .calendar: return "calendar"
        case .tray: return "tray"
        case .dashboard: return "dashboard"
        }
    }

    init?(key: String) {
        guard let o = HomeOption.allCases.first(where: { $0.key == key }) else { return nil }
        self = o
    }

    var title: String {
        switch self {
        case .camera: return T("카메라", "Camera")
        case .timer: return T("타이머", "Timer")
        case .usage: return T("AI 사용량", "AI Usage")
        case .memo: return T("메모", "Memo")
        case .calendar: return T("오늘 일정", "Today")
        case .tray: return T("에어드랍 · 트레이", "AirDrop · Tray")
        case .dashboard: return T("대시보드", "Dashboard")
        }
    }

    var symbol: String {
        switch self {
        case .camera: return "camera.fill"
        case .timer: return "timer"
        case .usage: return "gauge.medium"
        case .memo: return "note.text"
        case .calendar: return "calendar"
        case .tray: return "tray.and.arrow.down.fill"
        case .dashboard: return "square.grid.2x2.fill"
        }
    }
}

enum ExpandedPage: Equatable {
    case home
    case activity(ActivityKind)
    /// 확장 기능 탭 (모듈 id)
    case module(String)
    /// 명령 팔레트 (모든 도구 + 검색)
    case palette
}

/// 확장 패널에서 좌우로 넘기는 한 칸: 홈 페이지 또는 독에 고정한 확장 기능 탭
enum NavItem: Equatable {
    case home(HomeOption)
    case module(String)
}

/// 노치 크기·상태의 단일 원천. 상태는 액티비티 센터와 확장 여부에서 계산된다 (가이드라인 3장).
final class NotchViewModel: ObservableObject {
    let center: ActivityCenter
    let settings = AppSettings.shared

    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var hasPhysicalNotch = true
    @Published private(set) var isExpanded = false
    @Published var expandedPage: ExpandedPage = .home
    /// 길게누르기 전에 묻는다: 이 활동을 확장 화면으로 열지(true), 앱이 따로 처리했는지(false).
    var longPressShouldExpand: ((NotchActivity?) -> Bool)?
    /// 누르고 있을 때 커지는 반응을 보일지 (상세 알림처럼 길게누르기가 없는 경우 false → 클릭만 반응)
    var allowsPressFeedback: ((NotchActivity?) -> Bool)?
    /// 홈의 카메라 거울을 켰는지 (켜면 노치가 더 커져 화면을 크게 보여 줌)
    @Published var cameraOn = false
    /// 상세 알림 위에서 두 손가락으로 위로 올렸을 때 (전화 수신 카드는 접기, 그 밖은 닫기)
    var onDetailSwipeUp: (() -> Void)?
    /// 음악 팝업 아래에 음량 줄을 펼쳤는지 (출력 기기 아이콘을 길게 눌러 토글)
    @Published private(set) var mediaVolumeShown = false
    /// 음량 줄이 더하는 높이
    static let mediaVolumeRowHeight: CGFloat = 26
    @Published var isHovering = false
    /// 음악 호버 미리보기(미니 플레이어) 중
    @Published private(set) var isPeeking = false
    /// 길게누르기 진행도 (0...1). 누르는 동안 노치가 최대 6% 부풀어 오른다.
    @Published var pressProgress: CGFloat = 0
    /// 포스터치 stage 1 압력 (0...1).
    @Published var forcePressure: CGFloat = 0
    @Published var stretch = CGSize(width: 1, height: 1)
    @Published var shakeTrigger: CGFloat = 0
    /// 현재 홈 옵션. 마지막으로 본 옵션을 기억한다.
    @Published private(set) var homeOption: HomeOption = NotchViewModel.savedHomeOption() {
        didSet { if homeOption != .camera { cameraOn = false } }   // 다른 페이지로 넘기면 카메라 끔
    }

    private static let homeKey = "homeOptionKey"

    /// 마지막으로 본 홈 페이지 (이름으로 저장. 예전 번호 저장값은 한 번 옮겨 읽는다)
    private static func savedHomeOption() -> HomeOption {
        let d = UserDefaults.standard
        if let key = d.string(forKey: homeKey), let o = HomeOption(key: key) { return o }
        if d.object(forKey: "homeOption") != nil, let o = HomeOption(rawValue: d.integer(forKey: "homeOption")) { return o }
        return .camera
    }

    private func saveHomeOption() {
        UserDefaults.standard.set(homeOption.key, forKey: Self.homeKey)
    }

    // MARK: - 홈 페이지 목록 (설정 → 상호작용 → 기본)

    /// 보이는 홈 페이지 (설정한 순서, 끈 기능·노치에서 가린 트레이는 빠짐)
    var homePages: [HomeOption] {
        settings.homeOrder.compactMap(HomeOption.init(key:)).filter(settings.homeEnabled)
    }

    /// 지금 페이지가 꺼졌거나 가려졌으면 보이는 첫 페이지로 (파일을 끄는 중의 트레이는 예외)
    func ensureValidHome() {
        guard !isFileDragging else { return }
        let pages = homePages
        if !pages.contains(homeOption), let first = pages.first {
            homeOption = first
            saveHomeOption()
        }
    }
    /// 페이지 전환 방향 (true = 다음 페이지가 오른쪽에서 들어옴).
    @Published private(set) var pageForward = true
    /// 파일을 든 채 노치로 가져와 확장된 상태 (가이드라인 5.2).
    @Published private(set) var isFileDragging = false
    /// 두 손가락 스와이프 중 콘텐츠가 손가락을 따라가는 오프셋.
    @Published var swipeOffset: CGFloat = 0

    private var cancellables = Set<AnyCancellable>()

    init(center: ActivityCenter) {
        self.center = center
        // 액티비티 변화도 뷰 갱신을 일으키도록 전달한다.
        center.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // 바뀐 뒤의 값을 보고 교체 애니메이션을 정한다
        center.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateCompactSwap() }
            .store(in: &cancellables)
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        ModuleRegistry.shared.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // 홈 기능을 끄거나 순서를 바꾸면 지금 페이지가 남아 있는지 확인
        settings.$homeOrder.map { _ in () }
            .merge(with: settings.$homeDisabled.map { _ in () }, settings.$trayMode.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.ensureValidHome() }
            .store(in: &cancellables)
    }

    // MARK: - 상태

    /// 액티비티만 보고 정한 상태 (교체 애니메이션 반영 전)
    private var baseState: NotchState {
        if isExpanded { return .expanded }
        guard let a = center.displayed else { return .idle }
        if center.showingDetail, center.transient?.id == a.id { return .detail }
        if isPeeking, a.kind == .media, center.lockActivity == nil { return .detail }
        return .compact
    }

    var state: NotchState {
        let s = baseState
        // 컴팩트끼리 다른 항목으로 바뀌는 순간(예: 음악 → 블루투스)에는 먼저 노치 안으로 들어갔다가 나온다.
        if s == .compact, let shown = shownCompactKind, let kind = center.displayed?.kind, kind != shown {
            return .idle
        }
        return s
    }

    // MARK: - 컴팩트 교체 애니메이션 (들어갔다 나오기)

    /// 지금 노치에 그려진 컴팩트 항목의 종류. 새 항목과 다르면 교체 중(들어가는 중)이다.
    private var shownCompactKind: ActivityKind?
    private var swapWork: DispatchWorkItem?
    /// 들어가는 시간 (나오는 쪽은 openSpring)
    static let retractDuration: TimeInterval = 0.24

    var isRetracting: Bool {
        baseState == .compact && shownCompactKind != nil && center.displayed?.kind != shownCompactKind
    }

    /// 상태가 바뀔 때 노치 도형에 쓸 애니메이션
    var stateAnimation: Animation {
        if isRetracting { return reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: Self.retractDuration, bounce: 0) }
        return animationOverride ?? (state == .idle ? closeSpring : openSpring)
    }

    /// 액티비티가 바뀐 뒤 호출: 컴팩트 → 다른 컴팩트면 잠깐 들어갔다가 새 항목으로 나온다.
    /// 상세 알림·확장 팝업이 끼면 기존처럼 바로 바뀐다.
    /// 상시 표시 우선순위를 바꾼 뒤(설정에서 5초 동안 더 바뀌지 않으면) 지금 보이는 항목을 새 순서로 다시 맞춘다.
    /// 교체 애니메이션 대기 중이던 항목·이전 항목 기억을 버리고, 현재 우선순위가 가장 높은 항목으로 갱신한다.
    func resyncPersistentOrder() {
        swapWork?.cancel()
        swapWork = nil
        shownCompactKind = baseState == .compact ? center.displayed?.kind : nil
        withAnimation(openSpring) { objectWillChange.send() }
    }

    private func updateCompactSwap() {
        guard baseState == .compact, let kind = center.displayed?.kind else {
            swapWork?.cancel()
            swapWork = nil
            shownCompactKind = nil
            return
        }
        if shownCompactKind == nil || reduceMotion {
            shownCompactKind = kind
            return
        }
        guard kind != shownCompactKind, swapWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.swapWork = nil
            withAnimation(self.openSpring) {
                self.shownCompactKind = self.center.displayed?.kind
                self.objectWillChange.send()
            }
        }
        swapWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retractDuration, execute: work)
    }

    /// 목표 크기 (애니메이션 전 최종값).
    var targetSize: CGSize {
        let n = notchSize
        switch state {
        case .idle:
            // 호버 미리보기: 몸통(위쪽 오목 모서리 안쪽)이 물리 노치보다 양옆 1pt씩 넓어야
            // 물리 노치의 아래 모서리가 도형 밖으로 삐져나와 보이지 않는다.
            guard settings.hoverPreview && isHovering else { return n }
            return CGSize(width: n.width + 2 * (topRadius + 1), height: n.height + 4)
        case .compact:
            let wing = NotchActivity.wing(for: center.displayed)
            return CGSize(width: n.width + wing * 2, height: n.height)
        case .detail:
            // 상세(확장) 알림: 컴팩트보다 좌우·아래로 조금 더 커진다. 스크린샷처럼 전용 높이가 있으면 넓게.
            if let extra = center.displayed?.detailHeight {
                return CGSize(width: max(n.width + 190, 390), height: n.height + extra)
            }
            if isPeeking, center.displayed?.kind == .media, center.transient == nil { return peekSize }
            // 버튼이 달린 카드(에이전트 승인 등)는 버튼 줄만큼 아래로 더
            if let a = center.displayed, !a.actions.isEmpty {
                return CGSize(width: max(n.width + 190, 390), height: n.height + 58 + Self.actionRowHeight)
            }
            return CGSize(width: max(n.width + 150, 330), height: n.height + 58)
        case .expanded:
            switch expandedPage {
            case .home:
                if homeOption == .usage || homeOption == .memo { return usageSize }   // 메모도 AI 사용량과 같은 크기
                if homeOption == .dashboard { return dashboardSize }
                return homeOption == .camera && cameraOn ? cameraSize : expandedBaseSize
            case .activity(let kind):
                return popupSize(for: kind)
            case .module(let id):
                return moduleSize(ModuleRegistry.shared.module(id)?.tabContentSize ?? CGSize(width: 360, height: 160))
            case .palette:
                return moduleSize(CommandPaletteView.contentSize)
            }
        }
    }

    /// 확장 기능 탭 크기: 내용 + 공통 여백 (좌우 위쪽 모서리 + Island.panelMargin, 위 6, 아래 Island.panelMargin). 노치보다 좁아지지 않는다.
    func moduleSize(_ content: CGSize) -> CGSize {
        let side = 2 * (topRadius + Island.panelMargin)
        let width = max(content.width + side, notchSize.width + 2 * topRadius + 60)
        return CGSize(width: width.rounded(), height: (notchSize.height + 6 + content.height + Island.panelMargin).rounded())
    }

    /// 상시 표시 항목을 길게 눌렀을 때 뜨는 독립 팝업 크기.
    func popupSize(for kind: ActivityKind) -> CGSize {
        let n = notchSize
        switch kind {
        case .media:
            // 참고 이미지: 노치보다 좌우로 넓고, 앨범아트·진행 바·조작 버튼 3줄
            return CGSize(width: max(n.width + 125, 300) + 2 * topRadius,
                          height: n.height + 152 + (mediaVolumeShown ? Self.mediaVolumeRowHeight : 0))
        case .timer:
            return CGSize(width: max(n.width + 60, 240) + 2 * topRadius, height: n.height + 120)
        case .call:
            // 음악 팝업과 같은 폭, 한 줄(상대·버튼)
            return CGSize(width: max(n.width + 125, 300) + 2 * topRadius, height: n.height + 84)
        case .download:
            // 음악 팝업과 같은 폭, 두 줄(아이콘·파일명 / 진행 바)에 맞춘 높이
            return CGSize(width: max(n.width + 125, 300) + 2 * topRadius, height: n.height + 104)
        case .recording:
            return CGSize(width: max(n.width + 60, 240) + 2 * topRadius, height: n.height + 110)
        case .aiUsage:
            return usageSize
        default:
            return CGSize(width: max(n.width + 60, 240) + 2 * topRadius, height: n.height + 84)
        }
    }

    /// 기본 확장(길게누르기): 좌우로는 넓어지지 않고 노치 폭 그대로 아래로만 커진다.
    /// 도형의 위쪽 오목 모서리 폭(topRadius)만큼 양옆을 더해야 몸통이 노치 폭과 일치한다.
    /// 카메라를 켰을 때: 16:9 화면(약 356×200pt)이 들어가도록 좌우·아래로 더 커진다.
    var cameraSize: CGSize {
        let contentHeight: CGFloat = 200
        let contentWidth = (contentHeight * 16 / 9).rounded()
        return CGSize(width: contentWidth + 2 * (topRadius + Island.panelMargin), height: notchSize.height + 6 + contentHeight + Island.panelMargin)
    }

    /// 대시보드: 카드 2열 (음악 · 타이머 · 일정 · 확장 기능 카드)
    var dashboardSize: CGSize {
        var cards = 1 + DashboardPage.moduleCards.prefix(3).count
        if settings.homeEnabled(.timer) { cards += 1 }
        if settings.homeEnabled(.calendar) { cards += 1 }
        return moduleSize(CGSize(width: DashboardPage.contentWidth, height: DashboardPage.contentHeight(cards: cards)))
    }

    /// AI 사용량: 서비스 세 줄(이름 · 5시간 · 주간)이 들어가도록 좌우·아래로 조금 더 넓게
    var usageSize: CGSize {
        CGSize(width: 300 + 2 * (topRadius + Island.panelMargin), height: notchSize.height + 6 + 124 + Island.panelMargin)
    }

    var expandedBaseSize: CGSize {
        // 기본 팝업(홈): 노치 폭보다 좌우 8% 넓게, 아래로 확장
        CGSize(width: (notchSize.width * 1.08).rounded() + 2 * topRadius, height: ((notchSize.height + 154) * 0.9).rounded())
    }

    /// 상세 카드 버튼 줄 높이
    static let actionRowHeight: CGFloat = 38

    /// 확장 상태에서 노치 바깥 아래에 따로 표시하는 페이지 점 영역 높이.
    static let dotsAreaHeight: CGFloat = 30

    // MARK: - 다이나믹 아일랜드: 두 번째 활동 동그라미 · 음악 미리보기

    /// 노치 없는 화면에서 떠 있는 알약으로 그리는지 (설정은 IslandSettings, 화면은 NotchController가 알려 줌)
    @Published var floatingPillEnabled = true
    var floatingPill: Bool { !hasPhysicalNotch && floatingPillEnabled }
    /// 떠 있는 알약이 화면 위 가장자리에서 떨어진 거리
    var floatingInset: CGFloat { floatingPill ? 5 : 0 }

    /// 노치 없는 화면에서 쉬는 알약 모양 ("show" | "clock" | "hidden"), NotchController가 알려 줌
    @Published var idlePillStyle = "show"
    /// 쉬는 알약을 숨길지 (커서를 올리면 보임)
    var idlePillHidden: Bool { floatingPill && idlePillStyle == "hidden" && state == .idle && !isHovering }
    var idlePillClock: Bool { floatingPill && idlePillStyle == "clock" && state == .idle }

    /// 노치와 동그라미 사이 간격
    static let bubbleGap: CGFloat = 7

    /// 노치 오른쪽에 떨어져 보일 두 번째 라이브 활동 (컴팩트 상태에서만)
    var secondaryBubble: NotchActivity? {
        guard state == .compact, !isRetracting, center.lockActivity == nil, IslandSettings.secondaryBubble,
              let main = center.displayed, main.kind != .lock else { return nil }
        return center.orderedPersistent.first { $0.kind != main.kind && $0.kind != .lock }
    }

    var bubbleDiameter: CGFloat { notchSize.height }

    /// 음악 미리보기 켜기·끄기 (NotchController가 호버로 부른다)
    func setPeeking(_ on: Bool) {
        guard on != isPeeking else { return }
        withAnimation(on ? openSpring : closeSpring) { isPeeking = on }
    }

    var peekSize: CGSize { CGSize(width: max(notchSize.width + 190, 390), height: notchSize.height + 58) }

    /// 마우스가 반응해야 하는 영역 (확장 시 바깥 점 포함).
    var interactiveSize: CGSize {
        var size = targetSize
        size.height += floatingInset
        // 오른쪽 동그라미까지 (가운데 기준이라 양쪽으로 같이 넓힌다)
        if secondaryBubble != nil { size.width += 2 * (Self.bubbleGap + bubbleDiameter) }
        if state == .expanded, showsDock || showsPersistentDots { size.height += Self.dotsAreaHeight }
        return size
    }

    /// 누르기 피드백까지 반영한 실제 표시 크기.
    var displaySize: CGSize {
        let size = targetSize
        guard state != .expanded else { return size }
        let p = 1 + 0.06 * max(pressProgress, forcePressure)
        return CGSize(width: size.width * p, height: size.height * p)
    }

    /// 위쪽(디스플레이 안으로 들어가는) 오목 모서리. 확장될수록 아래쪽 모서리와 함께 더 크게 휜다.
    var topRadius: CGFloat {
        switch state {
        case .idle, .compact: return 8
        case .detail: return Self.detailTopRadius
        case .expanded: return 16
        }
    }

    /// 상세 카드의 위쪽 오목 모서리 (DetailActivityView가 노치 옆 칸 폭을 잴 때도 쓴다)
    static let detailTopRadius: CGFloat = 13

    /// 아래쪽 모서리: 쉬는 노치는 물리 노치와 같게, 작은 표시는 아일랜드처럼 양끝 반원,
    /// 펼친 카드·확장 화면은 아일랜드의 펼친 모양과 같은 반경 (Island)
    var bottomRadius: CGFloat {
        switch state {
        case .idle: return 10
        case .compact: return Island.compactRadius(notchHeight: notchSize.height)
        case .detail, .expanded: return Island.expandedRadius
        }
    }

    // MARK: - 애니메이션

    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// 모든 팝업 애니메이션은 확장 시간(0.42초)으로 통일한다. 길이가 정해진 스프링이라 닫힐 때도 같은 시간에 끝난다.
    static let popupDuration: TimeInterval = 0.42

    var openSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(duration: Self.popupDuration, bounce: 0.2)
    }

    var closeSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(duration: Self.popupDuration, bounce: 0.08)
    }

    var valueSpring: Animation {
        .interactiveSpring(response: 0.25, dampingFraction: 0.85)
    }

    // MARK: - 동작

    func expand(page: ExpandedPage) {
        guard !isExpanded else { return }
        if page == .home { ensureValidHome() }
        expandedPage = page
        mediaVolumeShown = false
        if !reduceMotion {
            // 스쿼시 & 스트레치: 진행 방향으로 잠깐 늘었다가 스프링으로 복귀.
            stretch = CGSize(width: 1.03, height: 0.97)
        }
        withAnimation(openSpring) {
            isExpanded = true
            isPeeking = false
            pressProgress = 0
            forcePressure = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                self.stretch = CGSize(width: 1, height: 1)
            }
        }
    }

    /// 음악 앨범아트 하나를 상태와 무관하게 계속 그리며, 상태별 위치·크기만 바꾼다 (도형 왼쪽 위 기준).
    /// 도형과 같은 스프링으로 움직이므로 항상 도형 안에서 커지고 줄어든다.
    var mediaArtRect: CGRect? {
        guard center.lockActivity == nil else { return nil }
        let n = notchSize
        switch state {
        case .expanded:
            // 상시 항목 팝업에서 다른 항목을 보는 동안에도 음악이 그 묶음에 있으면 남겨 두고 옆으로 비켜 둔다 (mediaArtPageShift)
            guard expandedPage == .activity(.media) || (showsPersistentDots && persistentPages.contains(.media)) else { return nil }
            // MediaPage: 좌우 여백(위쪽 모서리 + Island.panelMargin), 위 여백 6 + 4
            return CGRect(x: topRadius + Island.panelMargin, y: n.height + 10, width: 50, height: 50)
        case .detail:
            guard let a = center.displayed, a.kind == .media, a.artwork != nil else { return nil }
            // DetailActivityView: 옆 여백, 노치 아래 남은 높이(58 - 10)의 가운데
            let s = DetailActivityView.artSize
            return CGRect(x: DetailActivityView.sideInset, y: n.height + (48 - s) / 2, width: s, height: s)
        case .compact:
            guard let a = center.displayed, a.kind == .media, a.artwork != nil else { return nil }
            let s = min(19, n.height - 11)
            return CGRect(x: 4 + (a.wing - s) / 2, y: (n.height - s) / 2, width: s, height: s)
        case .idle:
            return nil
        }
    }

    /// 상시 항목 팝업에서 음악 앨범아트가 있어야 할 곳 (페이지 한 칸 = 1).
    /// 음악 페이지면 0, 음악보다 뒤 페이지를 보면 -1(왼쪽으로 밀려남), 앞 페이지를 보면 +1(오른쪽에서 대기).
    /// 페이지를 넘길 때 다른 내용과 같은 애니메이션으로 함께 밀려나고 들어온다.
    var mediaArtPageShift: CGFloat {
        guard state == .expanded, case .activity(let kind) = expandedPage, kind != .media,
              let current = persistentPages.firstIndex(of: kind), let media = persistentPages.firstIndex(of: .media) else { return 0 }
        return current > media ? -1 : 1
    }

    // 도형이 줄어드는 중인지 (줄어들 때 새로 나타나는 내용은 바깥으로 퍼지지 않고 제자리에서 나타나야 한다)
    private var lastArea: CGFloat = 0
    private var shrinkingFlag = false

    func isShrinking(to size: CGSize) -> Bool {
        let area = size.width * size.height
        if area != lastArea {
            shrinkingFlag = area < lastArea
            lastArea = area
        }
        return shrinkingFlag
    }

    /// 지금 진행 중인 전환에 쓸 애니메이션 (뷰의 크기·상태 애니메이션이 이 값을 따른다).
    private(set) var animationOverride: Animation?

    /// 음악 팝업은 닫힐 때 조금 더 천천히 (0.55초)
    var mediaCollapseSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(duration: 0.55, bounce: 0.06)
    }

    /// 음량 줄을 펼치거나 접는다: 팝업이 한 줄만큼 아래로 늘어나며 줄이 나타난다.
    func toggleMediaVolume() {
        guard isExpanded, expandedPage == .activity(.media) else { return }
        withAnimation(openSpring) { mediaVolumeShown.toggle() }
    }

    func collapse() {
        guard isExpanded else { return }
        let animation = expandedPage == .activity(.media) ? mediaCollapseSpring : closeSpring
        animationOverride = animation
        withAnimation(animation) {
            isExpanded = false
            pinnedOpen = false
            cameraOn = false   // 노치를 닫으면 카메라 끔
        }
        MemoryTrim.soon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.animationOverride = nil }
    }

    func beginPress(duration: TimeInterval) {
        withAnimation(.easeOut(duration: duration)) { pressProgress = 1 }
    }

    func endPress() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            pressProgress = 0
            forcePressure = 0
        }
    }

    func setForcePressure(_ value: CGFloat) {
        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9)) {
            forcePressure = value
        }
    }

    func shake() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 0.5)) { shakeTrigger += 1 }
    }

    func selectHomeOption(_ option: HomeOption) {
        guard option != homeOption || expandedPage != .home else { return }
        let items = navItems
        if let from = currentNav, let a = items.firstIndex(of: from), let b = items.firstIndex(of: .home(option)) {
            pageForward = b >= a
        } else {
            pageForward = true
        }
        withAnimation(openSpring) {
            homeOption = option
            expandedPage = .home
            swipeOffset = 0
        }
        saveHomeOption()
    }

    // MARK: - 상시 표시 항목 넘기기
    // 상시 표시 항목을 길게 눌러 연 팝업에서는 홈처럼 아래 점·두 손가락 좌우로 다른 상시 항목을 넘겨 본다.
    // (닫으면 노치는 언제나 우선순위가 가장 높은 항목을 보여 준다 — ActivityCenter.displayed)

    /// 길게 눌러 열 화면: 보이는 알림·상시 항목의 팝업, 아무것도 없으면 홈.
    /// AI 사용량만 상시 표시 중이면 홈의 AI 사용량 페이지로 연다 (홈 점·스와이프로 카메라·타이머 등).
    /// 다른 상시 항목과 함께 있으면 상시 항목 모음 팝업으로 연다 (점으로 넘겨 봄).
    func longPressPage(for activity: NotchActivity?) -> ExpandedPage {
        guard let a = activity else { return .home }
        if a.kind == .aiUsage, center.transient?.id != a.id, persistentPages.count <= 1, homePages.contains(.usage) {
            homeOption = .usage
            saveHomeOption()
            return .home
        }
        return .activity(a.kind)
    }

    // MARK: - 확장 기능 탭·명령 팔레트

    /// 확장 패널 아래 독(홈 점 · 고정 탭 · 검색)을 보일지
    var showsDock: Bool {
        guard state == .expanded else { return false }
        switch expandedPage {
        case .home, .module, .palette: return true
        case .activity: return false
        }
    }

    /// 독에 고정한 확장 기능 탭 id
    var dockTabs: [String] { ModuleRegistry.shared.dockTabs.map(\.id) }

    /// 좌우로 넘기는 순서: 홈 페이지들 → 고정 탭들
    var navItems: [NavItem] { homePages.map(NavItem.home) + dockTabs.map(NavItem.module) }

    var currentNav: NavItem? {
        switch expandedPage {
        case .home: return .home(homeOption)
        case .module(let id): return .module(id)
        default: return nil
        }
    }

    /// 열림 고정: 바깥을 눌러도 접히지 않는다 (독의 핀 버튼, 접으면 풀림)
    @Published var pinnedOpen = false

    /// 노치 창을 키 창으로 (글자 입력). AppDelegate가 넣는다.
    var requestKeyFocus: (() -> Void)?
    /// 명령 팔레트의 본 앱 동작 (설정 열기, 타이머 등). AppDelegate가 넣는다.
    var corePaletteActions: ((String) -> [PaletteAction])?

    /// 확장 기능 탭을 연다 (닫혀 있으면 펼치면서)
    func openModule(_ id: String) {
        guard ModuleRegistry.shared.module(id) != nil else { return }
        go(to: ExpandedPage.module(id))
    }

    func openPalette() {
        go(to: ExpandedPage.palette)
        requestKeyFocus?()
    }

    private func go(to page: ExpandedPage) {
        guard isExpanded else { expand(page: page); return }
        guard page != expandedPage else { return }
        let items = navItems
        let target: NavItem? = { if case .module(let id) = page { return .module(id) }; return nil }()
        if let from = currentNav, let to = target, let a = items.firstIndex(of: from), let b = items.firstIndex(of: to) {
            pageForward = b >= a
        } else {
            pageForward = true
        }
        withAnimation(openSpring) {
            expandedPage = page
            mediaVolumeShown = false
            swipeOffset = 0
        }
    }

    private func go(to item: NavItem) {
        switch item {
        case .home(let option): selectHomeOption(option)
        case .module(let id): go(to: ExpandedPage.module(id))
        }
    }

    /// ⌘1–9: 넘기는 순서의 n번째 칸으로
    func selectNav(index: Int) {
        let items = navItems
        guard items.indices.contains(index) else { return }
        go(to: items[index])
    }

    /// 넘겨 볼 수 있는 상시 표시 항목 (우선순위 순)
    var persistentPages: [ActivityKind] { center.orderedPersistent.map(\.kind) }

    /// 지금 상시 항목 팝업을 보고 있고, 넘길 항목이 둘 이상인지
    var showsPersistentDots: Bool {
        guard state == .expanded, case .activity(let kind) = expandedPage else { return false }
        let pages = persistentPages
        return pages.count > 1 && pages.contains(kind)
    }

    func selectPersistentPage(_ kind: ActivityKind) {
        guard case .activity(let current) = expandedPage, current != kind else { return }
        let pages = persistentPages
        pageForward = (pages.firstIndex(of: kind) ?? 0) >= (pages.firstIndex(of: current) ?? 0)
        withAnimation(openSpring) {
            expandedPage = .activity(kind)
            mediaVolumeShown = false
            swipeOffset = 0
        }
    }

    /// 스와이프 중 손가락을 따라 콘텐츠를 옮긴다. 양 끝에서는 고무줄처럼 덜 움직인다.
    func dragPage(by contentDX: CGFloat) {
        if expandedPage == .palette { swipeOffset = 0; return }
        if expandedPage != .home, !isModulePage {
            if expandedPage == .activity(.media) {
                // 음악 팝업은 좌우 스와이프로 곡 이동 → 살짝만 따라 움직임
                swipeOffset = contentDX * 0.2
            } else if showsPersistentDots, case .activity(let kind) = expandedPage {
                let pages = persistentPages
                let atEdge = (contentDX > 0 && pages.first == kind) || (contentDX < 0 && pages.last == kind)
                swipeOffset = atEdge ? contentDX * 0.15 : contentDX * 0.45
            } else {
                swipeOffset = 0
            }
            return
        }
        let items = navItems
        let current = currentNav
        let atEdge = current == nil || (contentDX > 0 && items.first == current) || (contentDX < 0 && items.last == current)
        swipeOffset = atEdge ? contentDX * 0.15 : contentDX * 0.45
    }

    /// 확장 상태의 세로 스크롤을 먼저 가져갈 처리기 (타이머 시·분·초 조절). 처리하면 true.
    var verticalScrollHandler: ((CGFloat) -> Bool)?
    var verticalScrollEnded: (() -> Void)?

    /// 음악 제어 페이지에서 좌우 스와이프 = 이전/다음 곡 (가이드라인 5.7)
    var onMediaSwipe: ((Bool) -> Void)?

    func switchExpandedPage(forward: Bool) {
        guard isExpanded else { return }
        if expandedPage == .activity(.media), let onMediaSwipe {
            onMediaSwipe(forward)
            cancelDrag()
            return
        }
        if expandedPage != .home, !isModulePage {
            // 상시 항목 팝업: 다른 상시 항목으로 넘긴다 (홈과는 따로)
            if showsPersistentDots, case .activity(let kind) = expandedPage {
                let pages = persistentPages
                if let i = pages.firstIndex(of: kind), pages.indices.contains(i + (forward ? 1 : -1)) {
                    selectPersistentPage(pages[i + (forward ? 1 : -1)])
                    return
                }
            }
            cancelDrag()
            return
        }
        let items = navItems
        if let current = currentNav, let i = items.firstIndex(of: current), items.indices.contains(i + (forward ? 1 : -1)) {
            go(to: items[i + (forward ? 1 : -1)])
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { swipeOffset = 0 }
        }
    }

    var isModulePage: Bool { if case .module = expandedPage { return true }; return false }

    /// 파일 드래그가 노치에 가까워지면 트레이 페이지로 자동 확장한다.
    func beginFileDrag() {
        guard !isFileDragging, settings.trayMode != .off else { return }
        homeOption = .tray
        expandedPage = .home
        withAnimation(openSpring) { isFileDragging = true }
        if !isExpanded { expand(page: .home) }
        Haptics.perform()
    }

    func endFileDrag(dropped: Bool) {
        guard isFileDragging else { return }
        withAnimation(openSpring) { isFileDragging = false }
        if !dropped { collapse() }
    }

    func cancelDrag() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { swipeOffset = 0 }
    }
}

import SwiftUI

/// 노치 패널의 루트 뷰. 검은 NotchShape가 상태에 따라 스프링으로 변형되고,
/// 그 안의 콘텐츠가 블러 전환으로 나타난다.
/// 3단계 기능 묶음 (뷰에서 기능별 화면을 그릴 때 사용).
struct NotchFeatures {
    let media: MediaController
    let screenshot: ScreenshotMonitor
    let recording: RecordingMonitor
    let tray: TrayStore
    let calendar: CalendarController
    let call: CallMonitor
    let usage: UsageStore
    let memo: MemoStore
}

struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel
    let timer: TimerController
    let features: NotchFeatures
    var openSettings: () -> Void
    /// 시스템 화면 모드 (아래에서 내용은 어두운 모드로 고정하므로 여기서 먼저 읽는다)
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let size = vm.displaySize
        let state = vm.state
        // 노치 없는 화면: 위쪽도 둥근 떠 있는 알약 (가로세로 중 짧은 쪽 절반까지 둥글게)
        let shape: AnyShape = vm.floatingPill
            ? AnyShape(RoundedRectangle(cornerRadius: min(vm.bottomRadius + 4, min(size.width, size.height) / 2), style: .continuous))
            : AnyShape(NotchShape(topRadius: vm.topRadius, bottomRadius: vm.bottomRadius))

        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                shape
                    .fill(Color.black)
                    .frame(width: size.width, height: size.height)
                    .shadow(color: .black.opacity(state == .expanded || state == .detail ? 0.4 : 0), radius: 14, y: 6)
                    // 어두운 모드에서는 아일랜드처럼 둘레에 가는 선을 그려 검은 메뉴 막대와 구분한다.
                    // 쉬는 노치는 물리 노치와 섞여야 하므로 그리지 않고, 화면 맨 위 가장자리(위쪽 1.5pt)는 가린다.
                    .overlay {
                        if systemScheme == .dark && state != .idle {
                            shape
                                .stroke(Color.white.opacity(Island.keylineOpacity), lineWidth: 1)
                                .frame(width: size.width, height: size.height)
                                .mask(VStack(spacing: 0) { Color.clear.frame(height: 1.5); Color.black })
                                .transition(.opacity)
                        }
                    }

                ZStack(alignment: .topLeading) {
                    content(state: state)
                        .frame(width: size.width, height: size.height, alignment: .top)
                    mediaArtLayer
                }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    // 사라지는 중인 이전 내용도 노치 도형 밖으로 삐져나오지 않게 한 묶음으로 잘라낸다.
                    .compositingGroup()
                    .clipShape(shape)
            }
            .opacity(vm.idlePillHidden ? 0 : 1)
            .modifier(ShakeEffect(animatableData: vm.shakeTrigger))
            .scaleEffect(x: vm.stretch.width, y: vm.stretch.height, anchor: .top)
            // 두 번째 활동: 노치 오른쪽에 떨어진 동그라미 (노치 가장자리에서 갈라져 나오듯 등장)
            .overlay(alignment: .topTrailing) {
                if let bubble = vm.secondaryBubble {
                    SecondaryBubble(activity: bubble, diameter: vm.bubbleDiameter)
                        .id(bubble.kind)
                        .offset(x: NotchViewModel.bubbleGap + vm.bubbleDiameter)
                        .transition(vm.reduceMotion ? .opacity :
                            .asymmetric(insertion: .scale(scale: 0.3, anchor: .leading).combined(with: .opacity)
                                            .combined(with: .offset(x: -vm.bubbleDiameter)),
                                        removal: .scale(scale: 0.3, anchor: .leading).combined(with: .opacity)
                                            .combined(with: .offset(x: -vm.bubbleDiameter))))
                }
            }
            .animation(vm.openSpring, value: vm.secondaryBubble?.kind)

            // 독(홈 점 · 고정 탭 · 검색): 확장된 노치 바깥 아래에 따로 떠 있다.
            if vm.showsDock {
                ExpandedDock(vm: vm)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.8), in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.5, anchor: .top)))
            } else if vm.showsPersistentDots {
                // 상시 표시 항목 팝업: 같은 모양의 점으로 다른 상시 항목을 넘겨 본다
                PersistentDots(vm: vm)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.8), in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.5, anchor: .top)))
            }
        }
        .padding(.top, vm.floatingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(vm.stateAnimation, value: state)
        .animation(vm.isRetracting ? vm.stateAnimation : (vm.animationOverride ?? vm.openSpring), value: vm.targetSize)
        .animation(vm.valueSpring, value: vm.center.displayed?.value)
        .environment(\.colorScheme, .dark)
    }

    /// 상태가 바뀌어도 사라지지 않는 단 하나의 앨범아트.
    /// 컴팩트(19pt) ↔ 상세 카드(36pt) ↔ 음악 팝업(50pt) 사이를 위치·크기만 바뀌며 이어서 움직인다.
    @ViewBuilder
    private var mediaArtLayer: some View {
        if let rect = vm.mediaArtRect, features.media.artwork != nil {
            let inMediaPage = vm.state == .expanded && vm.expandedPage == .activity(.media)
            // 상시 항목을 점·스와이프로 넘길 때는 음악 팝업의 다른 내용과 같은 거리·방향으로 밀려나고 들어온다
            let shift = vm.mediaArtPageShift
            let pageWidth = vm.displaySize.width - 2 * (vm.topRadius + Island.panelMargin)
            // 확장된 음악 팝업에서만 곡이 바뀔 때 앨범아트가 돌아간다 (곡 변경 알림 팝업에서는 안 함)
            MediaArtView(media: features.media, size: rect.size, flipEnabled: inMediaPage && !vm.reduceMotion)
                // 좌우로 쓸어 곡을 넘길 때 팝업의 글자·아이콘과 함께 움직인다
                .blur(radius: shift == 0 ? 0 : 6)
                .opacity(shift == 0 ? 1 : 0)
                .offset(x: rect.minX + shift * pageWidth + (inMediaPage ? vm.swipeOffset : 0), y: rect.minY)
                .allowsHitTesting(false)
                .transition(.opacity.animation(.easeOut(duration: 0.15)))
        }
    }

    @ViewBuilder
    private func content(state: NotchState) -> some View {
        // 줄어드는 전환이면 제자리 등장, 커지는 전환이면 노치에서 바깥으로 퍼지며 등장
        let appear: AnyTransition = vm.isShrinking(to: vm.targetSize) ? .notchContentInPlace : .notchContent
        switch state {
        case .idle:
            if vm.idlePillClock {
                // 노치 없는 화면의 쉬는 알약 가운데 시계
                TimelineView(.everyMinute) { ctx in
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.island(.subhead, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.opacity)
            } else {
                Color.clear
            }
        case .compact:
            if let a = vm.center.displayed {
                CompactActivityView(activity: a, notchSize: vm.notchSize)
                    .id(a.kind)
                    .transition(appear)
            }
        case .detail:
            if let a = vm.center.displayed {
                Group {
                    if vm.isPeeking, a.kind == .media, vm.center.transient == nil {
                        MediaPeekView(media: features.media, notchSize: vm.notchSize)
                    } else if a.kind == .screenshot {
                        ScreenshotCard(monitor: features.screenshot, notchSize: vm.notchSize)
                    } else if a.kind == .call {
                        CallIncomingCard(monitor: features.call, activity: a, notchSize: vm.notchSize)
                    } else {
                        DetailActivityView(activity: a, notchSize: vm.notchSize)
                    }
                }
                .id(a.id)
                .transition(appear)
            }
        case .expanded:
            ExpandedView(vm: vm, timer: timer, features: features, openSettings: openSettings)
                .transition(.notchContent)
        }
    }
}

/// 확장 상태: 노치 폭 그대로 아래로 커진 영역에 한 페이지씩 표시한다.
struct ExpandedView: View {
    @ObservedObject var vm: NotchViewModel
    let timer: TimerController
    let features: NotchFeatures
    var openSettings: () -> Void

    private var pages: HomePages {
        HomePages(
            camera: AnyView(CameraPage(vm: vm)),
            usage: AnyView(UsagePage(store: features.usage, openSettings: openSettings)),
            memo: AnyView(MemoPage(store: features.memo,
                                   active: vm.state == .expanded && vm.expandedPage == .home && vm.homeOption == .memo)),
            calendar: AnyView(CalendarPage(calendar: features.calendar)),
            tray: AnyView(TrayPage(store: features.tray, vm: vm)),
            dashboard: AnyView(DashboardPage(media: features.media, timer: timer, calendar: features.calendar,
                                             homeTimerOn: vm.settings.homeEnabled(.timer),
                                             homeCalendarOn: vm.settings.homeEnabled(.calendar)))
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: vm.notchSize.height)   // 카메라 영역
            Group {
                switch vm.expandedPage {
                case .home:
                    HomePager(vm: vm, timer: timer, pages: pages)
                        .transition(HomePager.pageTransition(forward: vm.pageForward))
                case .module(let id):
                    if let view = ModuleRegistry.shared.module(id)?.tabView() {
                        view
                            .id("module." + id)
                            .offset(x: vm.swipeOffset)
                            .transition(HomePager.pageTransition(forward: vm.pageForward))
                    }
                case .palette:
                    CommandPaletteView(vm: vm)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                case .activity(let kind):
                    activityPage(kind)
                        .id(kind)
                        .offset(x: vm.swipeOffset)
                        .transition(vm.showsPersistentDots ? HomePager.pageTransition(forward: vm.pageForward) : .opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 모든 확장 팝업 공통 여백: 옆과 아래를 같게 (Island.panelMargin). 팝업 크기는 그대로, 글자·아이콘만 안쪽으로
            .padding(.horizontal, vm.topRadius + Island.panelMargin)
            .padding(.top, 6)
            .padding(.bottom, Island.panelMargin)
            .clipped()
        }
    }

    @ViewBuilder
    private func activityPage(_ kind: ActivityKind) -> some View {
        switch kind {
        case .timer:
            TimerPage(timer: timer)
        case .media:
            MediaPage(media: features.media, volumeShown: vm.mediaVolumeShown) { vm.toggleMediaVolume() }
        case .recording:
            RecordingPage(monitor: features.recording)
        case .call:
            CallPage(monitor: features.call)
        case .aiUsage:
            UsagePage(store: features.usage, openSettings: openSettings)
        case .download:
            if let a = vm.center.displayed, a.kind == .download {
                DownloadPage(activity: a)
            }
        default:
            // 전용 화면이 없는 상시 항목(핫스팟·집중 모드 등)은 내용을 크게 보여 준다.
            // 알림은 확장 화면 대신 상세 카드로 표시한다.
            if let a = vm.center.orderedPersistent.first(where: { $0.kind == kind }) {
                PersistentInfoPage(activity: a)
            }
        }
    }
}


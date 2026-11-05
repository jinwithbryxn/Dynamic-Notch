import SwiftUI

/// 다이나믹 아일랜드식 표현 설정 (설정 → 확장 기능 → 아일랜드)
enum IslandSettings {
    private static var d: ModuleDefaults { ModuleDefaults(module: "island") }
    /// 두 번째 라이브 활동을 노치 오른쪽에 떨어진 작은 동그라미로 보인다
    static var secondaryBubble: Bool { d.bool("secondaryBubble", default: true) }
    /// 음악이 떠 있는 노치에 커서를 올리면 미니 플레이어로 펼친다
    static var mediaPeek: Bool { d.bool("mediaPeek", default: true) }
    /// 미니 플레이어가 펼쳐지기까지 기다리는 시간(초)
    static var peekDelay: Double { d.double("peekDelay", default: 0.3) }

    /// 노치가 없는 화면에서는 위에 붙은 가짜 노치 대신 메뉴바 아래에 떠 있는 알약으로 그린다
    static var floatingPill: Bool { d.bool("floatingPill", default: true) }

    /// 화면 공유·녹화에서 노치 창을 빼 달라고 시스템에 요청한다 (모든 캡처 방식에서 보장되지는 않음)
    static var hideFromCapture: Bool { d.bool("hideFromCapture", default: false) }

    /// '호버만으로 열기'의 지연(초)
    static var hoverDelay: Double { d.double("hoverDelay", default: 0.35) }
    /// 더블클릭으로 펼치기
    static var doubleClickOpen: Bool { d.bool("doubleClickOpen", default: false) }
    /// 커서가 떠나면 접기까지의 시간(초). 음수면 끔 (바깥을 눌러야 접힘)
    static var autoCollapse: Double { d.double("autoCollapse", default: -1) }
    /// 알림 전용: 클릭·호버·길게누르기로 펼치지 않는다 (명령 팔레트 단축키는 동작)
    static var alertsOnly: Bool { d.bool("alertsOnly", default: false) }
    /// 노치 없는 화면에서 쉬는 알약: "show" | "clock" | "hidden"(커서를 올릴 때만)
    static var idlePill: String { d.string("idlePill", default: "show") }
    /// 집중 모드 동안 덜 중요한 알림(다운로드·기기 연결·네트워크·곡 바뀜·확장 기능 안내 등)을 띄우지 않는다
    static var focusQuiet: Bool { d.bool("focusQuiet", default: false) }

    static func set(_ value: Any?, _ name: String) { d.set(value, name) }
}

/// 두 번째 라이브 활동: 노치와 떨어진 검은 동그라미 (아이폰 다이나믹 아일랜드의 minimal 표시)
struct SecondaryBubble: View {
    var activity: NotchActivity
    var diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            content
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activity.title ?? activity.kind.rawValue)
    }

    @ViewBuilder
    private var content: some View {
        let inner = diameter * 0.58
        if let art = activity.artwork {
            Image(nsImage: art)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: inner, height: inner)
                .clipShape(Circle())
        } else {
            switch activity.value {
            case .ring(let p), .ringPercent(let p), .bar(let p), .percent(let p):
                ZStack {
                    Circle().stroke(activity.tint.opacity(0.25), lineWidth: 2.5)
                    Circle().trim(from: 0, to: max(0.02, min(1, p)))
                        .stroke(activity.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: activity.symbol)
                        .font(.system(size: inner * 0.42, weight: .bold))
                        .foregroundStyle(activity.tint)
                }
                .frame(width: inner, height: inner)
            default:
                Image(systemName: activity.symbol)
                    .font(.system(size: inner * 0.62, weight: .semibold))
                    .foregroundStyle(activity.tint)
            }
        }
    }
}

/// 음악 호버 미리보기: 앨범아트(공용 레이어) · 곡 정보 · 이전/재생/다음
struct MediaPeekView: View {
    @ObservedObject var media: MediaController
    var notchSize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchSize.height)
            HStack(spacing: 12) {
                Color.clear.frame(width: 36, height: 36)   // 공용 앨범아트 레이어 자리
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.nowPlaying?.title ?? "")
                        .font(.island(.callout, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(media.nowPlaying?.artist ?? "")
                        .font(.island(.footnote))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    control("backward.fill", T("이전 곡", "Previous")) { media.previousTrack() }
                    control(media.nowPlaying?.playing == true ? "pause.fill" : "play.fill",
                            media.nowPlaying?.playing == true ? T("일시정지", "Pause") : T("재생", "Play"), size: 17) {
                        media.togglePlayPause()
                    }
                    control("forward.fill", T("다음 곡", "Next")) { media.next() }
                }
            }
            .padding(.horizontal, 35)
            .frame(maxHeight: .infinity)
            .padding(.bottom, 10)
        }
    }

    private func control(_ symbol: String, _ label: String, size: CGFloat = 13, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// 설정 → 확장 기능 맨 위: 아일랜드 표현
struct IslandSettingsSection: View {
    @State private var bubble = IslandSettings.secondaryBubble
    @State private var peek = IslandSettings.mediaPeek
    @State private var delay = IslandSettings.peekDelay
    @State private var pill = IslandSettings.floatingPill
    @State private var hideCapture = IslandSettings.hideFromCapture
    @State private var hoverDelay = IslandSettings.hoverDelay
    @State private var doubleClick = IslandSettings.doubleClickOpen
    @State private var autoCollapse = IslandSettings.autoCollapse
    @State private var alertsOnly = IslandSettings.alertsOnly
    @State private var idlePill = IslandSettings.idlePill
    @State private var focusQuiet = IslandSettings.focusQuiet

    var body: some View {
        Section {
            Toggle(T("두 번째 활동을 노치 옆 동그라미로 표시", "Show a second activity as a bubble beside the notch"), isOn: $bubble)
                .onChange(of: bubble) { _, v in IslandSettings.set(v, "secondaryBubble") }
            Toggle(T("노치 없는 화면에서는 떠 있는 알약으로", "Floating pill on displays without a notch"), isOn: $pill)
                .onChange(of: pill) { _, v in IslandSettings.set(v, "floatingPill") }
            if pill {
                Picker(T("쉬는 알약", "Idle pill"), selection: $idlePill) {
                    Text(T("보이기", "Show")).tag("show")
                    Text(T("시계", "Clock")).tag("clock")
                    Text(T("커서를 올릴 때만", "Only on hover")).tag("hidden")
                }
                .onChange(of: idlePill) { _, v in IslandSettings.set(v, "idlePill") }
            }
            HStack {
                Text(T("호버로 열기 지연", "Hover-open delay"))
                Slider(value: $hoverDelay, in: 0...1.5, step: 0.05)
                Text(String(format: T("%.2f초", "%.2fs"), hoverDelay)).monospacedDigit().frame(width: 52, alignment: .trailing)
            }
            .onChange(of: hoverDelay) { _, v in IslandSettings.set(v, "hoverDelay") }
            Toggle(T("더블클릭으로 펼치기", "Double-click to open"), isOn: $doubleClick)
                .onChange(of: doubleClick) { _, v in IslandSettings.set(v, "doubleClickOpen") }
            Picker(T("커서가 떠나면 접기", "Collapse when the pointer leaves"), selection: $autoCollapse) {
                Text(T("끔 (바깥 클릭)", "Off (click outside)")).tag(-1.0)
                Text(T("바로", "Immediately")).tag(0.0)
                Text(T("0.5초 뒤", "After 0.5 s")).tag(0.5)
                Text(T("1초 뒤", "After 1 s")).tag(1.0)
                Text(T("2초 뒤", "After 2 s")).tag(2.0)
            }
            .onChange(of: autoCollapse) { _, v in IslandSettings.set(v, "autoCollapse") }
            Toggle(T("알림 전용 (클릭·호버로 펼치지 않음)", "Alerts only (don't open on click or hover)"), isOn: $alertsOnly)
                .onChange(of: alertsOnly) { _, v in IslandSettings.set(v, "alertsOnly") }
            Toggle(T("집중 모드 동안 덜 중요한 알림 줄이기", "Quiet minor alerts during Focus"), isOn: $focusQuiet)
                .onChange(of: focusQuiet) { _, v in IslandSettings.set(v, "focusQuiet") }
                .help(T("다운로드, 기기 연결, 네트워크, 곡 바뀜, 확장 기능 안내·알림 미러링을 띄우지 않습니다. 통화, 배터리 부족, 타이머 끝, 에이전트 승인은 그대로 보입니다. 집중 모드 감지가 켜져 있어야 합니다.",
                        "Skips downloads, device connections, network, track changes, module notices and mirrored notifications. Calls, low battery, timer ends and agent approvals still show. Focus detection must be on."))
            Toggle(T("화면 공유·녹화에서 노치 숨기기 요청", "Ask macOS to hide the notch from screen sharing and recording"), isOn: $hideCapture)
                .onChange(of: hideCapture) { _, v in IslandSettings.set(v, "hideFromCapture") }
            Toggle(T("음악 위에 커서를 올리면 미니 플레이어", "Hover over music to peek a mini player"), isOn: $peek)
                .onChange(of: peek) { _, v in IslandSettings.set(v, "mediaPeek") }
            if peek {
                HStack {
                    Text(T("펼치기까지", "Delay"))
                    Slider(value: $delay, in: 0...1.5, step: 0.05)
                    Text(String(format: T("%.2f초", "%.2fs"), delay)).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                .onChange(of: delay) { _, v in IslandSettings.set(v, "peekDelay") }
            }
        } header: {
            Text(T("아일랜드", "Island"))
        } footer: {
            Text(T("'상호작용 → 커서를 올리면 열기'가 켜져 있으면 미니 플레이어 대신 전체 화면이 열립니다. 캡처 숨기기는 창의 공유 설정만 바꾸므로 macOS 버전과 캡처 앱에 따라 노치가 그대로 찍힐 수 있습니다.",
                   "When 'open on hover' is on, the full panel opens instead of the mini player. Hiding from capture only changes the window's sharing setting, so some macOS versions and capture apps may still record the notch."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

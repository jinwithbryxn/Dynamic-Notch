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
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(media.nowPlaying?.artist ?? "")
                        .font(.system(size: 11.5))
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

    var body: some View {
        Section {
            Toggle(T("두 번째 활동을 노치 옆 동그라미로 표시", "Show a second activity as a bubble beside the notch"), isOn: $bubble)
                .onChange(of: bubble) { _, v in IslandSettings.set(v, "secondaryBubble") }
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
            Text(T("'상호작용 → 커서를 올리면 열기'가 켜져 있으면 미니 플레이어 대신 전체 화면이 열립니다.",
                   "When 'open on hover' is on, the full panel opens instead of the mini player."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

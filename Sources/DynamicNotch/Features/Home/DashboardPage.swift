import SwiftUI

/// 홈 대시보드: 음악 · 타이머 · 다음 일정 · 확장 기능 카드(날씨 등)를 한 화면에 2열로 보여 준다.
/// 각 카드는 실제 상태만 보여 주고, 데이터가 없으면 빈 상태와 할 수 있는 일을 적는다.
struct DashboardPage: View {
    @ObservedObject var media: MediaController
    @ObservedObject var timer: TimerController
    @ObservedObject var calendar: CalendarController
    @ObservedObject private var registry = ModuleRegistry.shared
    var homeTimerOn: Bool
    var homeCalendarOn: Bool

    static let cardHeight: CGFloat = 68
    static let spacing: CGFloat = 8
    static let contentWidth: CGFloat = 440

    /// 카드 수에 맞춘 내용 높이 (최대 3줄)
    static func contentHeight(cards: Int) -> CGFloat {
        let rows = min(3, max(2, (cards + 1) / 2))
        return CGFloat(rows) * cardHeight + CGFloat(rows - 1) * spacing
    }

    /// 대시보드에 들어가는 확장 기능 카드
    static var moduleCards: [NotchModule] {
        ModuleRegistry.shared.modules.filter { ModuleRegistry.shared.running.contains($0.id) && $0.homeCard() != nil }
    }

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: Self.spacing), GridItem(.flexible(), spacing: Self.spacing)]
        LazyVGrid(columns: columns, spacing: Self.spacing) {
            card { musicCard }
            if homeTimerOn { card { timerCard } }
            if homeCalendarOn { card { eventCard } }
            ForEach(Self.moduleCards.prefix(3), id: \.id) { m in
                if let view = m.homeCard() { card { view } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .frame(height: Self.cardHeight)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    // MARK: 음악

    @ViewBuilder
    private var musicCard: some View {
        if let now = media.nowPlaying {
            HStack(spacing: 10) {
                Group {
                    if let art = media.artwork {
                        Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ZStack { Color.white.opacity(0.1); Image(systemName: "music.note").foregroundStyle(.white.opacity(0.6)) }
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(now.title).font(.island(.subhead, .semibold)).lineLimit(1)
                    Text(now.artist).font(.island(.footnote)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 2)
                iconButton(now.playing ? "pause.fill" : "play.fill", now.playing ? T("일시정지", "Pause") : T("재생", "Play")) {
                    media.togglePlayPause()
                }
                iconButton("forward.fill", T("다음 곡", "Next")) { media.next() }
            }
            .foregroundStyle(.white)
        } else {
            emptyCard(symbol: "music.note", title: T("음악", "Music"), note: T("재생 중인 음악 없음", "Nothing playing"))
        }
    }

    // MARK: 타이머

    @ViewBuilder
    private var timerCard: some View {
        if timer.isActive {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.orange.opacity(0.25), lineWidth: 3)
                    Circle().trim(from: 0, to: timer.progress)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "timer").font(.island(.subhead, .semibold)).foregroundStyle(.orange)
                }
                .frame(width: 38, height: 38)
                Text(TimerController.format(timer.remaining))
                    .font(.island(.title1, design: .rounded))
                    .monospacedDigit()
                Spacer(minLength: 2)
                iconButton(timer.isPaused ? "play.fill" : "pause.fill", timer.isPaused ? T("계속", "Resume") : T("일시정지", "Pause")) {
                    timer.isPaused ? timer.resume() : timer.pause()
                }
                iconButton("xmark", T("취소", "Cancel")) { timer.cancel() }
            }
            .foregroundStyle(.white)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label(T("타이머", "Timer"), systemImage: "timer")
                    .font(.island(.footnote, .semibold)).foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 6) {
                    ForEach([5, 10, 25], id: \.self) { m in
                        Button { timer.start(seconds: m * 60) } label: {
                            Text(T("\(m)분", "\(m)m"))
                                .font(.island(.subhead, .semibold))
                                .frame(maxWidth: .infinity).frame(height: 24)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(T("\(m)분 타이머 시작", "Start a \(m) minute timer"))
                    }
                }
            }
            .foregroundStyle(.white)
        }
    }

    // MARK: 다음 일정

    @ViewBuilder
    private var eventCard: some View {
        TimelineView(.everyMinute) { ctx in
            if !calendar.authorized {
                emptyCard(symbol: "calendar", title: T("일정", "Calendar"), note: T("캘린더 권한이 필요합니다", "Calendar access needed"))
            } else if let next = calendar.events.first(where: { $0.end > ctx.date }) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(next.color).frame(width: 4, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.title).font(.island(.subhead, .semibold)).lineLimit(1)
                        Text(Self.when(next, now: ctx.date)).font(.island(.footnote)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
            } else {
                emptyCard(symbol: "calendar", title: T("일정", "Calendar"), note: T("오늘 남은 일정 없음", "No more events today"))
            }
        }
    }

    static func when(_ e: CalendarController.Event, now: Date) -> String {
        if e.allDay { return T("하루 종일", "All day") }
        if e.start <= now { return T("진행 중 · \(Self.time(e.end))까지", "Now · until \(Self.time(e.end))") }
        let minutes = Int(e.start.timeIntervalSince(now) / 60)
        if minutes < 60 { return T("\(max(1, minutes))분 후 · \(Self.time(e.start))", "In \(max(1, minutes)) min · \(Self.time(e.start))") }
        return Self.time(e.start)
    }

    private static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: d)
    }

    // MARK: 공통

    private func emptyCard(symbol: String, title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.island(.footnote, .semibold)).foregroundStyle(.white.opacity(0.6))
            Text(note).font(.island(.subhead)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
        }
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.island(.subhead, .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

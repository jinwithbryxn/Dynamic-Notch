import AppKit
import SwiftUI

/// 원형 게이지.
struct RingGauge: View {
    var value: Double
    var tint: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// 가로 바 게이지.
struct BarGauge: View {
    var value: Double
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(tint).frame(width: geo.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 5)
    }
}


/// ActivityValue를 크기에 맞게 그린다.
struct ActivityValueView: View {
    /// 컴팩트 날개에 한 줄로 넣기엔 긴 두 단어 글자 → (윗줄, 아랫줄). 숫자가 든 값(64% 등)은 나누지 않는다.
    static func twoLines(_ s: String) -> (String, String)? {
        guard !s.contains(where: \.isNumber) else { return nil }
        let parts = s.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let width = (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: IslandText.subhead.rawValue, weight: .semibold)]).width
        return width > NotchActivity.compactWing - 12 ? (parts[0], parts[1]) : nil
    }

    var value: ActivityValue
    var tint: Color
    var large = false
    /// 숫자·글자 색 (nil이면 흰색)
    var textColor: Color? = nil
    /// 컴팩트 숫자 글꼴 (HUD·배터리는 조금 작게)
    var numberFont: Font = NotchActivity.compactNumberFont

    /// 크기별 값 고르기: 노치 옆 날개(compact) / 상세 카드·확장 화면(large)
    private func pick<T>(_ compact: T, _ large: T) -> T { self.large ? large : compact }

    var body: some View {
        switch value {
        case .none:
            EmptyView()
        case .text(let s):
            if !large, let (top, bottom) = Self.twoLines(s) {
                // 컴팩트: 두 단어 글자('전송 완료'·'녹화 시작')는 작게 위아래로 나눠 노치 안에 여백을 두고 넣는다
                VStack(spacing: -1) {
                    Text(top)
                    Text(bottom)
                }
                .font(.island(.caption, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(textColor ?? .white)
                .fixedSize()
            } else {
                RollingText(text: s)
                    .font(pick(s.contains(where: \.isNumber) ? numberFont : NotchActivity.compactFont,
                               .island(.headline, .semibold, design: .rounded)))
                    .monospacedDigit()
                    .lineLimit(1)
                    // 긴 한 단어(Connected 등)는 잘리지 않게 줄여서 날개 폭 안에 (양옆 여백 남김)
                    .minimumScaleFactor(large ? 1 : 0.6)
                    .frame(maxWidth: large ? nil : NotchActivity.compactWing - 12)
                    .foregroundStyle(textColor ?? .white)
            }
        case .percent(let v):
            RollingText(text: "\(Int((v * 100).rounded()))%")
                .font(pick(numberFont, .island(.title2, .semibold, design: .rounded)))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(textColor ?? .white)
        case .ring(let v):
            let d: CGFloat = pick(19, 34)
            RingGauge(value: v, tint: tint, lineWidth: pick(2.6, 4))
                .frame(width: d, height: d)
        case .bar(let v):
            BarGauge(value: v, tint: tint)
                .frame(width: pick(44, 120))
        case .ringPercent(let v):
            let d: CGFloat = pick(16, 26)
            HStack(spacing: 5) {
                RingGauge(value: v, tint: tint, lineWidth: pick(2.4, 4))
                    .frame(width: d, height: d)
                RollingText(text: "\(Int((v * 100).rounded()))%")
                    .font(pick(numberFont, .island(.title3, .semibold, design: .rounded)))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(textColor ?? .white)
            }
        case .recordingDot:
            RecordingDot()
        case .waveform(let playing):
            WaveformView(playing: playing, tint: tint)
                .frame(width: pick(18, 28), height: pick(12, 18))
        case .spinner:
            let d: CGFloat = pick(15, 26)
            SpinnerRing(tint: tint)
                .frame(width: d, height: d)
        case .bigNumber(let v):
            RollingText(text: "\(Int((v * 100).rounded()))")
                .font(pick(numberFont, .island(.title1, .regular, design: .rounded)))
                .monospacedDigit()
                .foregroundStyle(textColor ?? .white)
        case .elapsed(let since):
            CallDurationText(since: since, font: pick(numberFont, .island(.title3, .semibold, design: .rounded)))
                .fixedSize()
        case .usage(let label, let percent, let ring):
            UsageGlyph(label: label, percent: percent, ring: ring, tint: tint, large: large)
        case .labeledText(let label, let text):
            VStack(spacing: 1) {
                Text(label)
                    .font(.island(pick(.caption2, .caption), .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                Text(text)
                    .font(.island(pick(.footnote, .headline), pick(.medium, .semibold), design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(textColor ?? .white)
            }
            .lineLimit(1)
            .fixedSize()
        case .check:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: pick(14, 22), weight: .semibold))
                .foregroundStyle(tint)
                .transition(.scale.combined(with: .opacity))
        }
    }
}



/// 자물쇠. open이 되면 고리가 위로 튀어 오르며 왼쪽 기둥을 축으로 열린다.
struct LockGlyph: View {
    var open: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let bodyH = h * 0.55
            ZStack(alignment: .top) {
                // 고리
                Shackle()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: max(1.6, w * 0.14), lineCap: .round))
                    .frame(width: w * 0.62, height: h * 0.5)
                    // iOS 잠금해제처럼: 살짝 들린 뒤 오른쪽 기둥을 축으로 오른쪽으로 돌아가며 열린다
                    .rotation3DEffect(.degrees(open ? 180 : 0), axis: (x: 0, y: 1, z: 0),
                                      anchor: .trailing, perspective: 0.4)
                    .offset(y: open ? -h * 0.1 : 0)
                    .offset(y: h * 0.02)
                // 몸통
                RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                    .fill(Color.white)
                    .frame(width: w, height: bodyH)
                    .offset(y: h - bodyH)
            }
            .frame(width: w, height: h, alignment: .top)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: open)
    }

    private struct Shackle: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.width / 2))
            p.addArc(center: CGPoint(x: r.midX, y: r.minY + r.width / 2), radius: r.width / 2,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            return p
        }
    }
}

/// 좌측 아이콘: 이미지가 있으면 둥근 썸네일, 없으면 SF Symbol.
struct ActivityLeading: View {
    var activity: NotchActivity
    var size: CGFloat

    var body: some View {
        if let leading = activity.leadingValue {
            ActivityValueView(value: leading, tint: activity.tint)
        } else if activity.kind == .media, activity.artwork != nil {
            // 음악 앨범아트는 NotchRootView의 공용 레이어가 그린다 (상태 전환 시 끊기지 않게)
            Color.clear.frame(width: size, height: size)
        } else if activity.kind == .lock {
            // 자물쇠는 다른 아이콘보다 작게
            LockGlyph(open: activity.symbol == "lock.open")
                .frame(width: size * 0.5, height: size * 0.66)
        } else if let since = activity.startDate {
            // 통화·화면 녹화(계속 표시): 왼쪽에 경과 시간
            CallDurationText(since: since, font: NotchActivity.compactSmallNumberFont)
                .fixedSize()
        } else if activity.kind == .recording {
            RecordingDot()   // 화면 녹화 시작·완료 알림: 좌측 빨간 점 (완료는 우측 초록 체크)
        } else if let battery = activity.battery {
            BatteryGlyph(info: battery, tint: activity.tint, width: size * 1.15)
        } else if let art = activity.artwork {
            Image(nsImage: art)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        } else {
            // 항목 종류·심볼이 바뀌면 다른 아이콘으로 취급해 새로 그린다
            // (음량 HUD가 집중 모드 아이콘을 이어받아 보이던 문제 방지)
            Image(systemName: activity.symbol)
                .font(.system(size: size * 0.72, weight: .medium))
                // 블루투스 기기 아이콘은 흰색, 배터리 색(초록/빨강)은 값에만
                .foregroundStyle(activity.kind == .bluetooth ? Color.white : activity.tint)
                .id("\(activity.kind.rawValue)-\(activity.symbol)")
        }
    }
}

/// 컴팩트: 노치 좌측 아이콘, 우측 값 (노치 높이 그대로).
/// 아일랜드처럼 시간을 세는 값(타이머·통화·녹화 시간)은 그 활동의 색으로 쓴다.
struct CompactActivityView: View {
    var activity: NotchActivity
    var notchSize: CGSize

    /// 값 글자를 활동 색으로 쓰는 종류
    static let tintedValueKinds: Set<ActivityKind> = [.timer, .stopwatch, .pomodoro, .call, .recording]

    var body: some View {
        // 좌·우 요소를 각각 도형의 왼쪽·오른쪽 가장자리에 붙인다.
        // 도형이 좁아지며 사라질 때 양쪽이 함께 노치 쪽(가운데)으로 들어간다.
        // 좌우 끝의 둥근 모서리에 붙지 않게 4pt씩 안쪽으로 (노치 폭은 그대로)
        let icon = ActivityLeading(activity: activity, size: min(22, notchSize.height - 8))
            .frame(width: NotchActivity.wing(for: activity), alignment: .center)
            .padding(.leading, 4)
        let valueColor = activity.valueTint ?? (Self.tintedValueKinds.contains(activity.kind) ? activity.tint : nil)
        let value = ActivityValueView(value: activity.value, tint: activity.tint, textColor: valueColor,
                                      numberFont: NotchActivity.compactNumberFont(for: activity.kind))
            .frame(width: NotchActivity.wing(for: activity), alignment: .center)
            .padding(.trailing, 4)
        ZStack {
            if activity.swapSides {
                value.frame(maxWidth: .infinity, alignment: .leading)
                icon.padding(.trailing, 2).frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                icon.frame(maxWidth: .infinity, alignment: .leading)
                value.padding(.trailing, 2).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: notchSize.height)
    }
}

/// 상세: 노치 아래로 커진 카드에 아이콘, 제목, 부제, 값을 한 줄로 표시한다.
/// Mac 노치는 아이폰 카메라보다 카드 폭에서 차지하는 비율이 커서(약 절반), 아일랜드처럼 노치 옆에 아이콘·값을 두면
/// 모서리에 작게 몰려 보인다. 그래서 내용은 노치 아래 한 줄에 두고, 글자·모서리만 아일랜드 기준을 따른다.
struct DetailActivityView: View {
    var activity: NotchActivity
    var notchSize: CGSize

    /// 아이콘·앨범아트 크기
    static let artSize: CGFloat = 36
    /// 옆 여백: 위쪽 오목 모서리 + 확장 화면과 같은 여백
    static var sideInset: CGFloat { NotchViewModel.detailTopRadius + Island.panelMargin }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchSize.height)
            HStack(spacing: 12) {
                if activity.kind == .media, activity.artwork != nil {
                    Color.clear.frame(width: Self.artSize, height: Self.artSize)   // 공용 앨범아트 레이어 자리
                } else if activity.artwork != nil {
                    ActivityLeading(activity: activity, size: Self.artSize)
                } else if let battery = activity.battery {
                    ZStack {
                        Circle().fill(activity.tint.opacity(0.2))
                        BatteryGlyph(info: battery, tint: activity.tint, width: 24)
                    }
                    .frame(width: Self.artSize, height: Self.artSize)
                } else {
                    ZStack {
                        Circle().fill(activity.tint.opacity(0.2))
                        Image(systemName: activity.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(activity.tint)
                    }
                    .frame(width: Self.artSize, height: Self.artSize)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let title = activity.title {
                        Text(title)
                            .font(.island(.headline, .semibold))
                            .foregroundStyle(.white)
                    }
                    if let subtitle = activity.subtitle {
                        Text(subtitle)
                            .font(.island(.footnote))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                ActivityValueView(value: activity.detailValue ?? activity.value, tint: activity.tint, large: true,
                                  textColor: activity.valueTint ?? (CompactActivityView.tintedValueKinds.contains(activity.kind) ? activity.tint : nil))
            }
            .padding(.horizontal, Self.sideInset)
            .frame(maxHeight: .infinity)
            .padding(.bottom, activity.actions.isEmpty ? 10 : 0)
            if !activity.actions.isEmpty {
                ActivityActionRow(actions: activity.actions)
                    .padding(.horizontal, Self.sideInset)
                    .frame(height: NotchViewModel.actionRowHeight - 6)
                    .padding(.bottom, 14)
            }
        }
    }
}

/// 상세 카드 아래 버튼 줄 (허용·거부 등). 주 버튼은 흰 바탕, 위험 버튼은 빨간 글자.
struct ActivityActionRow: View {
    var actions: [ActivityAction]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(actions) { action in
                Button(action: action.run) {
                    Text(action.title)
                        .font(.island(.subhead, .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .foregroundStyle(action.role == .primary ? Color.black : (action.role == .destructive ? Color.red : Color.white))
                        .background(Capsule().fill(action.role == .primary ? Color.white : Color.white.opacity(0.14)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
            }
        }
    }
}

/// 숫자가 바뀔 때 위로 밀려 올라가며 바뀌는 텍스트.
/// SwiftUI의 `.contentTransition(.numericText())`는 이 macOS에서 값이 바뀔 때마다 약 1MB를 놓아주지 않아
/// (타이머·다운로드처럼 계속 바뀌는 숫자에서 메모리가 계속 늘어남) 직접 구현한 가벼운 전환으로 대체한다.
struct RollingText: View {
    var text: String
    /// 숫자가 커지면 위로, 작아지면 아래로 굴러간다. nil이면 이전 값과 비교해 자동으로 정한다.
    var up: Bool? = nil

    private final class Memory {
        var value: Double?
        var up = true
    }
    private let memory = State(initialValue: Memory())

    private var goingUp: Bool {
        if let up { return up }
        let m = memory.wrappedValue
        let digits = text.filter { $0.isNumber || $0 == "." }
        if let v = Double(digits) {
            if let old = m.value, v != old { m.up = v > old }
            m.value = v
        }
        return m.up
    }

    var body: some View {
        let rising = goingUp
        // 글자를 오른쪽 끝에서부터의 자리로 구분해, 바뀐 자리만 굴러가게 한다 (예: 46→47이면 1의 자리만)
        let chars = Array(text)
        HStack(spacing: 0) {
            // 식별자 = 오른쪽 끝에서부터의 자리 (자릿수가 바뀌어도 1의 자리는 1의 자리로 유지)
            ForEach(Array((0..<chars.count).reversed()), id: \.self) { place in
                RollingDigit(char: chars[chars.count - 1 - place], rising: rising)
            }
        }
        .clipped()
        .animation(.spring(duration: 0.3, bounce: 0.1), value: text)
    }
}

/// 한 자리 글자. 글자가 바뀔 때만 위/아래로 굴러간다.
private struct RollingDigit: View {
    let char: Character
    let rising: Bool

    var body: some View {
        ZStack {
            Text(String(char))
                .id(char)
                .transition(.asymmetric(
                    insertion: .move(edge: rising ? .bottom : .top).combined(with: .opacity),
                    removal: .move(edge: rising ? .top : .bottom).combined(with: .opacity)
                ))
        }
        .clipped()
    }
}

extension Image {
    /// 계속 바뀌는 이미지(앨범아트, 스크린샷 썸네일)용.
    /// `Image(nsImage:)`는 AppKit 외형 렌더러(CoreUI)의 캐시에 그린 결과를 남겨 곡이나 스크린샷이 바뀔 때마다
    /// 수백 KB~1MB 이상씩 메모리가 쌓이므로, CGImage로 직접 그려 그 캐시를 거치지 않는다.
    init(uncached image: NSImage) {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            self.init(decorative: cg, scale: 2)
        } else {
            self.init(nsImage: image)
        }
    }
}

/// 배터리 알림 아이콘 정보 (잔량 0~1, 충전 중이면 번개)
struct BatteryGlyphInfo: Equatable {
    var level: Double
    var charging: Bool
}

/// 충전·부족·완충 알림이 함께 쓰는 배터리 아이콘. 크기·모양이 같고 채움 양과 색만 다르다.
/// 충전 중에는 배터리 위에 번개를 겹친다(번개 둘레는 검은 테두리로 떼어 보이게).
struct BatteryGlyph: View {
    var info: BatteryGlyphInfo
    var tint: Color
    /// 아이콘 가로 길이 (세로는 가로의 0.5)
    var width: CGFloat

    var body: some View {
        let h = width * 0.5
        let bodyW = width - width * 0.08
        let stroke = max(1.2, width * 0.06)
        let inset = stroke + max(1, width * 0.05)
        let corner = h * 0.3
        let fillW = max(h * 0.18, (bodyW - inset * 2) * CGFloat(min(max(info.level, 0), 1)))
        HStack(spacing: width * 0.025) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: stroke)
                RoundedRectangle(cornerRadius: max(1, corner - inset * 0.6), style: .continuous)
                    .fill(tint)
                    .frame(width: fillW, height: h - inset * 2)
                    .padding(.leading, inset)
            }
            .frame(width: bodyW, height: h)
            .overlay {
                if info.charging {
                    ZStack {
                        // 번개 둘레를 검게 비워 채움과 구분
                        Image(systemName: "bolt.fill")
                            .font(.system(size: h * 1.02, weight: .black))
                            .foregroundStyle(.black)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: h * 0.82, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            RoundedRectangle(cornerRadius: width * 0.03, style: .continuous)
                .fill(Color.white.opacity(0.45))
                .frame(width: width * 0.055, height: h * 0.36)
        }
        .frame(width: width, height: h)
    }
}

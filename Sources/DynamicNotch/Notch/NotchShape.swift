import SwiftUI

/// 물리 노치처럼 위쪽 모서리는 바깥으로 휘고(오목) 아래쪽 모서리는 둥근 도형.
/// 아래쪽 모서리는 다이내믹 아일랜드처럼 곡률이 끊기지 않는 연속 모서리(.continuous)로 그린다.
/// 두 반경을 animatableData로 노출해 크기와 함께 모서리까지 연속으로 변형된다 (가이드라인 3.2).
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let t = min(topRadius, w / 4)
        // 연속 모서리는 반경의 약 1.53배 앞에서 휘기 시작하므로, 위쪽 오목 모서리와 만나지 않게 그만큼 줄인다
        let b = max(0, min(bottomRadius, (w - 2 * t) / 2, (h - t) / 1.53))
        // 몸통: 위쪽 모서리가 화면 위로 숨도록 위로 b만큼 늘린 연속 모서리 사각형
        let body = RoundedRectangle(cornerRadius: b, style: .continuous)
            .path(in: CGRect(x: rect.minX + t, y: rect.minY - b, width: max(0, w - 2 * t), height: h + b))
        guard t > 0 else { return body }
        // 양옆 위의 오목 모서리 (몸통과 1pt 겹쳐 이음매가 보이지 않게)
        var flares = Path()
        flares.move(to: CGPoint(x: rect.minX, y: rect.minY))
        flares.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                            control: CGPoint(x: rect.minX + t, y: rect.minY))
        flares.addLine(to: CGPoint(x: rect.minX + t + 1, y: rect.minY + t))
        flares.addLine(to: CGPoint(x: rect.minX + t + 1, y: rect.minY))
        flares.closeSubpath()
        flares.move(to: CGPoint(x: rect.minX + w, y: rect.minY))
        flares.addLine(to: CGPoint(x: rect.minX + w - t - 1, y: rect.minY))
        flares.addLine(to: CGPoint(x: rect.minX + w - t - 1, y: rect.minY + t))
        flares.addLine(to: CGPoint(x: rect.minX + w - t, y: rect.minY + t))
        flares.addQuadCurve(to: CGPoint(x: rect.minX + w, y: rect.minY),
                            control: CGPoint(x: rect.minX + w - t, y: rect.minY))
        flares.closeSubpath()
        return Path(body.cgPath.union(flares.cgPath))
    }
}

/// 가로 흔들림 효과 (타이머 종료 등).
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(animatableData * .pi * 6) * 7, y: 0))
    }
}

/// 콘텐츠 등장/퇴장 시 블러 전환.
struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    /// 도형이 줄어들 때 새로 나타나는 내용: 제자리에서 옅게 나타나기만 한다 (바깥으로 이동하지 않음)
    static var notchContentInPlace: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: BlurModifier(radius: 6), identity: BlurModifier(radius: 0))
                .combined(with: .opacity),
            removal: AnyTransition.scale(scale: 0.6, anchor: .top)
                .combined(with: .opacity)
                .animation(.easeOut(duration: 0.16))
        )
    }

    static var notchContent: AnyTransition {
        .asymmetric(
            // 나타날 때는 노치(위 가운데)에서 바깥으로 퍼지며: 왼쪽 요소는 왼쪽으로, 오른쪽 요소는 오른쪽으로 나온다.
            insertion: .modifier(active: BlurModifier(radius: 8), identity: BlurModifier(radius: 0))
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.45, anchor: .top)),
            // 사라지는 뷰는 마지막 위치에 머무르므로, 가운데(노치)로 오므라들며 빠르게 사라지게 한다.
            // 처음부터 빠르게 옅어지며(easeOut) 노치(위 가운데)로 오므라든다 → 줄어드는 도형 밖으로 보이지 않음
            removal: AnyTransition.scale(scale: 0.6, anchor: .top)
                .combined(with: .opacity)
                .animation(.easeOut(duration: 0.16))
        )
    }
}

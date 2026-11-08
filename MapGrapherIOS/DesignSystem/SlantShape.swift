import SwiftUI

/// 角を斜めに落とした面（台形・平行四辺形）。同じ角丸の箱が並ぶのを避けるための面。
///
/// 4つの角それぞれについて、横にどれだけ内側へ寄せるか（`insetTopLeft`など）と、角の丸み（`radiusTopLeft`など）を決める。
/// 画面の端から出てくる面は、端に付く側の角を丸めずに置く。AndroidのSlantShapeDrawableと同じ作り方。
struct SlantShape: Shape {
    var insetTopLeft: CGFloat = 0
    var insetTopRight: CGFloat = 0
    var insetBottomRight: CGFloat = 0
    var insetBottomLeft: CGFloat = 0
    var radiusTopLeft: CGFloat = 0
    var radiusTopRight: CGFloat = 0
    var radiusBottomRight: CGFloat = 0
    var radiusBottomLeft: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let xs = [rect.minX + insetTopLeft, rect.maxX - insetTopRight,
                  rect.maxX - insetBottomRight, rect.minX + insetBottomLeft]
        let ys = [rect.minY, rect.minY, rect.maxY, rect.maxY]
        let radii = [radiusTopLeft, radiusTopRight, radiusBottomRight, radiusBottomLeft]
        var path = Path()
        for i in 0..<4 {
            let previous = CGPoint(x: xs[(i + 3) % 4], y: ys[(i + 3) % 4])
            let corner = CGPoint(x: xs[i], y: ys[i])
            let next = CGPoint(x: xs[(i + 1) % 4], y: ys[(i + 1) % 4])
            // 角の前後の辺に沿って丸みの分だけ戻った2点を、角を制御点にした曲線でつなぐ
            let inLength = hypot(corner.x - previous.x, corner.y - previous.y)
            let outLength = hypot(next.x - corner.x, next.y - corner.y)
            guard inLength > 0, outLength > 0 else { continue }
            let radius = min(radii[i], min(inLength, outLength) / 2)
            let start = CGPoint(x: corner.x + (previous.x - corner.x) / inLength * radius,
                                y: corner.y + (previous.y - corner.y) / inLength * radius)
            let end = CGPoint(x: corner.x + (next.x - corner.x) / outLength * radius,
                              y: corner.y + (next.y - corner.y) / outLength * radius)
            if i == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: end, control: corner)
        }
        path.closeSubpath()
        return path
    }
}

/// 押している間だけ少し縮み、離すと弾んで戻る。台形の面やタイルに使う
struct PressableScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(configuration.isPressed
                       ? .easeOut(duration: 0.09)
                       : .spring(response: 0.3, dampingFraction: 0.5),
                       value: configuration.isPressed)
    }
}

/// 案Aの主ボタン。明るい朱の面の下に元の朱の縁を見せ、押すと縁の分だけ沈む
struct RakugakiPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    private let edge: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(AppColors.onAccent)
            .padding(.horizontal, AppSpacing.xLarge)
            .frame(minHeight: 49)
            .background {
                Capsule().fill(isEnabled ? AppColors.shu : AppColors.outline)
            }
            // 縁は面の真下に置き、押していないときだけ縁の幅だけ下にずらして見せる
            .background {
                Capsule()
                    .fill(isEnabled ? AppColors.shuEdge : AppColors.outline)
                    .offset(y: pressed ? 0 : edge)
            }
            .offset(y: pressed ? edge : 0)
            .padding(.bottom, edge)
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

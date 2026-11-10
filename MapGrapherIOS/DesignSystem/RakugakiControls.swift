import SwiftUI

/// 案Aの脇役のボタン。主ボタン（朱・縁つき）の隣に置いても重さがそろうよう、高さと角丸を合わせる
struct RakugakiSecondaryButtonStyle: ButtonStyle {
    enum Kind {
        /// 淡い藤の面。2番目に押してほしいボタン
        case tinted
        /// 白い面に細い線。ほかの方法（Googleなど）
        case outlined
    }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    init(kind: Kind = .tinted) {
        self.kind = kind
    }

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(AppColors.ink)
            .padding(.horizontal, AppSpacing.xLarge)
            .frame(minHeight: 49)
            .background {
                Capsule().fill(kind == .tinted ? AppColors.fujiTint : AppColors.surface)
            }
            .overlay {
                if kind == .outlined {
                    Capsule().strokeBorder(AppColors.outline, lineWidth: 1.5)
                }
            }
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Capsule())
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(pressed ? .easeOut(duration: 0.09) : .spring(response: 0.3, dampingFraction: 0.55),
                       value: pressed)
    }
}

extension View {
    /// 入力欄の見た目。白い面・角丸14・細い線。識別子や読み上げラベルを付けたあと、最後に付ける
    func rakugakiField() -> some View {
        self
            .padding(.horizontal, AppSpacing.large)
            .frame(minHeight: 52)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppColors.outline, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
    }
}

/// 下の辺だけ斜めに切った面。画面の上端から出てくる帯に使う（右下が`drop`だけ上がる）
struct SlantedBottomShape: Shape {
    var drop: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - drop))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

import SwiftUI

/// 地図に出す「ARの気配メーター」。白い角丸の面に、向きの丸・ひとこと・4本の強さを並べる（案A）。
/// 近くにARがないときは、呼び出し側でこの面ごと出さない。
struct NearbyARSensorCard: View {
    /// 1〜4。4がいちばん近い
    let strength: Int
    /// 画面の上を0度とした、ARのある向き。分からないときはnil
    let arrowDegrees: Double?
    /// 見られる距離に入っているか
    let canOpen: Bool

    var body: some View {
        HStack(spacing: 10) {
            dial
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(AppColors.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                bars
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, AppSpacing.large)
        .padding(.vertical, 10)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("ARの気配"))
        .accessibilityValue(Text(spokenValue))
        .accessibilityIdentifier("map.ar-sensor")
    }

    /// 向きの丸。向きが分かるときは矢印、分からないときは「？」
    private var dial: some View {
        ZStack {
            Circle().fill(dialColor)
            if let arrowDegrees {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppColors.onAccent)
                    .rotationEffect(.degrees(arrowDegrees))
                    .animation(.easeOut(duration: 0.2), value: arrowDegrees)
            } else {
                Text("？")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(strength >= 2 ? AppColors.onAccent : AppColors.fujiEdge)
            }
        }
        .frame(width: 44, height: 44)
    }

    /// 遠いうちは淡い藤、近づくと藤、見られる距離では朱
    private var dialColor: Color {
        if canOpen { return AppColors.shu }
        return strength >= 2 ? AppColors.fuji : AppColors.fujiTint
    }

    /// 強さの4本。右へ行くほど背が高い
    private var bars: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(1...4, id: \.self) { step in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(step <= strength ? AppColors.shu : AppColors.ink.opacity(0.12))
                    .frame(width: 22, height: CGFloat(4 + step * 3))
            }
        }
        .frame(height: 16, alignment: .bottom)
    }

    private var label: String {
        if canOpen { return "すぐそこ！カメラでさがそう" }
        switch strength {
        case 4: return "すぐそこ！"
        case 3: return "かなり近い！"
        case 2: return "近づいてきた"
        default: return "なにかの気配がする…"
        }
    }

    /// 読み上げ用。ひとことに、向きを言葉で足す
    private var spokenValue: String {
        guard let arrowDegrees else { return label }
        var relative = arrowDegrees.truncatingRemainder(dividingBy: 360)
        if relative > 180 { relative -= 360 }
        if relative < -180 { relative += 360 }
        let amount = Int(abs(relative).rounded())
        if amount <= 15 { return "\(label)。正面のあたり" }
        return "\(label)。\(relative > 0 ? "右" : "左")へ約\(amount)度"
    }
}

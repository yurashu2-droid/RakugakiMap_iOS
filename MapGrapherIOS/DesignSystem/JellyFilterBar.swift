import SwiftUI
import UIKit

/// 絞り込みのタブ（地図の「すべて・フレンド・24時間」など）。AndroidのJellyFilterTabsと同じ動き。
///
/// - 選んでいる札は色の角丸。インクは使わない
/// - 進む向きの端が先に走り、後ろの端は遅れて弾みながら追いつく。伸びているあいだは札が細くなる
/// - 色はタブごとの色へ途中で移り変わる。選んだ文字は少し傾いて小さくなってから、ぽよんと戻る
/// - 札を指で左右に引っ張っても選べる
struct JellyFilterBar<Item: Hashable>: View {
    struct Segment {
        let item: Item
        let title: LocalizedStringKey
        let color: Color
        let identifier: String
    }

    let segments: [Segment]
    let selection: Item
    let onSelect: (Item) -> Void

    @State private var motion = PillMotion()
    @State private var dragX: CGFloat?
    @State private var popCount = 0
    @State private var wobble = false
    /// 転がり終えたら描き直し、毎コマの更新を止めるための合図
    @State private var settleTick = 0

    private let inset: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let slotWidth = width / CGFloat(max(segments.count, 1))
            ZStack(alignment: .leading) {
                let paused = settleTick >= 0 && !motion.isRunning
                TimelineView(.animation(minimumInterval: nil, paused: paused)) { context in
                    let frame = motion.frame(at: context.date)
                    pill(frame: dragFrame(slotWidth: slotWidth, width: width) ?? frame,
                         height: proxy.size.height - inset * 2)
                }
                HStack(spacing: 0) {
                    ForEach(segments, id: \.item) { segment in
                        label(segment)
                            .frame(width: slotWidth, height: proxy.size.height)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(drag(slotWidth: slotWidth, width: width))
            .onAppear { place(width: width, animated: false) }
            .onChange(of: selection) { place(width: width, animated: true) }
            .onChange(of: width) { place(width: width, animated: false) }
            .task(id: popCount) {
                try? await Task.sleep(for: .seconds(PillMotion.duration + 0.08))
                settleTick += 1
            }
        }
        .frame(height: 44)
        .background(AppColors.surface, in: Capsule())
        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
    }

    private func pill(frame: PillMotion.Frame, height: CGFloat) -> some View {
        let spanWidth = max(frame.right - frame.left, 1)
        // 伸びているほど細く、縮んでいるほど太く（体積が変わらないように見せる）
        let stretch = spanWidth / max(motion.baseWidth, 1)
        let heightScale = min(max(1 / (0.55 + 0.45 * stretch), 0.72), 1.12)
        return Capsule()
            .fill(frame.color)
            .frame(width: spanWidth, height: height * heightScale)
            .scaleEffect(x: wobble ? 0.9 : 1, y: wobble ? 1.12 : 1)
            .offset(x: frame.left)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private func label(_ segment: Segment) -> some View {
        let isSelected = segment.item == selection
        return Button {
            select(segment.item)
        } label: {
            Text(segment.title)
                .font(.subheadline.weight(isSelected ? .heavy : .semibold))
                .foregroundStyle(isSelected ? AppColors.onAccent : AppColors.ink)
                .opacity(isSelected ? 1 : 0.72)
                .keyframeAnimator(initialValue: LabelPop(), trigger: isSelected ? popCount : 0) { content, value in
                    content
                        .scaleEffect(value.scale)
                        .rotationEffect(.degrees(value.angle))
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(0.78, duration: 0.12)
                        SpringKeyframe(1, duration: 0.42, spring: .bouncy(duration: 0.42, extraBounce: 0.25))
                    }
                    KeyframeTrack(\.angle) {
                        CubicKeyframe(-9, duration: 0.12)
                        SpringKeyframe(0, duration: 0.42, spring: .bouncy(duration: 0.42, extraBounce: 0.25))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(segment.identifier)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ item: Item) {
        if item == selection {
            // 同じタブをもう一度押したら、札だけぷるんと揺らす
            withAnimation(.easeOut(duration: 0.08)) { wobble = true }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.35).delay(0.08)) { wobble = false }
            return
        }
        onSelect(item)
    }

    private func place(width: CGFloat, animated: Bool) {
        guard let index = segments.firstIndex(where: { $0.item == selection }), width > 0 else { return }
        let slot = width / CGFloat(segments.count)
        let left = slot * CGFloat(index) + inset
        let right = slot * CGFloat(index + 1) - inset
        let color = segments[index].color
        if animated {
            motion.roll(to: left, right, color: color, now: .now)
            popCount += 1
        } else {
            motion.snap(to: left, right, color: color)
        }
    }

    private func dragFrame(slotWidth: CGFloat, width: CGFloat) -> PillMotion.Frame? {
        guard let dragX else { return nil }
        let half = (slotWidth - inset * 2) / 2
        let center = min(max(dragX, slotWidth / 2), width - slotWidth / 2)
        return PillMotion.Frame(left: center - half, right: center + half, color: motion.currentColor)
    }

    private func drag(slotWidth: CGFloat, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in dragX = value.location.x }
            .onEnded { value in
                dragX = nil
                let index = min(max(Int(value.location.x / slotWidth), 0), segments.count - 1)
                let item = segments[index].item
                if item == selection {
                    // 引っ張って同じ場所に戻したら、指を離した位置から元の場所へ転がす
                    let half = (slotWidth - inset * 2) / 2
                    let center = min(max(value.location.x, slotWidth / 2), width - slotWidth / 2)
                    motion.left = center - half
                    motion.right = center + half
                    place(width: width, animated: true)
                } else {
                    onSelect(item)
                }
            }
    }
}

private struct LabelPop {
    var scale: CGFloat = 1
    var angle: Double = 0
}

/// 札の左右の端と色の動き。端ごとに違う速さで動かすため、毎コマ自分で計算する
struct PillMotion {
    struct Frame {
        let left: CGFloat
        let right: CGFloat
        let color: Color
    }

    var left: CGFloat = 0
    var right: CGFloat = 0
    var baseWidth: CGFloat = 1
    private(set) var currentColor: Color = .clear
    private var fromLeft: CGFloat = 0
    private var fromRight: CGFloat = 0
    private var toLeft: CGFloat = 0
    private var toRight: CGFloat = 0
    private var fromRGB: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
    private var toRGB: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
    private var start: Date?

    static let duration: TimeInterval = 0.46

    var isRunning: Bool {
        guard let start else { return false }
        return Date.now.timeIntervalSince(start) < Self.duration + 0.05
    }

    mutating func snap(to left: CGFloat, _ right: CGFloat, color: Color) {
        self.left = left
        self.right = right
        toLeft = left
        toRight = right
        baseWidth = right - left
        currentColor = color
        toRGB = Self.rgb(color)
        fromRGB = toRGB
        start = nil
    }

    mutating func roll(to left: CGFloat, _ right: CGFloat, color: Color, now: Date) {
        fromLeft = self.left
        fromRight = self.right
        toLeft = left
        toRight = right
        baseWidth = right - left
        fromRGB = Self.rgb(currentColor)
        toRGB = Self.rgb(color)
        currentColor = color
        start = now
        self.left = left
        self.right = right
    }

    func frame(at date: Date) -> Frame {
        guard let start else {
            return Frame(left: toLeft, right: toRight, color: currentColor)
        }
        let t = CGFloat(min(max(date.timeIntervalSince(start) / Self.duration, 0), 1))
        // 進む向きの端は先に、後ろの端は遅れて弾みながら追いつく
        let front = Self.overshoot(min(t / 0.6, 1), tension: 0.9)
        let back = Self.overshoot(min(max((t - 0.16) / 0.84, 0), 1), tension: 2.4)
        var l: CGFloat
        var r: CGFloat
        if toLeft >= fromLeft {
            r = fromRight + (toRight - fromRight) * front
            l = fromLeft + (toLeft - fromLeft) * back
        } else {
            l = fromLeft + (toLeft - fromLeft) * front
            r = fromRight + (toRight - fromRight) * back
        }
        // 後ろの端が追い越しても、札が消えないよう最小の幅を残す
        let minWidth = baseWidth * 0.55
        if r - l < minWidth {
            let mid = (l + r) / 2
            l = mid - minWidth / 2
            r = mid + minWidth / 2
        }
        let c = min(t * 1.6, 1)
        let color = Color(
            red: fromRGB.0 + (toRGB.0 - fromRGB.0) * c,
            green: fromRGB.1 + (toRGB.1 - fromRGB.1) * c,
            blue: fromRGB.2 + (toRGB.2 - fromRGB.2) * c
        )
        return Frame(left: l, right: r, color: color)
    }

    /// AndroidのOvershootInterpolatorと同じ式
    static func overshoot(_ x: CGFloat, tension: CGFloat) -> CGFloat {
        let t = x - 1
        return t * t * ((tension + 1) * t + tension) + 1
    }

    private static func rgb(_ color: Color) -> (CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }
}

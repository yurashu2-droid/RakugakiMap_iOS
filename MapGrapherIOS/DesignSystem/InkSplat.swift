import SwiftUI
import UIKit

/// 計算で描くインクのしぶき。図形を貼り合わせず、インクの粒が紙に当たったときの形を距離場で作る（AndroidのInkSplatDrawableと同じ作り方）。
///
/// - 本体：ゆがんだだまり。低い周波数の波で輪郭を崩す
/// - 指：広がる縁は一定の間隔で指に割れる。本数は縁の長さ÷波長
/// - 指の先：表面張力で丸くふくらむ。さらに先は糸がちぎれた滴（糸の半径aに対して約9aおき、半径は約1.9a）
/// - 細かい飛沫：本体から離れるほど小さい
/// - 紙：輪郭を2段のノイズでゆがめてにじみを出し、縁を少し濃くする（コーヒーリング）
///
/// 部品どうしは滑らかな最小値でつなぐ。seedが同じなら同じ形になる。
/// `progress`を0から1へ動かすと、だまりが広がり、指が伸び、滴が飛び出す。
struct InkSplatField: Sendable {
    let width: Int
    let height: Int

    private struct Finger: Sendable {
        let bx, by, nx, ny, r1, r2, rb, length: Float
    }

    private struct Drop: Sendable {
        let x, y, r: Float
    }

    private let cx: Float
    private let cy: Float
    private let a: Float
    private let b: Float
    private let harmK: [Float] = [2, 3, 4, 5]
    private var harmAmp: [Float] = []
    private var harmPhase: [Float] = []
    private var lambda: Float = 1
    private var fingers: [Finger] = []
    private var drops: [Drop] = []
    private var warpMax: Float = 0
    private var wx: [Float] = []
    private var wy: [Float] = []
    private var mottle: [Float] = []

    private static let tau = Float.pi * 2
    private static let margin: Float = 1.5
    private static let far: Float = 1e4

    init(width: Int, height: Int, seed: Int) {
        self.width = max(width, 1)
        self.height = max(height, 1)
        let w = Float(self.width)
        let h = Float(self.height)
        cx = w / 2
        cy = h / 2
        b = 0.3 * h
        a = max(min(0.36 * w, b * 3.4), b)

        var rng = SeededRandom(seed: UInt64(bitPattern: Int64(seed)))
        harmAmp = harmK.map { k in (0.02 + 0.04 * rng.nextFloat()) / (k - 1).squareRoot() }
        harmPhase = harmK.map { _ in rng.nextFloat() * Self.tau }

        // 縁の長さ（楕円の周長）÷波長で指の本数を決める
        let perimeter = Float.pi * (3 * (a + b) - ((3 * a + b) * (a + 3 * b)).squareRoot())
        let count = min(max(Int((perimeter / (0.8 * b)).rounded()), 7), 16)
        lambda = perimeter / Float(count)
        let impact = rng.nextFloat() * Self.tau
        let theta0 = rng.nextFloat() * Self.tau
        for i in 0..<count {
            let th = theta0 + Self.tau * (Float(i) + rng.range(-0.3, 0.3)) / Float(count)
            var nx = cos(th) / a
            var ny = sin(th) / b
            let nl = hypot(nx, ny)
            nx /= nl
            ny /= nl
            let rr = coreRadius(th) * 0.9
            let bx = cx + a * rr * cos(th)
            let by = cy + b * rr * sin(th)
            let r1 = 0.2 * lambda * rng.range(0.75, 1.25)
            let r2 = r1 * rng.range(0.25, 0.45)
            let rb = r2 * rng.range(1.4, 1.9)
            // 長さはばらつきが大きく（対数正規）、斜めに当たった向きほど長い
            var length = lambda * exp(0.6 * rng.nextGaussian()) * (1 + 0.5 * cos(th - impact))
            let available = room(bx, by, nx, ny)
            length = min(length, available - rb)
            if length < r1 { continue }
            fingers.append(Finger(bx: bx, by: by, nx: nx, ny: ny, r1: r1, r2: r2, rb: rb, length: length))
            if rng.nextFloat() < 0.6 {
                let jet = r2 * 0.75
                let spacing = 9 * jet
                var d = length + rb + spacing * rng.range(0.45, 0.8)
                let dropCount = rng.nextInt(3) == 0 ? 2 : 1
                for k in 0..<dropCount {
                    let rd = 1.89 * jet * pow(0.72, Float(k)) * rng.range(0.85, 1.15)
                    if d + rd > available { break }
                    drops.append(Drop(x: bx + nx * d, y: by + ny * d, r: rd))
                    d += spacing * rng.range(0.8, 1.2)
                }
            }
        }
        for _ in 0..<(8 + rng.nextInt(7)) {
            let th = rng.nextFloat() * Self.tau
            let dx = cos(th)
            let dy = sin(th)
            let edge = 1 / hypot(dx / a, dy / b)
            let u = rng.nextFloat()
            let d = edge * (1.12 + 0.7 * pow(u, 1.4))
            let r = lambda * 0.11 * (1 - 0.55 * u) * rng.range(0.5, 1)
            let x = cx + dx * d
            let y = cy + dy * d
            if r >= 0.9, x - r >= Self.margin, x + r <= w - Self.margin,
               y - r >= Self.margin, y + r <= h - Self.margin {
                drops.append(Drop(x: x, y: y, r: r))
            }
        }

        // 紙ににじむ縁：低い周波数で大きくゆがめ、細かい凹凸を足す
        let f1 = 1 / (0.45 * b)
        let amp1 = 0.06 * b
        let f2 = 1 / (0.12 * b)
        let amp2 = 0.025 * b
        let fm = 1 / (0.7 * b)
        warpMax = amp1 + amp2
        let total = self.width * self.height
        wx = [Float](repeating: 0, count: total)
        wy = [Float](repeating: 0, count: total)
        mottle = [Float](repeating: 0, count: total)
        for y in 0..<self.height {
            for x in 0..<self.width {
                let px = Float(x) + 0.5
                let py = Float(y) + 0.5
                let i = y * self.width + x
                wx[i] = px + amp1 * (Self.noise(px * f1, py * f1, seed &+ 11) - 0.5) * 2
                    + amp2 * (Self.noise(px * f2, py * f2, seed &+ 13) - 0.5) * 2
                wy[i] = py + amp1 * (Self.noise(px * f1 + 31.7, py * f1, seed &+ 17) - 0.5) * 2
                    + amp2 * (Self.noise(px * f2 + 9.1, py * f2, seed &+ 19) - 0.5) * 2
                mottle[i] = (Self.noise(px * fm, py * fm, seed &+ 23) - 0.5) * 0.08
            }
        }
    }

    /// 0〜1の濃さ（アルファ）と、縁の濃さを掛けた明るさを1画素ずつ返す
    func coverage(progress rawProgress: Float) -> (alpha: [Float], shade: [Float]) {
        let progress = min(max(rawProgress, 0), 1)
        var dist = [Float](repeating: Self.far, count: width * height)
        let pc = Self.ease(progress / 0.45)
        let pf = Self.ease((progress - 0.08) / 0.7)
        let pd = Self.ease((progress - 0.25) / 0.75)
        let scale = 0.55 + 0.45 * pc
        let ca = a * scale
        let cb = b * scale
        let cmin = min(ca, cb)

        // 本体のだまり
        let ampSum = harmAmp.reduce(0, +)
        let pad = warpMax + 2
        forBox(cx - ca * (1 + ampSum) - pad, cy - cb * (1 + ampSum) - pad,
               cx + ca * (1 + ampSum) + pad, cy + cb * (1 + ampSum) + pad) { i in
            let ex = (wx[i] - cx) / ca
            let ey = (wy[i] - cy) / cb
            let d = (hypot(ex, ey) - coreRadius(atan2(ey, ex))) * cmin
            if d < dist[i] { dist[i] = d }
        }

        // 指（付け根は滑らかにつなぎ、先は丸くふくらむ）
        let kf = 0.35 * lambda
        for f in fingers {
            let length = f.length * pf
            if length < 0.5 { continue }
            let bx = cx + (f.bx - cx) * scale
            let by = cy + (f.by - cy) * scale
            let tx = bx + f.nx * length
            let ty = by + f.ny * length
            let rb = f.rb * min(1, pf * 1.5)
            let reach = max(f.r1, rb) + kf + warpMax + 1
            forBox(min(bx, tx) - reach, min(by, ty) - reach, max(bx, tx) + reach, max(by, ty) + reach) { i in
                let px = wx[i]
                let py = wy[i]
                var d = Self.unevenCapsule(px, py, bx, by, f.nx, f.ny, f.r1, f.r2, length)
                d = Self.smin(d, hypot(px - tx, py - ty) - rb, f.r2)
                dist[i] = Self.smin(dist[i], d, kf)
            }
        }

        // ちぎれた滴と飛沫は、中心から飛んで行く
        if pd > 0 {
            let grow = min(1, pd * 1.4)
            for drop in drops {
                let x = cx + (drop.x - cx) * pd
                let y = cy + (drop.y - cy) * pd
                let r = drop.r * grow
                let reach = r + warpMax + 1
                forBox(x - reach, y - reach, x + reach, y + reach) { i in
                    let d = hypot(wx[i] - x, wy[i] - y) - r
                    if d < dist[i] { dist[i] = d }
                }
            }
        }

        let rimWidth = max(1, 0.06 * b)
        var alpha = [Float](repeating: 0, count: dist.count)
        var shade = [Float](repeating: 1, count: dist.count)
        for i in dist.indices {
            let d = dist[i]
            let value = min(max(0.5 - d, 0), 1)
            guard value > 0 else { continue }
            // 縁ほど少し濃い（乾くときインクが縁に集まる）
            var rim = 1 - min(max(-d / rimWidth, 0), 1)
            rim = rim * rim * (3 - 2 * rim)
            alpha[i] = value
            shade[i] = 1 - 0.13 * rim + mottle[i]
        }
        return (alpha, shade)
    }

    /// 指定の色で塗った画像を作る
    func image(progress: Float, color: UIColor) -> CGImage? {
        var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, al: CGFloat = 0
        color.getRed(&r, green: &g, blue: &bl, alpha: &al)
        let (alpha, shade) = coverage(progress: progress)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in alpha.indices where alpha[i] > 0 {
            let s = CGFloat(shade[i])
            let o = i * 4
            let alphaValue = CGFloat(alpha[i])
            // 乗算済みアルファで並べる
            bytes[o] = Self.byte(r * s * alphaValue)
            bytes[o + 1] = Self.byte(g * s * alphaValue)
            bytes[o + 2] = Self.byte(bl * s * alphaValue)
            bytes[o + 3] = Self.byte(alphaValue)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    private func coreRadius(_ th: Float) -> Float {
        var r: Float = 1
        for i in 0..<harmK.count { r += harmAmp[i] * sin(harmK[i] * th + harmPhase[i]) }
        return r
    }

    // 点(x,y)から向き(dx,dy)へ、枠の内側にどこまで進めるか
    private func room(_ x: Float, _ y: Float, _ dx: Float, _ dy: Float) -> Float {
        let w = Float(width)
        let h = Float(height)
        var t = Float.greatestFiniteMagnitude
        if dx > 1e-6 { t = min(t, (w - Self.margin - x) / dx) }
        if dx < -1e-6 { t = min(t, (Self.margin - x) / dx) }
        if dy > 1e-6 { t = min(t, (h - Self.margin - y) / dy) }
        if dy < -1e-6 { t = min(t, (Self.margin - y) / dy) }
        return t
    }

    private func forBox(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ block: (Int) -> Void) {
        let xs = max(0, Int(x0.rounded(.down)))
        let ys = max(0, Int(y0.rounded(.down)))
        let xe = min(width - 1, Int(x1) + 1)
        let ye = min(height - 1, Int(y1) + 1)
        guard xs <= xe, ys <= ye else { return }
        for y in ys...ye {
            let row = y * width
            for x in xs...xe { block(row + x) }
        }
    }

    private static func byte(_ value: CGFloat) -> UInt8 {
        UInt8(min(max((value * 255).rounded(), 0), 255))
    }

    private static func ease(_ t: Float) -> Float {
        let c = min(max(t, 0), 1)
        let inv = 1 - c
        return 1 - inv * inv * inv
    }

    /// 2つの距離を滑らかにつなぐ最小値。kが大きいほど付け根が太くなる
    private static func smin(_ a: Float, _ b: Float, _ k: Float) -> Float {
        if k <= 0 { return min(a, b) }
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k * 0.25
    }

    /// 半径r1からr2へ細る棒までの距離。(ax,ay)から単位方向(dx,dy)へ長さlen
    private static func unevenCapsule(_ px: Float, _ py: Float, _ ax: Float, _ ay: Float,
                                      _ dx: Float, _ dy: Float, _ r1: Float, _ r2: Float, _ len: Float) -> Float {
        let lx = px - ax
        let ly = py - ay
        let qy = lx * dx + ly * dy
        let qx = abs(-lx * dy + ly * dx)
        let sb = (r1 - r2) / len
        let sa = max(1 - sb * sb, 0).squareRoot()
        let k = -sb * qx + sa * qy
        if k < 0 { return hypot(qx, qy) - r1 }
        if k > sa * len { return hypot(qx, qy - len) - r2 }
        return qx * sa + qy * sb - r1
    }

    private static func hash(_ ix: Int32, _ iy: Int32, _ seed: Int32) -> Float {
        var h = ix &* 374_761_393 &+ iy &* 668_265_263 &+ seed &* 1_442_695_041
        h = (h ^ Int32(bitPattern: UInt32(bitPattern: h) >> 13)) &* 1_274_126_177
        h = h ^ Int32(bitPattern: UInt32(bitPattern: h) >> 16)
        return Float(h & 0xFF_FFFF) / 16_777_215
    }

    private static func noise(_ x: Float, _ y: Float, _ seed: Int) -> Float {
        let fx0 = x.rounded(.down)
        let fy0 = y.rounded(.down)
        let ix = Int32(truncatingIfNeeded: Int(fx0))
        let iy = Int32(truncatingIfNeeded: Int(fy0))
        let s = Int32(truncatingIfNeeded: seed)
        let fx = x - fx0
        let fy = y - fy0
        let ux = fx * fx * (3 - 2 * fx)
        let uy = fy * fy * (3 - 2 * fy)
        let a = hash(ix, iy, s)
        let b = hash(ix &+ 1, iy, s)
        let c = hash(ix, iy &+ 1, s)
        let d = hash(ix &+ 1, iy &+ 1, s)
        return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy
    }
}

/// seedが同じなら同じ並びを返す乱数（SplitMix64）
struct SeededRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextFloat() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    mutating func nextInt(_ upperBound: Int) -> Int {
        Int(next() % UInt64(upperBound))
    }

    mutating func range(_ from: Float, _ to: Float) -> Float {
        from + (to - from) * nextFloat()
    }

    /// 平均0・標準偏差1の正規乱数（ボックス＝ミュラー法）
    mutating func nextGaussian() -> Float {
        let u1 = max(nextFloat(), 1e-7)
        let u2 = nextFloat()
        return (-2 * log(u1)).squareRoot() * cos(2 * Float.pi * u2)
    }
}

/// インクのしぶきを置く部品。`splashKey`が変わるたびに、しぶきが広がる動きを最初から流す。
/// 使うのは「選んでいる」「のこした」印だけ。飾りには使わない。
struct InkSplatView: View {
    let seed: Int
    let color: Color
    let splashKey: AnyHashable
    let animated: Bool

    @Environment(\.displayScale) private var displayScale
    @State private var startDate: Date?
    @State private var cache = InkSplatCache()

    init(seed: Int, color: Color, splashKey: AnyHashable = 0, animated: Bool = true) {
        self.seed = seed
        self.color = color
        self.splashKey = splashKey
        self.animated = animated
        // 最初のコマから広がり始める（いきなり広がり切った形を見せない）
        _startDate = State(initialValue: animated ? Date() : nil)
    }

    private static let duration: TimeInterval = 0.42

    var body: some View {
        GeometryReader { proxy in
            let pixelWidth = Int((proxy.size.width * displayScale).rounded())
            let pixelHeight = Int((proxy.size.height * displayScale).rounded())
            TimelineView(.animation(minimumInterval: nil, paused: startDate == nil)) { context in
                let value = progress(at: context.date)
                if let image = cache.image(width: pixelWidth, height: pixelHeight, seed: seed,
                                           color: UIColor(color), progress: value) {
                    Image(decorative: image, scale: displayScale)
                        .resizable()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        // 広がり終えたら毎コマの描き直しを止める
        .task(id: splashKey) {
            guard animated else { return }
            startDate = .now
            try? await Task.sleep(for: .seconds(Self.duration + 0.05))
            startDate = nil
        }
    }

    private func progress(at date: Date) -> Float {
        guard let startDate else { return 1 }
        let t = date.timeIntervalSince(startDate) / Self.duration
        return Float(min(max(t, 0), 1))
    }
}

/// 形の計算（重い）は大きさとseedごとに一度だけ行い、進み具合ごとの画像も使い回す
@MainActor
final class InkSplatCache {
    private var field: InkSplatField?
    private var key: (Int, Int, Int) = (0, 0, 0)
    private var images: [Int: CGImage] = [:]

    func image(width: Int, height: Int, seed: Int, color: UIColor, progress: Float) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        if field == nil || key != (width, height, seed) {
            field = InkSplatField(width: width, height: height, seed: seed)
            key = (width, height, seed)
            images.removeAll()
        }
        // 進み具合は30段に丸めて使い回す
        let step = Int((progress * 30).rounded())
        if let cached = images[step] { return cached }
        let image = field?.image(progress: Float(step) / 30, color: color)
        images[step] = image
        return image
    }
}

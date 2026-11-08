import SwiftUI
import UIKit

enum AppColors {
    static let paper = Color("AppPaper")
    static let ink = Color("AppInk")
    static let coral = Color("AppCoral")
    static let mint = Color("AppMint")

    // 案A：明るい朱と藤。主役の明るい色は夜も同じにし、淡い色と地の色だけ夜に暗くする（Androidのcolors.xmlと同じ値）
    static let shu = fixed(0xF2616C)
    static let shuEdge = fixed(0xC9434F)
    static let shuTint = dynamic(light: 0xFDE0E3, dark: 0x4A2A33)
    static let fuji = fixed(0xA58BF0)
    static let fujiEdge = fixed(0x7356B6)
    static let fujiTint = dynamic(light: 0xECE6FB, dark: 0x2E2847)
    static let yellow = fixed(0xFFC93C)
    static let yellowEdge = fixed(0xD9A21B)
    static let yellowTint = dynamic(light: 0xFFF1C7, dark: 0x3A3220)
    static let sky = fixed(0x8ED9F4)
    static let skyTint = dynamic(light: 0xDFF3FB, dark: 0x1E3340)
    static let lime = fixed(0xC8E86B)
    static let limeTint = dynamic(light: 0xEDF6D2, dark: 0x2B3320)

    /// 明るい色の面にのせる文字。夜も墨のまま
    static let onAccent = fixed(0x20263D)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x242738)
    static let muted = dynamic(light: 0x6F7080, dark: 0xC6C3CE)
    static let outline = dynamic(light: 0xE4DEDA, dark: 0x464A5D)

    private static func fixed(_ hex: UInt32) -> Color {
        Color(uiColor: uiColor(hex))
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            uiColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

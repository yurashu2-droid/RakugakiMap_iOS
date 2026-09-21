import Foundation

enum ARPlaneGeometryError: Error {
    case invalidDimensions
}

/// 画像の縦横比を保ったまま、AR上の表示寸法をメートルで求める。
struct ARPlaneGeometry {
    let widthM: Double
    let heightM: Double
    var standingCenterHeightM: Double { heightM / 2 }

    init(pixelWidth: Double, pixelHeight: Double, displayWidthM: Double) throws {
        guard pixelWidth.isFinite, pixelHeight.isFinite, displayWidthM.isFinite,
              pixelWidth > 0, pixelHeight > 0,
              (0.1...10).contains(displayWidthM) else {
            throw ARPlaneGeometryError.invalidDimensions
        }

        let heightM = (pixelHeight / pixelWidth) * displayWidthM
        guard heightM.isFinite, heightM > 0,
              Float(displayWidthM).isFinite, Float(displayWidthM) > 0,
              Float(heightM).isFinite, Float(heightM) > 0 else {
            throw ARPlaneGeometryError.invalidDimensions
        }

        self.widthM = displayWidthM
        self.heightM = heightM
    }
}

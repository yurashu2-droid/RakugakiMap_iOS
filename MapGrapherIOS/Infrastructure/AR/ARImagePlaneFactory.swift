import RealityKit
import UIKit

enum ARImagePlaneError: Error {
    case missingPixels
}

@MainActor
enum ARImagePlaneFactory {
    static func makeEntity(image: UIImage, displayWidthM: Double = 1) throws -> ModelEntity {
        guard let pixels = image.cgImage else {
            throw ARImagePlaneError.missingPixels
        }

        let geometry = try ARPlaneGeometry(
            pixelWidth: Double(pixels.width),
            pixelHeight: Double(pixels.height),
            displayWidthM: displayWidthM
        )
        // RealityKitの寸法型はFloat。変換後も有限かつ正であることを幾何型が保証する。
        let mesh = MeshResource.generatePlane(
            width: Float(geometry.widthM),
            depth: Float(geometry.heightM)
        )
        let texture = try TextureResource.generate(
            from: pixels,
            withName: "AR試作用透過画像",
            options: .init(semantic: .color)
        )
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        material.faceCulling = .none
        return ModelEntity(mesh: mesh, materials: [material])
    }

    /// 個人情報を含まない1000×500pxの透明な試験画像を実行時に生成する。
    static func makeFixtureImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 1_000, height: 500), format: format)
            .image { _ in
                UIColor(red: 0.96, green: 0.23, blue: 0.45, alpha: 0.78).setFill()
                UIBezierPath(ovalIn: CGRect(x: 250, y: 25, width: 500, height: 450)).fill()
                UIColor.white.withAlphaComponent(0.9).setStroke()
                let ring = UIBezierPath(ovalIn: CGRect(x: 325, y: 100, width: 350, height: 300))
                ring.lineWidth = 18
                ring.stroke()
                // 上下と左右の反転を実機で判別できる非対称の目印。
                UIColor(red: 0.04, green: 0.20, blue: 0.45, alpha: 1).setFill()
                let arrow = UIBezierPath()
                arrow.move(to: CGPoint(x: 500, y: 45))
                arrow.addLine(to: CGPoint(x: 455, y: 125))
                arrow.addLine(to: CGPoint(x: 485, y: 125))
                arrow.addLine(to: CGPoint(x: 485, y: 195))
                arrow.addLine(to: CGPoint(x: 515, y: 195))
                arrow.addLine(to: CGPoint(x: 515, y: 125))
                arrow.addLine(to: CGPoint(x: 545, y: 125))
                arrow.close()
                arrow.fill()
                UIBezierPath(ovalIn: CGRect(x: 105, y: 60, width: 80, height: 80)).fill()
            }
    }
}

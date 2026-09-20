import UIKit

@MainActor
enum PhotoCompositeRenderer {
    static func render(photo: UIImage, overlays: [UIImage]) -> UIImage {
        guard !overlays.isEmpty else { return photo }
        let size = CGSize(width: CGFloat(photo.cgImage?.width ?? Int(photo.size.width)),
                          height: CGFloat(photo.cgImage?.height ?? Int(photo.size.height)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let bounds = CGRect(origin: .zero, size: size)
            photo.draw(in: bounds)
            for overlay in overlays { overlay.draw(in: bounds) }
        }
    }
}

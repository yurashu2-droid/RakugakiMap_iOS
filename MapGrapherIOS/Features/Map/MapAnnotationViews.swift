@preconcurrency import MapKit
import UIKit
import MapGrapherCore

@MainActor
final class PlayerAnnotationView: MKAnnotationView {
    private static let size = CGSize(width: 72, height: 98)
    private static let frames: [UIImage] = {
        guard let sheet = UIImage(named: "AndroidPlayer")?.cgImage else { return [] }
        let frameWidth = sheet.width / 2
        let cropX = frameWidth / 4
        let cropWidth = frameWidth / 2
        let cropHeight = Int(Double(sheet.height) * 0.55)
        return (0..<2).compactMap { index in
            let rect = CGRect(x: CGFloat(index * frameWidth + cropX), y: 0,
                              width: CGFloat(cropWidth), height: CGFloat(cropHeight))
            return sheet.cropping(to: rect).map { UIImage(cgImage: $0) }
        }
    }()

    private let sprite = UIImageView()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        bounds = CGRect(origin: .zero, size: Self.size)
        centerOffset = CGPoint(x: 0, y: -Self.size.height / 2)
        sprite.frame = bounds
        sprite.contentMode = .scaleAspectFit
        sprite.animationImages = Self.frames
        sprite.animationDuration = 1
        sprite.image = Self.frames.first ?? UIImage(systemName: "figure.walk")
        addSubview(sprite)
        sprite.startAnimating()
        isAccessibilityElement = true
        accessibilityLabel = "現在地"
        accessibilityIdentifier = "map.player"
        displayPriority = .required
    }

    required init?(coder: NSCoder) { fatalError("Storyboardには対応していません") }
}

@MainActor
final class PhotoPinAnnotationView: MKAnnotationView {
    private static let size = CGSize(width: 60, height: 70)
    private let preview = UIImageView()
    private let frameImage = UIImageView(image: UIImage(named: "AndroidPhotoPin"))
    private var representedPhotoID: UUID?
    private var loadTask: Task<Void, Never>?

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        bounds = CGRect(origin: .zero, size: Self.size)
        centerOffset = CGPoint(x: 0, y: -Self.size.height / 2)
        preview.frame = CGRect(x: 8, y: 7, width: 44, height: 44)
        preview.contentMode = .scaleAspectFill
        preview.clipsToBounds = true
        preview.layer.cornerRadius = 22
        preview.backgroundColor = UIColor(named: "AppPaper")
        addSubview(preview)
        frameImage.frame = bounds
        frameImage.contentMode = .scaleToFill
        addSubview(frameImage)
        canShowCallout = false
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError("Storyboardには対応していません") }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        representedPhotoID = nil
        preview.image = nil
    }

    func configure(photo: Photo, assetLoader: PrivateAssetLoader?, context: SessionContext?) {
        loadTask?.cancel()
        representedPhotoID = photo.id
        preview.image = nil
        accessibilityLabel = "投稿: \(photo.title)"
        accessibilityIdentifier = "map.photo-pin.\(photo.id.uuidString)"
        guard let assetLoader, let context else { return }
        let asset = photo.thumbnail ?? photo.asset
        let photoID = photo.id
        loadTask = Task { @MainActor [weak self] in
            guard let image = try? await assetLoader.load(
                asset: asset, targetPixelSize: CGSize(width: 88, height: 88), context: context
            ), !Task.isCancelled, self?.representedPhotoID == photoID else { return }
            self?.preview.image = image
        }
    }
}

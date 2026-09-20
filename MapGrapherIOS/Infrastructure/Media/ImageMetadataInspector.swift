import Foundation
import ImageIO

enum ImageMetadataInspector {
    static func hasSensitiveMetadata(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return true
        }
        return properties[kCGImagePropertyGPSDictionary] != nil
            || properties[kCGImagePropertyExifDictionary] != nil
    }
}

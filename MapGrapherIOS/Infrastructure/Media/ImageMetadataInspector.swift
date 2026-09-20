import Foundation
import ImageIO

enum ImageMetadataInspector {
    static func hasSensitiveMetadata(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return true
        }
        // JPEGエンコーダーが画素寸法などの無害なEXIFを生成することがある。
        // 元のメタデータはCGImageへの画素化時に破棄し、出力に位置・端末・注記がないか検査する。
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        return properties[kCGImagePropertyGPSDictionary] != nil
            || exif?[kCGImagePropertyExifMakerNote] != nil
            || exif?[kCGImagePropertyExifUserComment] != nil
            || tiff?[kCGImagePropertyTIFFMake] != nil
            || tiff?[kCGImagePropertyTIFFModel] != nil
    }
}

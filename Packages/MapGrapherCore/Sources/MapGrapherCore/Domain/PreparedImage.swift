import Foundation

public struct PreparedImage: Equatable, Sendable {
    public let fileURL: URL
    public let mimeType: String
    public let byteSize: Int64
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let sha256: String

    public init?(fileURL: URL, mimeType: String, byteSize: Int64,
                 pixelWidth: Int, pixelHeight: Int, sha256: String) {
        guard fileURL.isFileURL,
              mimeType == "image/jpeg" || mimeType == "image/png",
              byteSize > 0, pixelWidth > 0, pixelHeight > 0,
              sha256.count == 64,
              sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            return nil
        }
        self.fileURL = fileURL
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sha256 = sha256
    }
}

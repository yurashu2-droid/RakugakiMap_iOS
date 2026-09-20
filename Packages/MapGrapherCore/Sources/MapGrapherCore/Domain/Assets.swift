import Foundation

public struct AssetReference: Equatable, Codable, Sendable {
    public let bucket: String
    public let path: String

    public init?(bucket: String, path: String) {
        guard !bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              URL(string: bucket)?.scheme == nil,
              URL(string: path)?.scheme == nil,
              !bucket.contains("/"), !bucket.contains("\\"),
              !path.hasPrefix("/"), !path.contains("\\"),
              !path.split(separator: "/", omittingEmptySubsequences: false)
                .contains(where: { $0 == "." || $0 == ".." }) else {
            return nil
        }
        self.bucket = bucket
        self.path = path
    }

    private enum CodingKeys: String, CodingKey {
        case bucket
        case path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bucket = try container.decode(String.self, forKey: .bucket)
        let path = try container.decode(String.self, forKey: .path)
        guard let reference = Self(bucket: bucket, path: path) else {
            throw DecodingError.dataCorruptedError(
                forKey: .path,
                in: container,
                debugDescription: "Storageのbucketまたはpathが不正です"
            )
        }
        self = reference
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bucket, forKey: .bucket)
        try container.encode(path, forKey: .path)
    }
}

public struct SignedAsset: Sendable {
    public let url: URL
    public let expiresAt: Date
    public let context: SessionContext

    public init(url: URL, expiresAt: Date, context: SessionContext) {
        self.url = url
        self.expiresAt = expiresAt
        self.context = context
    }

    public func isUsable(for context: SessionContext, now: Date) -> Bool {
        self.context == context &&
            expiresAt.timeIntervalSinceReferenceDate.isFinite &&
            now.timeIntervalSinceReferenceDate.isFinite &&
            now < expiresAt
    }
}

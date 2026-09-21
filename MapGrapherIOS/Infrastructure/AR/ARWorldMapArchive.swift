import ARKit
import Foundation

enum ARWorldMapArchiveError: Error, Equatable {
    case emptyData
    case oversized
    case invalidAnchorName
    case anchorMismatch
    case invalidArchive
    case unsupportedFormat
}

struct PersistentARPackage: Equatable, Sendable {
    static let formatVersion = 1
    static let maximumBytes = 25 * 1024 * 1024

    let data: Data
    let anchorName: String
    let displayWidthM: Double
    let formatVersion: Int

    init?(
        data: Data,
        anchorName: String,
        displayWidthM: Double,
        formatVersion: Int = Self.formatVersion
    ) {
        guard !data.isEmpty,
              data.count <= Self.maximumBytes,
              ARWorldMapArchive.isValidAnchorName(anchorName),
              displayWidthM.isFinite,
              ARPlacementLimits.widthRange.contains(displayWidthM),
              formatVersion == Self.formatVersion else {
            return nil
        }
        self.data = data
        self.anchorName = anchorName
        self.displayWidthM = displayWidthM
        self.formatVersion = formatVersion
    }
}

enum ARWorldMapArchive {
    static func encode(
        _ worldMap: ARWorldMap,
        requiredAnchorName: String
    ) throws -> Data {
        try validateAnchorNames(
            worldMap.anchors.map(\.name),
            required: requiredAnchorName
        )
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: worldMap,
            requiringSecureCoding: true
        )
        guard !data.isEmpty else { throw ARWorldMapArchiveError.emptyData }
        guard data.count <= PersistentARPackage.maximumBytes else {
            throw ARWorldMapArchiveError.oversized
        }
        return data
    }

    static func decode(
        _ data: Data,
        requiredAnchorName: String,
        maxBytes: Int = PersistentARPackage.maximumBytes
    ) throws -> ARWorldMap {
        guard maxBytes > 0 else { throw ARWorldMapArchiveError.oversized }
        guard !data.isEmpty else { throw ARWorldMapArchiveError.emptyData }
        guard data.count <= maxBytes else { throw ARWorldMapArchiveError.oversized }
        guard isValidAnchorName(requiredAnchorName) else {
            throw ARWorldMapArchiveError.invalidAnchorName
        }
        guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: ARWorldMap.self,
            from: data
        ) else {
            throw ARWorldMapArchiveError.invalidArchive
        }
        try validateAnchorNames(
            worldMap.anchors.map(\.name),
            required: requiredAnchorName
        )
        return worldMap
    }

    static func validateAnchorNames(
        _ names: [String?],
        required: String
    ) throws {
        guard isValidAnchorName(required) else {
            throw ARWorldMapArchiveError.invalidAnchorName
        }
        guard names.compactMap({ $0 }).filter({ $0 == required }).count == 1 else {
            throw ARWorldMapArchiveError.anchorMismatch
        }
    }

    static func isValidAnchorName(_ name: String) -> Bool {
        guard name.count <= 128,
              name.hasPrefix("rakugaki:"),
              !name.contains("/"),
              !name.contains("\\") else {
            return false
        }
        let suffix = name.dropFirst("rakugaki:".count)
        return !suffix.isEmpty && suffix.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
        }
    }
}

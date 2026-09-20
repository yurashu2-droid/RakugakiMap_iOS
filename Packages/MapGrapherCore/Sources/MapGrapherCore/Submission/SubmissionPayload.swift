import Foundation

/// 下書き作成時に固定する入力。再送時に位置や設定を読み直さない。
public enum SubmissionPayload: Codable, Equatable, Sendable {
    case photo(Photo)
    case rakugaki(Rakugaki)
    case ar(AR)
    case groupAnswer(GroupAnswer)

    public struct Photo: Codable, Equatable, Sendable {
        public let title: String
        public let point: GeoPoint
        public let privacy: Visibility
        public let drawPermission: Visibility
        public let requiresApproval: Bool
        public let mimeType: String
        public let byteSize: Int64
        public let sha256: String
        public init(title: String, point: GeoPoint, privacy: Visibility, drawPermission: Visibility,
                    requiresApproval: Bool, mimeType: String, byteSize: Int64, sha256: String) {
            self.title = title; self.point = point; self.privacy = privacy
            self.drawPermission = drawPermission; self.requiresApproval = requiresApproval
            self.mimeType = mimeType; self.byteSize = byteSize; self.sha256 = sha256
        }
    }

    public struct Rakugaki: Codable, Equatable, Sendable {
        public let targetPhotoID: UUID?
        public let mimeType: String
        public let byteSize: Int64
        public let sha256: String
        public init(targetPhotoID: UUID?, mimeType: String, byteSize: Int64, sha256: String) {
            self.targetPhotoID = targetPhotoID; self.mimeType = mimeType
            self.byteSize = byteSize; self.sha256 = sha256
        }
    }

    public struct AR: Codable, Equatable, Sendable {
        public let targetPhotoID: UUID?
        public let targetPhotoOperationID: UUID?
        public let targetRakugakiID: UUID?
        public let unlockRadiusM: Double
        public let discoveryRadiusM: Double
        public let displayWidthM: Double
        public init(targetPhotoID: UUID?, targetPhotoOperationID: UUID?, targetRakugakiID: UUID?,
                    unlockRadiusM: Double, discoveryRadiusM: Double, displayWidthM: Double) {
            self.targetPhotoID = targetPhotoID; self.targetPhotoOperationID = targetPhotoOperationID
            self.targetRakugakiID = targetRakugakiID; self.unlockRadiusM = unlockRadiusM
            self.discoveryRadiusM = discoveryRadiusM; self.displayWidthM = displayWidthM
        }
    }

    public struct GroupAnswer: Codable, Equatable, Sendable {
        public let missionID: UUID
        public let targetPhotoID: UUID?
        public init(missionID: UUID, targetPhotoID: UUID?) {
            self.missionID = missionID; self.targetPhotoID = targetPhotoID
        }
    }
}

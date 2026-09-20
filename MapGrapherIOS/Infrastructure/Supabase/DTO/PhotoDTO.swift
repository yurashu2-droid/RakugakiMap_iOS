import Foundation
import MapGrapherCore

enum SupabaseContract {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let withoutFraction = ISO8601DateFormatter()
            withoutFraction.formatOptions = [.withInternetDateTime]
            guard let date = withFraction.date(from: value) ?? withoutFraction.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                                                       debugDescription: "日時の形式が不正です")
            }
            return date
        }
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

struct NearbyPhotosRequestDTO: Encodable, Sendable {
    let lat: Double
    let lon: Double
    let radiusMeters: Double
}

struct NearbyPhotoDTO: Decodable, Sendable {
    let id: UUID
    let ownerId: UUID
    let ownerName: String?
    let ownerAvatarPath: String?
    let photoPath: String?
    let thumbnailPath: String?
    let title: String?
    let latitude: Double?
    let longitude: Double?
    let privacy: Visibility?
    let drawPermission: Visibility?
    let requiresApproval: Bool?
    let createdAt: Date?
    let likeCount: Int64?
    let likedByMe: Bool?
    let distanceMeters: Double?
}

struct CreatePhotoPinRequestDTO: Encodable, Sendable {
    let title: String
    let lat: Double
    let lon: Double
    let privacy: Visibility
    let drawPermission: Visibility
    let requiresApproval: Bool
    let photoPath: String
    let mimeType: String?
    let byteSize: Int64?
}

struct CreatePhotoPinV2RequestDTO: Encodable, Sendable {
    let clientRequestId: UUID
    let title: String
    let lat: Double
    let lon: Double
    let privacy: Visibility
    let drawPermission: Visibility
    let requiresApproval: Bool
    let photoPath: String
    let mimeType: String
    let byteSize: Int64
}

struct PhotoRowDTO: Decodable, Sendable {
    let id: UUID
    let ownerId: UUID
    let title: String?
    let latitude: Double?
    let longitude: Double?
    let privacy: Visibility?
    let drawPermission: Visibility?
    let requiresApproval: Bool?
    let createdAt: Date?
}

struct PhotoIDRequestDTO: Encodable, Sendable { let targetPhotoId: UUID }
struct UpdatePhotoSettingsRequestDTO: Encodable, Sendable {
    let targetPhotoId: UUID
    let newPrivacy: Visibility
    let newDrawPermission: Visibility
    let newRequiresApproval: Bool
}
struct PhotoPermissionDTO: Decodable, Sendable {
    let canView: Bool
    let canDraw: Bool
    let isOwner: Bool
}
struct LikeResultDTO: Decodable, Sendable {
    let liked: Bool
    let likeCount: Int64
}

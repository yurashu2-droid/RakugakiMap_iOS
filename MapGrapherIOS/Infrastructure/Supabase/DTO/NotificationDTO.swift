import Foundation

struct ListNotificationsRequestDTO: Encodable, Sendable {
    let targetLimit: Int
    let targetBefore: String?
}
struct NotificationIDRequestDTO: Encodable, Sendable { let targetNotificationId: UUID }

indirect enum JSONValue: Codable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let boolean = try? value.decode(Bool.self) { self = .bool(boolean) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? value.decode([JSONValue].self) { self = .array(array) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let x): try value.encode(x)
        case .number(let x): try value.encode(x)
        case .string(let x): try value.encode(x)
        case .array(let x): try value.encode(x)
        case .object(let x): try value.encode(x)
        }
    }
}

struct NotificationDTO: Decodable, Sendable {
    let id: UUID
    let recipientId: UUID
    let actorId: UUID?
    let eventType: String
    let groupId: UUID?
    let missionId: UUID?
    let photoId: UUID?
    let payload: [String: JSONValue]
    let readAt: Date?
    let createdAt: Date
}

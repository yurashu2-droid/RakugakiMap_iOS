import Foundation
import MapGrapherCore

enum GroupAnswerRecoveryPhase: String, Codable, Equatable, Sendable {
    case awaitingPhoto
    case ready
    case submitting
    case outcomeUnknown
    case needsCorrection
    case completed
}

struct GroupAnswerOperation: Codable, Sendable {
    let id: UUID
    let ownerID: UUID
    let groupID: UUID
    let missionID: UUID
    /// サーバーがJSTで決めた日付を保存する。翌日のお題に差し替えない。
    let missionDate: String
    let photoOperationID: UUID
    let createdAt: Date
    var remotePhotoID: UUID?
    var remoteAnswerID: UUID?
    var phase: GroupAnswerRecoveryPhase
    var updatedAt: Date
}

enum GroupAnswerStoreError: Error {
    case invalidPath
    case immutableInputChanged
    case corrupted
}

/// T11の自動再送キューとは独立した、回答操作の所有者別ジャーナル。
actor GroupAnswerRecoveryStore {
    let rootURL: URL

    init(rootURL: URL? = nil) throws {
        if let rootURL {
            guard rootURL.isFileURL else { throw GroupAnswerStoreError.invalidPath }
            self.rootURL = rootURL.standardizedFileURL
        } else {
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                          in: .userDomainMask).first else {
                throw GroupAnswerStoreError.invalidPath
            }
            self.rootURL = support.appendingPathComponent("MapGrapher/GroupAnswers",
                                                           isDirectory: true).standardizedFileURL
        }
        try FileManager.default.createDirectory(at: self.rootURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        guard !Self.isLink(self.rootURL) else { throw GroupAnswerStoreError.invalidPath }
    }

    func load(id: UUID, ownerID: UUID) throws -> GroupAnswerOperation? {
        let url = try fileURL(id: id, ownerID: ownerID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard !Self.isLink(url) else { throw GroupAnswerStoreError.invalidPath }
        let data = try Data(contentsOf: url)
        guard let operation = try? JSONDecoder().decode(GroupAnswerOperation.self, from: data),
              operation.id == id, operation.ownerID == ownerID else {
            throw GroupAnswerStoreError.corrupted
        }
        return operation
    }

    func save(_ operation: GroupAnswerOperation) throws {
        let url = try fileURL(id: operation.id, ownerID: operation.ownerID)
        if let existing = try load(id: operation.id, ownerID: operation.ownerID) {
            guard existing.groupID == operation.groupID,
                  existing.missionID == operation.missionID,
                  existing.missionDate == operation.missionDate,
                  existing.photoOperationID == operation.photoOperationID,
                  existing.createdAt == operation.createdAt,
                  existing.updatedAt <= operation.updatedAt,
                  existing.remotePhotoID == nil || existing.remotePhotoID == operation.remotePhotoID,
                  existing.remoteAnswerID == nil || existing.remoteAnswerID == operation.remoteAnswerID,
                  existing.phase != .completed || operation.phase == .completed else {
                throw GroupAnswerStoreError.immutableInputChanged
            }
        } else {
            // 回答RPCはmission/userでupsertする。別の操作IDから同時送信させない。
            let existingForOwner = try list(ownerID: operation.ownerID)
            guard !existingForOwner.contains(where: {
                $0.missionID == operation.missionID
            }) else { throw GroupAnswerStoreError.immutableInputChanged }
        }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        guard !Self.isLink(directory), !Self.isLink(url) else {
            throw GroupAnswerStoreError.invalidPath
        }
        let data = try JSONEncoder().encode(operation)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path)
    }

    func list(ownerID: UUID) throws -> [GroupAnswerOperation] {
        let directory = rootURL.appendingPathComponent(ownerID.uuidString, isDirectory: true)
        guard !Self.isLink(directory) else { throw GroupAnswerStoreError.invalidPath }
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
            .map { url in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                      let operation = try load(id: id, ownerID: ownerID) else {
                    throw GroupAnswerStoreError.corrupted
                }
                return operation
            }
    }

    private func fileURL(id: UUID, ownerID: UUID) throws -> URL {
        guard !Self.isLink(rootURL) else { throw GroupAnswerStoreError.invalidPath }
        let directory = rootURL.appendingPathComponent(ownerID.uuidString, isDirectory: true)
        guard !Self.isLink(directory) else { throw GroupAnswerStoreError.invalidPath }
        return directory.appendingPathComponent(id.uuidString + ".json").standardizedFileURL
    }

    private static func isLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}

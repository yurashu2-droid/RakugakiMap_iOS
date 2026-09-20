import Foundation

enum DraftFileStoreError: Error, Equatable {
    case invalidPath
    case alreadyExists
    case insufficientCapacity
    case unavailable
}

struct DraftFileStore: Sendable {
    let rootURL: URL

    init(rootURL: URL? = nil) throws {
        if let rootURL, !rootURL.isFileURL {
            throw DraftFileStoreError.invalidPath
        }
        if let rootURL {
            self.rootURL = rootURL.standardizedFileURL
        } else {
            guard let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first else { throw DraftFileStoreError.unavailable }
            self.rootURL = support.appendingPathComponent("MapGrapher/Drafts", isDirectory: true)
                .standardizedFileURL
        }
        try FileManager.default.createDirectory(
            at: self.rootURL, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        guard try !Self.isSymbolicLink(self.rootURL) else {
            throw DraftFileStoreError.invalidPath
        }
    }

    func save(_ data: Data, ownerID: UUID, operationID: UUID,
              fileName: String) throws -> URL {
        guard !data.isEmpty else { throw DraftFileStoreError.invalidPath }
        let destination = try validatedURL(ownerID: ownerID, operationID: operationID,
                                           fileName: fileName)
        let directory = destination.deletingLastPathComponent()
        try validateDirectories(ownerID: ownerID, operationID: operationID)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        try validateDirectories(ownerID: ownerID, operationID: operationID)
        if FileManager.default.fileExists(atPath: destination.path) {
            throw DraftFileStoreError.alreadyExists
        }
        let capacity = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        if let capacity, capacity < Int64(data.count) {
            throw DraftFileStoreError.insufficientCapacity
        }
        let staging = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            try data.write(to: staging, options: .atomic)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: staging.path
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                throw DraftFileStoreError.alreadyExists
            }
            try FileManager.default.moveItem(at: staging, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    func read(_ fileURL: URL, ownerID: UUID, operationID: UUID) throws -> Data {
        guard fileURL.isFileURL else { throw DraftFileStoreError.invalidPath }
        let expectedDirectory = rootURL
            .appendingPathComponent(ownerID.uuidString, isDirectory: true)
            .appendingPathComponent(operationID.uuidString, isDirectory: true)
            .standardizedFileURL
        let standardized = fileURL.standardizedFileURL
        try validateDirectories(ownerID: ownerID, operationID: operationID)
        guard standardized.deletingLastPathComponent() == expectedDirectory,
              !standardized.hasDirectoryPath,
              try !Self.isSymbolicLink(standardized) else {
            throw DraftFileStoreError.invalidPath
        }
        return try Data(contentsOf: standardized)
    }

    private func validatedURL(ownerID: UUID, operationID: UUID,
                              fileName: String) throws -> URL {
        guard !fileName.isEmpty,
              fileName != ".", fileName != "..",
              !fileName.contains("/"), !fileName.contains("\\"),
              !fileName.contains(":"), !fileName.contains("\0"),
              fileName == (fileName as NSString).lastPathComponent else {
            throw DraftFileStoreError.invalidPath
        }
        let directory = rootURL
            .appendingPathComponent(ownerID.uuidString, isDirectory: true)
            .appendingPathComponent(operationID.uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent(fileName, isDirectory: false)
            .standardizedFileURL
        guard destination.deletingLastPathComponent() == directory.standardizedFileURL else {
            throw DraftFileStoreError.invalidPath
        }
        return destination
    }

    private func validateDirectories(ownerID: UUID, operationID: UUID) throws {
        let owner = rootURL.appendingPathComponent(ownerID.uuidString, isDirectory: true)
        let operation = owner.appendingPathComponent(operationID.uuidString, isDirectory: true)
        guard try !Self.isSymbolicLink(rootURL),
              try !Self.isSymbolicLink(owner),
              try !Self.isSymbolicLink(operation) else {
            throw DraftFileStoreError.invalidPath
        }
    }

    private static func isSymbolicLink(_ url: URL) throws -> Bool {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink == true
    }
}

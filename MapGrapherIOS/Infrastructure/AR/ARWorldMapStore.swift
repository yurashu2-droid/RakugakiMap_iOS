import Foundation
import MapGrapherCore
import Supabase

@MainActor
protocol ARWorldMapStoring {
    func upload(package: PersistentARPackage, context: SessionContext) async throws -> AssetReference
    func download(asset: AssetReference, context: SessionContext) async throws -> Data
    func delete(asset: AssetReference, context: SessionContext) async throws
}

@MainActor
private final class UnavailableARWorldMapStore: ARWorldMapStoring {
    func upload(package: PersistentARPackage, context: SessionContext) async throws -> AssetReference {
        throw AppFailure.serviceUnavailable
    }
    func download(asset: AssetReference, context: SessionContext) async throws -> Data {
        throw AppFailure.serviceUnavailable
    }
    func delete(asset: AssetReference, context: SessionContext) async throws {}
}

@MainActor
func makeUnavailableARWorldMapStore() -> any ARWorldMapStoring {
    UnavailableARWorldMapStore()
}

@MainActor
final class ARWorldMapStore: ARWorldMapStoring {
    private static let bucket = "ar-world-maps"
    private static let maxBytes = 25 * 1024 * 1024
    private let gateway: SupabaseGateway
    private let session: any SessionProviding

    init(gateway: SupabaseGateway, session: any SessionProviding) {
        self.gateway = gateway
        self.session = session
    }

    func upload(package: PersistentARPackage, context: SessionContext) async throws -> AssetReference {
        guard !package.data.isEmpty, package.data.count <= Self.maxBytes,
              package.formatVersion == ARWorldMapArchive.formatVersion else {
            throw AppFailure.validation("ARワールドマップのサイズまたは形式が不正です")
        }
        try await check(context)
        let path = "\(context.userID.uuidString.lowercased())/world-maps/\(UUID().uuidString.lowercased()).armap"
        guard let asset = AssetReference(bucket: Self.bucket, path: path) else {
            throw AppFailure.validation("ARワールドマップの保存先が不正です")
        }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("armap")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        do {
            try package.data.write(to: temporaryURL, options: .atomic)
            try await gateway.client.storage.from(Self.bucket).upload(
                path, fileURL: temporaryURL,
                options: FileOptions(contentType: "application/octet-stream", upsert: false))
            try await check(context)
            return asset
        } catch {
            throw Self.map(error)
        }
    }

    func download(asset: AssetReference, context: SessionContext) async throws -> Data {
        guard asset.bucket == Self.bucket else {
            throw AppFailure.validation("ARワールドマップの参照先が不正です")
        }
        try await check(context)
        do {
            let data = try await gateway.client.storage.from(Self.bucket).download(path: asset.path)
            try await check(context)
            guard !data.isEmpty, data.count <= Self.maxBytes else {
                throw AppFailure.validation("ARワールドマップのサイズが不正です")
            }
            return data
        } catch {
            throw Self.map(error)
        }
    }

    func delete(asset: AssetReference, context: SessionContext) async throws {
        guard asset.bucket == Self.bucket else { return }
        try await check(context)
        do {
            try await gateway.client.storage.from(Self.bucket).remove(paths: [asset.path])
            try await check(context)
        } catch {
            throw Self.map(error)
        }
    }

    private func check(_ context: SessionContext) async throws {
        try Task.checkCancellation()
        guard await session.isCurrent(context) else { throw AppFailure.cancelled }
    }

    private static func map(_ error: Error) -> AppFailure {
        if let failure = error as? AppFailure { return failure }
        if error is CancellationError { return .cancelled }
        if let error = error as? StorageError {
            switch error.statusCode {
            case "401": return .needsLogin
            case "403": return .forbidden
            case "404": return .notFound
            case "429": return .rateLimited
            default: return .serviceUnavailable
            }
        }
        if error is URLError { return .offline }
        return .serviceUnavailable
    }
}

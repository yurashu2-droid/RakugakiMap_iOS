import CoreData
import Foundation

enum PersistentContainerFactory {
    static let modelVersion = "MapGrapherStoreV1"

    static func make(storeURL: URL) async throws -> NSPersistentContainer {
        let model = bundledModel() ?? makeModel()
        let container = NSPersistentContainer(name: "MapGrapherStore", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                container.loadPersistentStores { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            // migration失敗時に既存SQLiteを消さない。
            throw SubmissionStoreError.unreadableStore
        }
        return container
    }

    static func defaultStoreURL(fileManager: FileManager = .default) throws -> URL {
        guard let support = fileManager.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask).first else {
            throw SubmissionStoreError.unreadableStore
        }
        return support.appendingPathComponent("MapGrapher", isDirectory: true)
            .appendingPathComponent("MapGrapherStore.sqlite")
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = [modelVersion]
        let entity = NSEntityDescription()
        entity.name = "SubmissionRecord"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        let ownerID = attribute("ownerID", type: .stringAttributeType)
        ownerID.isIndexed = true
        entity.properties = [
            attribute("id", type: .stringAttributeType),
            ownerID,
            attribute("state", type: .stringAttributeType),
            attribute("remoteID", type: .stringAttributeType, optional: true),
            attribute("leaseOwner", type: .stringAttributeType, optional: true),
            attribute("leaseExpiresAt", type: .dateAttributeType, optional: true),
            attribute("createdAt", type: .dateAttributeType),
            attribute("snapshot", type: .binaryDataAttributeType)
        ]
        entity.uniquenessConstraints = [["id"]]
        // V1モデルを変更せず、新版は別モデルと対応するmigrationを追加する。
        model.entities = [entity]
        return model
    }

    private static func bundledModel() -> NSManagedObjectModel? {
        guard let url = Bundle.main.url(forResource: "MapGrapherStore", withExtension: "momd") else {
            return nil
        }
        return NSManagedObjectModel(contentsOf: url)
    }

    private static func attribute(_ name: String, type: NSAttributeType,
                                  optional: Bool = false) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }
}

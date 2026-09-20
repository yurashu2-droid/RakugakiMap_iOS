import Foundation
import XCTest
@testable import MapGrapherIOS

@MainActor
final class DraftFileStoreTests: XCTestCase {
    func testAtomicSaveSurvivesNewStoreAndKeepsOwnerPath() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = UUID()
        let operation = UUID()
        let bytes = Data(repeating: 0xAA, count: 1024)
        let store = try DraftFileStore(rootURL: root)
        let saved = try store.save(bytes, ownerID: owner, operationID: operation,
                                   fileName: "original.png")
        XCTAssertTrue(saved.path.contains(owner.uuidString))
        XCTAssertTrue(saved.path.contains(operation.uuidString))
        let reopened = try DraftFileStore(rootURL: root)
        XCTAssertEqual(try reopened.read(saved, ownerID: owner, operationID: operation), bytes)
        XCTAssertThrowsError(try reopened.read(saved, ownerID: UUID(), operationID: operation))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(
            at: saved.deletingLastPathComponent(), includingPropertiesForKeys: nil
        ).count, 1)
    }

    func testRejectsTraversalAndDoesNotOverwriteExistingDraft() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DraftFileStore(rootURL: root)
        let owner = UUID()
        let operation = UUID()
        for badName in ["../outside.png", "..", "/outside.png", "sub/file.png", "sub\\file.png"] {
            XCTAssertThrowsError(try store.save(Data([1]), ownerID: owner,
                                                operationID: operation, fileName: badName))
        }
        let saved = try store.save(Data([1]), ownerID: owner,
                                   operationID: operation, fileName: "draft.png")
        XCTAssertThrowsError(try store.save(Data([2]), ownerID: owner,
                                              operationID: operation, fileName: "draft.png"))
        XCTAssertEqual(try Data(contentsOf: saved), Data([1]))
    }

    func testRejectsOwnerDirectorySymbolicLink() throws {
        let root = temporaryDirectory()
        let outside = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let owner = UUID()
        let store = try DraftFileStore(rootURL: root)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent(owner.uuidString), withDestinationURL: outside
        )
        XCTAssertThrowsError(try store.save(Data([1]), ownerID: owner,
                                            operationID: UUID(), fileName: "draft.png"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            at: outside, includingPropertiesForKeys: nil
        ).isEmpty)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

import Foundation
import XCTest
@testable import MapGrapherIOS

final class ARWorldMapArchiveTests: XCTestCase {
    func testDecodeRejectsOversizedArchiveBeforeUnarchiving() {
        XCTAssertThrowsError(try ARWorldMapArchive.decode(
            Data(repeating: 0, count: 26 * 1024 * 1024),
            requiredAnchorName: "rakugaki:test",
            maxBytes: 25 * 1024 * 1024
        ))
    }

    func testDecodeRejectsEmptyArchiveBeforeUnarchiving() {
        XCTAssertThrowsError(try ARWorldMapArchive.decode(
            Data(),
            requiredAnchorName: "rakugaki:test"
        ))
    }

    func testValidationRejectsMissingAndDuplicateNamedAnchor() {
        XCTAssertThrowsError(try ARWorldMapArchive.validateAnchorNames(
            [],
            required: "rakugaki:test"
        ))
        XCTAssertThrowsError(try ARWorldMapArchive.validateAnchorNames(
            ["rakugaki:test", "rakugaki:test"],
            required: "rakugaki:test"
        ))
    }

    func testValidationAcceptsExactlyOneMatchingAnchor() throws {
        XCTAssertNoThrow(try ARWorldMapArchive.validateAnchorNames(
            [nil, "unrelated", "rakugaki:test"],
            required: "rakugaki:test"
        ))
    }

    func testPersistentPackageRejectsUnsafeMetadata() {
        XCTAssertNil(PersistentARPackage(
            data: Data([1]),
            anchorName: "",
            displayWidthM: 1,
            formatVersion: 1
        ))
        XCTAssertNil(PersistentARPackage(
            data: Data([1]),
            anchorName: "rakugaki:test",
            displayWidthM: .infinity,
            formatVersion: 1
        ))
        XCTAssertNil(PersistentARPackage(
            data: Data([1]),
            anchorName: "rakugaki:test",
            displayWidthM: 1,
            formatVersion: 2
        ))
    }
}

import XCTest
@testable import MapGrapherIOS

final class ConfigurationTests: XCTestCase {
    func testCameraPermissionHasJapaneseExplanation() {
        let explanation = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
        XCTAssertTrue(explanation?.contains("カメラ") == true)
    }
}

import XCTest
@testable import MapGrapherIOS

final class ConfigurationTests: XCTestCase {
    func testCameraPermissionHasJapaneseExplanation() {
        let bundle = Bundle(identifier: "com.rakugakimap.ios.development")
        let explanation = bundle?.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
        XCTAssertTrue(explanation?.contains("カメラ") == true)
    }
}

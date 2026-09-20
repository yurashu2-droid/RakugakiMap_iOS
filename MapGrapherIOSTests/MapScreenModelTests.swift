import XCTest
import MapGrapherCore
@testable import MapGrapherIOS

@MainActor
final class MapScreenModelTests: XCTestCase {
    func testPermissionRevocationClearsPreviouslyShownPhoto() async {
        let reader = FakePhotoReading()
        let model = MapScreenModel(photoReader: reader)
        let center = GeoPoint(latitude: 35, longitude: 139)!

        await model.search(center: center)
        XCTAssertEqual(model.state, .content)
        XCTAssertFalse(model.visiblePhotos.isEmpty)

        reader.nearbyResult = .failure(.forbidden)
        await model.search(center: center)
        XCTAssertEqual(model.state, .permissionDenied)
        XCTAssertTrue(model.visiblePhotos.isEmpty)
    }
}

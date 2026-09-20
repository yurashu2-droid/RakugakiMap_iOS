import XCTest
@testable import MapGrapherIOS

@MainActor
final class PostingFlowModelTests: XCTestCase {
    func testEditingSubmittedDrawingUsesNewOperationID() async {
        let model = PostingFlowModel(service: FakePostingUIService())
        await model.useUITestFixture()
        model.advanceFromReview()
        model.skipDrawing()
        model.setTitle("テスト投稿")
        await model.publish()
        XCTAssertEqual(model.step, .status)
        let submittedID = model.draft.id

        model.goBack()
        model.goBack()
        model.skipDrawing()

        XCTAssertNotEqual(model.draft.id, submittedID)
    }

    func testReplacingSubmittedPhotoUsesNewOperationID() async {
        let model = PostingFlowModel(service: FakePostingUIService())
        await model.useUITestFixture()
        model.advanceFromReview()
        model.skipDrawing()
        model.setTitle("テスト投稿")
        await model.publish()
        XCTAssertEqual(model.step, .status)
        let submittedID = model.draft.id

        model.goBack()
        model.goBack()
        model.goBack()
        model.goBack()
        await model.useUITestFixture()

        XCTAssertNotEqual(model.draft.id, submittedID)
    }
}

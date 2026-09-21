import XCTest
import MapGrapherCore
@testable import MapGrapherIOS

@MainActor
final class PostingFlowModelTests: XCTestCase {
    func testCompletedARReservationMovesDirectlyToPlacement() async throws {
        let photoID = UUID()
        let rakugakiID = UUID()
        let asset = try XCTUnwrap(AssetReference(
            bucket: "rakugakis", path: "owner/rakugakis/drawing.png"))
        let service = FakePostingUIService(submitResult: PostingSubmissionResult(
            draftID: UUID(), state: .completed, remotePhotoID: photoID,
            arPlacement: ARPlacementDraft(photoID: photoID, rakugakiID: rakugakiID,
                                          imageAsset: asset)))
        let model = PostingFlowModel(service: service)
        await model.useUITestFixture()
        model.advanceFromReview()
        let prepared = try XCTUnwrap(model.draft.preparedImage)
        let stroke = try XCTUnwrap(DrawingStroke(
            id: UUID(), brush: .pen,
            color: try XCTUnwrap(DrawingColor(red: 1, green: 0, blue: 0, alpha: 1)),
            width: 4, opacity: 1,
            points: [try XCTUnwrap(DrawingPoint(x: 10, y: 10))], randomSeed: 1))
        model.updateDrawing(try XCTUnwrap(DrawingDocument(
            pixelWidth: prepared.prepared.pixelWidth,
            pixelHeight: prepared.prepared.pixelHeight,
            strokes: [stroke])))
        model.advanceFromDrawing()
        model.setTitle("AR投稿")
        model.setReserveAR(true)

        await model.publish()

        XCTAssertEqual(model.step, .arPlacement)
        XCTAssertEqual(model.status?.arPlacement,
                       ARPlacementDraft(photoID: photoID, rakugakiID: rakugakiID,
                                        imageAsset: asset))
    }

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

import Foundation
import XCTest
@testable import MapGrapherCore

final class DomainModelTests: XCTestCase {
    private let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let remoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private let createdAt = Date(timeIntervalSince1970: 2_000)

    private func makeSubmission(
        id: UUID? = nil,
        schemaVersion: Int = 1,
        payloadData: Data = Data(#"{"title":"test"}"#.utf8),
        dependsOn: UUID? = nil,
        remoteID: UUID? = nil,
        state: SubmissionState = .queued,
        resumeStage: SubmissionResumeStage,
        attemptCount: Int = 0,
        updatedAt: Date? = nil
    ) -> PendingSubmission? {
        PendingSubmission(
            id: id ?? operationID,
            ownerID: ownerID,
            schemaVersion: schemaVersion,
            kind: .photo,
            payloadData: payloadData,
            localFilePaths: ["photo.jpg"],
            assetPaths: [AssetReference(bucket: "photos", path: "users/a/photo.jpg")!],
            dependsOn: dependsOn,
            remoteID: remoteID,
            state: state,
            resumeStage: resumeStage,
            attemptCount: attemptCount,
            nextAttemptAt: nil,
            lastFailure: nil,
            leaseOwner: nil,
            leaseExpiresAt: nil,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt
        )
    }

    private func makePhoto(likeCount: Int) throws -> Photo? {
        Photo(
            id: remoteID,
            ownerID: ownerID,
            title: "試験写真",
            location: try XCTUnwrap(GeoPoint(latitude: 35, longitude: 139)),
            visibility: .friends,
            drawPermission: .onlyMe,
            requiresApproval: true,
            createdAt: createdAt,
            asset: try XCTUnwrap(AssetReference(bucket: "photos", path: "users/a/photo.jpg")),
            thumbnail: nil,
            likeCount: likeCount,
            likedByMe: false
        )
    }

    private func makeExperience(
        unlockRadiusM: Double = 50,
        discoveryRadiusM: Double = 150,
        displayWidthM: Double = 1
    ) throws -> ArExperience? {
        ArExperience(
            id: operationID,
            photoID: remoteID,
            rakugakiID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            asset: try XCTUnwrap(AssetReference(bucket: "rakugakis", path: "users/a/drawing.png")),
            unlockRadiusM: unlockRadiusM,
            discoveryRadiusM: discoveryRadiusM,
            displayWidthM: displayWidthM,
            location: try XCTUnwrap(GeoPoint(latitude: 35, longitude: 139)),
            anchorType: .localPlane
        )
    }

    func testPhotoRejectsNegativeLikeCount() throws {
        XCTAssertNil(try makePhoto(likeCount: -1))
        XCTAssertNotNil(try makePhoto(likeCount: 0))
    }

    func testArExperienceRejectsInvalidRadiusRelationshipAndWidth() throws {
        XCTAssertNotNil(try makeExperience(unlockRadiusM: 10, discoveryRadiusM: 30, displayWidthM: 0.1))
        XCTAssertNotNil(try makeExperience(unlockRadiusM: 200, discoveryRadiusM: 500, displayWidthM: 10))
        XCTAssertNil(try makeExperience(unlockRadiusM: 9.99))
        XCTAssertNil(try makeExperience(unlockRadiusM: 200.01))
        XCTAssertNil(try makeExperience(discoveryRadiusM: 29.99))
        XCTAssertNil(try makeExperience(discoveryRadiusM: 500.01))
        XCTAssertNil(try makeExperience(unlockRadiusM: 100, discoveryRadiusM: 99.99))
        XCTAssertNil(try makeExperience(displayWidthM: 0.099))
        XCTAssertNil(try makeExperience(displayWidthM: 10.001))
        XCTAssertNil(try makeExperience(displayWidthM: .nan))
        XCTAssertNil(try makeExperience(displayWidthM: .infinity))
    }

    func testUnknownArAnchorTypeIsRejected() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            ArAnchorType.self, from: Data(#""SHARED_WORLD""#.utf8)
        ))
    }

    func testUnknownSubmissionKindAndResumeStageAreRejected() {
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(
            SubmissionKind.self, from: Data(#""story""#.utf8)
        ))
        XCTAssertThrowsError(try decoder.decode(
            SubmissionResumeStage.self, from: Data(#""restart""#.utf8)
        ))
    }

    func testPendingSubmissionRejectsBrokenIdentityAndPayload() {
        XCTAssertNil(makeSubmission(schemaVersion: 0, resumeStage: .upload))
        XCTAssertNil(makeSubmission(payloadData: Data(), resumeStage: .upload))
        XCTAssertNil(makeSubmission(dependsOn: operationID, resumeStage: .upload))
        XCTAssertNil(makeSubmission(resumeStage: .upload, attemptCount: -1))
        XCTAssertNil(makeSubmission(resumeStage: .upload, updatedAt: createdAt.addingTimeInterval(-1)))
    }

    func testCompletedSubmissionRequiresServerID() {
        XCTAssertNil(makeSubmission(remoteID: nil, state: .completed, resumeStage: .none))
        XCTAssertNotNil(makeSubmission(remoteID: remoteID, state: .completed, resumeStage: .none))
    }

    func testEveryStateAcceptsOnlyItsCompatibleResumeStages() {
        let cases: [(state: SubmissionState, allowed: [SubmissionResumeStage], remoteID: UUID?)] = [
            (.draft, [.upload, .register], nil),
            (.queued, [.upload, .register], nil),
            (.uploading, [.upload], nil),
            (.registering, [.register], nil),
            (.completed, [.none], remoteID),
            (.retryWaiting, [.upload, .register], nil),
            (.needsLogin, [.upload, .register], nil),
            (.needsCorrection, [.upload, .register], nil),
            (.outcomeUnknown, [.register], nil),
            (.cancelled, [.none], nil),
        ]
        let stages: [SubmissionResumeStage] = [.upload, .register, .none]

        for sample in cases {
            for stage in stages {
                XCTAssertEqual(
                    makeSubmission(
                        remoteID: sample.remoteID,
                        state: sample.state,
                        resumeStage: stage
                    ) != nil,
                    sample.allowed.contains(stage),
                    "\(sample.state) + \(stage)"
                )
            }
        }
    }

    func testResumeStageSelectsUploadOrRegisterFromWaitingStates() {
        let waitingStates: [SubmissionState] = [.queued, .retryWaiting, .needsLogin]

        for state in waitingStates {
            XCTAssertTrue(SubmissionTransition.allows(
                from: state, to: .uploading,
                requiresRemoteDependency: false, dependencyRemoteID: nil,
                resumeStage: .upload
            ), "\(state) → uploading")
            XCTAssertFalse(SubmissionTransition.allows(
                from: state, to: .uploading,
                requiresRemoteDependency: false, dependencyRemoteID: nil,
                resumeStage: .register
            ), "\(state) → uploading は再upload禁止")
            XCTAssertTrue(SubmissionTransition.allows(
                from: state, to: .registering,
                requiresRemoteDependency: false, dependencyRemoteID: nil,
                resumeStage: .register
            ), "\(state) → registering")
            XCTAssertFalse(SubmissionTransition.allows(
                from: state, to: .registering,
                requiresRemoteDependency: false, dependencyRemoteID: nil,
                resumeStage: .upload
            ), "\(state) → registering はupload未完了")
        }
    }

    func testDependentRegistrationStillNeedsPredecessorRemoteID() {
        XCTAssertFalse(SubmissionTransition.allows(
            from: .retryWaiting, to: .registering,
            requiresRemoteDependency: true, dependencyRemoteID: nil,
            resumeStage: .register
        ))
        XCTAssertTrue(SubmissionTransition.allows(
            from: .retryWaiting, to: .registering,
            requiresRemoteDependency: true, dependencyRemoteID: remoteID,
            resumeStage: .register
        ))
    }

    func testRegistrationRetryKeepsUploadFinishedEvenBeforeServerIDExists() throws {
        let retry = try XCTUnwrap(makeSubmission(
            remoteID: nil, state: .retryWaiting, resumeStage: .register
        ))

        XCTAssertEqual(retry.resumeStage, .register)
        XCTAssertNil(retry.remoteID)
    }

    func testProgressCopyRejectsInvalidStateAndKeepsFixedInput() throws {
        let queued = try XCTUnwrap(makeSubmission(resumeStage: .upload))

        XCTAssertNil(queued.replacingProgress(
            state: .completed,
            resumeStage: .none,
            remoteID: nil,
            attemptCount: 1,
            nextAttemptAt: nil,
            lastFailure: nil,
            leaseOwner: nil,
            leaseExpiresAt: nil,
            updatedAt: createdAt.addingTimeInterval(1)
        ))

        let uploading = try XCTUnwrap(queued.replacingProgress(
            state: .uploading,
            resumeStage: .upload,
            remoteID: nil,
            attemptCount: 1,
            nextAttemptAt: nil,
            lastFailure: nil,
            leaseOwner: nil,
            leaseExpiresAt: nil,
            updatedAt: createdAt.addingTimeInterval(1)
        ))
        XCTAssertEqual(queued.state, .queued)
        XCTAssertEqual(uploading.state, .uploading)
        XCTAssertEqual(uploading.id, queued.id)
        XCTAssertEqual(uploading.ownerID, queued.ownerID)
        XCTAssertEqual(uploading.payloadData, queued.payloadData)
    }

    func testRegistrationProgressCannotRevertToUploadAfterRetryOrLogin() throws {
        let registering = try XCTUnwrap(makeSubmission(
            state: .registering, resumeStage: .register
        ))
        let interruptedStates: [SubmissionState] = [.retryWaiting, .needsLogin]

        for state in interruptedStates {
            XCTAssertNil(registering.replacingProgress(
                state: state,
                resumeStage: .upload,
                remoteID: nil,
                attemptCount: 1,
                nextAttemptAt: nil,
                lastFailure: nil,
                leaseOwner: nil,
                leaseExpiresAt: nil,
                updatedAt: createdAt.addingTimeInterval(1)
            ), "\(state)でuploadへ巻き戻さない")

            let preserved = try XCTUnwrap(registering.replacingProgress(
                state: state,
                resumeStage: .register,
                remoteID: nil,
                attemptCount: 1,
                nextAttemptAt: nil,
                lastFailure: nil,
                leaseOwner: nil,
                leaseExpiresAt: nil,
                updatedAt: createdAt.addingTimeInterval(1)
            ))
            XCTAssertFalse(SubmissionTransition.allows(
                from: preserved.state,
                to: .uploading,
                requiresRemoteDependency: false,
                dependencyRemoteID: nil,
                resumeStage: preserved.resumeStage
            ))
        }
    }

    func testLocalOperationOwnerIsCheckedIndependentlyOfOperationAndRemoteIDs() throws {
        let completed = try XCTUnwrap(makeSubmission(
            remoteID: remoteID, state: .completed, resumeStage: .none
        ))
        let owner = SessionContext(
            userID: ownerID,
            epoch: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        )
        let other = SessionContext(
            userID: operationID,
            epoch: owner.epoch
        )
        let serverIDAsUser = SessionContext(
            userID: remoteID,
            epoch: owner.epoch
        )

        XCTAssertTrue(completed.isOwned(by: owner))
        XCTAssertFalse(completed.isOwned(by: other))
        XCTAssertFalse(completed.isOwned(by: serverIDAsUser))
    }
}

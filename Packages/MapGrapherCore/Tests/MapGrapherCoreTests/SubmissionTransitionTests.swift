import Foundation
import XCTest
@testable import MapGrapherCore

final class SubmissionTransitionTests: XCTestCase {
    func testNormalSubmissionMovesForwardOneStageAtATime() {
        let stages: [(from: SubmissionState, to: SubmissionState, resumeStage: SubmissionResumeStage)] = [
            (.draft, .queued, .upload),
            (.queued, .uploading, .upload),
            (.uploading, .registering, .upload),
            (.registering, .completed, .register),
        ]

        for stage in stages {
            XCTAssertTrue(SubmissionTransition.allows(
                from: stage.from, to: stage.to,
                requiresRemoteDependency: false, dependencyRemoteID: nil,
                resumeStage: stage.resumeStage
            ), "\(stage.from) → \(stage.to)")
        }
    }

    func testDependentUploadWaitsForRemoteID() {
        XCTAssertFalse(SubmissionTransition.allows(
            from: .queued, to: .uploading,
            requiresRemoteDependency: true, dependencyRemoteID: nil,
            resumeStage: .upload
        ))
        XCTAssertTrue(SubmissionTransition.allows(
            from: .queued, to: .uploading,
            requiresRemoteDependency: true,
            dependencyRemoteID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            resumeStage: .upload
        ))
    }

    func testRetryAndAuthenticationRecoveryRemainPossible() {
        XCTAssertTrue(SubmissionTransition.allows(
            from: .uploading, to: .retryWaiting,
            requiresRemoteDependency: false, dependencyRemoteID: nil,
            resumeStage: .upload
        ))
        XCTAssertTrue(SubmissionTransition.allows(
            from: .retryWaiting, to: .uploading,
            requiresRemoteDependency: false, dependencyRemoteID: nil,
            resumeStage: .upload
        ))
        XCTAssertTrue(SubmissionTransition.allows(
            from: .uploading, to: .needsLogin,
            requiresRemoteDependency: false, dependencyRemoteID: nil,
            resumeStage: .upload
        ))
        XCTAssertTrue(SubmissionTransition.allows(
            from: .needsLogin, to: .queued,
            requiresRemoteDependency: false, dependencyRemoteID: nil,
            resumeStage: .upload
        ))
    }

    func testTerminalAndBackwardTransitionsAreRejected() {
        let forbidden: [(from: SubmissionState, to: SubmissionState, resumeStage: SubmissionResumeStage)] = [
            (.completed, .uploading, .none),
            (.completed, .cancelled, .none),
            (.cancelled, .registering, .none),
            (.registering, .uploading, .register),
            (.outcomeUnknown, .uploading, .register),
            (.draft, .completed, .upload),
            (.queued, .queued, .upload),
        ]

        for stage in forbidden {
            XCTAssertFalse(SubmissionTransition.allows(
                from: stage.from, to: stage.to,
                requiresRemoteDependency: false, dependencyRemoteID: nil,
                resumeStage: stage.resumeStage
            ), "\(stage.from) → \(stage.to)")
        }
    }

    func testUnknownRegistrationOutcomeCannotRestartUpload() {
        XCTAssertTrue(SubmissionTransition.allows(
            from: .registering, to: .outcomeUnknown,
            requiresRemoteDependency: false, dependencyRemoteID: nil,
            resumeStage: .register
        ))
    }

    func testUnknownPersistedStateIsRejected() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            SubmissionState.self,
            from: Data(#""finished""#.utf8)
        ))
    }
}

import Foundation
import XCTest
@testable import MapGrapherCore

final class SubmissionTransitionTests: XCTestCase {
    func testNormalSubmissionMovesForwardOneStageAtATime() {
        let stages: [(SubmissionState, SubmissionState)] = [
            (.draft, .queued),
            (.queued, .uploading),
            (.uploading, .registering),
            (.registering, .completed),
        ]

        for (from, to) in stages {
            XCTAssertTrue(SubmissionTransition.allows(
                from: from, to: to,
                requiresRemoteDependency: false, dependencyRemoteID: nil
            ), "\(from) → \(to)")
        }
    }

    func testDependentUploadWaitsForRemoteID() {
        XCTAssertFalse(SubmissionTransition.allows(
            from: .queued, to: .uploading,
            requiresRemoteDependency: true, dependencyRemoteID: nil
        ))
        XCTAssertTrue(SubmissionTransition.allows(
            from: .queued, to: .uploading,
            requiresRemoteDependency: true,
            dependencyRemoteID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        ))
    }

    func testRetryAndAuthenticationRecoveryRemainPossible() {
        XCTAssertTrue(SubmissionTransition.allows(
            from: .uploading, to: .retryWaiting,
            requiresRemoteDependency: false, dependencyRemoteID: nil
        ))
        XCTAssertTrue(SubmissionTransition.allows(
            from: .retryWaiting, to: .uploading,
            requiresRemoteDependency: false, dependencyRemoteID: nil
        ))
        XCTAssertTrue(SubmissionTransition.allows(
            from: .uploading, to: .needsLogin,
            requiresRemoteDependency: false, dependencyRemoteID: nil
        ))
        XCTAssertTrue(SubmissionTransition.allows(
            from: .needsLogin, to: .queued,
            requiresRemoteDependency: false, dependencyRemoteID: nil
        ))
    }

    func testTerminalAndBackwardTransitionsAreRejected() {
        let forbidden: [(SubmissionState, SubmissionState)] = [
            (.completed, .uploading),
            (.completed, .cancelled),
            (.cancelled, .registering),
            (.registering, .uploading),
            (.outcomeUnknown, .uploading),
            (.draft, .completed),
            (.queued, .queued),
        ]

        for (from, to) in forbidden {
            XCTAssertFalse(SubmissionTransition.allows(
                from: from, to: to,
                requiresRemoteDependency: false, dependencyRemoteID: nil
            ), "\(from) → \(to)")
        }
    }

    func testUnknownRegistrationOutcomeCannotRestartUpload() {
        XCTAssertTrue(SubmissionTransition.allows(
            from: .registering, to: .outcomeUnknown,
            requiresRemoteDependency: false, dependencyRemoteID: nil
        ))
    }

    func testUnknownPersistedStateIsRejected() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            SubmissionState.self,
            from: Data(#""finished""#.utf8)
        ))
    }
}

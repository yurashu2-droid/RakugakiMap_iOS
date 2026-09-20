import Foundation

public protocol SubmissionTransport: Sendable {
    /// 同じStorage pathに既に存在すればサイズとMIMEを確認して再uploadを省く。
    func ensureUploaded(_ submission: PendingSubmission, payload: SubmissionPayload,
                        context: SessionContext) async throws
    /// 応答が失われても同じsubmission.idをclient_request_idとして再送する。
    func register(_ submission: PendingSubmission, payload: SubmissionPayload,
                  dependencyRemoteID: UUID?, relatedPhotoRemoteID: UUID?,
                  context: SessionContext) async throws -> UUID
}

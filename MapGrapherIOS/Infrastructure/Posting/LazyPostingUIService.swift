import Foundation
import MapGrapherCore

/// 認証済み画面でだけ永続キューを開く。初期化失敗時は下書きを消さず再試行する。
@MainActor
final class LazyPostingUIService: PostingUIService, ExistingPhotoRakugakiServing {
    let storesDraftsPersistently = false
    let performsNetworkSubmission = true

    private let context: SessionContext
    private let gateway: SupabaseGateway
    private let session: any SessionProviding
    private var initializing: Task<RealPostingUIService, Error>?
    private var existingPhotoService: ExistingPhotoRakugakiService?
    private let photoReader: any PhotoReading
    private let assetLoader: PrivateAssetLoader

    init(context: SessionContext, gateway: SupabaseGateway, session: any SessionProviding,
         photoReader: any PhotoReading, assetLoader: PrivateAssetLoader) {
        self.context = context
        self.gateway = gateway
        self.session = session
        self.photoReader = photoReader
        self.assetLoader = assetLoader
    }

    func prepareImage(data: Data, suggestedFilename: String) async throws -> PreparedPostingImage {
        try await service().prepareImage(data: data, suggestedFilename: suggestedFilename)
    }

    func currentLocation() async -> GeoPoint? {
        guard let service = try? await service() else { return nil }
        return await service.currentLocation()
    }

    func saveDraft(_ draft: PostingDraft) async throws {
        try await service().saveDraft(draft)
    }

    func submit(_ draft: PostingDraft) async throws -> PostingSubmissionResult {
        try await service().submit(draft)
    }

    func prepare(photo: Photo) async throws -> PreparedPostingImage {
        try await rakugakiService().prepare(photo: photo)
    }

    func submit(photo: Photo, base: PreparedPostingImage,
                document: DrawingDocument, operationID: UUID) async throws
        -> ExistingRakugakiSubmissionResult {
        try await rakugakiService().submit(photo: photo, base: base,
                                          document: document, operationID: operationID)
    }

    func discard(base: PreparedPostingImage) {
        existingPhotoService?.discard(base: base)
    }

    private func rakugakiService() async throws -> ExistingPhotoRakugakiService {
        if let existingPhotoService { return existingPhotoService }
        let created = try await service().existingPhotoRakugakiService(
            gateway: gateway, photoReader: photoReader, assetLoader: assetLoader)
        existingPhotoService = created
        return created
    }

    private func service() async throws -> RealPostingUIService {
        if initializing == nil {
            let context = context
            let gateway = gateway
            let session = session
            initializing = Task { @MainActor in
                guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
                let store = try await CoreDataSubmissionStore()
                guard await session.isCurrent(context) else { throw AppFailure.needsLogin }
                let files = try DraftFileStore()
                let transport = SupabaseSubmissionTransport(gateway: gateway, session: session,
                                                            files: files)
                let coordinator = SubmissionCoordinator(store: store, session: session,
                                                        transport: transport)
                let groups = SupabaseGroupsService(gateway: gateway, session: session)
                let answerJournal = try GroupAnswerRecoveryStore()
                let answerRecovery = GroupAnswerRecovery(journal: answerJournal,
                    photos: SubmissionPhotoLookup(submissions: store),
                    remote: GroupsMissionAnswerRemote(groups: groups), session: session)
                let temporary = FileManager.default.temporaryDirectory
                return RealPostingUIService(
                    context: context, session: session, store: store,
                    coordinator: coordinator, files: files,
                    imagePreparer: ImagePreparer(outputDirectory: temporary.appendingPathComponent("Prepared")),
                    drawingExporter: DrawingExporter(outputDirectory: temporary.appendingPathComponent("Drawings")),
                    location: MapLocationAdapter(),
                    missionLookup: GroupsMissionSnapshotLookup(groups: groups),
                    answerRecovery: answerRecovery
                )
            }
        }
        do {
            return try await initializing!.value
        } catch {
            initializing = nil
            throw error
        }
    }
}

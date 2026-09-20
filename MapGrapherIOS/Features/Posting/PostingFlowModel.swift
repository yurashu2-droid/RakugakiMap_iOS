import Combine
import CryptoKit
import Foundation
import ImageIO
import MapGrapherCore
import UIKit
import UniformTypeIdentifiers

@MainActor
protocol PostingUIService {
    var storesDraftsPersistently: Bool { get }
    var performsNetworkSubmission: Bool { get }
    func prepareImage(data: Data, suggestedFilename: String) async throws -> PreparedPostingImage
    func currentLocation() async -> GeoPoint?
    func saveDraft(_ draft: PostingDraft) async throws
    func submit(_ draft: PostingDraft) async throws -> PostingSubmissionResult
}

extension PostingUIService {
    var storesDraftsPersistently: Bool { false }
    var performsNetworkSubmission: Bool { false }
}

enum PostingServiceError: Error, Equatable, Sendable {
    case invalidImage
    case imageTooLarge
    case dimensionsTooLarge
    case outputFailed
    case permissionDenied
    case offline
    case invalidDraft
    case serviceUnavailable
}

struct PreparedPostingImage: Equatable, Sendable {
    let id: UUID
    let prepared: PreparedImage
    let previewData: Data

    init(id: UUID = UUID(), prepared: PreparedImage, previewData: Data) {
        self.id = id
        self.prepared = prepared
        self.previewData = previewData
    }
}

struct PostingDraft: Identifiable, Sendable {
    let id: UUID
    let missionID: UUID?
    let createdAt: Date
    var preparedImage: PreparedPostingImage?
    var title: String
    var location: GeoPoint?
    var visibility: Visibility
    var drawPermission: Visibility
    var requiresApproval: Bool
    var reserveAR: Bool
    var drawing: DrawingDocument?

    init(
        id: UUID = UUID(),
        missionID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.missionID = missionID
        self.createdAt = createdAt
        preparedImage = nil
        title = ""
        location = nil
        // 初期値は意図的に本人だけ。公開範囲は利用者が確認して変更する。
        visibility = .onlyMe
        drawPermission = .onlyMe
        requiresApproval = true
        reserveAR = false
        drawing = nil
    }

    var hasDrawing: Bool {
        !(drawing?.strokes.isEmpty ?? true)
    }
}

struct PostingSubmissionResult: Sendable {
    let draftID: UUID
    let state: SubmissionState
    let remotePhotoID: UUID?

    init(draftID: UUID, state: SubmissionState, remotePhotoID: UUID? = nil) {
        self.draftID = draftID
        self.state = state
        self.remotePhotoID = remotePhotoID
    }
}

enum PostingFlowStep: String, CaseIterable, Sendable {
    case capture
    case review
    case drawing
    case publish
    case status
}

enum PostingFlowError: Error, Equatable, Sendable {
    case invalidImage
    case imageTooLarge
    case dimensionsTooLarge
    case preparingFailed
    case invalidDraft
    case saveFailed
    case submissionFailed
}

@MainActor
final class PostingFlowModel: ObservableObject {
    @Published private(set) var step: PostingFlowStep = .capture
    @Published private(set) var draft: PostingDraft
    @Published private(set) var status: PostingSubmissionResult?
    @Published private(set) var error: PostingFlowError?
    @Published private(set) var isBusy = false
    @Published private(set) var didSaveDraft = false
    @Published private(set) var isEditingSubmittedDraft = false

    private let service: any PostingUIService
    private var needsNewOperation = false

    init(
        service: any PostingUIService,
        missionID: UUID? = nil
    ) {
        self.service = service
        draft = PostingDraft(missionID: missionID)
    }

    var canGoBack: Bool {
        !isBusy && step != .capture
    }

    var hasUnsavedDraft: Bool {
        if step == .status, status != nil, service.performsNetworkSubmission { return false }
        return draft.preparedImage != nil || !draft.title.isEmpty || draft.drawing != nil
    }

    var storesDraftsPersistently: Bool { service.storesDraftsPersistently }
    var performsNetworkSubmission: Bool { service.performsNetworkSubmission }

    func loadLocation() async {
        guard draft.location == nil else { return }
        draft.location = await service.currentLocation()
    }

    func importImage(data: Data, suggestedFilename: String) async {
        guard !isBusy else { return }
        error = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let prepared = try await service.prepareImage(
                data: data,
                suggestedFilename: suggestedFilename
            )
            prepareNewOperationIfNeeded()
            draft.preparedImage = prepared
            draft.drawing = nil
            if draft.location == nil {
                draft.location = await service.currentLocation()
            }
            step = .review
        } catch let known as PostingServiceError {
            error = Self.mapError(known)
        } catch {
            self.error = .preparingFailed
        }
    }

    func useUITestFixture() async {
        await importImage(
            data: FakePostingUIService.fixtureImageData(),
            suggestedFilename: "ui-fixture.png"
        )
    }

    func setTitle(_ title: String) {
        prepareNewOperationIfNeeded()
        draft.title = String(title.prefix(100))
    }

    func setVisibility(_ visibility: Visibility) {
        prepareNewOperationIfNeeded()
        draft.visibility = visibility
    }

    func setDrawPermission(_ permission: Visibility) {
        prepareNewOperationIfNeeded()
        draft.drawPermission = permission
    }

    func setRequiresApproval(_ requiresApproval: Bool) {
        prepareNewOperationIfNeeded()
        draft.requiresApproval = requiresApproval
    }

    func setReserveAR(_ reserveAR: Bool) {
        prepareNewOperationIfNeeded()
        guard !reserveAR || draft.hasDrawing else {
            draft.reserveAR = false
            return
        }
        draft.reserveAR = reserveAR
    }

    func advanceFromReview() {
        guard draft.preparedImage != nil else {
            error = .invalidImage
            return
        }
        error = nil
        step = .drawing
    }

    func updateDrawing(_ document: DrawingDocument) {
        prepareNewOperationIfNeeded()
        draft.drawing = document
        if !draft.hasDrawing {
            draft.reserveAR = false
        }
    }

    func skipDrawing() {
        guard let preparedImage = draft.preparedImage else {
            error = .invalidImage
            return
        }
        prepareNewOperationIfNeeded()
        let width = max(1, preparedImage.prepared.pixelWidth)
        let height = max(1, preparedImage.prepared.pixelHeight)
        draft.drawing = DrawingDocument(pixelWidth: width, pixelHeight: height, strokes: [])
        draft.reserveAR = false
        error = nil
        step = .publish
    }

    func advanceFromDrawing() {
        guard let preparedImage = draft.preparedImage else {
            error = .invalidImage
            return
        }
        if draft.drawing == nil {
            let width = max(1, preparedImage.prepared.pixelWidth)
            let height = max(1, preparedImage.prepared.pixelHeight)
            draft.drawing = DrawingDocument(pixelWidth: width, pixelHeight: height, strokes: [])
        }
        error = nil
        step = .publish
    }

    func publish() async {
        guard !isBusy else { return }
        guard validateDraft() else {
            error = .invalidDraft
            return
        }

        error = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await service.saveDraft(draft)
            didSaveDraft = true
            do {
                status = try await service.submit(draft)
            } catch {
                status = PostingSubmissionResult(draftID: draft.id, state: .retryWaiting)
                self.error = .submissionFailed
            }
            isEditingSubmittedDraft = false
            step = .status
        } catch {
            self.error = .saveFailed
        }
    }

    func retrySubmission() async {
        guard !isBusy else { return }
        await publish()
    }

    func saveAndClose() async -> Bool {
        guard hasUnsavedDraft else { return true }
        guard storesDraftsPersistently else { return false }
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await service.saveDraft(draft)
            didSaveDraft = true
            error = nil
            return true
        } catch {
            self.error = .saveFailed
            return false
        }
    }

    func discardDraft() {
        // 破棄は確認ダイアログで明示された場合だけ呼ばれる。
        draft = PostingDraft(missionID: draft.missionID)
        status = nil
        error = nil
        didSaveDraft = false
        isEditingSubmittedDraft = false
        needsNewOperation = false
    }

    func goBack() {
        guard canGoBack else { return }
        error = nil
        switch step {
        case .capture:
            break
        case .review:
            step = .capture
        case .drawing:
            step = .review
        case .publish:
            step = .drawing
        case .status:
            needsNewOperation = true
            isEditingSubmittedDraft = true
            step = .publish
        }
    }

    private func prepareNewOperationIfNeeded() {
        guard needsNewOperation else { return }
        let previous = draft
        var next = PostingDraft(
            id: UUID(),
            missionID: previous.missionID,
            createdAt: Date()
        )
        next.preparedImage = previous.preparedImage
        next.title = previous.title
        next.location = previous.location
        next.visibility = previous.visibility
        next.drawPermission = previous.drawPermission
        next.requiresApproval = previous.requiresApproval
        next.reserveAR = previous.reserveAR
        next.drawing = previous.drawing
        draft = next
        needsNewOperation = false
        didSaveDraft = false
    }

    private func validateDraft() -> Bool {
        guard draft.preparedImage != nil,
              draft.location != nil,
              !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.drawing != nil else {
            return false
        }
        return true
    }

    private static func mapError(_ error: PostingServiceError) -> PostingFlowError {
        switch error {
        case .invalidImage, .outputFailed:
            .invalidImage
        case .imageTooLarge:
            .imageTooLarge
        case .dimensionsTooLarge:
            .dimensionsTooLarge
        case .invalidDraft:
            .invalidDraft
        case .permissionDenied, .offline, .serviceUnavailable:
            .preparingFailed
        }
    }
}

@MainActor
final class FakePostingUIService: PostingUIService {
    var location: GeoPoint?
    var submitResult: PostingSubmissionResult
    var saveError: PostingServiceError?
    var submitError: PostingServiceError?
    private(set) var savedDrafts: [UUID: PostingDraft] = [:]

    init(
        location: GeoPoint? = GeoPoint(latitude: 35.0001, longitude: 139.0001),
        submitResult: PostingSubmissionResult? = nil
    ) {
        self.location = location
        self.submitResult = submitResult ?? PostingSubmissionResult(
            draftID: UUID(),
            state: .queued
        )
    }

    func prepareImage(data: Data, suggestedFilename: String) async throws -> PreparedPostingImage {
        guard !data.isEmpty else { throw PostingServiceError.invalidImage }
        guard data.count <= 20 * 1024 * 1024 else { throw PostingServiceError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw PostingServiceError.invalidImage
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_600
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PostingServiceError.invalidImage
        }
        guard image.width > 0, image.height > 0,
              image.width <= 20_000, image.height <= 20_000,
              Int64(image.width) * Int64(image.height) <= 100_000_000 else {
            throw PostingServiceError.dimensionsTooLarge
        }

        let normalized = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            normalized,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { throw PostingServiceError.outputFailed }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw PostingServiceError.outputFailed
        }

        let normalizedData = normalized as Data
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rakugaki-map-\(UUID().uuidString).jpg")
        do {
            try normalizedData.write(to: outputURL, options: .atomic)
        } catch {
            throw PostingServiceError.outputFailed
        }
        let digest = SHA256.hash(data: normalizedData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard let prepared = PreparedImage(
            fileURL: outputURL,
            mimeType: "image/jpeg",
            byteSize: Int64(normalizedData.count),
            pixelWidth: image.width,
            pixelHeight: image.height,
            sha256: digest
        ) else { throw PostingServiceError.outputFailed }
        return PreparedPostingImage(prepared: prepared, previewData: normalizedData)
    }

    func currentLocation() async -> GeoPoint? {
        location
    }

    func saveDraft(_ draft: PostingDraft) async throws {
        if let saveError { throw saveError }
        savedDrafts[draft.id] = draft
    }

    func submit(_ draft: PostingDraft) async throws -> PostingSubmissionResult {
        if let submitError { throw submitError }
        return PostingSubmissionResult(
            draftID: draft.id,
            state: submitResult.state,
            remotePhotoID: submitResult.remotePhotoID
        )
    }

    static func fixtureImageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480))
        return renderer.pngData { context in
            UIColor(red: 1.0, green: 0.98, blue: 0.93, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
            UIColor(red: 0.79, green: 0.26, blue: 0.31, alpha: 1).setStroke()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 100, y: 350))
            path.addCurve(
                to: CGPoint(x: 540, y: 150),
                controlPoint1: CGPoint(x: 220, y: 100),
                controlPoint2: CGPoint(x: 400, y: 430)
            )
            path.lineWidth = 14
            path.stroke()
        }
    }
}

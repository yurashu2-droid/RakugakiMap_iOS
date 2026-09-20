# T01 Core共有型・ローカル保存境界

設計§6/7と実装計画T01の公開境界。`MapGrapherCore` はFoundationだけを使う。ここでのUUIDは操作ID・依存操作ID・サーバーIDを別フィールドで扱い、所有者判定はサーバー側では常に`auth.uid()`を正とする。DTOのsnake_case変換、RLS、RPC、SDKは別工程。

## 値型

```swift
public struct LocationSample: Equatable, Sendable {
    public let point: GeoPoint
    public let horizontalAccuracyM: Double
    public let timestamp: Date
    public init?(point: GeoPoint, horizontalAccuracyM: Double, timestamp: Date)
}
public struct PhotoPermissions: Equatable, Sendable {
    public let canView: Bool
    public let canDraw: Bool
    public let isOwner: Bool
    public init(canView: Bool, canDraw: Bool, isOwner: Bool)
}
public struct AssetReference: Equatable, Codable, Sendable {
    public let bucket: String
    public let path: String
    public init?(bucket: String, path: String)
}
public struct SignedAsset: Sendable {
    public let url: URL
    public let expiresAt: Date
    public let context: SessionContext
    public init(url: URL, expiresAt: Date, context: SessionContext)
    public func isUsable(for context: SessionContext, now: Date) -> Bool
}
public enum AppFailure: Error, Equatable, Sendable {
    case offline, needsLogin, forbidden, notFound, cancelled
    case validation(String), rateLimited, outcomeUnknown, serviceUnavailable
}
public struct Photo: Equatable, Sendable {
    public let id: UUID
    public let ownerID: UUID
    public let title: String
    public let location: GeoPoint
    public let visibility: Visibility
    public let drawPermission: Visibility
    public let requiresApproval: Bool
    public let createdAt: Date
    public let asset: AssetReference
    public let thumbnail: AssetReference?
    public let likeCount: Int
    public let likedByMe: Bool
    public init?(id: UUID, ownerID: UUID, title: String, location: GeoPoint,
                 visibility: Visibility, drawPermission: Visibility,
                 requiresApproval: Bool, createdAt: Date, asset: AssetReference,
                 thumbnail: AssetReference?, likeCount: Int, likedByMe: Bool)
}
public enum ArAnchorType: String, Codable, Sendable {
    case localPlane = "LOCAL_PLANE"
}
public struct ArExperience: Equatable, Sendable {
    public let id: UUID
    public let photoID: UUID
    public let rakugakiID: UUID
    public let asset: AssetReference
    public let unlockRadiusM: Double
    public let discoveryRadiusM: Double
    public let displayWidthM: Double
    public let location: GeoPoint
    public let anchorType: ArAnchorType
    public init?(id: UUID, photoID: UUID, rakugakiID: UUID,
                 asset: AssetReference, unlockRadiusM: Double,
                 discoveryRadiusM: Double, displayWidthM: Double,
                 location: GeoPoint, anchorType: ArAnchorType)
}
```

`LocationSample`は負または非finiteの精度と非finiteの時刻を拒否し、鮮度・25m上限の判定は`RevealGate`で行う。`AssetReference`は空白だけのbucket/path、URL、絶対path、親ディレクトリ参照を拒否し、復号でも同じ検証を通す。DBに保存するのはこのStorage pathであり、`SignedAsset.url`は保存しない。`SignedAsset.isUsable`は同一userID/epochかつ有限の期限より前のみ真。開発環境のローカルURLを想定し、URL schemeの制限はここではしない。`Photo`のlikeCountは0以上。`ArExperience`は解放10〜200m、発見30〜500mかつ発見≥解放、実幅0.1〜10mのfinite値だけを受け付ける。未知anchorは復号エラー。

## 投稿キュー

```swift
public enum SubmissionKind: String, Codable, Sendable {
    case photo, rakugaki, ar, groupAnswer
}
public enum SubmissionResumeStage: String, Codable, Sendable {
    case upload, register, none
}
public struct PendingSubmission: Equatable, Sendable {
    public let id: UUID                  // ローカル操作ID。サーバー写真IDではない。
    public let ownerID: UUID
    public let schemaVersion: Int
    public let kind: SubmissionKind
    public let payloadData: Data         // 再試行時に変更しない入力。
    public let localFilePaths: [String]
    public let assetPaths: [AssetReference]
    public let dependsOn: UUID?          // 先行するローカル操作ID。
    public let createdAt: Date
    public let remoteID: UUID?           // サーバー作成が確定するまでnil。
    public let state: SubmissionState
    public let resumeStage: SubmissionResumeStage
    public let attemptCount: Int
    public let nextAttemptAt: Date?
    public let lastFailure: AppFailure?
    public let leaseOwner: UUID?
    public let leaseExpiresAt: Date?
    public let updatedAt: Date
    public init?(id: UUID, ownerID: UUID, schemaVersion: Int,
                 kind: SubmissionKind, payloadData: Data,
                 localFilePaths: [String], assetPaths: [AssetReference],
                 dependsOn: UUID?, remoteID: UUID?, state: SubmissionState,
                 resumeStage: SubmissionResumeStage, attemptCount: Int,
                 nextAttemptAt: Date?, lastFailure: AppFailure?,
                 leaseOwner: UUID?, leaseExpiresAt: Date?,
                 createdAt: Date, updatedAt: Date)
    public func replacingProgress(state: SubmissionState,
                                  resumeStage: SubmissionResumeStage,
                                  remoteID: UUID?, attemptCount: Int,
                                  nextAttemptAt: Date?, lastFailure: AppFailure?,
                                  leaseOwner: UUID?, leaseExpiresAt: Date?,
                                  updatedAt: Date) -> PendingSubmission?
    public func isOwned(by context: SessionContext) -> Bool
}
```

初期化時にschemaVersion>0、空でないpayload、非負の試行回数、createdAt≤updatedAt、自己依存なしを検証する。保存層が行を復元するときもこの検証付き`init`を使い、不正行を既定値で補完しない。全プロパティは不変で、進行時は`replacingProgress`で検証済みの新しい値を作る。この関数は状態・再開段階の値整合を検証する。遷移の許否は既存の`SubmissionTransition`で別に判定し、ここへ通信・権限判断を持ち込まない。

| state | 許容するresumeStage | 補足 |
|---|---|---|
| draft | upload / register | 画像のない種類はregisterから始められる |
| queued | upload / register | 送信開始前またはupload完了後 |
| uploading | upload | Storage工程中 |
| registering | register | 登録工程中 |
| completed | none | remoteID必須 |
| retryWaiting | upload / register | 前回工程を再開 |
| needsLogin | upload / register | 再認証後の工程を保持 |
| needsCorrection | upload / register | 要修正の段階を保持。既存payloadの変更は不可 |
| outcomeUnknown | register | 結果確認まで再uploadしない |
| cancelled | none | 自動再開しない |

再送待ちの`resumeStage == .register`はremoteIDがまだnilでも有効で、Coordinatorはuploadを繰り返さず同じ操作IDで登録結果を確認する。`SubmissionTransition.allows`へはこの保存済み`resumeStage`を必ず渡し、既定のupload段階を仮定しない。`isOwned`はローカル隔離の補助判定であり、呼び出し前後のepoch有効性は`SessionProviding.isCurrent`で別途確認する。依存操作のremote IDは`dependsOn`から保存層で先行行を検索して得る。`dependsOn`をサーバーIDと混同しない。

## Ports

```swift
public protocol AssetResolving: Sendable {
    func resolve(_ asset: AssetReference, context: SessionContext) async throws -> SignedAsset
    func invalidate(context: SessionContext) async
}
public protocol SessionProviding: Sendable {
    func currentContext() async -> SessionContext?
    func isCurrent(_ context: SessionContext) async -> Bool
}
public protocol SubmissionStoring: Sendable {
    func insertDraft(_ submission: PendingSubmission) async throws
    func listPending(ownerID: UUID) async throws -> [PendingSubmission]
    func completedRemoteID(for dependencyID: UUID, ownerID: UUID) async throws -> UUID?
    func claim(id: UUID, ownerID: UUID, leaseOwner: UUID,
               leaseExpiresAt: Date) async throws -> PendingSubmission?
    func save(_ submission: PendingSubmission, leaseOwner: UUID) async throws
    func release(id: UUID, ownerID: UUID, leaseOwner: UUID) async throws
}
```

`insertDraft`は未登録のdraft行だけを原子的に挿入し、同じ操作IDの二重登録を拒否する。`completedRemoteID`は同一ownerの完了行にremoteIDがある場合だけ返す。`claim`は有効leaseのない同一ownerの行だけを原子的に確保し、別ownerの行は返さない。`save`は保持中のleaseOwnerが一致するときだけ工程を更新し、id/ownerID/payloadDataなどの固定入力の変更を拒否する。これはローカル永続層の境界であり、サーバーの所有者認可や冪等化契約を追加しない。

# MapGrapherCore 先行テスト契約

T01の実装前に固定した公開境界。`Packages/MapGrapherCore/Tests/MapGrapherCoreTests` が期待する最小署名を示す。SDK、UI、DB型はCoreに入れない。

```swift
public enum Visibility: String, Codable, Sendable {
    case anyone = "ANYONE", friends = "FRIENDS", onlyMe = "ONLY_ME"
}
public enum ApprovalStatus: String, Codable, Sendable {
    case pending = "PENDING", approved = "APPROVED", rejected = "REJECTED"
}
public struct GeoPoint: Equatable, Codable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public init?(latitude: Double, longitude: Double)
}
public struct SessionContext: Equatable, Sendable {
    public let userID: UUID
    public let epoch: UUID
    public init(userID: UUID, epoch: UUID)
}
public struct RevealGate: Sendable {
    public init()
    public mutating func ingest(distanceM: Double, accuracyM: Double,
                                timestamp: Date, now: Date, radiusM: Double) -> Bool
}
public enum SubmissionState: String, Codable, Sendable {
    case draft, queued, uploading, registering, completed
    case retryWaiting, needsLogin, needsCorrection, outcomeUnknown, cancelled
}
public enum SubmissionTransition {
    public static func allows(from: SubmissionState, to: SubmissionState,
                              requiresRemoteDependency: Bool,
                              dependencyRemoteID: UUID?) -> Bool
}
```

`GeoPoint` は緯度±90・経度±180を含み、範囲外と非finite値を拒否する。`Codable`復元でも検証を迂回させない。未知の公開範囲、承認状態、投稿状態は復号エラーとし、既定値で補完しない。

`RevealGate` は距離が半径以下、精度が0〜25m、サンプル経過が0〜10秒の連続する異なる時刻の2サンプルで解放する。半径は10〜200mだけ有効。同一時刻は加算せず、無効値・範囲外は連続数を戻す。古い順序のサンプルは加算しない。解放後は探索中に再ロックしない。

`SubmissionTransition` は通常工程を一段ずつ進める。依存が必要な工程の`queued → uploading`は先行工程のremote IDがない限り拒否する。`completed`と`cancelled`からの再進行、逆行、同状態遷移を拒否する。認証と再試行からの復帰は許す。`outcomeUnknown`からの再uploadを拒否する。状態遷移はローカル制約であり、サーバーの権限判定や冪等性の代わりにはしない。

Windows環境にSwift/Xcodeがないため、ここではコンパイル・テスト未実行。Sources実装前のREDと、実装後のGREENをMac上のActionsで確認する。

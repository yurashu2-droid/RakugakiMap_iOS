# iOS版ブラッシュアップ移植 実装計画

> 実装エージェント向け: `superpowers:executing-plans` または `superpowers:subagent-driven-development` を使い、依存関係の順にタスクを実施する。ユーザーが指定したSol high / Luna maxの担当を維持する。本書は計画成果物であり、今のセッションで実装を開始する指示ではない。

**目標:** 初回10人が、写真・ラクガキ・グループと現地ARをiPhoneで利用できる、保守可能なネイティブ版を作る。

**構成:** SwiftUIの機能別画面、FoundationのみのCore、用途別Repository、Supabase adapter、Core Data送信キュー、ARKit/RealityKit。バックエンドの既存契約は共有し、必要な追加契約だけ別レビューする。

**技術:** Swift 6言語モード、iOS 17.0以上、SwiftUI、MapKit、AVFoundation、CoreGraphics/CoreImage、Core Data、ARKit、RealityKit、supabase-swift。

**仕様:** [IOS_PORT_DESIGN.md](IOS_PORT_DESIGN.md)。検証手順と実行依頼は [IOS_PORT_VALIDATION_HANDOFF.md](IOS_PORT_VALIDATION_HANDOFF.md)。両方を先に読む。

## 全体制約

- 新規ルート `MapGrapherClient/MapGrapherIOS`。既存Android、旧Spring Boot、本番設定は原則変更しない。
- iPhone・iOS 17.0以上、日本語。Swift 6言語モード。Xcode/SDK/依存解決版はT00で固定・記録する。
- `auth.uid()`、private bucket、path保存、公開範囲、承認状態は維持する。
- `ANYONE`は認証済み向け。グループ閲覧例外をクライアントのprivacy判定で消さない。
- ARは初回必須。LiDARを必須にせず、非LiDAR実機で確認する。
- 初版対象外は独自3Dマップ、プッシュ、常時追跡、永久/共有アンカー、動画投稿。必須機能は設計書§3に従う。
- DB/RLS/RPC/Storageの変更は共有台帳へ提案しレビュー後に実装。B01/B02の新API名は承認前に既存APIとして使わない。
- 同期済みデータは共有する。Android端末だけのRoom下書きやログイン状態は自動移行しない。
- 未コミットの既存作業を戻さない。git addは自分の担当ファイルを列挙し、`git add .`を使わない。
- ソース、fixture、ログにtoken、鍵、実在ユーザー情報、正確な個人位置を入れない。fixtureは合成データ。
- 各タスクのチェックは検証結果が出てから付ける。Macなしのコード作成をiOSビルド成功と呼ばない。

## レビュー重点と担当テスト

| 見落としやすい条件 | 期待挙動 | 担当 |
|---|---|---|
| Aのリクエスト中にBへ切替 | Aの画像/結果を表示せずAの下書きをBで送らない | T04/T05/T06/T11 |
| DB成功後に応答が失われる | 同じoperationは同じremote ID。重複なし | B01/T11 |
| 概算位置・古い位置・未来timestamp | ARを誤解放しない。地図は代替表示可能 | T07/T13 |
| HEIC回転・ズーム・消しゴム・透過 | 正しい写真座標と透明レイヤー、ARで黒背景なし | T08/T09/T02 |
| グループ回答が0時JSTを跨ぐ | 翌日へ勝手に投稿せず、写真と失敗理由を保持 | T16 |

## 担当とファイル所有権

Sol high = `gpt-5.6-sol` / reasoning `high`。Luna max = `gpt-5.6-luna` / reasoning `max`。実行時の利用可能モデルを確認し、利用不可なら黙って別モデルへ変更しない。ユーザー指定は実装時の担当であり、今回それらのエージェントを起動したという意味ではない。

| 所有範囲 | 主担当 | 補足 |
|---|---|---|
| Xcode project、SPM、AppContainer、Coreの公開protocol | Sol | 変更は統合担当に一本化 |
| 認証、通信、キュー、画像、AR、描画エンジン | Sol | Lunaが独自の代替adapterを作らない |
| DesignSystem、Resources文言、画面、プレビュー、UIテスト | Luna | 契約にない項目を画面の都合で追加しない |
| backend追加契約 | Sol実装、設計主任レビュー | B01/B02に限定。レビュー前は提案だけ |
| docs/verification.md | 各担当追記、Sol統合 | AGENTS.mdに進捗を書かない |

並列作業は別ファイルのタスクに限る。project.pbxprojとLocalizable.xcstringsを同時編集しない。Lunaは文言追加をタスク単位にまとめ、Solとの統合時に競合を解消する。試験環境のDB変更中に別担当のAPI試験を走らせない。

## 作業の依存関係

```text
T00 → T01 → T02（AR成立 G1）
        ├→ T03 → T04 → T05
        ├→ T06
        ├→ T07
        └→ T09
T01 → L01（部品・ナビゲーション）
T04 + T07 + T05 → L02（地図/詳細）
T06 → T08（撮影/画像）
T03 → B01（承認後の冪等化）
T04 + T05 + T06 + T08 + B01 → T11（投稿Coordinator）
L01 + T08 + T09 + T11 → L03（投稿/描画UI）
T02 + T03 + T07 + T09 + T11 → T13（AR統合）
T03 + T04 + T05 + T08 → T14（Social/Profile/Album adapter）→ L04
T03 + T04 + T11 → T16（Group adapter）→ L05
T03 → B02（承認後の安全機能）→ T18 → L06
全必須タスク → T19（統合・10人配布候補 G5）
```

L01やfixture作成はAR試作と並行可能。G1前に全機能の本実装へ大量着手しない。B01未承認ならT11はmockで停止し、実通信の作成再送へ進まない。B02未承認でも他の基本機能の開発は進められるが、公開候補とはしない。

## コマンド規約

以下のC0〜C5の正確なコマンドは引き継ぎ文書にある。実装時に作成するscriptとschemeもT00で定義する。

- C0: Coreの`swift test`。
- C1: 指定iOS Simulatorで全unit test。
- C2: 指定iOS Simulatorで対象XCUITest。
- C3: generic iOS device向け署名なしbuild。
- C4: 非LiDAR iPhoneでAR/カメラ/位置/中断を手動確認。
- C5: Backendのquick/DB/RLS/secret scan、必要ならAndroid回帰。

各実装タスクは、意味のある失敗テスト/失敗シナリオを先に用意→失敗確認→実装→指定検証→担当ファイルだけコミット、の順。単純な色定義に挙動を写すだけのunit testを増やさず、画面確認で検証する。

## T00: 実行環境とビルド可能な最小アプリ

**担当:** Sol high。依存なし。

**作成:** `MapGrapherClient/MapGrapherIOS/README.md`、`MapGrapherIOS.xcodeproj/project.pbxproj`、共有scheme `MapGrapherIOS.xcscheme`、`MapGrapherIOS/App/MapGrapherApp.swift`、`Packages/MapGrapherCore/Package.swift`、`Packages/MapGrapherCore/Sources/MapGrapherCore/BuildIdentity.swift`、`Packages/MapGrapherCore/Tests/MapGrapherCoreTests/BuildIdentityTests.swift`、`MapGrapherIOSTests/LaunchTests.swift`、`MapGrapherIOSUITests/LaunchUITests.swift`、`scripts/verify-ios.sh`、`docs/ENVIRONMENT.md`、`MapGrapherIOS/Configuration/Local.example.xcconfig`、`.gitignore`。

**触らない:** Android、backend、署名鍵、既存git設定。

**提供:** Core package、app/test targets、mock launch引数`--ui-testing`、C0〜C3。

- [ ] `xcodebuild -version`、`swift --version`、`xcrun simctl list devices available`を確認し、Mac/Xcode/SDK/SimulatorとiPhone機種・OSの有無をENVIRONMENTへ記録。Windowsだけなら環境待ちと明記。
- [ ] iOS deployment target 17.0、Swift 6、scheme共有、unit/UI test targetを作る。Bundle IDは開発用値を環境設定から与え、配布IDは所有アカウント確認後に設定。個人のTeam IDをハードコードしない。
- [ ] CoreはFoundationのみ。Core Data/AR/UI実装をpackageへ持ち込まない。supabase-swiftの固定版をapp targetへ追加し解決結果を保存。
- [ ] scriptは`set -euo pipefail`、`IOS_SIMULATOR_ID`必須、projectの絶対位置をscript自身から解決。検証結果を`.build/verification/`へ保存しgitignoreする。存在しないdestinationなら早く失敗する。
- [ ] C0/C1/C2のLaunchUITests/C3を実行。実機なくてもbuild完了とAR未確認を分けて報告。

**完了:** Macでクリーンチェックアウトから日本語の空画面が起動する。例示設定しか追跡されず、未設定本番接続は無効。

## T01: Core型、エラー、protocol、状態遷移

**担当:** Sol high。依存T00。

**作成（Core配下）:** `Domain/Identity.swift`、`Domain/Photo.swift`、`Domain/ArExperience.swift`、`Domain/Submission.swift`、`Domain/AppFailure.swift`、`Ports/AssetResolving.swift`、`Ports/SessionProviding.swift`、`Ports/SubmissionStoring.swift`、`Rules/RevealGate.swift`、`Rules/SubmissionTransition.swift`。テスト`IdentityTests.swift`、`RevealGateTests.swift`、`SubmissionTransitionTests.swift`。

**提供する追加境界:**

```swift
public protocol SessionProviding: Sendable {
    func currentContext() async -> SessionContext?
    func isCurrent(_ context: SessionContext) async -> Bool
}
public enum SubmissionState: String, Codable, Sendable {
    case draft, queued, uploading, registering, completed
    case retryWaiting, needsLogin, needsCorrection, outcomeUnknown, cancelled
}
public struct RevealGate: Sendable {
    // 同じtimestampはカウントしない。無効/範囲外なら連続数をリセット。
    public mutating func ingest(distanceM: Double, accuracyM: Double,
                               timestamp: Date, now: Date, radiusM: Double) -> Bool
}
```

この断片の関数本体はT01で実装する。仕様値は設計§8から固定。DTOやSDK型をCoreへ置かない。

- [ ] 設計§6の値型にpublic initializer、Equatable/Codable/Sendableを必要に応じて付け、検証付きfactoryで不正座標と空pathを拒否する。
- [ ] `Photo`はid/ownerID/title/location/visibility/drawPermission/requiresApproval/createdAt/asset/thumbnail/likeCount/likedByMe、`ArExperience`はid/photoID/rakugakiID/asset/unlockRadiusM/discoveryRadiusM/displayWidthM/location/anchorTypeを定義。UIのローカルIDと混ぜない。
- [ ] `PendingSubmission`を設計§7のフィールドで定義し、工程と依存の遷移表を実装。completed→uploading、cancelled→registering、remote IDなしの依存工程開始を拒否。
- [ ] 上記3テストファイルへ未知enum、範囲境界、epoch違い、無効遷移を追加。下記のARテストを実装する。

```swift
func testRevealNeedsTwoDistinctAccurateSamples() {
    var gate = RevealGate()
    let now = Date(timeIntervalSince1970: 2_000)
    XCTAssertFalse(gate.ingest(distanceM: 20, accuracyM: 5,
                              timestamp: now, now: now, radiusM: 50))
    XCTAssertFalse(gate.ingest(distanceM: 20, accuracyM: 5,
                              timestamp: now, now: now, radiusM: 50))
    XCTAssertTrue(gate.ingest(distanceM: 20, accuracyM: 5,
                             timestamp: now.addingTimeInterval(1),
                             now: now.addingTimeInterval(1), radiusM: 50))
}
```

- [ ] C0/C3。Lunaへ公開型一覧とcommitを渡し、以後のsignature変更はSolがまとめる。

**完了:** 不正な状態を画面都合のBoolで隠せず、OSなしでルールテストが動く。

## T02: ARローカル試作と採用判定 G1

**担当:** Sol high。依存T01。AR実機が必要。

**作成:** `Infrastructure/AR/ARSessionDriver.swift`、`ARCanvasView.swift`、`ARImagePlaneFactory.swift`、`ARSnapshotWriter.swift`、`Features/AR/ARProbeScreen.swift`、`Resources/Fixtures/ar-transparent-test.png`、`docs/AR_PROBE.md`。テスト`MapGrapherIOSTests/ARPlaneGeometryTests.swift`。

**触らない:** Supabase、位置判定API、共有アンカー、Android AR。

**提供:** `@MainActor ARSessionDriver`の`start()`、`place(at: CGPoint)`、`resetPlacement()`、`pause()`、`snapshot() async throws -> UIImage`。`ARCanvasView`だけがARViewを所有。入力画像はローカルfixture。

- [ ] 画像幅1000/高さ500/実幅1mなら板の高さ0.5mとなる純粋計算テストを用意し、0幅と非finiteを拒否する。
- [ ] `ARWorldTrackingConfiguration.isSupported`を確認し、horizontal/vertical平面検出で開始。raycast失敗時は配置せず「面を探しています」。hit結果からanchorを作り透過板1枚を配置する。
- [ ] 既存anchorを解除して再配置。追跡limited、session interruption、background、復帰、退出を扱う。snapshotは写真ライブラリへ直接保存せずUIImageを返す。
- [ ] 非LiDAR iPhoneで透明縁・表裏・縦横比・1m相当・横/縦平面・5分利用・10回入退場・snapshotを確認。場所や顔を含まない検証素材を保存。
- [ ] C1のARPlaneGeometryTests/C3/C4。技術的失敗ならAR方式を再設計してG1未通過と報告。カメラ上の2D画像で代用しない。

**完了:** 実機記録に機種/OS/ビルドcommit/各操作結果があり、G1通過。サーバー連携はT13。

## T03: 既存APIのSwift対応表とfixture

**担当:** Sol high。依存T01。

**作成:** `Infrastructure/Supabase/DTO/{Photo,Rakugaki,Ar,Social,Group,Profile,Album,Notification}DTO.swift`、`SupabaseGateway.swift`、`docs/API_PARITY.md`、`MapGrapherIOSTests/ContractDecodingTests.swift`、`MapGrapherIOSTests/Fixtures/`内のAPI別JSON。

**入力:** 台帳、`SupabaseApiService.kt`、`SupabaseDtos.kt`、最新順のmigration。文書だけでなく現行SQLとの不一致を記録。

**提供:** `SupabaseGateway`はSDKラッパー。API_PARITYに全利用RPC/RESTの引数名、返却shape、nullable、失敗、再送可否、担当adapterを1行ずつ記録する。

- [ ] 写真/描画/AR/友達/likes/album/profileと台帳の全19グループRPCを対応表へ列挙。旧AR4引数版を使わず5引数版へ合わせる。
- [ ] Photo/Rakugaki作成は単一行、nearby/permissions/AR取得の配列は要素数を明示。空配列をnotFoundとする対象と正常emptyの対象を分ける。
- [ ] SQLの型からCodableを実装。Dateは小数秒あり/なしISO8601、JST mission_dateは日付文字列として扱い端末timezone変換しない。Bool/null/64bit件数をテスト。
- [ ] test fixtureは合成UUIDと人工座標だけ。JSON encodeで正確な既存キー、decodeでnull/未知enum/配列shapeを検証。HTTP失敗を成功emptyへ変換しない。
- [ ] C1のContractDecodingTests/C3。台帳と違う契約は勝手に修正せず不一致表へ記録しSolが解決する。

**完了:** 後続がKotlinファイル全体を読まずにDTOを利用でき、v2やSafetyの未実装APIが既存契約と混ざっていない。

## T04: 認証とセッション一元化

**担当:** Sol high。依存T03。

**作成:** `App/SessionController.swift`、`App/AppContainer.swift`、`Infrastructure/Supabase/SupabaseAuthRepository.swift`、`Infrastructure/Supabase/KeychainSessionStorage.swift`、`App/AuthLinkHandler.swift`、`MapGrapherIOSTests/SessionControllerTests.swift`、`AuthLinkTests.swift`。

**提供:** `SessionController`はSessionProvidingを実装し、復元中/未認証/確認メール待ち/認証済み/再認証待ちを観測可能にする。`signIn(email:password:)`、`signUp(email:password:displayName:)`、`signOut()`、`requestPasswordReset(email:)`、`handleAuthURL(_:)`をasync throwsで公開。tokenは返さない。

- [ ] fake Auth adapterで再起動、同時認証更新、期限切れ、確認待ち、logout中request完了を先にテストする。
- [ ] SDKのセッションイベントを一箇所で購読。購読とrefreshを重複登録しない。ローカルKeychainはapp・環境ごとにnamespaceを分離。
- [ ] Auth callbackのscheme/host/pathとフローをallowlist化し、任意URLを認証URLと解釈しない。確認/再設定のcold/warm startを分けて扱う。許可redirect URL追加は環境設定タスクとして記録。
- [ ] logoutでepoch変更、同期取消、画像失効をAppContainerへ通知。通信断のlogoutでも端末側セッションを残さない。アカウント削除とlogoutを混同しない。
- [ ] C1のSessionControllerTests/AuthLinkTests、C3。開発Supabaseで実認証を確認。標準SMTPのまま一般ユーザーのメール確認ができると仮定しない。

**完了:** どの画面からlogoutしても同じ結果。token期限後の回復と別ユーザー切替に実証がある。

## T05: private画像表示とセッション別キャッシュ

**担当:** Sol high。依存T04。

**作成:** `Infrastructure/Media/PrivateAssetLoader.swift`、`AccountImageCache.swift`、`Infrastructure/Supabase/SupabaseAssetResolver.swift`、`MapGrapherIOSTests/PrivateAssetLoaderTests.swift`。

**提供:** AssetResolving実装と`load(asset:targetPixelSize:context:) async throws -> UIImage`。画像返却時にepoch再照合。Lunaはこの入口のみを利用。

- [ ] fake clock、URL signer、image downloaderを注入し、expiry直前、403、logout途中、同一path別userを試験。
- [ ] URLのkeyにuser/epoch/bucket/pathを含め、expiresAtの60秒前を再取得基準にする。要求TTLは最大300秒を開始値とする。失敗時にpublic URLへfallbackしない。
- [ ] 画像デコードを画面外で行い、target sizeでdownsample。画面再利用とTask取消で古い結果を捨てる。ディスク画像キャッシュは初版無効とし、メモリcacheを容量制限する。
- [ ] 403/404で破棄→権限再確認、再取得は最大1回。通信不通は再読込UIへ返す。
- [ ] C1 PrivateAssetLoaderTests/C3。A logout→B loginで同path画像が出ないことをC2に追加。

**完了:** 永続DBにsigned URLがなく、権限外の画像を前セッションのcacheから表示しない。

## T06: 所有者付き永続キューとmigration

**担当:** Sol high。依存T01。

**作成:** `Infrastructure/Persistence/CoreDataSubmissionStore.swift`、`PersistentContainerFactory.swift`、`MapGrapherStore.xcdatamodeld/MapGrapherStoreV1.xcdatamodel/contents`、`DraftFileStore.swift`、`MapGrapherIOSTests/SubmissionStoreTests.swift`、`DraftFileStoreTests.swift`。

**提供:** CoreのSubmissionStoring protocolは`save(_:)`、`pending(ownerID:now:)`、`claim(id:ownerID:leaseID:until:) -> Bool`、`update(_:leaseID:)`、`release(leaseID:)`をasync throwsで定義。型はPendingSubmission、UUID、Date。実装名はCoreDataSubmissionStore。未ログイン時にownerを推定しない。

- [ ] 一時SQLite storeでA/B混在、同時claim、再起動、lease期限、save失敗を試す。in-memory storeだけで完了しない。
- [ ] id uniqueとowner index、ファイルと工程を保存。NSManagedObjectはperform外へ出さずDTOへ変換。
- [ ] 画像はApplication Supportのowner/operationディレクトリに原子的保存しfile protectionを設定。パストラバーサル拒否、capacity不足をエラーにする。OS一時ディレクトリに下書き原本を置かない。
- [ ] schema versionとmigration方針を明記。fixtureのV1 storeを再openして下書き保持を確認。失敗時にstoreを消さず「保存データを開けません」と復旧経路を示す。
- [ ] C1 SubmissionStoreTests/DraftFileStoreTests/C3。保存→kill→再起動で同じid/owner/工程を取得。

**完了:** 作成時ownerが固定され、停止後に残る。解放前のleaseを別処理が奪わない。

## T07: 前景位置・方向と探索ロジック

**担当:** Sol high。依存T01。

**作成:** `Infrastructure/Location/ForegroundLocationProvider.swift`、`HeadingProvider.swift`、`TraceHaptics.swift`、Core `Rules/TraceDirection.swift`、`Rules/TraceDistanceBand.swift`、テスト`TraceDirectionTests.swift`、`TraceDistanceBandTests.swift`、`MapGrapherIOSTests/LocationLifecycleTests.swift`。

**提供:** 位置とheadingのAsyncStream、start/stop、認可状態。CoreへはLocationSampleとtrueHeadingDegrees/accuracyを渡す。

- [ ] ±180°正規化、359°→1°の2°差、0/15/50/100m境界、negative accuracyをテストする。
- [ ] CLLocationManagerはmain actor上。When In Useだけ要求し、画面退出/backgroundでlocation/heading購読とhapticsを停止。
- [ ] trueHeading無効時は方位不明。magnetic headingと真北bearingを無補正で混ぜない。概算位置は地図で利用し、ARゲートには使わない。
- [ ] 位置精度25m超/10秒超/未来timestampは無効、distinct sampleをT01ゲートへ渡す。hapticsは最短400ms、方位/位置無効なら停止、成功は1回。
- [ ] C0/C1 LocationLifecycleTests/C3/C4。権限拒否・設定復帰・センサー不在でクラッシュしない。

**完了:** 画面を離れた後に位置追跡と振動が残らない。

## L01: デザイン基盤、ナビゲーション、認証画面

**担当:** Luna max。依存T01。実認証接続はT04完了後。

**作成:** `DesignSystem/{AppColors,AppSpacing,LoadStateView,PrimaryButton}.swift`、`App/AppRoute.swift`、`App/RootTabs.swift`、`Features/Auth/{WelcomeScreen,SignInScreen,SignUpScreen,PasswordResetScreen}.swift`、`Resources/Assets.xcassets`、`Resources/Localizable.xcstrings`、`MapGrapherIOSUITests/AuthUITests.swift`。

**触らない:** SessionController、Keychain、AppContainer、project.pbxproj。統合依頼をSolへ渡す。

**提供:** 4タブとsheet/fullScreenCoverの単一router。各画面は注入されたModelまたはfakeを使い、直接SDKへ接続しない。

- [ ] 設計§4の4タブと投稿全画面、AR全画面をroute enumで表す。表示名変更ではなく型で遷移する。
- [ ] 意味別Color Assetのlight/dark、Dynamic Type、44pt、VoiceOver、Reduce Motionを実装。ブランド装飾はピン/描画周辺に限定。
- [ ] 認証画面に入力、送信中、確認メール待ち、再試行、再設定を用意。password/tokenをログに出さない。二重送信中の再タップだけ無効化。
- [ ] fake sessionで各状態をPreview/UIテスト。`auth.email`、`auth.password`、`auth.submit`等の安定accessibilityIdentifierを定義。
- [ ] C2 AuthUITests/C3。大きい文字・dark・VoiceOverでラベルとエラーが切れない。T04接続後にfakeだけの合格を実認証完了と混同しない。

**完了:** 全部品が状態を区別して表示し、logout後に保護画面のnavigation stackが残らない。

## L02: 地図・投稿詳細・一覧のUI

**担当:** Luna max。依存L01/T04/T05/T07、T03 DTO。MapKit adapterのレビューはSol。

**作成:** `Features/Map/{MapScreen,MapScreenModel,PhotoDetailScreen,PhotoListScreen,PhotoPinView}.swift`、`Infrastructure/Location/MapCanvasView.swift`、`Infrastructure/Supabase/PhotoReadRepository.swift`、`MapGrapherIOSTests/MapScreenModelTests.swift`、`MapGrapherIOSUITests/MapUITests.swift`。

**提供:** `PhotoReading.nearby(center: GeoPoint, radiusM: Double) async throws -> [Photo]`、`permissions(photoID: UUID) async throws -> PhotoPermissions`。protocol追加はSolのT01型レビュー後。PhotoReadRepositoryは既存nearby/permissions契約のみ。

- [ ] MKMapViewのdelegateをラッパー内へ閉じる。visible regionが落ち着いた時に検索し、古いrequestを取消、完了時も検索世代を比較。
- [ ] キャッシュの一覧は検索範囲別。結果にいない写真をDB全体から削除しない。写真ピン/clusterと同じ結果のリストを用意。
- [ ] 全て/友達/24時間は現行意味で表示。友達filterはサーバーで取得済み許可範囲内で適用し、グループ閲覧例外を全てから除外しない。
- [ ] 詳細は画像、作者、相対時刻、描く/ARの主行動、履歴、管理menu。permissions取得中は編集権限未確定。403/404では古い画像を消し権限説明。
- [ ] C1 MapScreenModelTests（検索順序逆転、空/失敗、権限未確定）/C2 MapUITests/C3。

**完了:** 地図・リスト・詳細で同じ投稿と権限を表示し、現在地拒否でも説明と地図移動が可能。

## T08: 撮影と画像の安全な準備

**担当:** Sol high。依存T06。

**作成:** `Infrastructure/Media/{CameraController,PhotoPickerAdapter,ImagePreparer,ImageMetadataInspector,PhotoLibraryWriter}.swift`、Core `Domain/PreparedImage.swift`、`MapGrapherIOSTests/ImagePreparerTests.swift`、fixture JPEG/HEIC/PNG。

**提供:** `prepare(input: URL) async throws -> PreparedImage`。PreparedImageはfileURL/mimeType/byteSize/pixelWidth/pixelHeight/sha256。CameraControllerは撮影した永続ファイルURLを返す。ARとカメラはAppContainerのexclusive camera leaseを共有。

- [ ] EXIF orientation各向き、HEIC、透明PNG、不正画像、巨大寸法、容量不足の合成fixtureを用意。
- [ ] ImageIOでdecode前に寸法確認とdownsample。再エンコード後にGPS/EXIFがないことをImageMetadataInspectorで確認。写真はJPEG、透明レイヤーはPNGとして別入口にする。
- [ ] 長辺1600/品質0.8から設計§9の調整を実装し、最終上限越えは保存前に理由を返す。main actorで巨大decodeしない。
- [ ] Camera session開始/停止を専用queueで管理し、退出時解放。写真保存はadd-only要求、拒否しても端末下書きは保持。
- [ ] C1 ImagePreparerTests/C3/C4。前後カメラ、portrait/landscape画像、選択取消、AR切替を確認。

**完了:** 出力の寸法・MIME・向き・metadataとメモリを実測。圧縮したつもりで原本をuploadしない。

## T09: ラクガキエンジンと透明書き出し

**担当:** Sol high。依存T01。描画本体は並行可能だが書き出し統合はT08のPreparedImage確定後。

**作成:** Core `Domain/DrawingDocument.swift`、`Rules/DrawingTransform.swift`、`Features/Drawing/{DrawingCanvasView,DrawingRenderer,DrawingHistory}.swift`、`Infrastructure/Media/DrawingExporter.swift`、テスト`DrawingTransformTests.swift`、`MapGrapherIOSTests/DrawingRendererTests.swift`。

**提供:** `DrawingRenderer.render(document:) -> CGImage`、`DrawingExporter.export(document:) async throws -> PreparedImage`（型はT08で統合）。端末上の編集データ形式はversioned Codable。

- [ ] 座標変換を先にテスト。aspectFit余白→pan/zoom逆変換→画像ピクセルへの変換を明示。余白のタッチはstrokeにしない。
- [ ] touch点を画像座標へ記録。通常pen、crayon粒状、neon光彩、spray粒子、eraserを別brush実装へ分ける。spray/crayonはstrokeの固定seedでUndo後も同じ描画。
- [ ] 一筆単位のUndo/Redo。消しゴムは透明レイヤーだけをclearし写真を削らない。履歴はvector+checkpointとし毎タッチ全画面bitmapコピーを避ける。
- [ ] 書出しは元写真を合成しない透明PNG。写真合成previewは別関数。中断・再起動後にDrawingDocumentから復元。
- [ ] C0変換テスト、C1レンダリング/alpha/seed再現、C3。T02のARへ書出しPNGを入れ黒背景がないことを確認。

**完了:** ズームと回転済み写真でずれず、5種brushと透明書出しが成立。

## B01: 投稿作成の冪等化（契約レビュー後のみ）

**担当:** Sol high。依存T03。触ってよい範囲はBackendの追加migration、対応試験、台帳だけ。

**作成予定:** `MapGrapherBackend/supabase/migrations/202609200001_add_submission_idempotency.sql`、`supabase/tests/submission_idempotency.sql`、`scripts/test-submission-idempotency.ps1`。番号衝突時は未使用の後続日時を選び文書を更新。

**変更:** `shared_interface_registry.md`、`package.json`に`test:submission-idempotency`。既存migrationを編集しない。

**提供:** 設計§7の2つのv2 RPC、operation receipt、同入力同結果、異入力拒否、削除後非復活。

- [ ] signature、receipt schema、hash対象、エラーcode、権限、保持/削除方針を台帳へ「提案」として記録し設計主任レビュー。未承認の間はSQL適用しない。
- [ ] ローカル用の合成A/B userで、同一再送、並行再送、owner違い、payload変更、対象削除、無認証を試験SQLへ記述。新RPCがない段階で失敗を確認。
- [ ] receipt一意キーとtransaction lock、現行作成処理とのatomic commitを実装。既存APIはそのまま。Storage path所有者・mime/sizeを引き続き検証。
- [ ] 同一operationを並行2接続で呼び写真/ラクガキが各1件、返却id一致を確認。ネットワーク応答消失はT11のfault injectionと組み合わせる。
- [ ] C5と新npm test。Androidの既存create RPC/RLS smokeが通る。DB reset対象がローカルであることを事前確認し、本番を使わない。

**完了:** 台帳に承認済み契約、回帰結果あり。署名だけ追加して内部で2重insertする実装は不可。

## T11: 再開可能な投稿Coordinator

**担当:** Sol high。依存T04/T05/T06/T08/B01。

**作成:** Core `Ports/SubmissionTransport.swift`、`Submission/SubmissionCoordinator.swift`、`Infrastructure/Supabase/SupabaseSubmissionTransport.swift`、`MapGrapherIOSTests/SubmissionIntegrationTests.swift`、Core `SubmissionCoordinatorTests.swift`。

**提供:** `enqueue(draftID: UUID, context: SessionContext) async throws -> UUID`、`resume(context:) async`、`cancel(operationID:context:) async throws`。HTTP詳細をUIへ返さず、永続状態を観測させる。

- [ ] fake transportでupload成功後、DB成功応答前、DB成功後local保存前、AR登録前、logout中の5点に障害を注入する。
- [ ] enqueue時にimmutable payloadとpathとownerを確定し、lease付きで工程を進める。時限leaseが有効でもactor reentrancyで同operationを重複開始しない。
- [ ] timeout/429/5xxは同一idでbackoff（開始2秒、最大60秒、jitter、5回で手動再試行待ち）、401は再認証、403/validationは要修正、cancelledは自動再試行なし。結果不明は冪等RPCで同じ結果へ回復。
- [ ] photo/rakugaki/ar/groupAnswerを独立行にし依存IDで開始制御。後続失敗が先行成功を消さない。アカウント変化時は各await前後でcontextを照合。
- [ ] C0/C1 SubmissionIntegrationTests/C3。各障害後に再起動してremote件数=1、owner不変、完了工程の再uploadなしを確認。

**完了:** 最新APK方式の「再ビルド」ではなく、永続状態から投稿処理を確実に再開できる。利用者へ送信済み/待機/要対応が正しく出る。

## L03: 撮影・描画・投稿確認UI

**担当:** Luna max。依存L01/T08/T09/T11。

**作成:** `Features/Posting/{CaptureScreen,PhotoReviewScreen,PublishScreen,SubmissionStatusScreen,PostingFlowModel}.swift`、`Features/Drawing/{DrawingScreen,DrawingToolbar}.swift`、`MapGrapherIOSUITests/PostingUITests.swift`。

**提供:** 撮影から送信状況まで1つのdraftIDを運ぶflow。group missionから入る場合も同じflowへmissionIDを添える。

- [ ] 撮影/選択、取り直し、描画、公開確認、端末保存、送信状態の遷移を接続。SDK/Storageへ直書きしない。
- [ ] 公開確認に場所、閲覧範囲、描画範囲、承認、AR予約を明示。初期値は`ONLY_ME`を提案値としてUI仕様に記録し、ユーザーが変更できる。既存サーバーenumの意味は変えない。
- [ ] AR予約は描画なしなら無効理由、APPROVED待ちなら待機理由を表示。保存したphoto IDがまだない状態でAR RPCを直接呼ばない。
- [ ] 戻る/閉じるは保存・破棄を選べる。再送でタイトル等を変えるときは新操作として明示し、同じ冪等キーに異入力を送らない。
- [ ] C2 PostingUITests（ネット断→送信待ち→再起動→再送、下書き破棄、複数タップ）/C3、C4の撮影と描画。

**完了:** UIの成功表示がサーバー工程に一致し、描いた内容を戻る操作で失わない。

## T13: AR公開・探索・閲覧の統合

**担当:** Sol high。依存T02/T03/T07/T09/T11。

**作成:** `Infrastructure/Supabase/ArRepository.swift`、`Features/AR/{ARScreen,ARScreenModel,TraceExplorerScreen,TraceExplorerModel,ARPublishSettingsScreen}.swift`、`MapGrapherIOSTests/ARFlowTests.swift`。

**提供:** `ArRepository.experience(photoID:)`、`nearbyTraces(at:)`、`publish(photoID:rakugakiID:unlockRadiusM:discoveryRadiusM:displayWidthM:)`。返却値はT01/T03のdomain/DTOからmapperで変換。

- [ ] owner/承認済み/READY/LOCAL_PLANE/各半径条件をテストfixture化。クライアントは親写真のpermissionsとRPC両方を利用し、UI Boolだけで公開しない。
- [ ] T07ゲート→get_ar_experience→private asset→T02配置へ接続。入場時位置を再確認し、期限切れ画像をT05で再取得。
- [ ] 公開予約と投稿詳細からの作成を接続。既存RPCにないpause/deleteを推測して呼ばない。必要なら別契約として提示。
- [ ] discovery対象が消える/閲覧不可/承認取消になるケースで画像とARを閉じ、理由と戻る導線を示す。カメラleaseを取得できないときは他session終了を待つ。
- [ ] C1 ARFlowTests/C3/C4。Android投稿→iOS AR、iOS投稿→Android ARの同素材・サイズ・承認状態を確認。

**完了:** ARがローカルfixtureだけでなく既存Supabaseの許可された素材で成立。位置条件を偽装防止の保証とは表現しない。

## T14: Social・Profile・Albumのadapter

**担当:** Sol high。依存T03/T04/T05/T08。

**作成:** `Infrastructure/Supabase/{SocialRepository,ProfileRepository,AlbumRepository,RakugakiRepository,PhotoWriteRepository}.swift`、Core `Domain/{Social,Profile,Album,Rakugaki}.swift`、`MapGrapherIOSTests/SocialRepositoryTests.swift`、`AlbumRepositoryTests.swift`、`ApprovalRepositoryTests.swift`、`PhotoWriteRepositoryTests.swift`。

**提供:** API_PARITYに沿うfriend request/respond/remove/list、like toggle、profile read/update、album CRUD/関連取得、rakugaki history/pending/approve/reject。UIへはdomain値型を返す。各methodの署名はT03表へ追記してL04開始前に固定する。

- [ ] 自己申請、既に友達、解除後閲覧不可、album owner違い、APPROVED/PENDING/REJECTEDをfixture化。
- [ ] 友達申請の識別にuser_unique_idを使い表示名を使わない。likeは操作中直列化、応答消失時は再取得し自動再toggleしない。
- [ ] album関連をUUIDで更新し、refreshで別IDを作ってリンクを消さない。ローカルDBをサーバーのowner判定に使わない。
- [ ] 承認/拒否成功時に該当詳細・一覧・AR情報cacheを無効化。未承認画像のsigned URLは権限を満たしたユーザーだけ取得。
- [ ] PhotoWriteRepositoryに`updateSettings(photoID:visibility:drawPermission:requiresApproval:) async throws -> Photo`と`delete(photoID:) async throws`を実装し、既存RPCへ接続。削除後に画像/詳細/AR/album cacheを失効。avatar変更はT08の画像処理を再利用し、avatars bucketの5MB上限と既存path規則を守る。プロフィール写真一覧はT03でRLS適用済みの取得経路を固定する。
- [ ] C1の4対象/C3。開発DBのowner/友達/非友達で権限結果を確認。

**完了:** Repositoryごとの責務と認証境界が分かれ、likesの再送で意図が反転しない。

## L04: 友達・履歴承認・プロフィール・アルバムUI

**担当:** Luna max。依存T14/L01/L02。

**作成:** `Features/Social/{FriendsScreen,FriendRequestScreen}.swift`、`Features/Drawing/{HistoryScreen,ApprovalScreen}.swift`、`Features/Profile/{ProfileScreen,ProfileEditScreen,StampCardView}.swift`、`Features/Albums/{AlbumListScreen,AlbumDetailScreen}.swift`、`Features/Map/PhotoSettingsScreen.swift`、各ScreenModel、`MapGrapherIOSUITests/SocialProfileUITests.swift`。変更: L02のPhotoDetailScreenへlike/設定/削除を接続。

**提供:** 詳細menu/マイページから上記へのroute。統計計算は現行StampCardCalculatorを参照してCore `Rules/StampCardCalculator.swift`と`StampCardCalculatorTests.swift`へ移す。

- [ ] empty/loading/errorと、操作可能/不可を描画。プロフィールの表示名と一意IDを区別する。
- [ ] friend申請→受信→承認/拒否→解除、rakugaki履歴→owner承認/拒否、album作成/追加/閲覧を接続。
- [ ] 管理操作はmenu、削除は確認。photo削除とalbumから外す操作は分ける。logoutはSessionControllerのみ。
- [ ] ownerだけPhotoSettingsScreenから公開/描画範囲/承認設定を変更し、写真削除を確認付きで接続。非ownerはUIを隠すだけでなくRPC拒否も確認。アバター選択と表示名変更をProfileEditScreenへ接続する。
- [ ] スタンプ/統計はサーバー取得範囲を明示してfixture比較。取得途中の件数を総件数として見せない。
- [ ] C0 StampCardCalculatorTests/C2 SocialProfileUITests/C3。大きい文字と写真なしアカウントを確認。

**完了:** 全routeが到達可能で、未実装buttonや任意のダミー件数がない。

## T16: グループ・お題・回答・通知adapter

**担当:** Sol high。依存T03/T04/T11。

**作成:** `Infrastructure/Supabase/{GroupRepository,MissionRepository,NotificationRepository}.swift`、Core `Domain/{Group,Mission,AppNotification}.swift`、`MapGrapherIOSTests/GroupContractTests.swift`、`MissionSubmissionTests.swift`。

**提供:** 台帳の全グループRPCのSwift adapter。作成のclient_request_idと回答のmissionID/photoIDを永続化。method署名/返却domainはAPI_PARITYへ固定。

- [ ] OWNER込み8人、招待枠、JST midnight、当日参加対象外、退出・除名・移譲・archiveを既存SQLからfixture化する。
- [ ] client dateでmissionを作らない。サーバー返却日付と参加者snapshotを表示用モデルへ変換。
- [ ] 回答工程はphoto remote IDを待つ。日付跨ぎエラーはneedsCorrectionとして写真を保持。取り下げで写真削除を呼ばない。
- [ ] create_groupの同一key再送は既存RPCを利用。古い回答置換を再送して新しい写真へ戻さないようmission/userごとに直列化。notificationsの既読更新は取り消し時に戻さない。
- [ ] C1 GroupContractTests/MissionSubmissionTests/C3、開発DBでAndroidとの相互回答。

**完了:** UI側でグループ仕様の別実装が不要。元photoのprivacyを書き換えず閲覧結果が一致。

## L05: グループ・お題・通知UI

**担当:** Luna max。依存T16/L01/L03。

**作成:** `Features/Groups/{GroupListScreen,GroupDetailScreen,GroupSettingsScreen,GroupInvitationScreen,MissionPromptScreen}.swift`、`Features/Notifications/NotificationScreen.swift`、各ScreenModel、`MapGrapherIOSUITests/GroupUITests.swift`。

- [ ] グループ一覧に当日お題・参加状況。詳細に投稿・参加者・自分の回答を表示。owner操作は権限に応じてmenuへ。
- [ ] 作成/編集/友達招待/取消/承認/辞退/退出/除名/移譲/archiveを既存契約へ接続。ownerが退出できない理由を表示。
- [ ] setterだけお題入力、OPEN後は編集不可。当日snapshot対象外は「回答への参加は明日からです」。撮影導線はL03を再利用。
- [ ] 通知一覧は表示・既読・関連画面へ移動。削除済みtargetは説明して一覧へ戻す。プッシュ設定のダミー画面を作らない。
- [ ] C2 GroupUITests/C3。mockのmidnightと権限変化、開発DBの複数アカウントを確認。

**完了:** グループRPCの全利用操作に対応画面か明確な内部利用箇所があり、未接続機能を完了報告しない。

## B02: 通報・ブロック・退会の契約とサーバー

**担当:** Sol high + 設計主任レビュー。依存T03。

**対象:** `MapGrapherBackend/docs/account_and_moderation_policy.md`、共有台帳、承認後の新migration/Edge Functions/試験。既存ファイルの他担当追記を保護する。

**成果:** `MapGrapherClient/MapGrapherIOS/docs/SAFETY_CONTRACT.md`。実装前にrequest/response、権限、安定エラーcode、削除対象、状態遷移、運営手順を記載する。

- [ ] 既存実装有無を再走査。通報とブロック、削除申請を既存であると仮定せず、API差分一覧を作る。
- [ ] 合意する具体項目: 通報target=photo/rakugaki/user、重複受付のキー、理由一覧、証拠保全期間、ブロック時の相互表示/グループ回答/AR/通知の扱い、owner退会の移譲または削除、退会完了の判定。ユーザー判断が必要な項目は選択肢と推奨を提示し、このタスクだけ判断待ちにする。
- [ ] 契約承認後、RLS・RPC・管理処理を追加。clientへservice roleを渡さない。画像/DB/Auth削除は再実行可能なサーバー工程にし、途中成功でも追跡する。
- [ ] 無認証/別人削除/ブロック迂回/通報連打/退会途中失敗/ownerグループへの影響をSQL/関数テストで確認。単にclient一覧をfilterするだけでブロック完了にしない。
- [ ] C5、運営の受付→処理→完了の試験。旧文書のメール問い合わせだけの案は採用しない。管理処理の本番適用は別途公開手順へ。

**完了:** アプリが呼べる承認済みAPIと運営手順が揃う。未承認ならL06はmock UIのみ、配布ゲートは未通過。

## T18: Safety adapter

**担当:** Sol high。依存B02/T04。

**作成:** `Infrastructure/Supabase/SafetyRepository.swift`、Core `Domain/Safety.swift`、`MapGrapherIOSTests/SafetyRepositoryTests.swift`。

- [ ] SAFETY_CONTRACTのrequest/responseをCodableとdomainへ変換し、JSON fixtureの一致を検証。
- [ ] 受付と完了を分離。退会は入力確認・必要なら再認証を経てサーバーへ依頼し、成功状態まで認証/キューを整理。
- [ ] block成功でprofile/photo/AR/notificationの関連cacheを失効し、進行中表示も更新。失敗なら成功扱いしない。
- [ ] 退会途中の通信断後に状態を照会し、別の退会操作を重複作成しない。
- [ ] C1 SafetyRepositoryTests/C3、開発環境の削除専用テストユーザーだけで確認。

**完了:** 一般アプリに管理資格情報なし、受付と削除完了が正確。

## L06: 設定・通報・ブロック・退会UI

**担当:** Luna max。依存T18/L04。

**作成:** `Features/Safety/{ReportScreen,BlockedUsersScreen,DeleteAccountScreen,SettingsScreen}.swift`、`MapGrapherIOSUITests/SafetyUITests.swift`。

- [ ] 投稿/ラクガキ/利用者menuへ通報・ブロックを接続。通報理由と受付結果、再試行を表示。
- [ ] 設定に公開ポリシー、問い合わせ、ブロック管理、logout、退会を設ける。未決定のURLを架空リンクで埋めない。
- [ ] 退会画面で消えるデータとグループへの影響を契約どおり表示し、取消/確定、処理中/完了/失敗を区別。
- [ ] 退会の開始導線はアプリ内で完結。外部メールアプリだけへ投げて終えない。
- [ ] C2 SafetyUITests/C3。確認前に削除依頼が送られないこと、失敗時の再試行、完了後の保護画面非表示を確認。

**完了:** 必要な安全機能が実APIへ接続し、利用者が処理状態を把握できる。

## T19: 統合・性能・互換性・配布候補 G5

**担当:** Sol high統合、Luna maxはUI不具合修正。依存全必須タスク。

**作成:** `docs/ACCEPTANCE_RESULTS.md`、`docs/RELEASE_RUNBOOK.md`、`Resources/PrivacyInfo.xcprivacy`、`MapGrapherIOSUITests/EndToEndUITests.swift`。変更: Config/署名設定（公開可能値のみ）、UI不具合の担当ファイル。

- [ ] 引き継ぎ文書の受入表全行を実行しcommit/環境/期待/実測/証拠を記録。「予定」「未実施」を成功件数へ算入しない。
- [ ] C0/C1/C2/C3/C4/C5。Androidとの相互投稿・承認・友達・グループ・ARと、signed URL権限回帰を確認。
- [ ] 100/500の合成写真ピン、5分AR、10回描画/AR切替、20回下書き保存でメモリ増加/発熱/スクロールを測定。ネット断・低容量・権限取消・大きい文字・VoiceOver・darkも実施。
- [ ] 依存SDKのprivacy manifest、Required Reason API、権限purpose文字列、収集データ説明、support/privacy URL、App Store申告を実装と照合。審査用の操作手順は位置ゲートを隠れて無効化せず、試験方法を正直に説明する。
- [ ] Release archive/署名/実機インストールをMacで確認し、TestFlight配布候補を作る。アップロード/配布/本番migrationはユーザーの公開指示後。10人の試験計画と不具合受付・復旧手順を添える。

**完了:** AR含む必須機能と安全項目が実証され、未確認事項が一覧化された配布候補。まだ実施していないApp Reviewを通過済みと報告しない。

## 計画の追跡

各タスク完了時に`docs/verification.md`へ担当/commit/変更ファイル/実行command/exit code/実機の有無/残課題/次担当を追記する。公開protocolを変更した場合は本書・API_PARITY・依存タスクを同じ変更で更新する。

全機能の実装に先立って、T00〜T02とT03で実際の環境と契約を固定する。安全機能のようにプロダクト判断が未確定の箇所は専用タスクとして隔離し、担当が空想のAPIを作って先へ進まない。

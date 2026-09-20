# iOS版ブラッシュアップ移植 設計仕様

作成日: 2026-09-20
状態: 実装前の設計提案。ユーザー依頼に基づく計画成果物。アプリ、DB、本番設定は未変更。

## 1. 目的と確定事項

「撮って、描いて、その場所に残し、現地でARとして見つける」体験をiPhoneへ展開する。最初は同じ生活圏の10人、その後100人程度の利用で価値と運用量を確認する。Androidの画面・クラス構成を複製するのではなく、操作とデータの信頼性を改善する。

ユーザー指定: Expoに限定しない。ARは初回から必須。実装担当はSol highとLuna max。今回の成果物は実装可能な計画書であり、実装開始ではない。

設計上の既定案: iPhone・iOS 17.0以上、日本語、SwiftUI主体のネイティブアプリ。iPad専用UI、Web版、Androidの全面改修は別工程。Mac/iPhoneの準備状況は回答または着手時確認により確定し、用意できるまでは実機完了と扱わない。

関連文書:

- [実装計画](IOS_PORT_IMPLEMENTATION_PLAN.md)
- [検証・担当別引き継ぎ](IOS_PORT_VALIDATION_HANDOFF.md)
- [共有契約](reference/shared_interface_registry.md)
- [ドメイン設計](reference/domain_design_guidelines.md)
- [既存構造のレビュー](reference/REFACTORING_REVIEW_2026-09-12.md)

本案はiOS移植に関して旧Expo検討案を置き換える。旧文書は検討履歴として残す。

## 2. 技術選択

| 選択肢 | 評価 | 判断 |
|---|---|---|
| SwiftUI + ARKit/RealityKit | iOSのAR、権限、カメラ、ライフサイクルを直接扱える。AndroidとUIコードは共有しない | 採用案 |
| React Native + ネイティブAR | UIを共有できるが、AR境界と両OSビルドの保守が追加される | 今回は選ばない |
| Unityをアプリの中心にする | AR中心の体験に強いが、SNS画面、認証、配布サイズ、通常UIとの連携を別途整える必要 | 現在の機能比率では選ばない |

| 分野 | 採用案 | 理由・境界 |
|---|---|---|
| UI | SwiftUI、NavigationStack、sheet、Observation | 画面遷移と状態を一元化。UIKitは端末機能だけ |
| AR | ARKit world tracking + RealityKit ARView | ローカル平面、透過画像板、タップ配置。LiDARを必須にしない |
| 地図 | MapKitのMKMapViewをSwiftUIへラップ | 写真ピン・クラスタ・可視範囲イベントを一箇所で制御。Google Mapsの配色は完全再現しない |
| 撮影 | AVFoundation、PhotosUI | カメラと写真選択を分離。ARと同時にカメラを保持しない |
| ラクガキ | UIKit描画面 + CoreGraphics/CoreImage | ペン・クレヨン・ネオン・スプレー・消しゴムを維持。写真と透明レイヤーを分離 |
| ローカル永続化 | Core Data + Application Support内の画像ファイル | 送信工程とアカウント所有者をトランザクションで保存。外部DB依存を増やさない |
| 認証/通信 | supabase-swift、Swift Concurrency | SDKはデータ層に限定。セッションと通信を各画面へ持ち込まない |
| 資格情報 | Keychain | tokenをUserDefaults、ログ、通常DBに置かない |
| テスト | XCTest、XCUITest、実機AR検証 | 業務ロジック、画面、センサー体験を別の証拠で確認 |

PencilKitだけでは既存の特殊ブラシをそのまま満たすとは限らないため、第一案にしない。SwiftDataも候補だが、今回の永続キューは工程の明示とmigration試験を優先してCore Dataへ統一する。DIフレームワーク、TCA、RxSwift、多数のSwift Package分割は初期導入しない。

最低OSは製品側の選択であり、最新SDKを使うことと分ける。Swift 6言語モードを既定とし、T00でMacに導入可能な安定版XcodeとSDKを記録する。supabase-swiftは確認できた安定版2.55.2を開始候補とし、T00で互換性を確認してPackage.resolvedに固定。mainやbetaへ自動追従しない。[SDK公式リリース](https://github.com/supabase/supabase-swift/releases)、[Xcode要件](https://developer.apple.com/xcode/system-requirements)

## 3. 機能範囲

| 機能 | 最初の10人向け版 | 改善内容/後続 |
|---|---|---|
| 登録・ログイン・確認メール・再設定・ログアウト | 必須 | Auth状態と復帰処理を統一 |
| 地図、近傍写真、友達/24時間フィルター、詳細 | 必須 | 地図から撮影までの主操作を明確化 |
| 写真撮影・選択・下書き・公開設定 | 必須 | 撮影→描画→公開確認を連続したフローへ |
| ラクガキ、Undo/Redo、履歴、承認/拒否 | 必須 | 拡大中も座標がずれない。透明画像をARでも再利用 |
| AR公開予約・現地探索・配置・撮影結果保存 | 必須 | 投稿・承認・AR公開の進行を別々に表示 |
| 友達、いいね、プロフィール、写真一覧、アルバム | 必須 | 閲覧と管理を分ける |
| グループ、お題、回答、招待、アプリ内通知 | 必須 | 既存契約のまま移植。回答と写真を二重保存しない |
| 個人の統計・スタンプカード | 必須 | 計算規則を現行からテストfixture化。未取得を0と偽らない |
| 通報、ブロック、退会 | 配布前の必要項目 | バックエンド未整備部分はB02で設計・実装。画面だけで完了にしない |
| 独自WebView 3Dマップ | 初版から除外する提案 | 通常MapKitの傾斜表示を同等機能と呼ばない。ARの代替でもない |
| プッシュ通知、常時位置追跡、共有永久アンカー、動画投稿 | 初版対象外 | アプリ内通知と前景位置更新は実装する |

除外対象以外を黙って削らない。AR非対応端末の写真表示は救済であり、AR必須要件の達成証拠にはならない。

## 4. UXのブラッシュアップ

画面入口は「地図」「グループ」「お知らせ」「マイページ」の4タブ。撮影は地図の主ボタンから全画面へ。現在のホームにあるお題は地図上の小さなカードとグループ詳細へまとめる。「今日」を独立した管理画面にしない。これはiOS版の提案であり、Androidのタブを変更する指示ではない。

投稿導線:

```text
地図 → 撮影/選択 → 写真確認 → ラクガキ（スキップ可）
     → 公開確認（場所・閲覧範囲・描ける人・承認・AR予約）
     → 端末へ保存 → 送信状況 → 地図の投稿詳細
```

画面ごとに主CTAは1つ。削除、通報、設定はメニューへ置く。sheetを閉じる際、編集済み下書きは保存か破棄を明示する。保存成功前に「投稿しました」と表示しない。写真成功・ラクガキ再送中・AR公開待ちを一つの成功表示に潰さない。

ブランドは既存の「ポップなノート」を継承する。Paper #FFF9F2、Ink #20263D、Coral #C9434Fを基礎に、dark mode用の意味別Color Assetを作る。文字はDynamic Type。操作領域は最低44pt、VoiceOverラベルを付ける。地図が使いにくい人には同じ取得結果の一覧を提供する。動きを減らす設定では装飾アニメーションを抑える。標準sheet/ナビゲーションのジェスチャーを使い、処理中でも取消・戻るを不必要にロックしない。

全画面で loading / content / empty / error を分離。権限不足・認証期限・削除済み・ネットワーク不通を同じ「失敗」にしない。空状態には次の操作を1つだけ置く。日本語文言はLocalizable.xcstringsへ集める。

初回権限要求は操作時に行う。位置情報はWhen In Use、カメラは撮影/AR開始時、写真保存は保存時。近傍探索で常時位置権限を要求しない。概算位置では地図閲覧を許可し、AR解放には精度不足を説明する。

## 5. コード構成と責任

新規ルートは `MapGrapherClient/MapGrapherIOS`。既存Androidはそのまま維持する。

```text
MapGrapherIOS/
  MapGrapherIOS.xcodeproj          アプリ/テストの共有scheme
  MapGrapherIOS/
    App/                          起動・依存注入・セッション・遷移
    Features/                     Auth Map Posting Drawing AR Social Groups
                                  Notifications Profile Albums Safety
    Infrastructure/               Supabase Persistence Media Location AR
    DesignSystem/                 意味別色・共通状態UI・余白
    Resources/                    Assets Localizable PrivacyInfo
    Configuration/                xcconfigの公開可能設定
  Packages/MapGrapherCore/
    Sources/MapGrapherCore/        値型・protocol・純粋な判定・同期工程
    Tests/MapGrapherCoreTests/     XCTestと合成fixture
  MapGrapherIOSTests/              adapter/永続化/画像テスト
  MapGrapherIOSUITests/            主要画面の操作テスト
  scripts/verify-ios.sh            Mac向け検証入口
  docs/                           環境・API対応表・実測ログ
```

CoreはFoundation以外のApple UI/AR/Supabase SDKに依存させない。UIは `@MainActor @Observable` の画面Modelを所有し、Modelから用途別Repositoryを呼ぶ。Core DataのNSManagedObject、ARView、SDKのSessionを画面横断で渡さない。

`PhotoRepository`に友達・AR・アルバムまで集めない。PhotoReading、PhotoWriting、Rakugaki、Social、Group、Profile、Album、Safetyに分ける。複数保存工程がある投稿だけSubmissionCoordinatorを置く。単純なプロフィール取得にUseCase等の空の中間層を増やさない。

SessionControllerがログイン・期限更新・logout・account switchを一元管理。Supabase SDKの更新機構を利用し、独自refreshループを重ねない。状態変化時にsessionEpochを更新し、古いAPI結果・画像結果の描画を破棄する。tokenはSDK adapterの内部から外へ返さない。

Core Data操作は専用contextのperform内に閉じ、Sendableな値型へ変換して返す。actorを付けただけでNSManagedObjectのスレッド安全性が得られたとは扱わない。[Apple Core Data concurrency](https://developer.apple.com/documentation/coredata/using-core-data-in-the-background)

## 6. 最小の共有型・境界

T01で以下の名前と意味を固定し、後続担当は別名の同等型を作らない。追加DTOはT03のAPI対応表に定義する。下記は実装指針であり現時点のコンパイル済みコードではない。

```swift
import Foundation

public enum Visibility: String, Codable, Sendable {
    case anyone = "ANYONE", friends = "FRIENDS", onlyMe = "ONLY_ME"
}
public enum ApprovalStatus: String, Codable, Sendable {
    case pending = "PENDING", approved = "APPROVED", rejected = "REJECTED"
}
public struct SessionContext: Equatable, Sendable {
    public let userID: UUID
    public let epoch: UUID
}
public struct GeoPoint: Equatable, Codable, Sendable {
    public let latitude: Double
    public let longitude: Double
}
public struct LocationSample: Sendable {
    public let point: GeoPoint
    public let horizontalAccuracyM: Double
    public let timestamp: Date
}
public struct PhotoPermissions: Sendable {
    public let canView: Bool
    public let canDraw: Bool
    public let isOwner: Bool
}
public struct AssetReference: Equatable, Codable, Sendable {
    public let bucket: String
    public let path: String
}
public struct SignedAsset: Sendable {
    public let url: URL
    public let expiresAt: Date
    public let context: SessionContext
}
public protocol AssetResolving: Sendable {
    func resolve(_ asset: AssetReference, context: SessionContext) async throws -> SignedAsset
    func invalidate(context: SessionContext) async
}
public enum AppFailure: Error, Equatable, Sendable {
    case offline, needsLogin, forbidden, notFound, cancelled
    case validation(String), rateLimited, outcomeUnknown, serviceUnavailable
}
```

UUIDはすべてSupabaseのremote IDに使用する。ローカル投稿IDとサーバー写真IDは別フィールドで、remote IDは確定前nil。数値IDや`-1`を混ぜない。公開範囲の未知値は安全側のエラーにし、ANYONEへ補完しない。緯度±90・経度±180・finiteを検証。DTOはCodingKeysで既存snake_caseに対応し、日付の小数秒有無、null、配列/単一行をfixtureで固定する。

描画は`DrawingDocument`（schemaVersion、pixelWidth/Height、strokes）、`DrawingStroke`（UUID、brush、色RGBA、width、opacity、points、randomSeed）をCodable値型としてT09で定義する。座標は向き補正後の画像ピクセル座標。編集データは端末内、サーバーには既存形式の透明PNGだけを送る。

## 7. 投稿キューとサーバー変更の境界

Core Dataの`PendingSubmission`は次を保持する。

| 項目 | 意味 |
|---|---|
| id / ownerID / schemaVersion | 固定操作ID、作成時ユーザー、ローカル形式 |
| kind / payloadData / state | photo/rakugaki/ar/groupAnswer、immutable入力、工程 |
| localFilePaths / assetPaths | 永続ファイルと固定Storage path |
| dependsOn / remoteID | 前工程IDと成功したサーバーID |
| attemptCount / nextAttemptAt / lastFailure | 再試行の制御。生レスポンスを保存しない |
| leaseOwner / leaseExpiresAt | 同一工程の二重処理防止 |
| createdAt / updatedAt | ローカル工程の監査用。ログへ位置を出さない |

状態: draft → queued → uploading → registering → completed。補助状態: retryWaiting、needsLogin、needsCorrection、outcomeUnknown、cancelled。キャンセルはサーバー成功の取消とは限らず、削除は別操作。

写真作成→ラクガキ作成→AR公開、写真作成→グループ回答の依存関係を持つ。先行成功を巻き戻さず、未完了工程だけ再開する。ARは写真ownerかつAPPROVEDのラクガキが必要。承認待ちなら「AR公開待ち」とし無限再試行しない。

固定pathは最初の保存時に生成し、再試行ごとに変えない。書込は一度ファイルへ完了→atomic rename→DB登録。中断時の孤立ファイルはキュー参照との照合後に回収し、下書きは対象にしない。失敗したmigrationでDBを削除して復旧しない。

同じownerの行だけを処理する。logoutではキュー停止→epoch無効化→SDKセッション破棄→表示キャッシュ破棄。未送信の本人データは保護した領域に隔離し、別人から見せず同一アカウント再認証後に再開する。

通常同期は起動・前景復帰・通信復帰・手動再送。iOSのBackgroundTasksは補助であり15分ごとの確実な送信を約束しない。初版では独立した常時バックグラウンドアップロードを必須にしない。強制終了後は次回起動から回復する。[Apple BackgroundTasks](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)

### B01: 投稿v2の冪等契約（検証用DBに適用済み）

既存のcreate_photo_pin/create_rakugakiを変更せず、v2の追加RPCを検証用Supabaseに適用した。公開用プロジェクトへの適用とiOSからの実投稿は未検証。詳細は`B01_IDEMPOTENT_POSTING_CONTRACT.md`に合わせる。

- `create_photo_pin_v2(client_request_id,title,lat,lon,privacy,draw_permission,requires_approval,photo_path,mime_type,byte_size)` → 既存`PhotoRowDTO`と同形の単一JSON object。
- `create_rakugaki_v2(client_request_id,target_photo_id,target_asset_path)` → 既存`RakugakiRowDTO`と同形の単一JSON object。
- ownerは`auth.uid()`から取得する。`(actor_id,operation_kind,client_request_id)`をreceiptの一意キーとし、正規化した入力JSONと結果JSONを保存する。同一キー・同一入力は同じ結果、異なる入力は`REQUEST_CONFLICT`。
- 同時再送はDB内の同一トランザクションとロックで直列化し、投稿作成とreceipt保存を不可分にする。Storageはこのトランザクションの外側。
- 戻り値対象が削除済みでも保存済み結果JSONを返して再生成しない。成功応答は投稿が現在も存在することを保証しない。別ownerのreceiptは取得不可。匿名呼出不可。
- 新規作成時はStorage管理行のbucket、本人path、owner_id、MIME、サイズを検証する。SQL RPCはオブジェクトストアのバイト実体を直接検証できない。再送時はreceiptを先に照合し、Storageオブジェクトが後に削除されても同じ結果を返す。
- 旧RPC/Android動作は維持。migrationは追加のみ。既存RLSを緩めず、SECURITY DEFINERが必要ならsearch_path、execute権限、owner検証を別レビューする。
- toggle_likeは非冪等なので自動再送しない。応答喪失時は再取得して状態確認。AR upsert/回答upsertも古い操作が新操作を上書きしないよう対象ごとに直列化し、再送前に最新状態を確認する。

署名とエラーcodeはバックエンドの共有台帳と追加migrationを正とする。UIの二度押し禁止だけを重複対策としない。

## 8. AR・探索の受入仕様

- 既存`LOCAL_PLANE`方式を維持。現地の位置条件で解放し、そのセッション内で平面へ置く。翌日同じ物理座標への復元やAndroid/iOS間のアンカー共有は行わない。
- ARKit対応を実行時確認。horizontal/vertical平面検出、raycast、AnchorEntity、透過画像の板を利用。背景が黒くならず、縦横比・向き・単位mが一致すること。
- `get_ar_experience`、`get_nearby_ar_traces`と既存asset_pathを使う。表示時のVIEW許可はサーバーを正とする。GPSゲートは体験条件であり、偽装耐性のあるアクセス制御とは呼ばない。
- 位置accuracyは0以上25m以下、サンプル経過は0以上10秒以下。範囲内の連続する別サンプル2回で解放。未来の時刻、負精度、重複timestamp、NaNは解放に使わない。探索中は解放後に再ロックせず、AR入場時は最新位置と閲覧権限を再確認する。
- 設定範囲は解放10〜200m、発見30〜500mかつ発見≥解放、実幅0.1〜10m。既定は50m/150m/1m。クライアントと既存RPCの検証を一致させる。
- 方向は真北基準へ揃え、headingAccuracy<0を無効にする。距離帯と方向だけを表示し、正確な座標を画面・ログへ出さない。Core Hapticsは補助、非対応時は視覚案内。
- カメラ画面を終了してからARセッション開始。background/終了時pause、復帰時は必要なら再配置。中断、追跡不能、発熱、画像期限切れに再試行/戻るを提供。
- AR公開予約は投稿確認で明示的に選択し、写真/ラクガキ成功後に実行する。既存詳細からの素材選択も提供。古いAR作成仕様の「撮影直後に予約しない」記述より、現在のpost-time migration/実装を優先して整合確認する。
- 非LiDARのAR対応iPhoneで平面配置、5分連続利用、10回入退場、前景復帰、snapshot保存を実測する。ARの完了判定をSimulatorのスクリーンショットで代替しない。

[ARKit公式](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration)、[RealityKit ARView](https://developer.apple.com/documentation/realitykit/arview)

## 9. 画像・キャッシュ・費用

写真はImageIOで向き補正とdownsample後、JPEGへ再エンコード。開始値は長辺1600px・品質0.8・目標1MB以下、超過時は品質0.65まで調整し、さらに寸法を下げて再評価する。画質と実測容量をT08で確認して固定する。透過ラクガキは写真と同じ座標系のPNG。既存20MB/5MB上限を越えない。HEIC入力はJPEGに変換する。

EXIF、GPS、元ファイル名などは引き継がず、出力を検査する。プレビュー画像に元画像をBase64で抱えない。画像デコードはmain thread外、画面にはサムネイルサイズで渡す。

キャッシュキーはuserID + epoch + bucket + path + variant。signed URLはDBへ保存せず、期限より前に再取得する。403/404は権限再確認・キャッシュ失効へ、無限再試行しない。ログアウト後の古いrequest completionも破棄する。取得済みURLを他人へコピーした場合の即時失効を保証しない。

初版は既存thumbnail_pathがあれば利用し、なければ端末側縮小。サーバーサムネイル生成は別契約であり、画像転送量そのものは端末縮小で減らないことを計測に反映する。読み取り範囲、画像取得回数、送信byte数を集計し、正確な位置や個人IDを解析ログに残さない。

## 10. グループと安全機能

既存グループ契約はOWNER込み8人、OWNERから承認済み友達への招待、有効招待も定員へ算入、当日参加者スナップショット、JST日付、1人1回答、元写真の公開範囲を変更しない。グループ写真はprivacyだけでローカル除外せず、サーバーの対象写真への閲覧許可に従う。写真成功前にgroup answerを送らない。日付跨ぎはエラー表示して写真だけ残し、翌日のお題へ勝手に付け替えない。

B02で通報・ブロック・退会の不足を解消する。既存の`account_and_moderation_policy.md`は案であり、メール問い合わせだけで退会要件を満たすと解釈しない。アプリ内の削除開始、対象データ、処理状況、ブロック適用範囲、運営対応を契約として確定する。初版公開前にAppleのUGC/削除要件へ照合する。[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)、[アカウント削除](https://developer.apple.com/support/offering-account-deletion-in-your-app)

退会によるグループowner削除の既存cascadeを認識し、移譲を促すか削除を明示するかをB02のプロダクトレビューで確定する。Lunaは独自に挙動を決めない。service roleが必要な処理はサーバー側に限定。

## 11. 実施順と合格ゲート

1. Mac/Xcode/実機・API契約の準備 → ARローカル試作。G1: 非LiDAR実機で成立。
2. 認証・キャッシュ・永続キュー・描画・写真処理。G2: logout/再起動/座標変換をテストで固定。
3. 冪等化契約レビューと投稿縦断。G3: Android/iOS相互表示、応答喪失でも重複なし。
4. AR公開/探索、友達・グループ・アルバム・通知を統合。G4: 必須機能が実データで成立。
5. 安全機能・性能・アクセシビリティ・配布検証。G5: 10人向けTestFlight配布候補。

本計画は公開や本番migrationの実行指示ではない。必要な環境・契約が不足したタスクはその不足を明記し、独立したmock UIや純粋ロジックの作業だけ進める。所要日数は実機・ビルド環境とAR試作の結果が出る前に確約しない。

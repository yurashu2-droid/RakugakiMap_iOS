# iOS版 検証・Sol high / Luna maxへの引き継ぎ

作成日: 2026-09-20
状態: 計画のみ。以下のiOSファイル、scheme、scriptはこれから作成するもの。現時点でSwiftコンパイル・AR実機検証は未実施。

読む順序: [設計仕様](IOS_PORT_DESIGN.md) → [実装計画](IOS_PORT_IMPLEMENTATION_PLAN.md) → 本書。旧Expo案を実装方針として使わない。

## 1. 開始条件と担当

| 項目 | 開始時に確認する内容 | 不足時に進められるもの |
|---|---|---|
| Mac | 安定版Xcodeが動くmacOS、空き容量、Simulator | 文書、fixture、レビュー。WindowsでのiOSビルド成功を報告しない |
| iPhone | iOS 17以上、AR対応、非LiDAR機を最低1台 | SimulatorのUIとunit test。AR合格は保留 |
| 開発Supabase | migration適用状況、Authメール、private Storage | fake repositoryとローカル試験 |
| Apple開発アカウント | Team/Bundle ID/署名/配布方法 | unsigned build、可能な範囲の個人実機試験 |
| Android比較環境 | 現行APKと開発Supabase | iOS内単体試験。OS間互換性は保留 |

この計画作成時のホストはWindows。Mac/iPhoneの実機環境は確認できていない。リモートMacを使う場合も実際の端末AR検証を別に必要とする。環境がないからExpoへ戻す判断を勝手にしない。

Sol highは基盤・AR・認証・永続化・同期・契約・統合を担当。Luna maxは決まったprotocol上の画面・文言・状態表示・UI検証を担当。モデル名は実行時の利用可能一覧に照合する。

プロジェクトが未コミット変更を多く含むため、開始前に基準スナップショットを確認する。HEADだけのworktreeへ移ると、未コミットのAR/グループ実装・本計画を含まない可能性がある。必要な作業ツリーを選別して移すか、共有作業ツリーの新iOSフォルダで進める。ユーザー作業を勝手にcommit/破棄しない。

## 2. ディレクトリ・編集範囲の表記

実装計画の新規パスは、特記なければ`MapGrapherClient/MapGrapherIOS/`からの相対パス。`Infrastructure`、`Features`、`App`、`Resources`、`DesignSystem`はアプリ側の`MapGrapherIOS/`内。

Coreの実装は`Packages/MapGrapherCore/Sources/MapGrapherCore/`、Coreテストは`Packages/MapGrapherCore/Tests/MapGrapherCoreTests/`。iOSテストはルートの`MapGrapherIOSTests/`、UIテストは`MapGrapherIOSUITests/`。

任意のタスクで触らない共通範囲: Android実装、`MapGrapherBackend_old`、本番環境、秘密情報、既存migrationの履歴。Backend変更はB01/B02に限り、レビュー承認後だけ。

## 3. 再利用する契約のチェック表

下表は機能の対応を示す。引数名・返却shapeの正本は共有台帳/最新SQLで、T03が`docs/API_PARITY.md`へ固定する。SQLとDTOの不一致は黙ってUI側で吸収しない。

| 分野 | 既存入口 | 実装担当 |
|---|---|---|
| Auth | Supabase Auth SDK、profiles REST | T04 |
| 写真検索/設定/削除 | nearby_photos、photo_permissions、update_photo_settings、delete_photo | L02/T14（写真更新adapterはT14統合時に追加） |
| 写真作成 | create_photo_pin → 承認後create_photo_pin_v2 | B01/T11 |
| ラクガキ作成 | create_rakugaki → 承認後create_rakugaki_v2 | B01/T11 |
| 履歴/承認 | history_rakugakis、pending_rakugakis、approve_rakugaki | T14/L04 |
| AR | get_ar_experience、get_nearby_ar_traces、create_ar_experience | T13 |
| 友達 | request_friend、pending_friend_requests、accepted_friends、respond_friend_request、remove_friend、accepted_friend_ids | T14/L04 |
| いいね | toggle_like | T14、L02の詳細UIへ接続 |
| アルバム | albums、album_photosの既存REST/policy | T14/L04 |
| グループ管理 | create_group、update_group、list_my_group_summaries、get_group_members、leave_group、remove_group_member、transfer_group_ownership、archive_group | T16/L05 |
| グループ招待 | invite_group_member、cancel_group_invitation、list_my_group_invitations、respond_group_invitation | T16/L05 |
| ミッション | reassign_group_mission_setter、set_group_mission_prompt、get_group_mission_status、submit_group_answer、withdraw_group_answer | T16/L05 |
| 通知 | list_notifications、mark_notification_read | T16/L05 |
| Storage | uploadObject/createSignedUrl相当。既存photos/rakugakis/avatars | T05/T11/T14 |
| 通報/ブロック/退会 | 実装有無の棚卸し後にB02で承認・固定 | B02/T18/L06 |

ARの半径・実幅・承認済み条件は設計書に固定。グループ最大8人、招待/当日参加者/JST日付は`GROUP_FEATURE_LUNAMAX_IMPLEMENTATION_SPEC.md`を参照する。ただし古い「実装前」の状態ラベルより現行SQL/実装結果を優先する。

## 4. 検証コマンド

以下はMacのzsh/bashで、リポジトリルートから実行する。T00でschemeとtest targetをこの名前に揃える。SimulatorのUDIDは`xcrun simctl list devices available`から実在値を設定し、文書中に固定機種名を仮定しない。

### C0: Core

```bash
swift test --package-path MapGrapherClient/MapGrapherIOS/Packages/MapGrapherCore
```

例: 特定の判定だけ確認する場合。

```bash
swift test --package-path MapGrapherClient/MapGrapherIOS/Packages/MapGrapherCore --filter RevealGateTests
```

### C1: iOS unit test

事前に`IOS_SIMULATOR_ID`を環境へ設定する。下記の`${...:?}`は未設定なら処理を止めるための構文。

```bash
xcodebuild test \
  -project MapGrapherClient/MapGrapherIOS/MapGrapherIOS.xcodeproj \
  -scheme MapGrapherIOS \
  -destination "platform=iOS Simulator,id=${IOS_SIMULATOR_ID:?SimulatorのUDIDを設定}" \
  -only-testing:MapGrapherIOSTests \
  CODE_SIGNING_ALLOWED=NO
```

1クラスだけなら`-only-testing:MapGrapherIOSTests/SessionControllerTests`などへ変更。全体検証では限定指定を元へ戻す。

### C2: UI test

```bash
xcodebuild test \
  -project MapGrapherClient/MapGrapherIOS/MapGrapherIOS.xcodeproj \
  -scheme MapGrapherIOS \
  -destination "platform=iOS Simulator,id=${IOS_SIMULATOR_ID:?SimulatorのUDIDを設定}" \
  -only-testing:MapGrapherIOSUITests \
  CODE_SIGNING_ALLOWED=NO
```

UIテストは`--ui-testing`で合成データを注入し、実際の開発ユーザーや本番データを削除しない。実API試験は別のintegration設定で行い、mock通過と区別する。

### C3: device向けcompile

```bash
xcodebuild build \
  -project MapGrapherClient/MapGrapherIOS/MapGrapherIOS.xcodeproj \
  -scheme MapGrapherIOS \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
```

これは署名済みarchiveや実機インストールの成功ではない。T19で正規署名のRelease archiveと実機起動を別に確認する。署名の秘密値をコマンド引数やログに出さない。

### C4: 実機

Xcodeから指定iPhoneへ実行し、下の受入表のAR/撮影/権限/位置/中断を操作する。機種・OS・commit・結果を残す。実在位置や顔が映る動画は共有ログへ入れず、許可された試験素材を使う。

### C5: backendとAndroid回帰

現行npm scriptは`powershell`実行に依存する。Macでそのまま動くと仮定せず、既存Windows開発環境で実行するか、別タスクで移植した実行環境を使う。今回のiOS移植に便乗して全scriptを書き換えない。

```powershell
# 作業ディレクトリ: MapGrapherBackend
npm run verify:quick
npm run verify:db
npm run test:rls
npm run scan:secrets
# B01でscriptを追加した後
npm run test:submission-idempotency
```

DB検証は接続先がローカル/専用試験環境であることを秘密値を表示せず確認する。ユーザーの本番DBをresetしない。

```powershell
# 作業ディレクトリ: MapGrapherClient/MapGrapher
.\gradlew.bat testDebugUnitTest assembleDebug
```

Backend契約を変えた段階では、既存Androidを使った主要書込/読取も確認する。ビルド成功だけでAPI互換とはしない。

## 5. 実行用scriptの仕様

T00で作る`verify-ios.sh`は`core`/`unit`/`ui`/`build`/`all`の引数を受ける。上のコマンドを実行し、未設定環境変数や失敗終了を握り潰さない。

```bash
bash MapGrapherClient/MapGrapherIOS/scripts/verify-ios.sh core
bash MapGrapherClient/MapGrapherIOS/scripts/verify-ios.sh unit
bash MapGrapherClient/MapGrapherIOS/scripts/verify-ios.sh all
```

xcresult保存先は実行ごとに別ディレクトリ。`xcodebuild ... | tee`を使う場合はpipefailで元の終了コードを保持。端末ログにtoken/URL query/位置を含めない。環境別xcconfigの私的ファイルはgitignore、exampleはキー名と無効な例だけ。

## 6. 受入マトリクス

全行について期待どおりならPASS、実行していなければNOT RUN、問題があればFAIL。証拠のないPASSは禁止。

| ID | 操作・障害 | 合格条件 | 担当 |
|---|---|---|---|
| V01 | 登録、確認リンク、cold start、期限切れ | 正しい認証状態へ戻り、再ログイン無限ループなし | T04/L01 |
| V02 | Aで画像取得中にlogout、Bでlogin | Aの画像・下書き・完了通知をBに表示しない | T04/T05/T06 |
| V03 | 写真DB成功直後の応答消失 | 同一操作の再開後も写真1件、同じid | B01/T11 |
| V04 | ラクガキだけ失敗、再起動 | 写真を再作成せず描画→ARへ続行 | T11/T13 |
| V05 | 書込中cancel、logout、force quit | 他人として続行しない。成功済みサーバー処理を未送信と誤認しない | T11 |
| V06 | private/友達/ANYONE、未承認画像 | owner/author/友達/非友達/未認証の各取得が契約どおり | T03/T05/T14 |
| V07 | friend解除、privacy変更、画像期限切れ | 再認可して失効。古いURLを永久利用しない | T05/L02 |
| V08 | 回転HEIC、巨大写真、低容量 | 正方向・縮小・metadataなし。下書きを黙って消さない | T08 |
| V09 | zoom/panしながら描画、erase、Undo/Redo | 筆跡が画像座標と一致、透明出力、同じseed | T09/L03 |
| V10 | 地図検索A/Bの応答順逆転 | 最新検索結果だけ表示、範囲外データを無差別削除しない | L02 |
| V11 | accuracy26m、古い/未来位置、同timestamp連打 | ARを解放しない、位置状態を説明 | T07/T13 |
| V12 | 非LiDARで水平/垂直面へ配置 | 透明画像が面に留まる。1m/縦横比が正常 | T02/T13 |
| V13 | AR5分、10回入退場、電話相当中断/復帰 | カメラ競合・クラッシュなし、必要時再配置案内 | T02/T13 |
| V14 | AR snapshot保存拒否/許可 | 拒否してもアプリ利用可能、許可時に保存成功 | T08/T13 |
| V15 | Android作成→iOS閲覧/承認/AR、逆方向 | 素材・状態・サイズ・権限が一致 | T13/T19 |
| V16 | group定員8、招待競合、当日途中加入 | server判定に一致、翌日回答案内 | T16/L05 |
| V17 | 23:59回答準備→0:00後送信 | 当日終了の理由表示、写真保持、翌日付替えなし | T16 |
| V18 | group owner移譲/退出/archive | 権限・snapshot・関連表示が契約どおり | T16/L05 |
| V19 | album refresh/削除、プロフィール統計 | リンク消失なし、集計範囲が正しく未取得を0扱いしない | T14/L04 |
| V20 | 通報→運営受付、block→相手表示 | APIと運用の両方で成立。AR/通知からの迂回も確認 | B02/T18/L06 |
| V21 | 退会開始、途中障害、再起動 | 状態照会可能、対象データ削除とownerグループの説明が一致 | B02/T18 |
| V22 | Dark/Dynamic Type最大/VoiceOver/Reduce Motion | 読めて操作可能、重要ラベル欠落なし | Luna/T19 |
| V23 | 合成500ピン、20下書き、描画/AR反復 | クラッシュなし、メモリ/通信の実測と改善記録 | T19 |
| V24 | DebugとReleaseの設定、権限、署名 | 本番値取り違えなし、Release実機起動、秘密混入なし | T19 |

性能の開始目標は、テスト端末で地図/一覧操作中の継続した引っ掛かりをなくし、ARは安定追跡中30fps以上を目指す。数値は製品保証ではなくT02/T19の観測基準。OS/端末/温度/描画数を併記し、未測定値を記入しない。

## 7. Sol highへ渡す実行依頼

```text
MapGrapherのiOSブラッシュアップ移植を担当してください。
モデルはSol、reasoning high。

まず次の3文書とAGENTS.mdを読んでください。
- docs/IOS_PORT_DESIGN.md
- docs/IOS_PORT_IMPLEMENTATION_PLAN.md
- docs/IOS_PORT_VALIDATION_HANDOFF.md

ARは最初から必須です。SwiftUI + ARKit/RealityKitで、既存Supabaseを継続します。
最初の実行範囲はT00→T01→T02（AR実機ゲート）とT03です。
新規MapGrapherClient/MapGrapherIOS配下と、その実施記録だけを編集してください。
Android、本番、旧Spring Boot、既存migrationは変更しないでください。

Mac/非LiDAR AR対応iPhone/開発Supabaseの準備状況を確認し、実行できない検証は
NOT RUNとして明示してください。Windowsでコードを書けたことをiOS動作確認済みと
報告しないでください。ビルド可能性とAR実機成立を先に確認してください。

Coreの公開型とAPI_PARITYを固定し、Lunaが使うprotocol/fixture/担当ファイルを
具体的に引き継いでください。backend変更はB01/B02のレビュー承認後だけです。
未コミットの他担当作業を戻さず、依存タスクを飛ばさないでください。

完了条件: T00〜T03の指定成果物、C0〜C4の実施結果、AR合否、API対応表、
変更ファイルとcommit、未実施項目、次に実行可能なタスクを提示してください。
他タスクへ実装を依頼する場合は範囲・禁止範囲・完了条件・検証コマンドを添えてください。
```

T02のG1通過後は計画のSol担当タスクを順に割り当てる。全文を渡して「全部適当に実装」と依頼しない。T04〜T19も1つの意味ある成果単位で検証・レビューする。

## 8. Luna maxへ渡す最初の実行依頼

```text
MapGrapher iOS版のL01（デザイン基盤・ナビゲーション・認証画面）を担当してください。
モデルはLuna、reasoning max。

AGENTS.md、docs/IOS_PORT_DESIGN.md、docs/IOS_PORT_IMPLEMENTATION_PLAN.md、
docs/IOS_PORT_VALIDATION_HANDOFF.mdと、SolのT01公開型/完了報告を読んでください。
SwiftUI、日本語、iOS 17以上、4タブ、ポップなノートのブランドです。

編集可能なのはL01に列挙されたDesignSystem/画面/route/Resources/UIテスト。
SessionController、AppContainer、Xcode project、Core公開型、SDK adapter、
DB/RLS/RPC、Android実装、本番設定は変更しないでください。

まずfake sessionで状態表示と遷移を完成させてください。
T04が未完成なら独自の認証処理を作らず、mock確認と実認証確認を区別してください。
必要なprotocol変更とproject登録はSolへ依頼してください。
Localizable.xcstringsを他担当と同時編集しないでください。

完了条件: L01指定画面・色・状態UI、Dynamic Type/Dark/VoiceOver対応、
C2 AuthUITestsとC3の結果。Macがなければ未実施を明記し完了扱いしない。
変更ファイル、使ったprotocol、画面証拠、未確認事項を報告してください。
```

L02/L03/L04/L05/L06を割り当てるときは、この依頼のタスク名・許可ファイル・先行条件・対象テストを該当節へ差し替える。担当が別の型を作らないようSolが確定したAPI_PARITYとcommitを必ず添える。

## 9. 報告テンプレート

```text
タスクID / 担当モデル・reasoning:
基準commit / 完了commit:
変更したファイル:
実装した利用者の操作:
使用・変更したprotocol（変更なしも明記）:
検証command / exit code:
Mac・Simulator・実機の機種/OS:
受入IDごとのPASS / FAIL / NOT RUN:
秘密情報を含まない証拠の保存先:
未実施と理由:
他担当の変更との競合:
次の担当と開始可能タスク:
```

「動くはず」「ビルドは後で」「UIができたので認証も完了」は完了報告として受け入れない。テストコードと実行結果を分け、利用者の操作が成立するかをレビューする。

## 10. 配布前にユーザーと確定する事項

計画はこれらの回答を待たず作成できるが、該当実装/公開工程では確定が必要。

- Mac/iPhoneとApple開発アカウント、配布用Bundle ID、署名の管理者。
- iOS 17以上・独自3Dマップ後続・4タブ・投稿初期値ONLY_MEという提案の採否。
- 通報/ブロック/退会の挙動と運営窓口。特にグループowner退会の扱い。
- 開発/本番Supabase、SMTP、認証redirect、公開support/privacy URL。
- TestFlightの招待対象と、配布・本番変更を実際に行うタイミング。

実装着手前に設計書をレビューし、採否が変わった項目はタスクと受入表を同時に更新する。ユーザーの今回の依頼を、ストア公開や本番DB操作の許可と解釈しない。

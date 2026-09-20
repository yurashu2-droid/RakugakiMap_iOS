# MapGrapher リファクタリング調査

調査日: 2026-09-12  
対象: 未コミット変更を含む現在のAndroid実装、新Supabase実装、設計資料、既存テスト。旧Spring Bootは移植元として扱わない。  
状態: **設計提案。実装・DB/RLS/API契約は変更していない。**

## 結論

優先すべきなのは、認証・投稿同期・ローカルデータの管理を一箇所に集め、画面をそれらから切り離すこと。現状は見通しの問題だけでなく、ログアウト処理の不整合や、再送・キャッシュ更新の欠落につながっている。

この規模と既存構成には、**実用的なレイヤードアーキテクチャ、MVVMと単方向データフロー、機能ごとの責務分離、アカウント別の永続投稿キュー**が適していると判断する。既存の `domain_design_guidelines.md` の依存方向を、実装へ段階的に反映する方針である。

「唯一最適な設計」を一般論で決めるのではなく、投稿を失わないこと、他アカウントと混ぜないこと、公開範囲を守ること、少人数で改修できることを評価基準にする。

Android公式もRepositoryを介したデータアクセスと単方向データフローを推奨し、UseCase層は複雑な処理や再利用が必要な場合に導入するものとしている。単純な取得操作まで一律に層を増やす必要はない。[Android architecture recommendations](https://developer.android.com/topic/architecture/recommendations)、[Domain layer](https://developer.android.com/topic/architecture/domain-layer)

## 調査方法と限界

- ソースの呼び出し元・保存先・再送条件・例外処理を追跡した。
- `shared_interface_registry.md`、`domain_design_guidelines.md`、既存migrationを確認した。
- `.\gradlew.bat testDebugUnitTest` を今回実行し成功。5スイート、14テスト、失敗・エラー・スキップは0。
- 14テストのうち13件はAR距離・方向・振動・解放判定、1件はテンプレートの加算テスト。認証・同期・Repository・Room migrationのテストは今回の対象ツリーに見当たらない。
- 同じ会話の直前のUI確認で、現在のコードの `assembleDebug` は成功している。今回の調査でアプリ実装は変更していない。
- アカウント切替、通信断、旧バージョンからの更新、本番DB/RLS、画像キャッシュ漏れは実機で再現していない。以下は静的に確認した実装事実と、その条件下で起こり得る問題を分けて記載する。
- 認証情報や本番データの読み取り、本番への接続・変更は行っていない。

## 優先順位

| ID | 優先度 | 対象 | 主な問題 |
|---|---|---|---|
| R1 | P1 公開前 | 認証・ログアウト | 処理が画面に分散し、プロフィール側のログアウトが未接続。token更新経路もない |
| R2 | P1 公開前 | 投稿キューの所有者 | 別アカウントの未送信写真を現在のアカウントとして送る経路がある |
| R3 | P1 公開前 | 写真・ラクガキの同期 | 再送の重複防止、途中成功後の再開、失敗時の再試行が不十分 |
| R4 | P1 公開前 | 読み取り同期・画像キャッシュ | 取得済み写真の更新・失効を反映せず、signed URLのキャッシュがアカウント非依存 |
| R5 | P1 配布前 | Roomの保存・更新 | 破壊的migration fallbackと、アルバムのREPLACEによる関連消失リスク |
| R6 | P2 継続改善 | 大きな画面・Repository | UI、通信、保存、権限表示、同期が絡み合い、変更範囲が広い |
| R7 | P2 継続改善 | モデル・型・旧引数 | ローカルIDとUUID、画像参照、同期状態が混在し、無効なAPIも残る |
| R8 | P2 継続改善 | 例外・依存注入・テスト | 失敗が空データやfalseに変わり、取消と通信失敗も区別しない |
| R9 | P2 継続改善 | 非同期画像表示 | Viewの再利用時に古い画像取得が後から表示される可能性 |

P1は公開前に修正または再現検証と対策を要する項目。P2はP1を直しながら順次整える項目である。行番号は調査時点の作業ツリーに対応する。

## R1 認証状態とログアウトを一元化する

**確認した事実**

- `ProfileActivity.kt:355` は `FROM_LOGOUT=true` を付けてMainActivityへ遷移するが、このextraを読む実装は見当たらない。プロフィール側ではtokenを消していない。
- `MainActivity.kt:226` には別の `performLogout()` があるが、ホーム自身のボタンからしか呼ばれない。
- `LoginActivity.kt:53` と `SignUpActivity.kt:66` 周辺でセッション保存処理が重複する。
- `MainActivity.kt:211` は `access_token` の有無でログインを判断し、API側は `supabase_access_token` を読む。
- `SupabaseSessionStore.kt:10` は保存済みtokenを返すだけ。refresh tokenは保存されるが、refreshの呼び出し・有効期限に応じた更新・再認証状態への遷移は見当たらない。

**影響**: プロフィールからログアウトしたつもりでもセッションが残る。token期限後もUIはログイン済みと判断し、通信だけが失敗し続ける可能性がある。Supabaseのセッションは短命のaccess tokenをrefresh tokenで更新する前提である。[Supabase sessions](https://supabase.com/docs/guides/auth/sessions)

**提案**: `AuthRepository` と `SessionManager` に保存・復元・更新・ログアウトを集約する。画面は `AuthState` を観測する。複数リクエストの同時refreshは一つにまとめ、tokenとユーザーIDを同じセッションのスナップショットとして扱う。ログアウト時の投稿キュー停止・表示キャッシュ失効も同じ入口へ接続する。チュートリアル完了やテーマ設定まで一括で消す `MyPrefs.clear()` は用途を分ける。

実際の通信実装はRetrofitによるSupabase REST/RPC呼び出しである。SDK導入自体を必須条件にせず、まず呼び出し側から認証の内部処理を隠す。

## R2 未送信投稿を作成時のアカウントに固定する

**確認した事実**

- `PhotoDao.kt:46` の未送信取得は `serverId = -1` のみで、アカウント条件がない。
- `PhotoDao.kt:42` のログアウト時削除は未送信写真を残す。
- `UploadWorker.kt:41` はその全件を送り、`PhotoRepository.kt:221` は送信時点のセッションからStorage pathと作成者を決める。保存行の作成者との一致確認がない。
- `pending_group_answers` にも作成アカウントの列がなく、`GroupAnswerSyncRepository.kt:30` は全件を再送する。

**影響**: Aで保存した未送信写真を、Bのログイン直後のWorkerがBとして投稿する経路がある。サーバー側が `auth.uid()` を正しく使っていても、Bの正規投稿として扱われるため、この取り違えをRLSだけでは防げない。

**提案**: 投稿・回答キューに作成時のSupabase UUIDを保存する。再送対象、ローカル表示、Workerをそのアカウントに限定する。ログアウトで下書きを削除せず隔離し、同じアカウントで再開できるようにする。既存データの作成者を一意に復元できない場合、現在のログインユーザーへ自動で割り当てず、隔離する移行方針が必要。

## R3 永続キューと再送可能な投稿処理を設ける

**確認した事実**

- `PhotoRepository.kt:237` は再試行のたびにStorage pathのUUIDを作り、upload、`create_photo_pin`、Room更新を順に実行する。
- `202606130001_initial_schema.sql:476` の `create_photo_pin` は呼び出しごとに新しい写真を作る。投稿リクエストを識別する固定IDがない。
- `PhotoRepository.kt:263` で写真を同期済みにした後、ラクガキを同期する。後半だけ失敗してAR公開予約がない場合、Workerの「未同期写真＋AR再送対象」という選別から外れる可能性がある。
- `PhotoRepository.kt:77` の既存写真へのラクガキ更新は、upload関数が返すサーバー識別子を保存せず、失敗時も独立したラクガキ再送キューに載せていない。
- `UploadWorker.kt:66` は失敗しても `Result.success()` を返し、地図画面で登録する15分周期に再送を依存する。一度だけのWorkerと周期Workerは別名で、画面からの直接同期もある。

**影響**: サーバー成功・応答喪失時の二重投稿、孤立したStorage画像、写真だけ送られてラクガキが未送信のまま残る状態、同じ投稿の同時送信が起こり得る。

**提案**: `PendingPost` / `PendingRakugaki` を永続キューとして扱い、端末に保存してからWorkerが送る。投稿単位の固定リクエストID、作成者UUID、工程、送信済みremote ID、再試行理由を持たせる。同じ行の処理権を排他的に取得し、即時・周期・画面操作で並行送信しない。失敗を再試行可能・再認証待ち・入力不正・権限拒否に分ける。Storage uploadとDB処理は別サービスなので、単一トランザクションで完結すると仮定せず、再開と孤立assetの回収を設計する。

写真作成RPCの冪等化は**API/DB契約の変更提案**であり、先に台帳を更新してレビューする。既存ARの `photo_id` upsertやグループ回答の `(mission_id, user_id)` upsertは、再送対策を考える際の既存の参考になる。[Android offline-first](https://developer.android.com/topic/architecture/data-layer/offline-first)

## R4 読み取り同期とキャッシュの有効範囲を明確にする

**確認した事実**

- `PhotoRepository.kt:49` は取得済み `serverId` を除外して新規分だけ保存する。同じ写真の公開設定、タイトル、いいね数、サーバーからの削除・閲覧不可化を反映する処理ではない。
- `PhotoDao.kt:30` の表示用Flowは全写真を返す。
- `SupabaseStorageUrlResolver.kt:15` のキャッシュキーはpathのみ。キャッシュ命中は認証確認より先で、有効期間は30分。ログアウトやアカウント変更時のクリア入口がない。
- `MapsActivityInitializer.kt:375` はローカル公開範囲から仮の権限を算出し、RPCで後から更新する。`else -> true` があり、`:517` では権限取得完了前でも画像読込を開始する。

**影響**: サーバーで変更した状態が古いまま見える。別アカウントから同じpathを参照すると、前のセッションで取得したURLを使う余地がある。これらはサーバーRLSの破れを実証したものではなく、端末に取得済みの情報の管理問題である。

**提案**: UUIDをキーに既存行を更新し、閲覧確認と取得範囲を管理する。近傍検索に出なかった写真を無条件に削除すると検索範囲外の写真まで失うため、クエリ範囲・ページング・個別閲覧確認を区別する。表示キャッシュと未送信投稿を分け、前者だけを安全に失効できるようにする。URL/画像キャッシュをアカウントとセッション世代に結び付け、セッション変更後に完了した古いリクエストの結果も破棄する。権限UIは「確認中・許可・拒否・取得失敗」を表す。

signed URLはアプリ側キャッシュを消せば外部コピーまで即時失効するものではない。URLの期限、CDNの保持、端末キャッシュは別問題なので、公開範囲変更時の期待を決めて検証する。[Supabase signed URLs](https://supabase.com/docs/guides/storage/serving/downloads)、[Smart CDN](https://supabase.com/docs/guides/storage/cdn/smart-cdn)

## R5 Roomの永続データ保護と安全な更新を整える

**確認した事実**

- `AppDatabase.kt:20` は `exportSchema = false`、`:125` は `fallbackToDestructiveMigration()`。
- 登録migrationは1→5と9→13で、5→9の経路がない。影響する旧版を配布したかは今回未確認。
- `AlbumRepository.kt:27` はremote albumを `localId=0` の新規Entityとして作る。`AlbumDao.kt:17` は `REPLACE`、`AlbumEntity.kt:11` はSupabase IDがuniqueで、関連表には削除cascadeがある。

**影響**: migration経路がない版から更新すると未送信写真まで失う。アルバム再取得では既存行が置換され、ローカルIDと関連写真リンクを失う可能性がある。SQLiteのREPLACEは競合行を削除してから挿入する動作で、単純なUPDATEとは異なる。[Room migration](https://developer.android.com/training/data-storage/room/migrating-db-versions)、[SQLite ON CONFLICT](https://www.sqlite.org/lang_conflict.html)

**提案**: 配布対象の旧schemaを確定し、未送信データを残すmigrationとテストを追加する。releaseでは下書きDBに破壊的fallbackを適用しない。アルバム更新はremote UUIDで既存local IDを引き当て、同じIDを維持した更新をトランザクションで行う。単に `@Upsert` に置き換えてlocalId=0を渡すだけで済むとは判断しない。

## R6 機能の責務を分離して画面を小さくする

確認したファイルの物理行数は `MapsActivityInitializer.kt` が799行、`ProfileActivity.kt` が758行、`PhotoRepository.kt` が457行。行数だけでなく、変更理由が複数ある点が問題である。

- 地図initializer: UI設定、Worker登録、検索結果の絞り込み、権限RPC、いいね、削除、AR導線、ダイアログが混在。
- プロフィール: 表示、Authの後処理、アバターupload、プロフィール更新、友達RPC、アルバム、実績、adapterが同居。画面がSupabase DTOとRoomの両方を扱う。
- PhotoRepository: 写真取得・保存・同期に加え、ラクガキ承認・履歴、友達ID、画像加工、AR公開を扱う。関係の薄い変更にも影響が広がる。

**提案**: `ProfileViewModel`、`MapViewModel`、必要なら `PhotoDetailViewModel` を設け、UI状態を `StateFlow` で公開する。RepositoryはAuth/Profile、Photo、Rakugaki、Social、Groupなど実際の変更単位で分ける。複数Repositoryをまたぐ投稿・退会・同期などに限ってUseCase/Coordinatorを置く。地図SDKやカメラ・ARのライフサイクル操作はUI側のcontrollerへ残し、Activity参照をViewModelへ移さない。

既存の `ArViewerViewModel` / `ArTraceExplorerViewModel` の状態表現、`ArProximityGate` / `TraceUnlockGate` の純粋な判定処理は、他機能を整える際の良い出発点になる。例外取消の改善余地はあるため、そのまま全面コピーはしない。

## R7 ID・画像参照・状態を型で区別する

`PhotoEntity.kt` の `Photo` はRoom保存、UI表示、送信待ち状態を兼ねる。`id`、`serverId`、`supabaseId` が併存し、`photoUri` は端末URIとStorage pathの両方を表す。`privacy` や同期状態も文字列である。

`SupabasePhotoMapper.kt:29` はUUIDの上位部分をLongへ縮める。実際の衝突は今回確認していないが、同一性の判定を縮約IDへ寄せる必然性はない。`PhotoRepository.kt:198` には常にfalseを返す旧承認メソッドが残り、`MainViewModel.kt:47` には旧通信由来のMultipartBody/RequestBody引数が残る。

**提案**: remote IDはUUID、local row IDはLong、RecyclerView等の表示補助IDは別用途にする。`StoragePath` と `LocalImageUri`、公開範囲・承認状態・同期状態を区別する。Entityと表示モデルの分離は責務が混ざった部分から進める。旧メソッドは参照を確認して削除し、未実装の互換APIを残さない。既存DB値・DTO名・公開範囲の意味は維持する。

## R8 結果と失敗を表現し、テスト可能な依存にする

`PhotoRepository` / `AlbumRepository` は取得失敗を `emptyList()`、`emptySet()`、`false` に変える箇所が多い。たとえば「友達が0人」と「友達の取得が失敗した」を画面が区別できない。反対に `GroupDetailActivity.kt:71` は例外メッセージを直接Toastへ出す。

また、RepositoryやViewModelで `catch (Exception)` / `runCatching` を使うため、コルーチンの取消まで通常の失敗に変わる箇所がある。公式ガイドはCancellationExceptionを握りつぶさず伝播するよう求める。[Coroutine best practices](https://developer.android.com/kotlin/coroutines/coroutines-best-practices)

**提案**: データ層では `Unauthenticated`、`PermissionDenied`、`NetworkUnavailable`、`ValidationFailed`、`NotFound` など扱う必要のある失敗を型で返し、表示文言はUIで選ぶ。取消は伝播し、再試行は処理の冪等性と失敗種別に応じて決める。`SupabaseClient.api` の直接参照、Context経由のtoken読み取り、時計、Dispatcherを必要な境界で注入できるようにし、fake実装で通信断・期限切れ・切替を再現する。導入初期は手動のAppContainerで足りる。

## R9 View再利用時の非同期画像表示を安定させる

`ImageViewStorageLoader.kt:12` は呼び出しごとにlifecycleScopeでURL解決を起動するが、同じImageViewの前の処理の取消やリクエスト識別がない。空pathでplaceholder未指定の場合も前の画像を消さず戻る。

**影響**: スクロールしてViewが別の写真に再利用された後、以前のURL解決が遅れて完了すると古い画像が表示される可能性がある。

**提案**: ImageViewごとの処理識別・取消・現在のpath確認を導入するか、Coilの取得処理にStorage path解決を組み込み、一つのキャンセル可能な画像リクエストにまとめる。認証世代の変更時にも結果を破棄する。空状態では表示を明示的にクリアする。

## 到達させたい構成

| 境界 | 責務 | 守ること |
|---|---|---|
| Activity / XML / Compose | 表示、操作受付、OS権限、SDKのライフサイクル | SQL・token・RPC引数の知識を持たせない |
| ViewModel | UI状態とイベント処理 | 読み込み・成功・空・失敗・送信待ちを区別する |
| UseCase / Coordinator | 複数の責務にまたがる処理の順序 | 投稿やログアウトなど必要な処理だけに導入する |
| 機能別Repository | 取得・更新とlocal/remoteの整合 | 呼び出し元にデータの保存場所を意識させない |
| SessionManager / DataSource / Worker | 認証、通信、Room、永続再送 | アカウント分離、取消、失敗種別、依存注入 |
| Supabase Auth / RLS / RPC / Storage | 本人確認、権限、共有データの整合 | `auth.uid()`、private bucket、path保存を維持する |

画面用データの入口はRepositoryへ集約する。一方、**権限の正は常にSupabase**に置く。Roomの値やUIのowner表示をアクセス許可の根拠にしない。未送信の本人データと、サーバーから一時取得した他者データは保持方針を分ける。

## 段階別の実装案

以下は実装担当に渡せる作業範囲であり、今回実行した変更ではない。DB/RLS/RPC/DTOの変更は共有台帳へ提案し、契約レビュー後に実装する。

| 段階 | 触ってよい範囲 | 触らない範囲 | 完了条件 | 検証 |
|---|---|---|---|---|
| 1 認証の一元化 | AuthRepository、SessionStore、Login/SignUp、両ログアウト入口、認証テスト | ログイン方式、公開範囲、DB/RLSの意味 | 両入口のログアウトが同じ結果になる。期限切れ・同時refresh・アカウント切替を検証できる | Android単体テスト・assembleDebug、実機で両入口 |
| 2 所有者付き投稿キュー | Photo/Rakugaki/Group回答のlocalモデル・DAO・Worker・同期、承認済み契約に沿う新migration/RPC | 地図の見た目、AR描画、既存公開範囲 | 別アカウント送信0、同一投稿の重複0、途中成功から再開、取消時に余分な送信をしない | Android単体・Roomテスト、verify:db、test:rls、scan:secrets、assembleDebug |
| 3 キャッシュとmigration | Photo/Album同期、Room migration、URL/画像キャッシュ、関連テスト | Storage public化、公開範囲変更、既存migrationの履歴書換え | refreshで既存情報が更新される。アカウントを跨いで表示しない。旧版の下書き・関連リンクを保持する | Room migration/instrumentation、権限変更の複数アカウント確認、assembleDebug |
| 4 画面の責務分離 | Profile/MapのViewModel、Repository抽出、UI状態、adapter/controller | 新機能追加、全画面の再デザイン、認証やRPCの再変更 | 対象画面のDB/API直呼びを除き、成功・空・失敗の状態をテストできる | Android単体テスト・assembleDebug、既存主要導線の実機確認 |

コマンドはAndroidでは `MapGrapherClient/MapGrapher`、Backendでは `MapGrapherBackend` で実行する。

```powershell
.\gradlew.bat testDebugUnitTest assembleDebug
# Room migration / 実機向けのテストを追加した段階で実行
.\gradlew.bat connectedDebugAndroidTest
```

```powershell
# Backend契約変更の段階で、対象を確認したローカル検証環境へ実行
npm run verify:db
npm run test:rls
npm run scan:secrets
```

サーバー成功直後に応答を失う、写真成功後にラクガキだけ失敗する、再送中にログアウトする、別アカウントで再ログインする、公開範囲や友達関係を変更する、旧schemaからアップデートする、というシナリオを受入条件に含める。メソッド名をなぞるだけのテストは増やさない。

## 維持する設計と別途判断が必要な事項

- Supabase、RLS、RPC、private Storageの方針は維持する。巨大なSQLファイルという理由だけで既存migrationを分割・書き換えない。変更は追加migrationと権限回帰テストで追跡する。
- XML画面はViewModel化と責務分離を進められる。全面Compose移行やGradleの大量モジュール化は今回の第一目標にしない。
- 関数ごとのUseCase、共通BaseRepository、全面的な汎用化、DIライブラリの導入だけを成果にしない。
- 認証の `@mapgrapher.local` への疑似メール変換は、本人確認・パスワード復旧の方式と一緒に決める**仕様課題**。単なるファイル整理で解決した扱いにしない。
- 退会・通報・ブロック、本番設定、対象API更新は公開要件の作業であり、リファクタリングだけでは完了しない。
- build時にはAGP 8.6.0とcompileSdk 36の組み合わせに警告が出た。構造改善とツールチェーン更新は検証範囲を分けて進める。

最初の実装単位はR1の認証・ログアウト統一。その後R2/R3の投稿キューを整え、R4/R5のデータ保護を確認してから、大きな画面を機能単位で移す。

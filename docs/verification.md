# 実施記録

## 2026-09-20 初期基盤

- ユーザー指定の空リポジトリを専用ディレクトリへclone。開発ブランチ: codex/ios-foundation。
- Ruling: モノレポ内配置ではなく、このリポジトリのルートをiOSルートとする。Android/Backendの作業ツリーは移動しない。
- Ruling: WindowsとCIで同じXcode構成を生成できるようproject.ymlを正本とし、XcodeGenを採用する。生成projectは追跡せず、CI生成・ビルドで検証する。
- 実装担当: Sol highはCoreの失敗テスト先行、Luna maxはshellのUIテスト先行。親はCIと統合を担当。
- ローカルにSwift/Xcodeなし。CIと実機の結果は取得後に記録し、未実施を成功扱いしない。
- AR実機、Supabase通信、署名、配布は未実施。
- Core RED確認: [run 35513476330](https://github.com/yurashu2-droid/RakugakiMap_iOS/actions/runs/35513476330)。Xcode 16.4 / Swift 6.1.2で未実装のGeoPoint等が見つからず失敗。最初のrun 35513457773は後続pushによりキャンセルされ、判定には使わない。
- UIは起動だけ可能な空画面から先行テストを実行し、4タブ不足を確認してから実装する。
- 静的レビューで位置ゲートの2点を検出: 無効値後に過去サンプルを再利用できること、長い中断前のサンプルを2回目へ加算できること。回帰テスト→CIで失敗→修正→再レビューの順で処理する。
- Ruling: 解放時に2つとも10秒以内のサンプルを要求する。中断後の新しい有効サンプルは新しい連続列の1つ目とする。単なる「入力時に新鮮」の解釈だと古い位置で解放するため。
- Ruling: Supabase SDK追加はT03のadapter着手時へ移動。初期AR試作では通信しないため、未使用のSDKと接続設定を持ち込まない。T00の全項目完了とは扱わない。
- T01は現在、座標・enum・セッション値・位置ゲート・遷移表まで。Photo、ArExperience、PendingSubmissionとPortsの残りを完了したとは扱わない。
- run 35513661831: XcodeGen生成・署名なしdevice build成功。unit段階でUI test targetのSwift 6隔離違反（同期setUpWithErrorからMainActor操作）を検出。UIテスト実行前の失敗でありUIのRED確認には数えない。起動helperの隔離を修正して再実行する。
- CI設定は別担当の静的レビュー承認済み。Simulator runtimeはXcode 16.4に合わせ18.5へ固定。既知の秘密値・精密座標パターン検査は該当なし。
- run 35514124788: Core 20件のうち位置ゲートの追加回帰2件で計3assert失敗、他は成功。UIはsuper.setUpのSwift 6非Sendableエラーで未実行。起動処理を各MainActorテストから呼ぶ同期helperへ移動した。
- [run 35514451027](https://github.com/yurashu2-droid/RakugakiMap_iOS/actions/runs/35514451027): ARPlaneGeometry未実装のRED確認。UIは3件を実行し、空画面のscreen.map/tab.groups不足で期待通り3件失敗。T01残りのドメイン型も未定義のRED確認済み。
- T01実装の静的レビューで登録工程からuploadへ戻れる進行コピーを検出し、回帰テストを追加してCIのRED確認へ送付した。
- ユーザー回答: iPhoneあり、Macなし、Apple Developer Program未加入、iLoaderで導入する。Ruling: 現段階の実機導入はTestFlightではなく、検証成功後の署名前IPAをArtifactsへ出し、本人のiLoaderで署名する。Appleへのuploadはしない。
- run 35514864399: Core 37件中、登録工程からuploadへ戻る追加回帰1件で2assert失敗。進行コピーにも工程後退禁止を適用した。
- [run 35515352880](https://github.com/yurashu2-droid/RakugakiMap_iOS/actions/runs/35515352880): Core 37件成功。iOSはAppIcon asset不足でdevice build失敗、unit/UI/IPAは未実行。アイコン不足を修正する。
- 統合レビューで写真共有の保存経路に必要な用途説明と、snapshot完了時の退出・停止判定不足を検出。写真追加の日本語説明と撮影要求の無効化を修正する。実機での撮影中退出・連打も確認対象に加える。
- c1c7bb3の撮影取消し・用途説明の修正は静的再レビュー承認。run 35515657934ではAppIcon不足は解消し、続いてRealityKitのfaceCullingがiOS 18以降であるためコンパイル失敗。7270be4でavailability guardを適用した。
- [run 35515877735](https://github.com/yurashu2-droid/RakugakiMap_iOS/actions/runs/35515877735): Core 37件、実機向けunsigned build、Simulator unit 8件、AR画面へのUI遷移1件成功。タブUI 2件は独自identifierが見つからず失敗。exportしたUI hierarchyでは4タブの日本語ラベルと選択状態を確認でき、独自identifierがUITabBarButtonへ伝播しないことを確認。b874aabで標準タブの日本語ラベルを使う検証へ変更し、タブ数・画面ID・選択状態の確認を維持した。契約変更はUI_TEST_CONTRACT.mdへ記録した。

## 初回実機用IPAの検証結果

- ソース: `b874aabdc036681ca2a43947914aa735d67e5fc2`。後続の記録文書更新はこのIPAに含まれない。
- [run 35516367757](https://github.com/yurashu2-droid/RakugakiMap_iOS/actions/runs/35516367757)は全ジョブ成功。Core 37件、Simulator unit 8件、UI 3件（計48件）成功。Debugのunsigned device build、Release archive、IPA作成も成功。
- Xcode 16.4 / Swift 6 / iOS 18.5 Simulator。iOS 17 deployment targetでコンパイル済みだが、iOS 17での実機実行を認定するものではない。
- 起動画面のスクリーンショットを目視確認。日本語4タブ、試作表示、AR動作確認ボタンに文字欠けや重なりなし。全画面・全端末・Dynamic Typeの網羅検証ではない。
- [IPA artifact](https://github.com/yurashu2-droid/RakugakiMap_iOS/actions/runs/35516367757/artifacts/10606884052)をWindowsへ取得し、ZIP整合性と同梱SHA256の一致を確認。`Payload/MapGrapherIOS.app`、arm64 Mach-O、iPhoneOS、最小OS 17.0、日本語Camera/PhotoLibraryAdd用途説明を確認。embedded provisioning profileなし、署名はiLoader側で行う。
- IPA SHA256: `a616dec280a93a1fbb88992ad7c27d8909e407b1d5af6b03886845913276d1f6`。
- 現在の成果はCore型・ルールとPorts、4タブの試作、ローカルAR試作、CI/IPA生成。T00のSupabase SDKはT03へ繰越、T01の公開型実装済み、T02はG1実機待ち。T03以降のSupabase adapter、認証、地図データ、投稿などは未実装。
- iLoader導入、iPhoneでの起動、AR実機、G1は未確認。AR_PROBE.mdの実測記録が揃うまでAR成立・移植完了とは扱わない。

## 2026-09-21 iPhoneでの追加確認（ユーザー報告）

- 検証用Supabaseの確認済みテストアカウントでログイン成功。
- 写真撮影とラクガキ操作は成功。投稿は完了できず、地図に現在地は表示されなかった。投稿時の具体的な画面状態とエラーは未確認。
- 実機で確認した導入版は地図の現在地マーカーを非表示にしていた。投稿には位置座標が必須で、取得失敗時は投稿ボタンが無効になる。実機症状との因果関係は追加確認が必要。

## 2026-09-21 起動時の位置許可と現在地表示

- 初回起動時に位置情報の「使用中」許可を要求し、地図の現在地マーカーを表示する変更を追加した。拒否済みの場合は再要求せず、既存の拒否表示を使う。
- CIでのコンパイルとiPhoneでの許可ダイアログ・現在地表示・投稿の再確認は未実施。

## 2026-09-21 Android地図マーカーのiOS移植

- Androidの`image2.png`の2コマを現在地プレイヤーとして使い、`pin_rakugaki.png`を写真投稿ピンの枠として使う。画像はAndroidからそのまま複製した。
- 投稿ピン内の写真は、認証済みセッションでprivate Storageのsigned URL経由から縮小読込する。再利用時は前の読込を取り消す。
- iOS SimulatorのUIテストでは実端末の位置許可を要求しないよう、テスト用地図の現在地表示をオフにする。
- CIとiPhone実機での見た目・位置・アニメーションの確認は未実施。

## 2026-09-21 地図カメラと方位追従

- [run 35538439449](https://github.com/yurashu2-droid/RakugakiMap_iOS/actions/runs/35538439449)で前回の現在地表示・Androidマーカー移植はCore、iOS unit/UI、unsigned IPAの全ジョブ成功。iPhone上での見た目と位置許可ダイアログは未確認。
- 地図カメラの初期pitchを45度、北向き、中心からの距離を1,000mに変更。位置取得後はMapKitの方位追従を自動開始する。
- 地図右下に現在地ボタンを追加。手動移動で追従が解除された後、現在地と端末の向きへの追従を再開できる。
- 方位変化による細かなカメラ移動で近傍写真を再検索し続けないよう、前回通知位置から75m未満の中心移動は検索対象から外す。
- 新しい変更のCIとiPhone実機での傾き・位置・方位追従は未確認。

## 2026-09-21 写真詳細のラクガキ表示と地図ピン比率

- 写真詳細で既存の`history_rakugakis` RPCから承認済みラクガキを取得し、private `rakugakis` bucketのStorage pathをsigned URLで読み込む。写真と透明PNGを同じ画像座標で重ねる。未承認・別写真の行は表示しない。
- 画像や履歴の取得に失敗した場合は「ラクガキなし」と区別し、再読込を出す。追加ラクガキ画面から戻った時と画面の引き下げ操作で再取得する。
- Androidのピン画像は458×710px。iOSの60×70ptへの引き伸ばしをやめ、60×93ptで比率を保つ。円窓と座標を指す先端の位置も調整する。
- [run 35542114167](https://github.com/yurashu2-droid/RakugakiMap_iOS/actions/runs/35542114167)でCore、署名なしiOSビルド、unit/UIテスト、IPA生成の全ジョブ成功。新規の透明PNG合成テストと承認済み履歴のStorage pathテストも通過。IPAのcommit.txtは`3006a77`と一致し、SHA-256を照合した。iPhone実機での合成位置・ピン外観は未確認。

## 2026-09-21 AR付き投稿の一括送信

- 投稿画面のARスイッチで、写真・本人のラクガキ・AR公開を1回の操作で永続キューへ登録する。ARは写真とラクガキの登録完了後、解放50m・発見150m・表示幅1mの既定値で公開する。
- 後続のラクガキとAR操作は依存先を固定した待機状態で保存し、アプリ再起動後のキュー再開でも残らないようにする。投稿結果はAR公開が完了するまで完了扱いにしない。
- [run 35543019152](https://github.com/yurashu2-droid/RakugakiMap_iOS/actions/runs/35543019152)で実装前の新規テストが`invalidDraft`で失敗することを確認。[run 35543843787](https://github.com/yurashu2-droid/RakugakiMap_iOS/actions/runs/35543843787)でCore、署名なしiOSビルド、unit/UIテスト、IPA生成の全ジョブ成功。IPAのcommit.txtは`42981b9`と一致し、SHA-256を照合した。iPhone実機での投稿・現地AR表示は未確認。

## 2026-09-21 通常投稿の回帰修正・航空写真・対象写真の現地AR

- 前回の一括送信は後続ラクガキを`.queued`として挿入したが、実機の`CoreDataSubmissionStore.insertDraft`は`.draft`以外を拒否していた。既存の簡易テスト保存層は受け付けたため、CIで見逃した。写真と依存関係のある後続行のみ、所有者と初期状態を確認して保存できるようにし、SQLite再オープンの回帰テストを追加した。
- 地図右下の切り替えから標準地図と航空写真を選べる。両方とも対応地域ではMapKitのrealistic elevationを使い、現在のカメラ位置・45度の傾き・方位追従を維持する。
- 写真詳細のARボタンはその写真のAR公開情報を読み込み、現地の位置検証と平面検出・透過ラクガキ配置画面へ直接進む。未公開・閲覧不可の場合はエラーを表示する。近くのAR一覧から探す既存導線も継続する。
- [run 35556617303](https://github.com/yurashu2-droid/RakugakiMap_iOS/actions/runs/35556617303)でCore、署名なしiOSビルド、Core Data保存を使う通常ラクガキ投稿のunitテスト、地図切り替えを含むUIテスト、IPA生成がすべて成功。IPA内のcommit.txtは`a455cc5`と一致し、SHA-256を照合した。iPhone実機での通常投稿・航空写真表示・現地ARの平面検出は未確認。

## 2026-09-21 現地ARの測位待ち修正

- 実機ではAR解放に必要な2回の測位に対して位置更新の`distanceFilter`が5mだったため、同じ場所で構えると2回目が届かず「現地で位置を確認しています」のまま停止していた。AR表示中は移動距離による間引きを無効にし、自動停止もしない。
- 正確な位置情報が無効なら測位通知を待たず設定案内を表示する。15秒以内に2回目を取得できなければ専用エラーと「位置情報を再確認」ボタンを出し、無限待ちを避ける。2回の異なる正確な測位を必要とする解放条件は維持する。
- [run 35558814715](https://github.com/yurashu2-droid/RakugakiMap_iOS/actions/runs/35558814715)で、タイムアウト専用状態が終了済み測位ストリームの汎用エラーで上書きされる競合を新規unitテストが検出した。
- 競合修正後の[run 35559570870](https://github.com/yurashu2-droid/RakugakiMap_iOS/actions/runs/35559570870)でCore、署名なしiOSビルド、AR測位のunitテスト、既存UIテスト、IPA生成がすべて成功。IPA内のcommit.txtは`8489009`と一致し、SHA-256を照合した。iPhone実機での現地AR再確認は未実施。

## 2026-09-21 永続AR配置・公開・現地復元

- AR付き通常投稿は、写真とラクガキの登録完了後に同じ操作の流れで現地配置画面へ進む。水平・垂直面上で移動・回転・拡大縮小し、固定後の1回の公開操作でworld mapのuploadと公開RPCを完了する。途中失敗時は取得済みpackageを保持して再送でき、二重公開を防ぐ。
- `WORLD_MAP_V1`はprivate `ar-world-maps` bucketへsecure coding済み`ARWorldMap`を保存し、DBにはStorage path、名前付きアンカー、画像比率、表示幅を保存する。閲覧時はworld mapを復号して`initialWorldMap`へ設定し、指定名のアンカーをARKitが再認識した場合だけ同じtransformと大きさで表示する。25秒でタイムアウトし、古いsession結果を採用せず再試行できる。
- 従来の`LOCAL_PLANE`はworld mapを取得せず、現地で面をタップして表示する互換経路を維持した。Geo Trackingの利用可否は案内に使い、world map復元の成否とは分離した。
- [run 35576120250](https://github.com/yurashu2-droid/RakugakiMap_iOS/actions/runs/35576120250)で公開側のCore、device build、unit/UI、IPA生成がすべて成功。閲覧・復元側も[run 35578463402](https://github.com/yurashu2-droid/RakugakiMap_iOS/actions/runs/35578463402)でCore、device build、unit/UI、IPA生成がすべて成功した。
- 検証用クラウドSupabaseにはmigration `202609210004`まで適用済み。通常のiPhone接続先はクラウドを維持する。ローカルSupabaseはDB/RLS/migrationの自動検証に適する場合だけ起動し、今回のiOS閲覧実装では使用していない。
- 自動検証はデータ契約・archive検証・private Storage転送・状態遷移・タイムアウト・従来互換を対象とする。同じ物理位置への復元精度はSimulatorでは判定できないため、`docs/AR_PROBE.md`のA18〜A23は未実施。

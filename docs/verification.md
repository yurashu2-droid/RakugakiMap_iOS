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

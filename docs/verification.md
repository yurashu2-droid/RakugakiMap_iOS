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

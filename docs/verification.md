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

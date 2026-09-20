# 実施記録

## 2026-09-20 初期基盤

- ユーザー指定の空リポジトリを専用ディレクトリへclone。開発ブランチ: codex/ios-foundation。
- Ruling: モノレポ内配置ではなく、このリポジトリのルートをiOSルートとする。Android/Backendの作業ツリーは移動しない。
- Ruling: WindowsとCIで同じXcode構成を生成できるようproject.ymlを正本とし、XcodeGenを採用する。生成projectは追跡せず、CI生成・ビルドで検証する。
- 実装担当: Sol highはCoreの失敗テスト先行、Luna maxはshellのUIテスト先行。親はCIと統合を担当。
- ローカルにSwift/Xcodeなし。CIと実機の結果は取得後に記録し、未実施を成功扱いしない。
- AR実機、Supabase通信、署名、配布は未実施。

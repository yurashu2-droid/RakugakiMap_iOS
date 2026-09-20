# iOS実装ルール

- 日本語の文言・説明・コメントを基本とする。
- docs/IOS_PORT_DESIGN.md、docs/IOS_PORT_IMPLEMENTATION_PLAN.md、docs/IOS_PORT_VALIDATION_HANDOFF.mdを読む。
- このリポジトリルートが計画のMapGrapherClient/MapGrapherIOSに相当する。
- ARは初回必須。実機確認なしにAR完了と報告しない。
- Sol highは基盤・AR・契約、Luna maxは確定した契約上のUIを担当。
- Supabaseのauth.uid()、RLS、private Storage、path保存、公開範囲・承認状態を維持する。
- API契約変更と本番操作をUI実装に混ぜない。サービス用秘密鍵はアプリへ入れない。
- 既存変更を戻さない。進捗はdocs/verification.mdへ記載する。
- Xcode projectはproject.ymlからXcodeGenで生成する。生成物を手編集しない。
- バックエンド未接続の画面は試作であることを明示する。
- CIの成功と実機ARの成功を区別する。署名・公開は別工程。

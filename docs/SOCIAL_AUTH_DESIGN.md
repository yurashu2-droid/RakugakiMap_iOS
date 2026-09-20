# Google・Apple 認証と初回プロフィール

## 目的

iOS で Google および Apple のアカウントから Supabase Auth に登録・ログインできるようにする。メール登録を含め、認証済みでも `profiles` 行がない利用者は表示名と公開 ID の初回設定を終えるまで通常画面へ進めない。

## 境界

- Google は Supabase が生成する OAuth URL を `ASWebAuthenticationSession` で開く。Google の callback は Supabase の `/auth/v1/callback`、アプリへの callback は既存の `rakugakimap-dev://auth/callback` とする。Google の client secret は Supabase 側だけに保存する。
- Apple は `AuthenticationServices` のネイティブ認証で ID token を取得し、nonce とともに Supabase Auth へ渡す。Apple の署名・Capability・プロバイダー設定は Apple Developer Program の用意後に有効化する。秘密鍵をアプリや Git に含めない。
- 認証手段に関係なく Supabase の user ID を唯一の本人識別子とする。同じ確認済みメールの自動連携は Supabase Auth に任せ、アプリ側でメール文字列を根拠に別ユーザーのプロフィールを統合しない。
- `profiles` は本人の RLS 付き既存テーブルを使う。未作成のときだけ `id = auth.uid()` の行を作り、表示名は1〜64文字、公開 ID は既存 DB 制約の形式に合わせる。409 の公開 ID 重複は入力を修正して再試行できるようにする。
- プロフィール取得が失敗した場合は通常画面に入れず、再試行を提示する。ログアウト、アカウント切替、遅延した古い要求が新しいセッションの画面を開かないようにする。

## 配布と設定

検証用 Supabase で Google/Apple プロバイダーは現時点で無効。Google Cloud OAuth client の発行、Google consent screen、Supabase への client ID/secret 登録が必要。Apple の有効化には Apple Developer Program と App ID の Capability が必要。アプリの無署名 IPA だけで Apple 認証の実機成立を主張しない。

App Store 公開では Apple のログインサービス基準 4.8 を満たすよう、Google と同等の位置に Apple ログインを提供する。メール登録・再設定は残るため外部 SMTP の設定も別途必要。

## 検証

ログイン成功、キャンセル、コールバック偽装、既存メールとの連携、未作成プロフィール、重複公開 ID、通信途切れ、ログアウト中の遅延応答を確認する。CI の unit/UI、署名なし device build、設定後の実機ログインを別々に判定する。

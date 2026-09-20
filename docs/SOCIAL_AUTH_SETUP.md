# Google・Appleログインの外部設定

アプリ側の認証実装は Supabase Auth に接続する。以下の設定が完了するまでは、ボタンからのログイン成功を検証できない。秘密値は Git や IPA に入れず、各サービスの管理画面だけで扱う。

## Google

1. Google Cloud で新しいプロジェクトを作る。OAuth 同意画面のアプリ名、連絡先、必要な公開範囲を設定する。テスト状態では実機テスターを追加する。
2. OAuth クライアントを「ウェブ アプリケーション」として作る。承認済みリダイレクト URI は検証用 Supabase の `https://naaxtyjscuhufxfflbqy.supabase.co/auth/v1/callback` とする。
3. クライアント ID とシークレットを Supabase Dashboard の Authentication → Sign In / Providers → Google に登録し、有効化する。
4. Supabase Dashboard の URL Configuration でアプリへの `rakugakimap-dev://auth/callback` が Redirect URLs にあることを確認する。
5. 検証用 iPhone で Google ログイン、キャンセル、再起動後のセッション復元、初回プロフィール作成を確認する。

## Apple

1. Apple Developer Program の準備後、App ID に Sign in with Apple Capability を有効化し、署名済みアプリの Bundle ID と一致させる。Xcode プロジェクトには entitlement の宣言を含めている。
2. Supabase Dashboard の Authentication → Sign In / Providers → Apple で、ネイティブアプリの App ID を Client IDs に登録して有効化する。Web 認証も使用する場合は、Apple の Services ID・リダイレクト URL・署名キーを追加し、Supabase の手順に従う。
3. 署名済み実機ビルドで、メールを隠す選択、キャンセル、再起動後の復元、初回プロフィール作成を確認する。無署名 IPA のビルド成功だけでは Apple ログインの実機動作確認にならない。

## 公開前の確認

- Google と Apple を同等に選べる状態にし、Apple の App Review 4.8 を確認する。
- 同じ確認済みメールのアカウント連携は Supabase Auth の動作を確認し、アプリ側でメール文字列を使ってプロフィールを統合しない。
- メール登録を残す場合は外部 SMTP と差出人ドメインを別途設定する。

参考: [Google 設定](https://supabase.com/docs/guides/auth/social-login/auth-google)、[Apple 設定](https://supabase.com/docs/guides/auth/social-login/auth-apple)、[App Review 4.8](https://developer.apple.com/app-store/review/guidelines/#login-services)

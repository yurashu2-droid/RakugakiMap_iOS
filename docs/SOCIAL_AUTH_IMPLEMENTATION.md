# Google・Apple 認証の実装計画

**目的:** Supabase Auth を使い、Google と Apple の登録・ログイン、および全認証方式共通の初回プロフィール設定を提供する。

**設計:** [SOCIAL_AUTH_DESIGN.md](SOCIAL_AUTH_DESIGN.md)。既存セッション境界を維持し、Google は OAuth + `ASWebAuthenticationSession`、Apple は native ID token + nonce を使用する。認証後のプロフィール確認を通常画面より前に置く。

## 作業

1. `ProfileBootstrapService` と画面を追加する。`profiles` の本人行を読み、欠けている時は表示名と公開 ID を検証して作成する。ログアウト・通信失敗・公開 ID 重複を区別し、セッション切替時の古い結果を破棄する。unit test でゲート遷移を確認する。
2. Google OAuth の URL 生成と iOS ブラウザ認証を追加する。既存の許可済み callback を使用し、URL と code を検証して Supabase session を確立する。キャンセルを正常な中断として扱い、認証エラーを画面へ示す。CI で unsigned device build と関連 unit/UI test を実行する。
3. Apple native sign-in を追加する。ランダム nonce を生成し、Apple にハッシュを渡し、Supabase には元値を渡す。Apple ID token と user ID が欠けた場合はセッションを作らない。署名・entitlement・実機検証は Apple Developer Program の設定後に行う。
4. Welcome 画面で利用可能な認証ボタンを同じ重みで表示する。Google を App Store 向けに有効化する前に Apple も使用可能にする。メール・パスワード導線は残す。
5. 検証用 Supabase に Google/Apple プロバイダーを設定する。Google Cloud OAuth の Web client ID/secret と Apple Developer 設定は外部管理とし、秘密値をコード・ドキュメント・ログへ保存しない。
6. 2種類の新規登録、既存メールとの自動連携、プロフィール作成、ログアウト、再起動を実機で確認して検証記録へ残す。

## 制約

- `auth.uid()` と既存 RLS を維持する。DB スキーマと公開範囲の契約を変更しない。
- Google/Apple provider 未設定時は実機ログイン成功を主張しない。
- Apple Developer Program 未加入の間は Apple の実機・配布検証を未完了と記録する。

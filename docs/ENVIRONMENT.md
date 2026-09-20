# 開発環境

## Supabase のメール認証

iOS の新規登録・パスワード再設定メールからアプリに戻すため、使用する Supabase プロジェクトの Authentication → URL Configuration → Redirect URLs に `rakugakimap-dev://auth/callback` を登録する。アプリは新規登録時にこの URL を `redirectTo` として送信する。既に送信済みのメールのリンク先は後から変わらない。

Site URL は Android など同じプロジェクトを使うクライアントの既定値にも影響するため、iOS 用 URL へ一括変更しない。

## 自動検証

- GitHub Actions: `macos-15`。最初の実測はarm64 / macOS 15.7.9。
- `DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer`
- Xcode 16.4 / Swift 6.1.2 / deployment target iOS 17.0
- XcodeGen 2.44.1（commitをscriptで検証）
- Simulatorは選択したXcodeで利用可能なiPhoneを使用。
- 署名なしで実機向けbuild、Simulatorのunit/UI testを行う。配布用archiveではない。

## 手元のMac

Xcode 16.4、Git、Command Line Toolsが必要。リポジトリのルートで実行する。

```bash
export DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer
bash scripts/generate-project.sh
xcrun simctl list devices available
export IOS_SIMULATOR_ID='<利用するiPhone SimulatorのUDID>'
bash scripts/verify-ios.sh all
open MapGrapherIOS.xcodeproj
```

`project.yml`がprojectの正本。構成を変更したら生成scriptを再実行する。
Coreだけなら`bash scripts/verify-ios.sh core`。テスト結果は`.build/verification/`に残る。
unitは`MapGrapherIOS`、UIは`MapGrapherIOSUI`という共有schemeで分離し、一方のテストコードのコンパイル失敗が他方の実行を妨げないようにする。

## 実機

この作業環境はWindowsで、Swift/Xcodeと接続iPhoneはない。ユーザーはiPhoneを所有しているがMacはないため、[Windowsからの実機検証](IPHONE_FROM_WINDOWS.md)へ進む。ARのG1判定は未実施。
Macでprojectを生成後、Signing & Capabilitiesで所有するTeamと開発用Bundle IDを設定してiPhoneへ実行する。
Teamや署名鍵はコミットしない。生成projectへの設定は再生成で消えるので、手元の設定値を管理する場合はgitignore対象の`Local.xcconfig`を使う。

`Local.example.xcconfig`を同じディレクトリの`Local.xcconfig`へコピーすると手元の開発署名に使える。CIはこのファイルを持たず署名しない。
Supabase SDK・実接続はAPI対応表を確定する段階で追加する。現時点ではURLやキーを設定しても通信しない。
App Storeへの提出時は、その時点のAppleのSDK要件を別途確認する。

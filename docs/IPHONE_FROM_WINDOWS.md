# WindowsとiLoaderでiPhoneへ入れる

ユーザー環境はWindowsとiPhone、Macなし、Apple Developer Program未加入。本人の希望に合わせ、当面の実機導入はiLoaderを使う。TestFlightへの登録・アップロードは行わない。

## IPAの取得

1. GitHubのActionsで対象commitの`iOS verification`を開く。
2. Core・iOSテスト・IPA作成が成功したrunのArtifactsから`RakugakiMap-unsigned-ipa`をダウンロードする。
3. ZIPを展開し、`RakugakiMap-unsigned.ipa`をiLoaderのIPA読み込みで選ぶ。
4. いつものiLoaderの手順で署名・インストールし、iPhoneで起動する。
5. 「地図」→「AR動作確認」から[AR_PROBE](AR_PROBE.md)の項目を実機で確認する。

IPAは実機向けRelease archiveの`Payload/MapGrapherIOS.app`を梱包した署名前の成果物。Simulator用アプリではない。署名は利用者のiLoader側で行うので、Apple ID・証明書・pairingファイルをGitHubやチャットへ渡す必要はない。

同梱の`commit.txt`と`SHA256SUMS.txt`で対象ソースとファイルを識別できる。PowerShellでは次の値をチェックサムと比較できる。

```powershell
Get-FileHash .\RakugakiMap-unsigned.ipa -Algorithm SHA256
```

Artifactsの保存期間は14日。期限切れならActionsを手動再実行する。IPA作成はCoreとiOSの検証成功後だけ実行される。
初期版はバックエンド未接続の試作。IPA生成成功と、iLoaderでの導入・AR実機成功は別々に記録する。

## 将来のTestFlight / App Store

一般テスターへのTestFlight配布へ進むときはApple Developer Program、配布署名、App Store Connect登録を別途整える。
2026-09-20確認時、AppleはiOS提出buildにXcode 26以降を要求している。現在のXcode 16.4による基盤検証を提出可能と扱わず、提出前に対応Xcode/SDKへ更新する。

- [iLoader公式サイト（IPA読み込み・署名手順の説明）](https://iloader.app/)
- [iLoader公式リポジトリ](https://github.com/nab138/iloader)
- [Apple: beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Apple: Upload builds / supported Xcode versions](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)

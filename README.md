# RakugakiMap iOS

写真・ラクガキ・現地ARをiPhoneで楽しむネイティブ版です。現在は基盤とAR試作を実装中で、完成アプリではありません。

- iOS 17以上 / Swift 6 / SwiftUI
- ARKit + RealityKit（ARは初回版から必須、LiDARは必須にしない）
- 既存Supabaseの契約を利用予定。現時点で本番への接続はありません。

## 設計

- [設計仕様](docs/IOS_PORT_DESIGN.md)
- [Sol high / Luna max実装計画](docs/IOS_PORT_IMPLEMENTATION_PLAN.md)
- [検証・引き継ぎ](docs/IOS_PORT_VALIDATION_HANDOFF.md)
- [実施記録](docs/verification.md)

このリポジトリルートは、設計書の `MapGrapherClient/MapGrapherIOS` に相当します。Androidリポジトリは変更しません。

## 検証

GitHub ActionsのmacOSランナーでCore・署名なしiOSビルド・Simulatorのunit/UIテストを検証します。ARの平面検出・追跡はiPhone実機で別途確認します。CIは署名鍵やSupabaseの秘密情報を使いません。

```bash
swift test --package-path Packages/MapGrapherCore
```

Macでの生成・実行手順は[開発環境](docs/ENVIRONMENT.md)を参照してください。

# 空間AR落書き Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iPhoneのカメラ位置をペン先として、空間に独立した3D落書きを描けるモードを追加する。

**Architecture:** 純粋な`SpatialStrokeRecorder`が点列と操作履歴を所有し、専用`SpatialARDrawingDriver`がARKitのカメラ姿勢を入力してRealityKitへ線分を描く。専用SwiftUI画面とrouteだけを既存ナビゲーションへ接続し、写真ARのdriver・投稿・backend契約は変更しない。

**Tech Stack:** Swift 6、SwiftUI、ARKit、RealityKit、XCTest、XcodeGen、GitHub Actions

**Spec:** `docs/SPATIAL_AR_DRAWING_DESIGN.md`

## Global Constraints

- iOS 17以上、日本語UI、AR実機成功とCI成功を区別する。
- `MapGrapherIOS/Features/Safety/`を編集・追加しない。
- 写真投稿、`WORLD_MAP_V1`、Supabase schemaを変更しない。
- 新しい公開関数はMainActorまたはSendable境界を明示する。

## Review Focus

- 追跡更新の高頻度入力で5,000点を超えず、上限到達を利用者へ示す。
- NaN・infinityをRealityKitへ渡さない。
- ボタンを離した後のフレームを同じストロークへ混ぜない。
- background・退出・カメラ競合でsessionとleaseを解放する。
- 既存の投稿とAR閲覧の入口・状態を変えない。

---

### Task 1: 3Dストローク記録モデル

**Files:**
- Create: `MapGrapherIOS/Infrastructure/AR/SpatialStrokeRecorder.swift`
- Test: `MapGrapherIOSTests/SpatialStrokeRecorderTests.swift`

**Interfaces:**
- Produces: `SpatialStrokePoint`、`SpatialStroke`、`SpatialStrokeRecorder.beginStroke/append/endStroke/undo/clear`

- [ ] 失敗テストに、描画中のみ採用、2cm間引き、非有限拒否、1点破棄、上限、undo、clearを書く。
- [ ] GitHub Actionsで型未定義によるREDを確認する。
- [ ] 値型の最小実装を追加する。
- [ ] 全unit suiteをGREENにする。
- [ ] `feat(ar): 空間ストローク記録モデルを追加`でcommitする。

### Task 2: ARKitカメラ軌跡のRealityKit描画

**Files:**
- Create: `MapGrapherIOS/Infrastructure/AR/SpatialARDrawingDriver.swift`
- Create: `MapGrapherIOS/Infrastructure/AR/SpatialARCanvasView.swift`
- Test: `MapGrapherIOSTests/SpatialStrokeGeometryTests.swift`

**Interfaces:**
- Consumes: Task 1の点列。
- Produces: `SpatialStrokeSegmentGeometry`、`SpatialARDrawingDriver.start/stop/setDrawing/undo/clear`

- [ ] 2点間の中心・長さ・向きを定めるgeometryテストを書く。
- [ ] CIでREDを確認する。
- [ ] ARSessionのcamera translationをrecordし、線分entityを生成するdriverとcanvasを実装する。
- [ ] camera lease、中断、上限、権限状態を実装する。
- [ ] unit/device buildをGREENにしてcommitする。

### Task 3: 独立画面と入口

**Files:**
- Create: `MapGrapherIOS/Features/AR/SpatialARDrawingScreen.swift`
- Modify: `MapGrapherIOS/App/AppRoute.swift`
- Modify: `MapGrapherIOS/App/RootTabs.swift`
- Modify: `MapGrapherIOS/Features/Map/MapScreen.swift`
- Test: `MapGrapherIOSUITests/SpatialARDrawingUITests.swift`

**Interfaces:**
- Produces: `.spatialARDrawing` routeと`screen.spatial-ar-drawing`。

- [ ] 地図に独立入口があり写真投稿画面を経由しないUI testを書く。
- [ ] CIでREDを確認する。
- [ ] 色、太さ、押して描く、undo、clear、終了を備えた全画面を実装する。
- [ ] Core、device build、unit/UI、IPAをGREENにする。
- [ ] 実機受入項目と検証記録を更新してcommitする。

## Self-review

- Spec coverage: 初版の操作、独立境界、上限、カメラlease、実機未検証をTask 1〜3がすべて担当する。
- Placeholder scan: 実装保留を示すTBD/TODOなし。公開保存は初版非対象として仕様で固定した。
- Type consistency: recorderの点列をgeometryとdriverが消費し、画面はdriverの公開操作だけを使う。
- Review Focus: 5項目すべてTask 1〜3のテストまたはdevice buildで検証する。

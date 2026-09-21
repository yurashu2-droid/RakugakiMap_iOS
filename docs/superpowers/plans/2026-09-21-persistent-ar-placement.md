# 現地固定AR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 投稿者が現地で調整したラクガキをARWorldMapへ保存し、別セッション・別端末で同じ位置と向きへ復元する。

**Architecture:** 緯度経度は探索と解放にだけ使い、精密な姿勢は名前付きARAnchorを含むARWorldMapを正本にする。private Supabase Storageの`ar-world-maps`へarchiveを保存し、既存RPCを維持したまま永続AR専用RPCを追加する。閲覧時はworld map relocalizationを優先し、ARGeoTrackingは利用可能地域で復元開始を補助する。

**Tech Stack:** Swift 6、SwiftUI、RealityKit、ARKit、XCTest、Supabase PostgreSQL/RLS/Storage、PowerShell検証スクリプト

**Spec:** `docs/PERSISTENT_AR_DESIGN.md`

## Global Constraints

- iOS deployment targetは17.0を維持する。
- `LOCAL_PLANE`の既存データとAndroid向け`create_ar_experience`を維持する。
- 認可は`auth.uid()`とRLSを正本とし、RLSを無効化しない。
- world mapはprivate bucketへ保存し、DBにはStorage pathだけを保存する。
- service role keyをiOSへ入れない。
- world map archiveは25 MiB以下、format versionは1とする。
- カメラ画像はStorageへ保存しない。
- `MapGrapherIOS/Features/Safety/`の未コミット変更を編集・追加・削除しない。
- 実機確認なしに永続AR完了と報告しない。

## Review Focus

- world mapに指定したanchorがない、または重複する場合は公開・表示を拒否する。Task 3とTask 7でテストする。
- upload成功後にRPCが失敗した場合、今回のorphan objectだけを削除し、以前の公開を維持する。Task 5でテストする。
- 旧`LOCAL_PLANE`行は新しいnullable列がなくても従来表示へ進む。Task 4とTask 7でテストする。
- relocalizationが終わらない場合、無期限に操作不能にせず再試行できる。Task 7でテストする。
- ブロック・非公開・未承認ラクガキのworld mapはsigned URLを発行できない。Task 4でRLSテストする。

---

### Task 1: AR配置値の純粋モデル

**Files:**
- Create: `MapGrapherIOS/Infrastructure/AR/ARPlacement.swift`
- Create: `MapGrapherIOSTests/ARPlacementTests.swift`

**Interfaces:**
- Produces: `ARPlacement(position:yawRadians:displayWidthM:)`、`scaled(by:)`、`rotated(by:)`。
- Produces: `ARPlacementLimits.widthRange = 0.1...10.0`。

- [ ] **Step 1: Write the failing tests**

```swift
func testScaleClampsDisplayWidthToPublishedLimits() throws {
    let placement = try XCTUnwrap(ARPlacement(position: .zero, yawRadians: 0, displayWidthM: 1))
    XCTAssertEqual(placement.scaled(by: 100).displayWidthM, 10)
    XCTAssertEqual(placement.scaled(by: 0.001).displayWidthM, 0.1)
}

func testRotationNormalizesFiniteYaw() throws {
    let placement = try XCTUnwrap(ARPlacement(position: .zero, yawRadians: 0, displayWidthM: 1))
    XCTAssertEqual(placement.rotated(by: .pi * 3).yawRadians, -.pi, accuracy: 0.0001)
    XCTAssertNil(ARPlacement(position: .zero, yawRadians: .infinity, displayWidthM: 1))
}
```

- [ ] **Step 2: Run tests to verify RED**

Run on macOS CI: `xcodebuild test -project MapGrapherIOS.xcodeproj -scheme MapGrapherIOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MapGrapherIOSTests/ARPlacementTests`

Expected: FAIL because `ARPlacement` does not exist.

- [ ] **Step 3: Implement the value type**

```swift
struct ARPlacement: Equatable, Sendable {
    let position: SIMD3<Float>
    let yawRadians: Float
    let displayWidthM: Double

    init?(position: SIMD3<Float>, yawRadians: Float, displayWidthM: Double) {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              yawRadians.isFinite, displayWidthM.isFinite else { return nil }
        self.position = position
        self.yawRadians = Self.normalized(yawRadians)
        self.displayWidthM = min(10, max(0.1, displayWidthM))
    }

    func scaled(by factor: Double) -> Self {
        Self(position: position, yawRadians: yawRadians,
             displayWidthM: displayWidthM * factor)!
    }

    func rotated(by delta: Float) -> Self {
        Self(position: position, yawRadians: yawRadians + delta,
             displayWidthM: displayWidthM)!
    }
}
```

- [ ] **Step 4: Run focused and full unit suites**

Run the focused command from Step 2, then:

`xcodebuild test -project MapGrapherIOS.xcodeproj -scheme MapGrapherIOS -destination 'platform=iOS Simulator,name=iPhone 16'`

Expected: PASS.

- [ ] **Step 5: Commit**

```text
test(ar): 配置値の境界を定義
```

### Task 2: 縦向き表示と編集ジェスチャー

**Files:**
- Modify: `MapGrapherIOS/Infrastructure/AR/ARImagePlaneFactory.swift`
- Modify: `MapGrapherIOS/Infrastructure/AR/ARSessionDriver.swift`
- Modify: `MapGrapherIOS/Infrastructure/AR/ARCanvasView.swift`
- Modify: `MapGrapherIOS/Features/AR/ARScreen.swift`
- Modify: `MapGrapherIOSTests/ARPlaneGeometryTests.swift`
- Create: `MapGrapherIOSTests/ARPlacementGestureTests.swift`

**Interfaces:**
- Consumes: `ARPlacement` from Task 1.
- Produces: `ARSessionDriver.movePlacement(to:)`、`scalePlacement(by:)`、`rotatePlacement(by:)`、`lockPlacement()`。
- Produces: `@Published placementState: ARPlacementState` with `.scanning`, `.editing`, `.locked`。

- [ ] **Step 1: Add failing geometry and gesture-policy tests**

```swift
func testStandingPlaneRaisesItsCenterByHalfHeight() throws {
    let geometry = try ARPlaneGeometry(pixelWidth: 1000, pixelHeight: 500, displayWidthM: 2)
    XCTAssertEqual(geometry.heightM, 1)
    XCTAssertEqual(geometry.standingCenterHeightM, 0.5)
}

func testPinchIsIgnoredAfterPlacementIsLocked() throws {
    var editor = ARPlacementEditor(initial: try XCTUnwrap(
        ARPlacement(position: .zero, yawRadians: 0, displayWidthM: 1)))
    editor.lock()
    editor.scale(by: 2)
    XCTAssertEqual(editor.placement.displayWidthM, 1)
}
```

- [ ] **Step 2: Verify RED**

Run only `ARPlaneGeometryTests` and `ARPlacementGestureTests` in Xcode CI.

Expected: missing standing geometry and editor APIs.

- [ ] **Step 3: Generate a vertical XY plane and add input routing**

Use the existing `MeshResource.generatePlane(width:depth:)` and rotate the model by `-.pi / 2` around X so the local plane stands in XY. Set the local Y position to `height / 2`, generate collision shapes, and set iOS 18 face culling to `.none`.

Add pan, pinch, and rotation recognizers to `ARCanvasView.Coordinator`. Forward only `.began/.changed/.ended` values to the driver. On a horizontal raycast, use a gravity-upright transform whose yaw faces the current camera. On a vertical raycast, align the plane with the wall normal.

- [ ] **Step 4: Add lock and redo controls**

Show `ここに固定` only in `.editing`; show `配置をやり直す` in `.locked`. Update Japanese instructions and accessibility identifiers `ar.placement.lock` and `ar.placement.redo`.

- [ ] **Step 5: Run focused and full suites**

Expected: all unit and UI compile tests PASS.

- [ ] **Step 6: Commit**

```text
feat(ar): ラクガキを立たせて配置編集できるようにする
```

### Task 3: ARWorldMapの安全なarchiveと復号

**Files:**
- Create: `MapGrapherIOS/Infrastructure/AR/ARWorldMapArchive.swift`
- Create: `MapGrapherIOS/Infrastructure/AR/ARWorldMapCapturing.swift`
- Modify: `MapGrapherIOS/Infrastructure/AR/ARSessionDriver.swift`
- Create: `MapGrapherIOSTests/ARWorldMapArchiveTests.swift`

**Interfaces:**
- Produces: `PersistentARPackage(data: Data, anchorName: String, displayWidthM: Double, formatVersion: Int)`。
- Produces: `ARWorldMapArchive.encode(_:requiredAnchorName:) throws -> Data`。
- Produces: `ARWorldMapArchive.decode(_:requiredAnchorName:maxBytes:) throws -> ARWorldMap`。
- Produces: `ARWorldMapArchive.validateAnchorNames(_:required:) throws` as a pure validation seam。
- Produces: `ARSessionDriver.capturePersistentPackage() async throws -> PersistentARPackage`。

- [ ] **Step 1: Write failing validation tests using an injectable archive envelope**

```swift
func testDecodeRejectsOversizedArchiveBeforeUnarchiving() {
    XCTAssertThrowsError(try ARWorldMapArchive.decode(
        Data(repeating: 0, count: 26 * 1024 * 1024),
        requiredAnchorName: "rakugaki:test", maxBytes: 25 * 1024 * 1024))
}

func testValidationRejectsMissingAndDuplicateNamedAnchor() {
    XCTAssertThrowsError(try ARWorldMapArchive.validateAnchorNames(
        [], required: "rakugaki:test"))
    XCTAssertThrowsError(try ARWorldMapArchive.validateAnchorNames(
        ["rakugaki:test", "rakugaki:test"], required: "rakugaki:test"))
}
```

- [ ] **Step 2: Verify RED**

Expected: archive types do not exist.

- [ ] **Step 3: Implement secure archive boundaries**

Use `NSKeyedArchiver.archivedData(withRootObject:requiringSecureCoding:)` and `NSKeyedUnarchiver.unarchivedObject(ofClass:from:)`. Reject empty data, data over 25 MiB, unsupported format, and any map that does not contain exactly one matching named anchor. Unit tests exercise the pure name validator and byte limits; the real `ARWorldMap` archive round trip is an iPhone integration check because ARKit does not expose a public world-map initializer for simulator fixtures.

- [ ] **Step 4: Capture only after mapping is usable**

Track `ARFrame.WorldMappingStatus`; enable capture only for `.extending` or `.mapped`. At lock time, remove the editable `AnchorEntity`, add one `ARAnchor(name:transform:)`, obtain the current world map, validate it, and return the package. Restore editing state if capture fails.

- [ ] **Step 5: Run tests**

Run archive tests, then the full suite. Expected: PASS.

- [ ] **Step 6: Commit**

```text
feat(ar): 名前付きアンカーをworld mapへ保存する
```

### Task 4: Supabase永続AR契約とRLS

**Files:**
- Create: `C:/Programer___Amano/MapGrapher/MapGrapherBackend/supabase/migrations/202609210004_persistent_ar_anchors.sql`
- Modify: `C:/Programer___Amano/MapGrapher/MapGrapherBackend/docs/shared_interface_registry.md`
- Modify: `C:/Programer___Amano/MapGrapher/MapGrapherBackend/scripts/test-rls.ps1`
- Modify: `docs/reference/shared_interface_registry.md`

**Interfaces:**
- Produces: private bucket `ar-world-maps` and path rule `<uid>/world-maps/<uuid>.armap`。
- Produces: `publish_persistent_ar_experience(...) returns public.ar_experiences`。
- Extends: `get_ar_experience(uuid)` response with world map metadata。

- [ ] **Step 1: Add failing SQL/RLS assertions**

Add checks that owner A can upload its prefix and publish its approved rakugaki; user B cannot overwrite/delete A's map; an allowed viewer can select the object; a blocked or unauthorized viewer cannot; `LOCAL_PLANE` remains valid; `WORLD_MAP_V1` without required metadata fails.

- [ ] **Step 2: Verify RED**

Run: `npm run test:rls`

Expected: FAIL because bucket, columns, and RPC are absent.

- [ ] **Step 3: Add schema and validation**

Create the private bucket with `file_size_limit = 26214400` and `allowed_mime_types = ARRAY['application/octet-stream']`. Add nullable metadata columns, replace the anchor check with `LOCAL_PLANE`/`WORLD_MAP_V1`, and add a row check enforcing the required V1 fields only for `WORLD_MAP_V1`.

```sql
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ar-world-maps', 'ar-world-maps', false, 26214400,
        array['application/octet-stream'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

alter table public.ar_experiences
  add column world_map_path text,
  add column anchor_name text,
  add column fallback_altitude_m double precision,
  add column fallback_heading_deg double precision,
  add column world_map_format_version integer;
```

- [ ] **Step 4: Add storage policies and RPC**

Policies must use `auth.uid()` and `can_view_photo`; do not grant public access. The RPC verifies photo ownership, approved rakugaki, normalized owner prefix, existing `storage.objects` metadata, finite numeric fields, and updates the row only after every check succeeds.

```sql
create policy "world maps inserted by owner prefix"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'ar-world-maps'
  and (storage.foldername(name))[1] = auth.uid()::text
  and (storage.foldername(name))[2] = 'world-maps'
);

create or replace function public.publish_persistent_ar_experience(
  target_photo_id uuid,
  target_rakugaki_id uuid,
  target_world_map_path text,
  target_anchor_name text,
  target_unlock_radius_m double precision,
  target_discovery_radius_m double precision,
  target_display_width_m double precision,
  target_fallback_altitude_m double precision default null,
  target_fallback_heading_deg double precision default null
) returns public.ar_experiences;
```

- [ ] **Step 5: Keep old RPC compatible and update registry copies**

Do not change the signature or semantics of `create_ar_experience`. Document the new bucket, enum value, columns, and RPC in both registry copies.

- [ ] **Step 6: Verify backend**

Run sequentially:

```text
npm run verify:quick
npm run test:rls
npm run scan:secrets
```

Expected: PASS with no secret findings.

- [ ] **Step 7: Commit in the backend repository**

```text
feat(ar): 永続ARアンカーの保存契約を追加
```

### Task 5: iOS world map転送と公開処理

**Files:**
- Modify: `Packages/MapGrapherCore/Sources/MapGrapherCore/Domain/ArExperience.swift`
- Modify: `MapGrapherIOS/Infrastructure/Supabase/DTO/ArDTO.swift`
- Create: `MapGrapherIOS/Infrastructure/AR/ARWorldMapStore.swift`
- Modify: `MapGrapherIOS/Infrastructure/AR/ARRepository.swift`
- Modify: `MapGrapherIOS/App/AppContainer.swift`
- Create: `MapGrapherIOSTests/ARWorldMapStoreTests.swift`
- Modify: `MapGrapherIOSTests/ARFlowTests.swift`

**Interfaces:**
- Produces: `ArAnchorType.worldMapV1`。
- Extends: `ArExperience` with `worldMap: AssetReference?`、`anchorName: String?`、`worldMapFormatVersion: Int?`、fallback fields。
- Produces: `ARWorldMapStoring.upload(package:context:)`、`download(asset:context:)`、`delete(asset:context:)`。
- Produces: `ARExperienceServing.publishPersistent(...)`。

- [ ] **Step 1: Write failing mapper and compensation tests**

```swift
func testWorldMapExperienceRequiresCompleteMetadata() throws {
    let row = makeWorldMapRow(worldMapPath: nil, anchorName: "rakugaki:a", version: 1)
    XCTAssertThrowsError(try ARRepository.mapForTesting(row))
}

func testRpcFailureDeletesOnlyNewlyUploadedWorldMap() async {
    store.uploaded = AssetReference(bucket: "ar-world-maps", path: "owner/world-maps/new.armap")!
    remote.publishPersistentError = AppFailure.serviceUnavailable
    do {
        _ = try await repository.publishPersistent(package: package,
            photoID: photoID, rakugakiID: rakugakiID,
            unlockRadiusM: 50, discoveryRadiusM: 150, context: context)
        XCTFail("RPC失敗を返す必要があります")
    } catch {
        XCTAssertEqual(error as? AppFailure, .serviceUnavailable)
    }
    XCTAssertEqual(store.deleted, [store.uploaded])
}
```

- [ ] **Step 2: Verify RED**

Expected: new DTO/domain/store APIs are missing.

- [ ] **Step 3: Implement authenticated upload/download**

Use `gateway.client.storage.from("ar-world-maps")`. Generate a UUID path under the authenticated user's lowercase UUID prefix, set `application/octet-stream`, reject data above 25 MiB before upload, and check the current `SessionContext` before and after network calls.

- [ ] **Step 4: Implement the new RPC and mapping**

Use a separate DTO matching the exact SQL argument names. Map nullable fields strictly by anchor type. Keep old `publish(...)` for compatibility. If RPC fails after upload, delete the new object best-effort and rethrow the original failure.

- [ ] **Step 5: Run focused and full tests**

Expected: PASS.

- [ ] **Step 6: Commit**

```text
feat(ar): world mapのprivate転送と公開を接続
```

### Task 6: 投稿画面を配置・固定・公開へ接続

**Files:**
- Modify: `MapGrapherIOS/Features/AR/ARPublishSettingsScreen.swift`
- Create: `MapGrapherIOS/Features/AR/ARPersistentPublishModel.swift`
- Modify: `MapGrapherIOS/Infrastructure/Posting/RealPostingUIService.swift`
- Create: `MapGrapherIOSTests/ARPersistentPublishModelTests.swift`
- Modify: `MapGrapherIOSUITests/PostingUITests.swift`

**Interfaces:**
- Consumes: `capturePersistentPackage()` and `publishPersistent(...)`。
- Produces: publish states `.scanning`, `.editing`, `.capturing`, `.uploading`, `.published`, `.failed(retryable:)`。

- [ ] **Step 1: Write failing state-machine tests**

Test that publish stays disabled before mapping is usable, transitions capture→upload→published once, ignores double taps, retains the package for a retryable upload error, and clears it on session epoch change.

- [ ] **Step 2: Verify RED**

Expected: persistent publish model is absent.

- [ ] **Step 3: Implement the model and screen flow**

Open the camera before showing radius controls. Explain that surrounding feature points are saved. After placement lock and successful map capture, show radius/width summary and a single `この場所にARを公開` action. Width shown by the form must come from the final placement package.

- [ ] **Step 4: Connect one-operation AR posting**

When the ordinary post includes AR, route the approved drawing into this placement flow and call only `publishPersistent`. Do not show success until both Storage and RPC complete.

- [ ] **Step 5: Run unit and UI tests**

Expected: PASS.

- [ ] **Step 6: Commit**

```text
feat(ar): 現地配置から永続AR公開まで接続
```

### Task 7: 閲覧時の復元とフォールバック

**Files:**
- Modify: `MapGrapherIOS/Features/AR/ARScreenModel.swift`
- Modify: `MapGrapherIOS/Features/AR/ARScreen.swift`
- Modify: `MapGrapherIOS/Infrastructure/AR/ARSessionDriver.swift`
- Create: `MapGrapherIOS/Infrastructure/AR/ARGeoTrackingAdvisor.swift`
- Create: `MapGrapherIOSTests/ARRelocalizationTests.swift`
- Modify: `MapGrapherIOSUITests/MapUITests.swift`

**Interfaces:**
- Produces: `ARSessionDriver.startRelocalizing(worldMap:anchorName:)`。
- Produces: relocalization states `.loadingMap`, `.relocalizing`, `.localized`, `.timedOut`, `.corruptMap`。
- Produces: `ARGeoTrackingAdvisor` that returns `.available`, `.unavailable`, or `.unsupported` without blocking world-map mode。

- [ ] **Step 1: Write failing restoration tests**

Test exact named-anchor selection, missing/duplicate anchor rejection, `LOCAL_PLANE` compatibility, timeout to retryable state, session pause cancellation, and geo unavailable fallback to world tracking.

- [ ] **Step 2: Verify RED**

Expected: restoration APIs and states are absent.

- [ ] **Step 3: Start with `initialWorldMap` and wait for the named anchor**

Configure `ARWorldTrackingConfiguration.initialWorldMap`, horizontal/vertical plane detection, and session delegate callbacks. Render only after the expected anchor is reported. Use a cancellable timeout and expose `再認識する` and `戻る` actions.

- [ ] **Step 4: Add optional geo assistance**

Check support and availability at the post coordinate. If available, use geo status only to improve user guidance and heading; do not make it a requirement for world-map relocalization. Treat accuracy below medium as approximate.

- [ ] **Step 5: Preserve `LOCAL_PLANE` behavior**

Route old rows to the existing tap-to-place path, with updated vertical rendering. Never attempt to decode a missing world map for this type.

- [ ] **Step 6: Run all tests**

Expected: PASS.

- [ ] **Step 7: Commit**

```text
feat(ar): 現地で永続アンカーを復元する
```

### Task 8: 実機検証、文書、リリース用artifact

**Files:**
- Modify: `docs/AR_PROBE.md`
- Modify: `docs/verification.md`
- Modify: `docs/IOS_PORT_VALIDATION_HANDOFF.md`
- Modify: `.github/workflows/ios.yml` if existing artifact steps need the new tests but do not alter signing secrets.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: reproducible manual evidence and the unsigned IPA artifact link/path.

- [ ] **Step 1: Run automated verification**

Run XcodeGen, Swift package tests, app unit tests, UI smoke tests, and Release archive on GitHub Actions. Record exact run URL, commit SHA, artifact SHA-256, and failing test names if any.

- [ ] **Step 2: Run author-device manual test**

At one outdoor location, scan until mapping is usable, place the drawing upright, move/rotate/scale it, publish, close the app, reopen, and confirm relocalization. Record only approximate test area; do not record exact personal coordinates.

- [ ] **Step 3: Run second-session or second-device test**

Download the same private world map under another authorized account/device, revisit the scene from a different initial camera pose, and confirm the drawing appears at the same physical feature. Also test changed lighting and geo unavailable mode.

- [ ] **Step 4: Record limitations clearly**

Document that substantial scene or lighting changes can prevent relocalization, and that geo availability varies by location. Record whether fallback was used; do not label approximate placement as exact.

- [ ] **Step 5: Commit docs**

```text
docs(ar): 永続ARの実機検証結果を記録
```

- [ ] **Step 6: Deliver artifact**

Provide the local unsigned IPA path and GitHub Actions artifact link. Keep TestFlight/signing as a separate release step.

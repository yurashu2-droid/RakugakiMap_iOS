# 現地固定AR設計

## 目的

投稿者が現地でラクガキを立たせ、移動・回転・拡大縮小して固定し、後から同じ場所を訪れた利用者が同じ位置と向きで見られるようにする。

地図上の発見と入場判定には既存の緯度経度を使い、現地での精密な復元にはARKitの`ARWorldMap`を使う。`ARGeoTrackingConfiguration`が利用できる場所では地理アンカーを復元開始の補助に使うが、対応地域外でも`ARWorldMap`による復元を試せる構成にする。

## 現状と問題

- `ARImagePlaneFactory`は画像をRealityKitのXZ平面として生成するため、水平面では床に寝る。
- `ARSessionDriver.place(at:)`は検出面の姿勢をそのまま採用し、配置後の移動・回転・拡大縮小を受け付けない。
- `ar_experiences`は画像、緯度経度、表示幅だけを持ち、作者が決めたAR空間上の姿勢を保存しない。
- 閲覧のたびに利用者が面をタップして配置するため、同じ場所へ復元されない。
- `anchor_type`は`LOCAL_PLANE`だけを許可している。

## 採用方式

### 二段階の位置合わせ

1. **現地への誘導**
   - 既存の`photos.location`と発見半径を使う。
   - 既存の正確な位置情報による解放判定を維持する。
2. **現地での精密な復元**
   - 投稿時に名前付き`ARAnchor`を追加した`ARWorldMap`を保存する。
   - 閲覧時に同じworld mapを読み込み、ARKitが周囲の特徴点と照合する。
   - 名前付きanchorが復元されたら、そのtransformへラクガキを表示する。

緯度経度だけでセンチメートル級の固定はできない。`ARGeoAnchor`も利用地域と精度に制約があるため、正確な配置の正本にはしない。

### 表示形状

- ラクガキは縦向きのXY平面として生成する。
- 表裏から見える素材にする。
- 下端が設置点に接するよう、モデル中心を画像高の半分だけ上げる。
- 厚みを感じられる薄い背面と控えめな影を追加できる構造にする。初版の正本は透過画像面で、画像内容自体は変換しない。

### 配置操作

- 初回タップ：検出した床または壁へ仮配置する。
- 1本指ドラッグ：画面上の位置へ再raycastして移動する。
- ピンチ：表示幅を`0.1...10.0m`へ制限して変更する。
- 2本指回転：重力軸を中心に回転する。
- 「ここに固定」：名前付きanchorを作り直し、world map取得を開始する。
- 固定後も「配置をやり直す」で編集状態へ戻せる。

床へ置く場合は画像を垂直に立て、初期yawはカメラを向く値にする。壁へ置く場合は壁と平行にする。配置中だけジェスチャーを有効にし、閲覧中は誤操作を防ぐ。

## 永続化契約

### Storage

private bucket `ar-world-maps`を追加する。

- path: `<auth.uid>/world-maps/<uuid>.armap`
- MIME: `application/octet-stream`
- 最大サイズ: 25 MiB
- DBにはpathだけを保存し、signed URLは保存しない。
- ownerは自分のprefixへだけupload/update/deleteできる。
- readは親写真を閲覧でき、対象ARが`READY`である利用者だけに許可する。
- 親写真またはAR体験の削除時はサーバー処理でobjectも削除対象にする。

### `ar_experiences`追加列

| 列 | 型 | 意味 |
|---|---|---|
| `world_map_path` | text nullable | private world mapのStorage path |
| `anchor_name` | text nullable | world map内の名前付きanchor |
| `fallback_altitude_m` | double precision nullable | 地理アンカー補助用の楕円体高 |
| `fallback_heading_deg` | double precision nullable | world map復元前の案内方向 |
| `world_map_format_version` | integer nullable | archive互換性。初版は1 |

`anchor_type`へ`WORLD_MAP_V1`を追加する。`WORLD_MAP_V1`では`world_map_path`、`anchor_name`、`world_map_format_version = 1`を必須にする。既存の`LOCAL_PLANE`行は列をNULLのまま維持する。

表示幅は配置確定時の幅で`display_width_m`を更新する。位置と回転はworld map内の名前付き`ARAnchor.transform`を正本とする。

### RPC

既存`create_ar_experience`はAndroid互換のため残す。新しく`publish_persistent_ar_experience`を追加する。

入力：

- `target_photo_id uuid`
- `target_rakugaki_id uuid`
- `target_world_map_path text`
- `target_anchor_name text`
- `target_unlock_radius_m double precision`
- `target_discovery_radius_m double precision`
- `target_display_width_m double precision`
- `target_fallback_altitude_m double precision default null`
- `target_fallback_heading_deg double precision default null`

サーバーは`auth.uid()`を所有者として扱い、次を検証する。

- 写真ownerであること。
- ラクガキが対象写真に属し`APPROVED`であること。
- world map pathが`<auth.uid>/world-maps/`配下であること。
- `storage.objects`に対象objectがあり、bucket、owner、MIME、25 MiB上限を満たすこと。
- 半径、幅、高度、headingが有限で許容範囲内であること。

戻り値は更新後の`ar_experiences`一行。アップロード後にRPCが失敗した場合、iOSは今回のpathだけをbest-effortで削除する。

`get_ar_experience`にはworld map情報を追加する。`get_nearby_ar_traces`は地図探索用なので大きなpath情報を返さない。

## 投稿フロー

1. 承認済みラクガキ画像を読み込む。
2. 現地でARセッションを開始し、周囲をスキャンする。
3. 利用者が縦向きのラクガキを配置・調整する。
4. `worldMappingStatus`が`.extending`または`.mapped`になるまで案内する。
5. 「ここに固定」で名前付きanchorを追加する。
6. `getCurrentWorldMap`を呼び、`NSSecureCoding`でarchiveする。
7. サイズとanchor存在を端末内で検証する。
8. private Storageへuploadする。
9. 新RPCでDB行を`WORLD_MAP_V1 / READY`へ更新する。
10. 成功後に公開完了を表示する。

world mapを取得できない状態では公開ボタンを有効にしない。既存の`LOCAL_PLANE`公開を暗黙の成功扱いにはしない。

## 閲覧フロー

1. 既存の緯度経度ゲートと閲覧権限確認を行う。
2. `LOCAL_PLANE`なら従来表示を互換動作として残す。
3. `WORLD_MAP_V1`ならprivate Storageからworld mapを取得する。
4. archiveを安全に復号し、format versionとanchor名を検証する。
5. `initialWorldMap`を設定してセッションを開始する。
6. 「投稿地点の周囲をゆっくり映してください」と案内する。
7. 名前付きanchorが復元されたらラクガキを表示する。
8. 一定時間復元できない場合は再試行と、概算方向を示す案内を出す。

復元に失敗したとき、利用者の現在位置へ勝手に配置して「同じ場所」と表示しない。概算表示を行う場合は「おおよその位置」と明示する。

## ARGeoTrackingの扱い

- `ARGeoTrackingConfiguration.isSupported`と`checkAvailability(at:)`を実機で確認する。
- 利用可能かつnetworkがある場合だけ復元開始の補助に使う。
- `.localized`かつaccuracyが`.medium`以上になるまで正確な復元完了とは扱わない。
- 対応地域外、屋内、通信断では通常のworld trackingへ切り替える。
- geo trackingが使えないこと自体を投稿・閲覧不可の理由にしない。

## エラーと回復

- world mapが大きすぎる：周囲を狭くスキャンして再取得するよう案内する。
- upload失敗：端末内draftを保持し、同じpathへの再送を可能にする。
- RPC失敗：uploadした今回のobjectを削除し、既存の公開行は維持する。
- download/復号失敗：破損扱いにして自動的なローカル配置へ偽装しない。
- relocalization timeout：再試行または退出を選べるようにする。
- tracking中断：同じworld mapで再開し、失敗時は明示的にリセットする。

## プライバシーと安全性

- world mapはprivate bucketに保存する。
- world mapには現実空間の特徴点が含まれるため、AR公開確認画面で保存目的を説明する。
- カメラ画像そのものは初版では保存しない。
- signed URLをログ、DB、ドキュメントへ保存しない。
- RLSを無効化しない。クライアントからのuser IDを権限判断に使わない。
- ブロック、公開範囲、削除済み投稿の既存条件をworld map readにも適用する。

## 初版の完了条件

- ラクガキが床から垂直に立つ。
- 配置中に移動・回転・拡大縮小できる。
- 投稿者が固定したworld mapをprivate Storageへ保存できる。
- 別セッションでworld mapを読み込み、名前付きanchorへ復元できる。
- 別端末での同一地点復元を実機2台または同一world map共有で確認する。
- 対応地域外でも通常のworld map復元経路へ進める。
- 既存`LOCAL_PLANE`投稿が引き続き閲覧できる。

## 初版で扱わないもの

- 動くアニメーションや物理演算を永続化すること。
- 複数人による同時編集。
- Androidでのworld map生成・復元。
- Apple以外のVPSやcloud anchorサービス。

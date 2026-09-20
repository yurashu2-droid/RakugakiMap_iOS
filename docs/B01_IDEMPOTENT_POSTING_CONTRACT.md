# B01 投稿作成の冪等契約案

状態: レビュー済みの実装案。追加migrationが適用されるまでiOSから呼び出さない。既存`create_photo_pin`/`create_rakugaki`はAndroid互換のため残す。

## 入口と応答

- `create_photo_pin_v2(client_request_id, title, lat, lon, privacy, draw_permission, requires_approval, photo_path, mime_type, byte_size)`
- `create_rakugaki_v2(client_request_id, target_photo_id, target_asset_path)`

作成者は常に`auth.uid()`。request IDは端末で下書き作成時に固定したUUIDで、再試行で作り直さない。成功応答は既存の`PhotoRowDTO`/`RakugakiRowDTO`と同じJSON object。DB上の投稿を後で削除しても、同じID・同じ入力の再送は保存済み応答を返して復活させない。別入力で同じrequest IDなら`REQUEST_CONFLICT`として失敗する。

receiptの一意キーは`(actor_id, operation_kind, client_request_id)`。正規化した入力JSONと結果JSONを保持する。receipt行を確保して排他した後、入力比較、投稿作成、結果保存を同一transactionで行う。同時2接続では一方のcommitを待って同じ結果を読む。途中失敗はreceiptと投稿をともにrollbackし、結果未設定のreceiptを成功扱いしない。receiptは投稿FKのCASCADE対象にしない。

新規作成時はStorage実体のbucket、本人prefix、所有者、MIME、サイズを照合する。写真はbucket `photos`・path `<auth.uid>/photos/<uuid>.<ext>`、ラクガキはbucket `rakugakis`・path `<auth.uid>/rakugakis/<uuid>.<ext>`の組で扱う。既存Storage policyの本人prefixだけを投稿作成の十分な検証とみなさない。再送でreceiptがある場合は、画像を後に削除していても同じ結果を返す。

ネットワーク応答が失われた状態でiOSが素材を直ちに削除してはならない。receiptの結果照会を優先し、未参照が確定した画像だけを遅延回収する。二重投稿・同一ID別入力・削除後再送・Storage未存在・MIME/サイズ不一致・別人path・応答消失をDBとiOS coordinatorで検証する。

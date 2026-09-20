# iOS API対応表（T03・初版）

正本: `MapGrapherBackend/docs/shared_interface_registry.md`、Android `SupabaseApiService.kt` / `SupabaseDtos.kt`、`MapGrapherBackend/supabase/migrations/` の適用順（最終 `202607120002_add_group_missions.sql`）。この表は既存APIだけを示す。`create_photo_pin_v2`、`create_rakugaki_v2`、Safety APIは未実装であり、呼び出さない。

`SupabaseGateway.rpc(_:parameters:as:)` は既存RPCのJSONをSDKで送受信する入口。Swift DTOは `Infrastructure/Supabase/DTO/` に置く。HTTP/RPC失敗は例外として伝播し、空配列へ置き換えない。日時は小数秒の有無を含むISO 8601、`mission_date` はJSTで決められた `yyyy-MM-dd` を文字列のまま保持する。nullableは `?`、PostgreSQL bigintは `Int64`。所有者の識別はクライアントが送るIDでなくDBの `auth.uid()` を正とする。通常の閲覧RPCは再取得可能だが非冪等の操作を通信断後に自動再送しない。

| RPC | 引数JSONキー | 応答shape / DTO | 空・null / 失敗 | 自動再送 | 後続担当 |
|---|---|---|---|---|---|
| `nearby_photos` | `lat,lon,radius_meters` | 配列 `NearbyPhotoDTO` | 0件は正常。`photo_path,thumbnail_path`等はnullable | 読取のみ可 | L02 |
| `create_photo_pin` | `title,lat,lon,privacy,draw_permission,requires_approval,photo_path,mime_type,byte_size` | 単一 `PhotoRowDTO` | 失敗は例外。`mime_type,byte_size`はnullable | 不可（B01審査待ち） | T11 |
| `create_rakugaki` | `target_photo_id,target_asset_path` | 単一 `RakugakiRowDTO` | 失敗は例外 | 不可（B01審査待ち） | T11 |
| `approve_rakugaki` | `target_rakugaki_id,approved` | 単一 `RakugakiRowDTO` | 権限違反は例外 | 状態再取得後のみ | T14 |
| `pending_rakugakis` | `{}` | 配列 `PendingRakugakiDTO` | 0件は正常 | 読取のみ可 | T14 |
| `history_rakugakis` | `target_photo_id` | 配列 `PendingRakugakiDTO` | 0件は正常 | 読取のみ可 | T14 |
| `photo_permissions` | `target_photo_id` | 配列 `PhotoPermissionDTO` | 0件はnotFound相当。1件を判定、複数件は契約違反 | 読取のみ可 | L02/T14 |
| `update_photo_settings` | `target_photo_id,new_privacy,new_draw_permission,new_requires_approval` | 単一 `PhotoRowDTO` | 権限違反は例外 | 状態再取得後のみ | T14 |
| `delete_photo` | `target_photo_id` | void | 未所有・未存在は例外 | 状態再取得後のみ | T14 |
| `toggle_like` | `target_photo_id` | 配列 `LikeResultDTO` | 通常1件。0件は成功扱いしない | 不可（toggle） | T14 |
| `request_friend` | `target_user_unique_id` | 単一 `FriendRequestRowDTO` | 未存在・権限違反は例外 | 状態再取得後のみ | T14 |
| `pending_friend_requests` | `{}` | 配列 `FriendRelationDTO` | 0件は正常 | 読取のみ可 | T14 |
| `accepted_friends` | `{}` | 配列 `FriendRelationDTO` | 0件は正常 | 読取のみ可 | T14 |
| `respond_friend_request` | `target_request_id,accepted` | 単一 `FriendRequestRowDTO` | 権限違反は例外 | 状態再取得後のみ | T14 |
| `remove_friend` | `target_request_id` | void | 権限違反は例外 | 状態再取得後のみ | T14 |
| `accepted_friend_ids` | `{}` | 配列 `AcceptedFriendIDDTO` | 0件は正常 | 読取のみ可 | T14 |
| `get_ar_experience` | `target_photo_id` | 配列 `ArExperienceDTO` | 0件は体験なし/閲覧不可。最大1件 | 読取のみ可 | T13 |
| `get_nearby_ar_traces` | `current_latitude,current_longitude` | 配列 `NearbyArTraceDTO` | 0件は正常 | 読取のみ可 | T13 |
| `create_ar_experience` | `target_photo_id,target_rakugaki_id,target_unlock_radius_m,target_discovery_radius_m,target_display_width_m` | 単一 `ArExperienceRowDTO` | 承認済み・owner・半径をSQLが検証 | 状態再取得後のみ | T13 |
| `create_group` | `client_request_id,group_name,group_description` | 単一 `GroupRowDTO` | `client_request_id`はUUID。衝突はSQLを正とする | 同一ID/入力の結果照会後のみ | T16 |
| `update_group` | `target_group_id,group_name,group_description` | 単一 `GroupRowDTO` | owner以外は例外 | 状態再取得後のみ | T16 |
| `list_my_group_summaries` | `{}` | 配列 `GroupSummaryDTO` | `mission_id,date,status,prompt_text,setter_*`はnullable | 読取のみ可 | T16 |
| `get_group_members` | `target_group_id` | 配列 `GroupMemberDTO` | 0件とエラーを区別 | 読取のみ可 | T16 |
| `invite_group_member` | `target_group_id,target_user_unique_id` | 単一 `GroupInvitationRowDTO` | SQLの8人/友達/owner判定 | 状態再取得後のみ | T16 |
| `cancel_group_invitation` | `target_invitation_id` | 単一 `GroupInvitationRowDTO` | 権限/状態違反は例外 | 状態再取得後のみ | T16 |
| `list_my_group_invitations` | `{}` | 配列 `GroupInvitationSummaryDTO` | 0件は正常 | 読取のみ可 | T16 |
| `respond_group_invitation` | `target_invitation_id,accepted` | 単一 `GroupInvitationRowDTO` | 権限/期限違反は例外 | 状態再取得後のみ | T16 |
| `leave_group` | `target_group_id` | void | owner操作はSQL制約 | 状態再取得後のみ | T16 |
| `remove_group_member` | `target_group_id,target_member_id` | void | 権限違反は例外 | 状態再取得後のみ | T16 |
| `transfer_group_ownership` | `target_group_id,target_new_owner_id` | 単一 `GroupRowDTO` | 権限違反は例外 | 状態再取得後のみ | T16 |
| `archive_group` | `target_group_id` | 単一 `GroupRowDTO` | 権限違反は例外 | 状態再取得後のみ | T16 |
| `reassign_group_mission_setter` | `target_mission_id` | 単一 `GroupMissionRowDTO` | 状態/権限違反は例外 | 状態再取得後のみ | T16 |
| `set_group_mission_prompt` | `target_mission_id,target_prompt_text` | 単一 `GroupMissionRowDTO` | 当日/担当者の制約はSQL | 状態再取得後のみ | T16 |
| `get_group_mission_status` | `target_group_id` | 配列 `GroupMissionParticipantDTO` | 0件は状態なし。回答/画像pathはnullable | 読取のみ可 | T16 |
| `submit_group_answer` | `target_mission_id,target_photo_id` | 単一 `GroupAnswerRowDTO` | 既存写真UUIDを参照、複製しない | 状態再取得後のみ | T16 |
| `withdraw_group_answer` | `target_mission_id` | void | 状態違反は例外 | 状態再取得後のみ | T16 |
| `list_notifications` | `target_limit,target_before` | 配列 `NotificationDTO` | `target_before`はnullable timestamptz。0件は正常。`payload`はjsonb | 読取のみ可 | T16 |
| `mark_notification_read` | `target_notification_id` | 単一 `NotificationDTO` | 未存在は`NOTIFICATION_NOT_FOUND` (`P0001`) | 状態再取得後のみ | T16 |

| REST / Storage | 入力 / JSON | 応答shape | 空・失敗 | 後続担当 |
|---|---|---|---|---|
| Auth SDK signup/password/reset/callback/logout | SDKのAuth request（tokenはDTOに渡さない） | SDK sessionまたは確認待ち | signup後sessionなしは確認待ち。復帰時refresh失敗は再認証 | T04 |
| `GET rest/v1/profiles` | `id=eq.<auth.uid>&select=id,user_unique_id,display_name,avatar_path` | 配列 `ProfileDTO` | 0件はprofile未作成 | T04/T14 |
| `POST rest/v1/profiles` | `ProfileUpsertDTO`、`Prefer:return=representation` | 配列 `ProfileDTO` | 0件は登録成功扱いしない | T04/T14 |
| `PATCH rest/v1/profiles` | `id=eq.<auth.uid>`、変更キー、`Prefer:return=representation`をiOS adapterで明示 | 配列 `ProfileDTO` | 0件は更新成功扱いしない | T14 |
| `GET/POST rest/v1/albums` | `owner_id=eq.<auth.uid>` / `title,description` | 配列 `AlbumDTO` | 0件は一覧では正常、作成時は異常 | T14 |
| `GET/POST rest/v1/album_photos` | `album_id=eq.<uuid>` / `album_id,photo_id` | 配列 `AlbumPhotoDTO` | 0件は一覧では正常、追加時は異常 | T14 |
| `POST storage/v1/object/{bucket}/{path}` | private `photos/rakugakis/avatars`、画像bytes、`x-upsert:false` | Storage upload応答 | 競合を別画像への上書きで回避しない | T11/T14 |
| `POST storage/v1/object/sign/{bucket}/{path}` | `expiresIn` | 一時的signed URL | 永続DBへURLを保存しない | T05 |

## 確認済みのSQLと台帳の差分・保留

- ARの古い4引数 `create_ar_experience` は `202607110003_add_post_time_ar_publication.sql` で削除され、5引数版のみ残る。上表とDTOは5引数版。
- 台帳のグループRPC一覧は `transfer_group_ownership` を含む一方、早期の一覧にない場合がある。現行 `SupabaseApiService.kt` と `202607120001_add_groups.sql` に存在するため対応表へ含めた。
- `list_notifications.target_before` はSQLでは `timestamptz`、Android DTOでは `String?`。Swiftは送信時ISO 8601文字列として保持し、日付変換による時差を避ける。
- Androidの `updateProfile` は戻り値を配列と定義する一方で `Prefer:return=representation` が指定されていない。PostgRESTのminimal応答では配列が返らないため、iOS adapterはheaderを明示してから配列をdecodeする。現行Androidの挙動は開発環境で再確認する。
- バックエンドの例外メッセージは全RPCで安定したcodeに統一されていない。HTTP失敗を包括的に`notFound`へ割り当てない。後続adapterは既知codeのみ分類し、未分類は失敗として上げる。
- 実Supabaseでのデコードとエラー分類は未実施。合成fixture試験、MacのC1/C3、開発DBの契約試験で確定する。

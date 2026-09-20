# 共有インターフェース台帳

作成日: 2026-06-14

この台帳は、Codex、Antigravity、MiniMax が同じ MapGrapher を触るための共有ページです。クラス名、RPC、DTO、Storage path、変更禁止の契約をここに集めます。

## 使い方

- 実装担当は、作業前にこの台帳を読み、既存名を変えずに使う。
- 新しい endpoint、RPC、DTO、Storage bucket、DB column が必要に見えた場合は、まず「変更案」としてこの文書か作業報告に書く。
- Codex またはユーザーのレビュー前に、DB/RLS/API 契約を変更しない。
- secret、API key、service role key、DB password はこの台帳に書かない。

## 役割

| 担当 | 役割 | 主に触るもの |
|---|---|---|
| Codex | 設計主任、backend、RLS、RPC、data layer、レビュー | migration、Repository、Supabase API、検証 script |
| Antigravity | UI、UX、文言、実機確認、公開素材 | layout、strings、画面、manual test、store docs |
| MiniMax | 実装担当、既存契約に沿う実装補助 | 小さな UI 接続、既存 API 利用、テスト補助、単純修正 |
| ユーザー | product 判断、公開判断、key 管理 | Supabase project、Google Maps key、ストア、法務方針 |

## 変更禁止の契約

実装担当が自分判断で変えないもの:

- Supabase table 名、column 名、RLS policy。
- RPC 名、引数名、戻り値の形。
- `SupabaseApiService.kt` の endpoint path。
- `SupabaseDtos.kt` の `@SerializedName`。
- Storage bucket 名と path 規則。
- `ANYONE`, `FRIENDS`, `ONLY_ME` の意味。
- `PENDING`, `APPROVED`, `REJECTED` の意味。
- Android に service role key を入れない原則。

## Android 主要クラス

| クラス / ファイル | 役割 | 変更担当 |
|---|---|---|
| `data/remote/SupabaseConfig.kt` | Supabase URL と anon key の BuildConfig 参照 | Codex |
| `data/remote/supabase/SupabaseClient.kt` | Retrofit client と `apikey` header 設定 | Codex |
| `data/remote/supabase/SupabaseApiService.kt` | Supabase Auth、REST、RPC、Storage endpoint 定義 | Codex |
| `data/remote/supabase/SupabaseDtos.kt` | Supabase API の request / response DTO | Codex |
| `data/remote/supabase/SupabaseAuthRepository.kt` | signup、login、profile 作成/取得 | Codex |
| `data/remote/supabase/SupabaseSessionStore.kt` | access token と Supabase user id の保存 | Codex |
| `data/remote/supabase/SupabaseStorageUrlResolver.kt` | private Storage path から signed URL を取得 | Codex |
| `data/remote/supabase/SupabasePhotoMapper.kt` | Supabase photo row から Room 用 model への変換 | Codex |
| `data/repository/PhotoRepository.kt` | 写真、落書き、友達、いいね、同期の中心 | Codex |
| `util/ImageUploadPreparer.kt` | upload 前の MIME、サイズ、EXIF 削除、再エンコード | Codex |
| `ui/*` | 画面表示、文言、ユーザー操作 | Antigravity / MiniMax |

## Supabase REST / Auth endpoint

| Kotlin 関数 | HTTP | path | DTO |
|---|---|---|---|
| `signUp` | POST | `auth/v1/signup` | `SupabaseAuthRequest` -> `SupabaseSessionResponse` |
| `login` | POST | `auth/v1/token?grant_type=password` | `SupabaseAuthRequest` -> `SupabaseSessionResponse` |
| `getProfile` | GET | `rest/v1/profiles` | `SupabaseProfile` |
| `createProfile` | POST | `rest/v1/profiles` | `SupabaseProfileUpsert` -> `SupabaseProfile` |
| `updateProfile` | PATCH | `rest/v1/profiles` | `Map<String, String?>` -> `SupabaseProfile` |
| `getAlbums` | GET | `rest/v1/albums` | `List<SupabaseAlbum>` |
| `createAlbum` | POST | `rest/v1/albums` | `Map<String, String?>` -> `List<SupabaseAlbum>` |
| `getAlbumPhotos` | GET | `rest/v1/album_photos` | `List<SupabaseAlbumPhoto>` |
| `addAlbumPhoto` | POST | `rest/v1/album_photos` | `Map<String, String?>` -> `List<SupabaseAlbumPhoto>` |

## Supabase RPC

| Kotlin 関数 | RPC | 目的 | Request | Response |
|---|---|---|---|---|
| `nearbyPhotos` | `nearby_photos` | 近傍写真検索 | `NearbyPhotosRequest` | `List<SupabaseNearbyPhoto>` |
| `createPhotoPin` | `create_photo_pin` | 写真ピン作成 | `CreatePhotoPinRequest` | `SupabasePhotoRow` |
| `createRakugaki` | `create_rakugaki` | 落書き投稿 | `CreateRakugakiRequest` | `SupabaseRakugakiRow` |
| `approveRakugaki` | `approve_rakugaki` | 落書き承認/拒否 | `ApproveRakugakiRequest` | `SupabaseRakugakiRow` |
| `pendingRakugakis` | `pending_rakugakis` | 承認待ち落書き取得 | empty map | `List<SupabasePendingRakugaki>` |
| `historyRakugakis` | `history_rakugakis` | 写真の落書き履歴取得 | `PhotoIdRequest` | `List<SupabasePendingRakugaki>` |
| `photoPermissions` | `photo_permissions` | 閲覧/落書き/owner 権限確認 | `PhotoIdRequest` | `List<PhotoPermissionResult>` |
| `updatePhotoSettings` | `update_photo_settings` | 写真設定更新 | `UpdatePhotoSettingsRequest` | `SupabasePhotoRow` |
| `deletePhoto` | `delete_photo` | 写真削除 | `PhotoIdRequest` | `Unit` |
| `toggleLike` | `toggle_like` | いいね追加/解除 | `PhotoIdRequest` | `List<ToggleLikeResult>` |
| `requestFriend` | `request_friend` | 友達申請 | `RequestFriendRequest` | `SupabaseFriendRequestRow` |
| `pendingFriendRequests` | `pending_friend_requests` | 受信した友達申請一覧 | empty map | `List<SupabaseFriendRelation>` |
| `acceptedFriends` | `accepted_friends` | 承認済み友達一覧 | empty map | `List<SupabaseFriendRelation>` |
| `respondFriendRequest` | `respond_friend_request` | 友達申請の承認/拒否 | `RespondFriendRequest` | `SupabaseFriendRequestRow` |
| `removeFriend` | `remove_friend` | 友達解除 | `RemoveFriendRequest` | `Unit` |
| `acceptedFriendIds` | `accepted_friend_ids` | 友達限定表示の補助 | empty map | `List<AcceptedFriendId>` |
| `getArExperience` | `get_ar_experience` | 投稿に紐づく閲覧可能なAR体験取得 | `PhotoIdRequest` | `List<SupabaseArExperience>` |
| `getNearbyArTraces` | `get_nearby_ar_traces` | 現在地の発見半径内にある閲覧可能なAR痕跡取得 | `NearbyArTracesRequest` | `List<SupabaseNearbyArTrace>` |
| `createArExperience` | `create_ar_experience` | 投稿時のAR公開予約を同期後に作成・差し替え | `CreateArExperienceRequest`（photo/rakugaki/unlock/discovery/width） | `SupabaseArExperienceRow` |

## Storage endpoint

| Kotlin 関数 | HTTP | path | 目的 |
|---|---|---|---|
| `uploadObject` | POST | `storage/v1/object/{bucket}/{path}` | private bucket へ画像 upload |
| `createSignedUrl` | POST | `storage/v1/object/sign/{bucket}/{path}` | 表示用 signed URL 発行 |

## Storage bucket と path

| bucket | 用途 | 最大サイズ | MIME | path |
|---|---|---:|---|---|
| `photos` | 元写真 | 20MB | `image/jpeg`, `image/png`, `image/webp` | `<auth.uid>/photos/<uuid>.<ext>` |
| `rakugakis` | 落書き画像 | 20MB | `image/jpeg`, `image/png`, `image/webp` | `<auth.uid>/rakugakis/<uuid>.<ext>` |
| `avatars` | アバター | 5MB | `image/jpeg`, `image/png`, `image/webp` | `<auth.uid>/avatars/<uuid>.<ext>` |

DB には signed URL や public URL ではなく、Storage path だけ保存します。

## DB table

| table | 目的 |
|---|---|
| `profiles` | Auth user に紐づくプロフィール |
| `photos` | 地図上の写真ピンと公開設定 |
| `photo_assets` | 写真や派生画像の Storage path 管理 |
| `rakugakis` | 写真に紐づく落書き画像と承認状態 |
| `friend_requests` | 友達申請、承認、拒否 |
| `likes` | 写真へのいいね |
| `albums` | ユーザー本人の写真整理用アルバム。初期実装では owner だけ閲覧・編集可 |
| `album_photos` | アルバムと写真の紐づけ。初期実装では album owner だけ閲覧可。追加できる写真は `can_view_photo` で見える写真だけ |
| `ar_experiences` | 写真、承認済み落書き、AR用Storage path、解放半径、発見半径、READY/PAUSED状態、表示実幅の紐づけ。公開範囲は親写真から継承 |

## enum 相当の値

| 種類 | 値 | 意味 |
|---|---|---|
| photo privacy | `ANYONE` | ログイン済みユーザーなら閲覧可 |
| photo privacy | `FRIENDS` | owner と承認済み友達だけ閲覧可 |
| photo privacy | `ONLY_ME` | owner だけ閲覧可 |
| draw permission | `ANYONE` | 見える写真に落書き可 |
| draw permission | `FRIENDS` | owner と承認済み友達だけ落書き可 |
| draw permission | `ONLY_ME` | owner だけ落書き可 |
| rakugaki status | `PENDING` | 承認待ち |
| rakugaki status | `APPROVED` | 承認済み |
| rakugaki status | `REJECTED` | 拒否済み |
| friend request status | `PENDING` | 申請中 |
| friend request status | `ACCEPTED` | 承認済み |
| friend request status | `REJECTED` | 拒否済み |

## DTO 一覧

Auth / profile:

- `SupabaseAuthRequest`
- `SupabaseSessionResponse`
- `SupabaseAuthUser`
- `SupabaseProfile`
- `SupabaseProfileUpsert`
- `SupabaseSignedInUser`

Photo:

- `NearbyPhotosRequest`
- `SupabaseNearbyPhoto`
- `CreatePhotoPinRequest`
- `SupabasePhotoRow`
- `PhotoIdRequest`
- `UpdatePhotoSettingsRequest`
- `PhotoPermissionResult`

Storage:

- `StorageUploadResponse`
- `CreateSignedUrlRequest`
- `CreateSignedUrlResponse`

Rakugaki:

- `CreateRakugakiRequest`
- `ApproveRakugakiRequest`
- `SupabaseRakugakiRow`
- `SupabasePendingRakugaki`

Friends / likes:

- `ToggleLikeResult`
- `AcceptedFriendId`
- `RequestFriendRequest`
- `RespondFriendRequest`
- `RemoveFriendRequest`
- `SupabaseFriendRelation`
- `SupabaseFriendRequestRow`

Albums:

- `SupabaseAlbum`
- `SupabaseAlbumPhoto`

AR:

- `SupabaseArExperience`
- `SupabaseArExperienceRow`
- `SupabaseNearbyArTrace`
- `NearbyArTracesRequest`
- `CreateArExperienceRequest`
- request は既存 `PhotoIdRequest` を再利用する。
- `anchor_type` のMVP値は `LOCAL_PLANE` のみ。
- `status` が `READY` の体験だけを探索・表示する。`PAUSED` は近傍RPCと単体取得から返さない。
- Androidへ渡す識別子はSupabase UUIDとし、local long idを権限判定に使わない。
- AR体験の `asset_path` は選択した承認済み `rakugakis.asset_path` と完全一致させる。private `rakugakis` bucketのpathであり、URLをDBへ保存しない。

## アルバム機能の現在の契約

- `albums` にはまだ `privacy` を持たせない。
- そのため、初期公開では本人だけが自分のアルバムと `album_photos` を読める。
- 友達や全体へアルバムを公開したい場合は、先に `albums.privacy public.visibility_scope` のような明示的な公開範囲を設計し、RLS と Android UI を同時に更新する。
- `album_photos` へ追加できる写真は、追加者が `public.can_view_photo(photo)` で見える写真だけ。
- `SupabaseApiService.kt` の `uploadObject` 用 `@POST("storage/v1/object/{bucket}/{path}")` を他のREST endpointに移動しない。

## 実装担当への依頼テンプレート

```markdown
# 実装依頼

## 担当
- Antigravity / MiniMax

## 先に読む
- `MapGrapherBackend/docs/current_migration_status.md`
- `MapGrapherBackend/docs/codex_antigravity_working_agreement.md`
- `MapGrapherBackend/docs/shared_interface_registry.md`
- `MapGrapherBackend/docs/domain_design_guidelines.md`

## 触ってよい範囲
- 

## 触らない範囲
- `SupabaseApiService.kt`
- `SupabaseDtos.kt`
- `202606130001_initial_schema.sql`

## やること
- 

## 完了条件
- `.\gradlew.bat assembleDebug` が成功する。
- 変更した画面を実機または emulator で確認する。
- 変更内容、検証、残課題を報告する。
```

## MiniMax の起動方法

Codex のモデル選択 UI に `MiniMax-M3` が出ない場合があります。その場合は、TokenRouter 用の専用 profile を使って起動します。

```powershell
codex exec -p minimax --sandbox workspace-write -C C:\Programer___Amano\MapGrapher "ここに実装依頼を書く"
```

MiniMax profile は `C:\Users\raito\.codex\minimax.config.toml` に置き、API key 本体は `TOKENROUTER_API_KEY` 環境変数から読む前提です。

## 変更案メモ

新しい契約が必要になった場合は、実装前にここへ追記します。

| 日付 | 提案者 | 変更案 | 理由 | 状態 |
|---|---|---|---|---|
| 2026-06-14 | Codex | 初版作成 | 三者並行作業の衝突防止 | 採用 |
| 2026-06-17 | Codex | アルバムREST/DB契約を追加。RLSは本人限定で採用 | Antigravity自律追加後の過剰公開を防ぐため | 採用 |
| 2026-07-12 | Codex | グループ機能のDB/RPC/DTO契約を追加し、G1/G2 migrationとAndroid接続を実装 | Lunamax実装時の契約分岐を防ぎ、既存写真投稿を再利用するため | 実装済み・検証済み |

## グループ機能の実装契約

詳細と実装順は `docs/GROUP_FEATURE_LUNAMAX_IMPLEMENTATION_SPEC.md` および `docs/GROUP_FEATURE_LUNAMAX_HANDOFF.md` を正とする。DBは `202607120001_add_groups.sql` / `202607120002_add_group_missions.sql`、Androidは `GroupRepository` と `GroupListActivity` / `GroupDetailActivity` を実装済み。RPC戻り値はmigrationと `SupabaseDtos.kt` を同時に更新する。

### DB table

- `groups`
- `group_members`
- `group_invitations`
- `group_missions`
- `group_mission_participants`
- `group_answers`
- `notifications`

### enum

- `group_role`: `OWNER` / `MEMBER`
- `group_member_status`: `ACTIVE` / `LEFT` / `REMOVED`
- `group_invitation_status`: `PENDING` / `ACCEPTED` / `DECLINED` / `CANCELED` / `EXPIRED`
- `group_mission_status`: `AWAITING_PROMPT` / `OPEN` / `CLOSED`

### RPC

- `create_group`
- `update_group`
- `list_my_group_summaries`
- `get_group_members`
- `invite_group_member`
- `cancel_group_invitation`
- `list_my_group_invitations`
- `respond_group_invitation`
- `leave_group`
- `remove_group_member`
- `transfer_group_ownership`
- `archive_group`
- `reassign_group_mission_setter`
- `set_group_mission_prompt`
- `get_group_mission_status`
- `submit_group_answer`
- `withdraw_group_answer`
- `list_notifications`
- `mark_notification_read`

### Android DTO

- `CreateGroupRequest`
- `UpdateGroupRequest`
- `GroupIdRequest`
- `InviteGroupMemberRequest`
- `InvitationIdRequest`
- `RespondGroupInvitationRequest`
- `RemoveGroupMemberRequest`
- `MissionIdRequest`
- `SetGroupMissionPromptRequest`
- `SubmitGroupAnswerRequest`
- `ListNotificationsRequest`
- `NotificationIdRequest`
- `SupabaseGroupRow`
- `SupabaseGroupSummary`
- `SupabaseGroupMember`
- `SupabaseGroupInvitationRow`
- `SupabaseGroupInvitationSummary`
- `SupabaseGroupMissionRow`
- `SupabaseGroupMissionParticipantStatus`
- `SupabaseGroupAnswerRow`
- `SupabaseNotification`

### 変更禁止条件

- 最大8人にはOWNERを含める。
- 招待はOWNERから承認済みフレンドにだけ送る。
- 権限は `auth.uid()` で判定する。
- 既存写真を `group_answers` から参照し、画像を複製しない。
- グループ回答でも元photoの `privacy` と `draw_permission` を書き換えない。
- グループメンバー閲覧条件は `can_view_photo` に対象photo限定で追加する。
- 新規Storage bucketを作らず、既存private bucketとsigned URLを利用する。

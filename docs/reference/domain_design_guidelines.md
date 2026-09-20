# ドメイン設計ガイドライン

作成日: 2026-06-14

この文書は、MapGrapher の設計ルールを DDD 風に整理したものです。厳密な DDD を全面採用するというより、個人開発でも迷いにくくするための用語、境界、依存方向を決めます。

## 設計の目的

- 旧 Spring Boot backend 依存を消し、Supabase を信頼境界にする。
- Android から送られる `userId` を信用しない。
- Auth、RLS、Storage policy、RPC で権限を守る。
- UI は Supabase の内部構造を直接意識しすぎない。
- オフライン投稿は Android のローカル都合、権限判定は Supabase のサーバー都合として分ける。

## 境界づけられたコンテキスト

### Identity Context

扱うもの:

- Supabase Auth user
- profile
- display name
- avatar
- user unique id

ルール:

- 認証済み本人は `auth.uid()` で判断する。
- Android 側の local long id は表示や Room 用の補助 ID として扱う。
- 権限判定に local long id を使わない。
- avatar は private Storage に置き、DB には path だけ保存する。

### Map Photo Context

扱うもの:

- photo pin
- latitude / longitude
- title
- privacy
- draw permission
- approval setting
- photo asset

ルール:

- 位置情報検索は PostGIS の `geography(Point, 4326)` を使う。
- 近傍検索は `nearby_photos` RPC に集約する。
- `ANYONE`, `FRIENDS`, `ONLY_ME` は RLS と RPC の両方で守る。
- DB には画像 URL ではなく Storage path を保存する。

### Rakugaki Context

扱うもの:

- rakugaki image
- author
- status
- approval / rejection
- history

ルール:

- 未承認落書きは投稿者本人と写真所有者だけが見える。
- 承認後の落書きだけ、親写真を見られるユーザーに見える。
- 承認/拒否は写真所有者だけができる。
- rakugaki の画像 asset も private Storage に置く。

### Social Context

扱うもの:

- friend request
- accepted friend
- rejected request
- friend-only visibility

ルール:

- 友達関係は承認済み request を正とする。
- typo のある `frend` や旧命名は新設計へ持ち込まない。
- 自分自身への友達申請は許可しない。
- friend-only 表示は RLS と RPC で判断する。

### Engagement Context

扱うもの:

- likes
- liked state
- like count

ルール:

- 同一ユーザーが同じ photo に複数いいねできない。
- `likes.user_id + photo_id` は unique。
- 見えない写真にはいいねできない。
- Android は `toggle_like` RPC を使い、複数更新を持たない。

### Offline Sync Context

扱うもの:

- Room
- WorkManager
- pending photo
- sync retry
- local id / supabase id mapping

ルール:

- Room はオフラインキューと一時表示のために使う。
- Supabase に同期済みの行は `supabaseId` を持つ。
- 二重投稿を避けるため、同期済み判定を必ず見る。
- Worker は旧 Spring Boot API を呼ばない。

## 依存方向

望ましい依存方向:

```text
UI
  -> ViewModel
    -> Repository
      -> Supabase API / Room
        -> Supabase Auth / DB / Storage
```

禁止したい依存:

- UI から RLS 相当の権限判定を自前で決める。
- UI から複雑な SQL 相当の複数更新を組み立てる。
- Android が他人の `userId` を指定して作成者や所有者を決める。
- Storage public URL を DB に保存する。
- service role key を Android に入れる。

## 用語

| 用語 | 意味 | 使う場所 |
|---|---|---|
| profile | Supabase Auth user に紐づく公開プロフィール | DB/API/UI |
| photo | 地図上の写真ピン | DB/API/UI |
| photo asset | 写真の Storage path 管理行 | DB/API |
| rakugaki | 写真に重ねる落書き画像 | DB/API/UI |
| friend request | 友達申請 | DB/API/UI |
| accepted friend | 承認済み友達関係 | DB/API/UI |
| privacy | 写真の閲覧範囲 | DB/API/UI |
| draw permission | 落書きできる範囲 | DB/API/UI |
| signed URL | private Storage path を一時的に表示する URL | API/UI |

## 命名ルール

- DB table は複数形の snake_case。
- DB column は snake_case。
- Kotlin property は camelCase。
- Storage path は `<auth.uid>/<kind>/<uuid>.<ext>` を基本にする。
- 旧 typo の `frend` は新規コードに追加しない。
- `userId` という名前は local long id と Supabase UUID が混ざりやすいため、可能なら `userLongId`, `supabaseUserId`, `ownerId` のように明確化する。

## 公開範囲の意味

| 値 | 意味 |
|---|---|
| `ANYONE` | ログイン済みユーザーなら閲覧できる |
| `FRIENDS` | owner と承認済み友達だけ閲覧できる |
| `ONLY_ME` | owner だけ閲覧できる |

注意:

- 未ログインユーザーにはアプリデータを読ませない。
- `ANYONE` はインターネット全体公開ではなく、認証済みユーザー向け公開とする。

## Storage 設計

bucket:

- `photos`: private、最大 20MB、jpeg/png/webp。
- `rakugakis`: private、最大 20MB、jpeg/png/webp。
- `avatars`: private、最大 5MB、jpeg/png/webp。

ルール:

- DB に保存するのは URL ではなく path。
- 表示時に signed URL を取得する。
- Android は upload 前に EXIF 削除、MIME 検証、サイズ検証を行う。
- 権限外ユーザーには signed URL を発行しない。

## RPC 設計ルール

RPC に寄せるもの:

- 近傍検索。
- 写真投稿。
- 落書き投稿。
- 落書き承認/拒否。
- いいね toggle。
- 友達申請/承認/拒否/解除。
- 写真設定更新。
- 写真削除。

Android に持たせないもの:

- 友達関係の SQL 組み立て。
- いいね count の複数更新。
- photo asset と photo row の整合性管理。
- owner 判定。

## UI 設計ルール

- UI は「見える/見えない」の理由をできるだけ自然な文言にする。
- 権限エラーを内部エラーとして出さない。
- `ANYONE`, `FRIENDS`, `ONLY_ME` はユーザーが誤解しない表示にする。
- エラー Toast に SQL、JWT、Storage path、endpoint を出さない。
- 画像が権限外または期限切れの場合、placeholder または再取得で自然に扱う。

## 変更判断ルール

Antigravity が変更してよい:

- UI 表示文言。
- レイアウト崩れ。
- 空状態。
- エラー文言。
- 手動検証ログ。
- 公開素材の草案。

Codex が変更してよい:

- DB schema。
- RLS。
- RPC。
- Storage policy。
- Repository。
- Supabase API service。
- 自動テスト。

相談が必要:

- 公開範囲の意味を変える。
- Auth 方針を変える。
- 退会や通報の仕様を決める。
- 本番 key を扱う。
- 料金、公開可否、ストア掲載内容を決める。

## ADR の書き方

大きな設計判断をしたら、次の形式で `docs/adr/` に追加します。

```markdown
# ADR-番号: タイトル

## 状態
提案 / 採用 / 却下 / 置き換え

## 背景

## 決定

## 結果

## 未解決
```

最初に記録しておきたい ADR:

- Supabase を主 backend にする。
- Storage bucket を private にする。
- Android の旧 Spring Boot fallback を削除する。
- `ANYONE` を未ログイン公開ではなく認証済み公開にする。
- Room / WorkManager をオフラインキューとして残す。

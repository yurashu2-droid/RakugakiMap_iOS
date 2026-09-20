# 通報・ブロック・退会の契約案

状態: 提案。現行のSupabase migrationには下記APIがなく、iOS側で呼び出してはならない。実装前にバックエンド共有台帳と追加migrationへ反映し、RLS回帰テストを通す。

## 利用者に見える動作

- 写真・ラクガキ・利用者を通報できる。送信後は「受け付けました」と表示し、運営による確認・削除を完了したとは表示しない。
- 利用者をブロックすると、相手の写真・ラクガキ・AR・プロフィールを相互に表示しない。第三者の写真に描かれた相手のラクガキも対象。グループへの所属は自動解除せず、回答写真・通知内の対象素材も非表示にする。人数などの集計値は維持し、該当者の名前・avatar・画像pathは伏せる。
- 設定から退会を開始できる。確認画面で、本人の投稿・ラクガキ・アルバム・回答・通知とStorage画像が消えること、他人が本人の写真に描いたラクガキも親写真とともに消えることを説明する。
- 退会者がグループownerなら、`joined_at`、次に`user_id`の昇順で最も古いACTIVE参加者へownerを移す。候補がいなければグループを終了し、退会者のAuth削除に伴いグループを削除する。ユーザーが2026-09-21にこの引き継ぎ方針を選択した。

## API案

新RPCの権限判定はすべて`auth.uid()`。クライアントから送られたactor/owner IDを採用しない。request IDはUUIDで、同じIDの再送は同じ結果を返す。受理した結果を空配列へ変換しない。

| 入口 | 入力 | 成功応答 | 権限・失敗 |
|---|---|---|---|
| `report_content` | `client_request_id`, `target_kind` (`PHOTO`/`RAKUGAKI`/`USER`), `target_id`, `reason` (`HARASSMENT`/`SEXUAL`/`VIOLENCE`/`PRIVACY`/`SPAM`/`OTHER`), `detail`（任意、最大500字） | `report_id`, `received_at`, `status=RECEIVED` | ログイン必須。存在しない対象は`NOT_FOUND`。自分への通報は`INVALID_TARGET`。同一request IDと異なる内容は`REQUEST_CONFLICT`。 |
| `block_user` | `target_user_id` | `target_user_id`, `blocked_at` | 本人・未存在を拒否。再送は同じ状態。 |
| `unblock_user` | `target_user_id` | `target_user_id`, `unblocked=true` | 本人だけ解除。再送可能。 |
| `list_blocked_users` | なし | `target_user_id`, 表示可能なプロフィール識別子の配列 | 本人のブロックだけ返す。 |
| `request_account_deletion` | `client_request_id` | `request_id`, `status=ACCEPTED`, `requested_at` | 再認証済みセッションを要求。二重依頼は既存requestを返す。受付は完了ではない。 |
| `account_deletion_status` | なし | `request_id`, `status` (`ACCEPTED`/`PROCESSING`/`FAILED`/`COMPLETED`) | 本人の進捗だけ返す。Auth削除後の照会はできないため、完了は実行関数の応答と端末側セッション破棄で扱う。 |

退会の特権処理はサーバー側でのみ実行し、アプリへ`service_role`を渡さない。工程は、退会要求の固定と新規書込停止→グループowner移譲→削除manifest確定→対象Storage pathの削除→Auth user削除（FK cascade）→完了記録。書込停止は旧RPC、直接REST、Storage upload、招待・グループ操作にも適用する。manifestはDBのpathだけを信用せず、Storage実体の所有者と正規pathを検証する。本人写真に他人が描いた画像も含め、他の存続投稿から参照される画像を誤削除しない。途中失敗はlease付きの工程記録を保持して再実行し、別人のファイルや行を削除しない。工程記録は退会者のAuth/プロフィールからCASCADEされない管理領域に保持する。Auth削除後の応答消失を「成功」と推測せず、同じ要求の最終状態を管理側で照合する。

グループ移譲ではgroupと候補memberをロックした後、ACTIVE資格を再判定する。旧OWNER降格、新OWNER昇格、`owner_id`更新を同一transactionに入れ、退出・除名・手動移譲・招待応答ともロック順序を統一する。現行の`groups(owner_id,client_request_id)`一意制約はowner変更で衝突するため、作成者固定の冪等receiptへ移す設計が必要。

相互ブロックは写真RLSだけで完結しない。現行のSECURITY DEFINER RPC、プロフィール、ラクガキ、AR、通知payloadと既読更新の返り値、グループ一覧・回答・招待、private Storageの新規signed URL発行まで同じ素材アクセス判定を適用する。発行済みsigned URLは期限まで残り得るため、即時失効を保証した表示はしない。短いTTLと新規発行拒否を前提に、発行済みURLへの対応は配布前に検証する。

## 公開前の確認

- RLS/RPC/Storageで、ブロックされた写真・ラクガキ・AR・プロフィール・グループ回答画像・通知payload・既読更新応答から相手の素材が見えないことを複数アカウントで確認する。第三者の写真に描かれたブロック相手のラクガキも含む。iOSの表示フィルタだけに依存しない。
- 無認証、別人対象、通報連打、同一request IDの内容変更、退会途中の再実行、グループowner移譲と候補なしをテストする。
- 通報の運営連絡先、審査手順、対応記録、公開されるプライバシーポリシーを用意する。受付だけで運営対応が完成したとは扱わない。

AppleのUGCガイドラインは不適切素材のフィルタ、通報と対応、利用者のブロック、連絡先を要求する。また、アカウント作成を提供するアプリにはアプリ内の削除導線が必要。[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)、[アカウント削除ガイダンス](https://developer.apple.com/support/offering-account-deletion-in-your-app)。

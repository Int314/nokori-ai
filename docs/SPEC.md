# Nokori AI MVP仕様書

Oct 31, 2026 · @貴浩

## 概要

Claude CodeとCodexのサブスク使用量（5時間枠・週間枠）を、Macのメニューバーと iPhoneのウィジェットで常に確認できるOSSアプリを作る。既存のCodexBarは対応サービスが多すぎて見た目が雑多なため、この2サービスに絞り、デザインを最優先にする。

- 対象ユーザー：Claude CodeとCodexをサブスク（Pro／Max、Plus／Pro）で使う開発者
- 配布：GitHubでOSS公開（MITライセンス）
- デザイン：[モック（キャンバス）](https://claude.ai/artifact/PinoUWcGieSqdtt1K9MKV7)の次のアートボードが正。「最初の3案（不採用）」の列は参考にしない
  - 「推奨案 — ライト／ダーク」：メニューバー（横バー2段）、詳細ポップアップ、ウィジェット4種
  - 「メニューバーのラベル比較」の4番と「メニューバー 追加パターン」の7・8・10番：プリセット4種（横バー2段・縦バー・数字だけ・一番危ない枠だけ）
  - 「状態 — エラー・古いデータ・未使用」「設定画面（Mac）」「iPhoneアプリ・片方表示・古いデータ」：各アートボードの Tweaks の dark でダークも確認できる
- 進め方：この仕様書をClaude Codeに渡し、リポジトリの `docs/SPEC.md` として置いて実装する。MVPが完成したら、理由・制約・外部の事実だけを残して削る（コードで分かる数値や実装の説明は残さない）
- アプリ名：Nokori AI（「残り」から。App Storeに出すときのサブタイトルは「AIコーディングの使用量メーター」）。「Claude」「Codex」はアプリ名に入れない
- コピーライト表記：`2026 Nokori AI`（README、Macアプリの「このアプリについて」、LICENSEの著作権者）。実名・ハンドルは入れない

## MVPのスコープ

MVPは「Macで取得してメニューバーに出す」「iPhoneのウィジェットで見る」の2つだけを作る。

**やること**

- Claude CodeとCodexの5時間枠・週間枠の使用率とリセット時刻を、Macで定期取得する
- メニューバーに表示する（プリセット4種から選択）
- メニューバーのクリックで詳細ポップアップを開く
- 外観をライト／ダーク／システム追従の3択で切り替える
- 表示するサービスを「両方／Claude Codeのみ／Codexのみ」から選べるようにする
- iPhoneアプリとウィジェット（ホーム画面の小・中、ロック画面の円形・長方形）で同じ数値を表示する。配布はTestFlightまで

**やらないこと（MVP以降）**

- 表示内容の自由なカスタマイズ（書式テンプレート、部品の組み合わせ設定）
- 3つ目以降のサービス対応、複数アカウント
- モデル別の週間枠のうち、Claudeの `seven_day_sonnet`／`seven_day_opus` の表示（1モデル限定の `limits[].weekly_scoped` は表示する。「決定事項」参照）
- Macのデスクトップウィジェット、Apple Watch、ダイナミックアイランド
- 通知（上限が近いときのアラート）、警告色
- 使用履歴のグラフ、コスト（金額）表示
- Windows／Linux対応
- iPhoneアプリのApp Store公開（審査ではMacアプリなしで動作を確かめられないため、審査メモとMacで更新される様子のデモ動画を用意してから出す）

## 技術スタックと構成

Swift／SwiftUIのネイティブアプリ1本（Mac・iPhone・ウィジェット）と、共通ロジックのSwift Packageで構成する。

| 項目 | 採用 |
| --- | --- |
| 対応OS | macOS 14 Sonoma以降、iOS 17以降 |
| 言語・UI | Swift 6、SwiftUI |
| 表示言語 | 英語・日本語（String Catalog）。OSの言語設定に従う |
| メニューバー | `MenuBarExtra`（`.window` スタイルで詳細ポップアップ）。アイコンはSwiftUIで描いて `ImageRenderer` で `NSImage` 化し、`isTemplate = true` でモノクロ表示 |
| 設定画面 | SwiftUIの `Settings` シーン＋ `@AppStorage` |
| ログイン時起動 | `SMAppService.mainApp` |
| ウィジェット | WidgetKit。アプリとはApp Groupの共有コンテナでデータを受け渡す |
| iPhoneへの同期 | iCloud（CloudKitのプライベートDB）。下の「iPhoneへの同期」を参照 |
| 識別子 | Mac `dev.int314.nokori.mac`、iPhone `dev.int314.nokori`、ウィジェット `dev.int314.nokori.widgets`、iCloudコンテナ `iCloud.dev.int314.nokori`、App Group `group.dev.int314.nokori` |
| 署名（開発中） | Macは手動署名（Apple Development＋プロファイル「Nokori AI Mac Development」。iCloudにはコンテナを割り当てたプロファイルが要り、Xcodeにアカウントを入れずに済ませるため）。iPhoneのシミュレータはプロファイルなしでiCloudの権限が入る |
| Macアプリの配布 | サンドボックス外のDeveloper ID署名＋公証、GitHub Releases と自前の Homebrew tap（`Int314/homebrew-tap` の cask `nokori-ai`）。アプリの更新は Sparkle（フィードは最新リリースに添付した `appcast.xml`、EdDSA 署名。cask は `auto_updates true` で更新を Sparkle に任せる）。他アプリのキーチェーン読み取りと `codex` の起動にサンドボックス外が必要なため、Mac App Storeでは配布できない。CloudKitを使うため、Developer ID用のプロビジョニングプロファイルを埋め込む |
| テスト | Swift Testing。取得処理はレスポンスのフィクスチャで単体テスト |

```
nokori-ai/
├── docs/SPEC.md            この仕様書
├── Packages/UsageCore/     共通のSwift Package
│   ├── Sources/UsageCore/  モデル、ペース計算、表示用フォーマット、Claude／Codexの応答の解釈、CloudKitのレコード変換
│   └── Sources/UsageUI/    MacとiPhoneで共有するSwiftUI部品（バー、二重リング、サービスごとの行）
├── Mac/                    メニューバーアプリ（取得処理はここだけ）
│   ├── Fetchers/           ClaudeFetcher, CodexFetcher（キーチェーン・HTTP・プロセスの入出力だけ。解釈はUsageCore）
│   ├── MenuBar/            プリセット4種の描画
│   └── Popover/
├── iOS/                    iPhoneアプリ
├── iOSWidgets/             ウィジェット拡張
└── LICENSE                 MIT
```

## 画面仕様

メニューバーはモノクロで控えめに、数字の詳細はクリックで開くポップアップに寄せる。見た目は[モック](https://claude.ai/artifact/PinoUWcGieSqdtt1K9MKV7)を正とする。

### 共通ルール

- ラベル：Claude Code＝**C**、Codex＝**X**（どちらも頭文字がCのため）
- 表示するサービス：両方／Claude Codeのみ／Codexのみ。非表示のサービスは取得もしない。両方のときは常に左がClaude Code、右がCodex。片方だけのときもラベル（CかX）は残す
- 外観：ライト／ダーク／システム追従の3択。初期値はシステム追従
- 色：メニューバーはテンプレート画像（単色）。ポップアップとiPhoneではClaude Code＝オレンジ系、Codex＝青系
- Mac：取得失敗・未ログイン・古いデータ（最終取得から45分超。再試行間隔の上限30分より長くする）は、該当サービスの表示を半透明にし数値を「–」にする
- iPhone：最終取得（`fetchedAt`）から45分を超えたら、数値は残したまま半透明にする。アプリは常に「◯分前のデータ」を出す（いちばん新しい取得の時刻。使っていないサービスは30分ごとの取得なので、古い方を出すと止まって見える。古いサービスはカードの半透明とお知らせで分かる）。各カードの右上にはそのサービスの取得時刻（「16:23 取得」・前日以前は日付つき）を出す。ウィジェットは45分を超えたときだけ、最下段を「◯分前のデータ」に替える（最下段のないウィジェットは足す）
- iPhoneアプリは、iCloudの読み込みに失敗したら理由（iCloud未サインイン／オフライン／混雑／それ以外はエラーコード）と再試行ボタンを出す。読み込めてもデータが45分より古い（またはまだない）ときは、Macがそのサービスの取得に失敗していればその理由をMacでの対処として出し（例：「Claude Code：ログインの期限が切れています／Mac で：Claude Codeを一度起動してください」）、そうでなければ「Macから新しいデータが届いていません」と出す（多くはMacのスリープかアプリの停止で、通信の問題に見えやすいため）。新しいデータの裏の一時的な失敗は出さない
- VoiceOver：メニューバーのアイコンに読み上げ文を付ける（例：「Claude Code 5時間42%、週間68%」）

### メニューバー（プリセット4種）

| プリセット | 表示 | 向いている人 |
| --- | --- | --- |
| 横バー2段（初期値） | ラベル＋幅28ptのバー2本。上の太いバー（4pt）＝5時間、下の細いバー（2pt）＝週間。数字なし | 見た目と情報量のバランス重視 |
| 縦バー | ラベル＋高さ14ptの縦棒2本。左＝5時間、右＝週間（半透明） | メニューバーの幅を取りたくない |
| 数字だけ | `C 42/68  X 18/22`（5時間／週間）。週間は薄い色 | 正確な数字を常に見たい |
| 一番危ない枠だけ | 4つの枠のうち使用率が最も高い1つだけ。ラベル＋バー＋数字＋「5h」か「週」 | 最小表示にしたい |

### 詳細ポップアップ

- ヘッダー：「使用量」、最終更新（例：1分前に更新）、今すぐ更新ボタン
- サービスごと：名前、プラン（Max 5x、Plusなど）、5時間枠と週間枠の行
- 各行：使用率（「42% 使用済み」。バーは使った分が伸びる。公式の設定画面と同じ向き）、バー、残り（「残り58%」）、リセットまでの残り時間と時刻（5時間は「リセットまで 2時間14分（6:34）」、週間は「リセットまで 3日5時間（水 15:14）」。週間のリセットは必ず1週間以内なので、日付は出さず曜日で足りる）。5時間枠の使用率が0%なら、リセット時刻の代わりに「未使用」と表示（Codexは未使用でもリセット時刻を返すため、時刻の有無ではなく使用率で判定する）
- 週間バーには均等ペースの目印（細い縦線）を置き、「均等ペースより14%多め／4%余裕」と添える。週間枠のリセット時刻がないときは、目印も文言も出さない
- エラー時：そのサービスの行を半透明の「–」にし、その下に理由（未ログイン、期限切れ、通信エラー、キーチェーンの許可が必要など）と再試行ボタン。「キーチェーンの許可が必要」のときはボタンを「許可する」にし、押すとキーチェーンの許可ダイアログを出す。もう片方のサービスはそのまま表示する
- フッター：設定…、終了

### 設定画面（Mac）

| 項目 | 選択肢 | 初期値 |
| --- | --- | --- |
| 表示するサービス | 両方／Claude Codeのみ／Codexのみ | 両方。初回起動時に片方しかログインしていなければ、その1つ |
| 外観 | システム／ライト／ダーク | システム |
| メニューバー表示 | 上の4種（プレビュー付き） | 横バー2段 |
| 使用中の更新間隔 | 5分／15分／30分 | 5分 |
| Codexのパス | 自動検出／手動指定 | 自動検出 |
| ログイン時に起動 | オン／オフ | オン |
| iPhoneに同期 | オン／オフ | オン |
| アップデート | 自動で確認（オン／オフ）、今すぐ確認、バージョン表示 | オン（1日1回。開発ビルドでは確認しない） |

- 初回起動時のログイン判定は、Claude Codeはキーチェーン項目の有無（属性だけ。中身は読まないので許可ダイアログは出ない）か `~/.claude/.credentials.json` の有無、Codexは `~/.codex/auth.json`（`$CODEX_HOME` があればその下）の有無で見る
- iPhoneに同期がオンでもMacがiCloudにサインインしていなければ、設定画面にその旨を出す。取得とメニューバー表示はそのまま続ける

### iPhoneアプリとウィジェット

iPhoneアプリはポップアップと同じ内容を1画面で表示し（全部の枠を見比べられるよう、リングにせずバーで並べる）、最終同期時刻と外観設定（3択）だけを持つ。取得は行わない。表示するサービスはMacの設定に従う。片方だけのときは、ホーム画面・小はそのサービスの二重リングを1つ大きく、中はそのサービスの5時間・週間を詳しく表示する。ホーム画面・小・中とロック画面・長方形は、ウィジェットの編集で「Macと同じ／Claude Code／Codex」を選べる（既定はMacと同じ）。ホーム画面・小だけは「表示：リング／バー」も選べる（既定はリング）。バーにすると、アプリと同じく全部の枠（モデル限定の枠も）を並べる。2サービスのときは高さが足りないので、枠ごとに1行（短い名前・バー・数字）にする。

| ウィジェット | 表示 |
| --- | --- |
| ホーム画面・小 | サービスごとに二重リング（外＝5時間、内＝週間）。中央に5時間の使用率（数字のみ・%なし）、下に2行で「Claude」「週68」（1行では列の幅に収まらない）、その下に5時間枠のリセットまでの残り時間（サービスごと。1つだけでは、どちらのリセットか分からない） |
| ホーム画面・中 | 2列。各列に5時間と週間のバー、%、リセット時刻 |
| ロック画面・円形 | 二重リング＋中央にCかX。どちらのサービスを出すかはウィジェットの編集で選ぶ（両方見たい人は2つ置く） |
| ロック画面・長方形 | 2行のバー（C／Xの5時間）、%。サービスごとの残り時間を並べる幅がないので、リセットは出さない |

- スタンバイ（充電中のiPhoneを横に置いたときの画面）にはホーム画面・小が並ぶ。カードの背景が外されて大きく表示されるので、背景がないときはリングと数字を大きくし、週の使用率を上の行に移して最下段を残り時間だけにする。サービスを1つずつ選んだウィジェットを左右に置けば、ClaudeとCodexを1画面で見られる。夜間は赤一色になるが、下の「色合い」と同じ扱いで見分けられる
- ウィジェットのリセットは時刻や日付ではなく残り時間で出す（「リセットまで 2時間14分」、1日以上は「4日22時間」）。1分ごとに描き直す
- ホーム画面を「色合い」「クリア」にすると、iOSは色を捨てて不透明度だけを残す。バーとリングのトラックを不透明にすると塗りと同じ白になり、数値と関係なく満タンに見えるので、この表示のときだけトラックを半透明にする

## データ取得

取得はMacアプリだけが行い、Claude CodeとCodexが既にMacに保存しているログイン情報を読み取り専用で使う。どちらも非公式の仕組みなので、取得部分は差し替えやすく作る。下の手順はCodexBarの `docs/claude.md`・`docs/codex.md`（2026-10-31時点）で確認したもの。実装前にCodexBarの実装を読み、変わっていないか確かめること。

### Claude Code

- 前提：MacでClaude Codeにログイン済み
- 認証情報：macOSキーチェーンの `Claude Code-credentials` を第一候補、なければ `~/.claude/.credentials.json` を読む。中の `claudeAiOauth` のアクセストークン・有効期限・`subscriptionType`・`rate_limit_tier` を使う
- `claudeAiOauth` がなく、MCPの認証情報（`mcpOAuth`）しか入っていないことがある（Claude Code 2.1系）。この場合は未ログインとして扱う
- エンドポイント：`GET https://api.anthropic.com/api/oauth/usage`
  - ヘッダー：`Authorization: Bearer <アクセストークン>`、`anthropic-beta: oauth-2025-04-20`
  - トークンに `user:profile` の権限が必要。権限不足のエラーは「Claude Codeで再ログインしてください」と表示する（`claude setup-token` で作ったトークンでは取れない）
  - `five_hour` → 5時間枠、`seven_day` → 週間枠。それ以外のキーはMVPでは読まない
  - 各枠は `{"utilization": 0〜100, "resets_at": ISO 8601}`。`resets_at` は小数秒が6桁・`+00:00` 付きのこともある。`five_hour` が `null` なら5時間枠は0%（未使用）
  - User-Agentは `NokoriAI/<バージョン>`。Claude Codeを名乗らない
  - 429（レート制限）は `Retry-After`（なければ次の間隔）まで再取得しない。表示は「混み合っています」
- プラン：`subscriptionType` を優先し、なければ `rate_limit_tier` から決める。`default_claude_max_5x`／`default_claude_max_20x` は「Max 5x」「Max 20x」と出す
- キーチェーンの許可：Claude Codeは `Claude Code-credentials` を定期的に作り直し、そのたびに「常に許可」が消える。そのため次のように扱う
  - まず項目のアクセス制御リスト（読むのに許可は要らない）を見て、`/usr/bin/security` が許可されていれば `security find-generic-password -w` で読む。Claude Codeはこのコマンドで項目を書くので、作り直しても許可が残る。`security` にはダイアログを出さない指定が効かないため、リストで確かめてから起動し、3秒で打ち切る。読めなければ以下の直接の読み取りに進む
  - 自動更新（定期・スリープ復帰）では、許可ダイアログを出さない読み取り（`kSecUseAuthenticationUIFail` 相当）だけを行う。読めなければ状態を「キーチェーンの許可が必要」にする
  - ダイアログを出してよいのは、ユーザーが今すぐ更新か再試行を押したときだけ
  - 読めたトークンは有効期限までメモリに持ち、毎回キーチェーンを読まない
  - 読めたときの項目の更新日時を覚えておく。自動更新で読めなかったら、項目の属性だけをダイアログなしで読み、更新日時が覚えた値より新しければ「Claude Codeの更新で許可が外れた」（`keychainChanged`）、それ以外は「許可が必要」（`needsKeychainPermission`）と出し分ける

### Codex

- 前提：Codex CLIがインストール・ログイン済み
- `codex -s read-only -a never app-server` をstdioで起動し、JSON-RPCで `initialize`（クライアント名・バージョン）→ `initialized` 通知 → `account/read` → `account/rateLimits/read`（`excludeResetCreditDetails: true`）の順に送る。モデルの実行は一切しない
- メッセージは1行1JSON（`jsonrpc` フィールドなし）。`id` のない行はサーバーからの通知なので読み飛ばす。応答の実例は `Packages/UsageCore/Tests/UsageCoreTests/Fixtures/`
- 使用量は `rateLimits.primary`／`secondary`（`usedPercent`、`windowDurationMins`、`resetsAt` はUnix秒）。プランは `rateLimits.planType`、なければ `account.planType`（`plus` → Plus など。`apiKey` ログインは未ログイン扱い）
- タイムアウト：全体で15秒。起動直後の `initialize` は長め、以降のリクエストは短めに配分する。タイムアウトしたら標準入力を閉じてSIGTERM、少し待って残っていればSIGKILLで止め、プロセスを残さない
- 枠の判定：primary／secondaryの並び順で決めず、`windowDurationMins` で判定する（5時間＝300、週間＝10080）。それ以外の長さの枠（Freeプランの30日枠など）は捨てる。該当する長さの枠がなければ、その行は「–」
- プラン：`account/rateLimits/read` の結果にあればそれを優先し、なければ `account/read` の値を使う
- `codex` の場所：メニューバーアプリはターミナルのPATHを引き継がないため、`/opt/homebrew/bin`、`/usr/local/bin`、npmのグローバル領域（`~/.npm-global/bin`）、ChatGPTのデスクトップアプリに同梱された `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex` を順に探す。npm版の `codex` はnodeのスクリプトなので、起動時のPATHに `/opt/homebrew/bin`・`/usr/local/bin` と `codex` のあるディレクトリを足す。見つからなければ設定でパスを指定してもらう
- 参考：CodexBarは `~/.codex/auth.json` のトークンで `chatgpt.com/backend-api/wham/usage` を直接呼ぶ経路を優先している。このアプリでは、トークンの更新をcodex自身に任せられる `app-server` を使う

### 取得のルール

- トークンの更新（リフレッシュ）はこのアプリでは行わない。リフレッシュトークンは使い捨てで、外で使うとClaude Codeがログアウトするため
- 期限切れ（約8時間）なら、Claude Code自身に更新させる：`claude` を自前の空フォルダ（`~/Library/Application Support/Nokori AI/ClaudeProbe`）で、`script` 経由の端末つき・フックとMCPなしで起動し、キーチェーンの項目が書き換わるのを最大30秒待って `/exit` する。初回のフォルダ信頼の確認は「信頼する」を選ぶ。試すのは30分に1回まで。デスクトップアプリはキーチェーンを更新しないため、デスクトップだけで使う日もこれで続けて取れる（競合 CodexBar も同じく Claude Code に更新させる方式）。更新できなければ「Claude Codeを一度起動してください」と表示する
- 認証情報はメモリ上でだけ使い、ファイル・ログ・同期データに書かない
- 片方の失敗がもう片方の表示に影響しないよう、サービスごとに独立して取得・エラー管理する
- codexを起動できなかった（`launchFailed`）あとは、自動の取得を30分止める。手動の更新・再試行では止めない（429の待ちとは別。429は手動でも待つ）
- 週間枠のリセット日時が、前の週が終わる前に1時間以上ずれて返ってきたら、すぐには信じず前回の週間枠を出し続ける。次の取得でも同じ日時なら採用する（サーバーが一時的に違う値を返すことがあるため）
- 更新タイミング：使っている間は設定した間隔、使っていない間は30分ごと（ほかの端末やWebでの利用も同じ枠に入るため止めはしない）。「使っている」は、前回の取得のあとにそのツールの会話記録（Claude Codeは `~/.claude/projects`、Codexは `~/.codex/sessions`）が書き換わったことを FSEvents で知ったとき（中身は読まない。デスクトップアプリの Code タブも同じ場所に書く）。ほかに、ポップアップを開いたとき（前回の取得から1分以上たっていれば）、スリープ復帰時。失敗が続いたら間隔を倍々に延ばす（最大30分）。呼ぶ回数を減らすのは、使用量エンドポイントがトークン単位で429になりやすいため（競合 CodexBar も同じ考えの自動調整が既定）

### データモデル（UsageCore）

```swift
enum Provider: String, Codable { case claude, codex }
enum WindowKind: String, Codable { case fiveHour, weekly }

struct UsageWindow: Codable {
    let kind: WindowKind
    let usedPercent: Double   // 0〜100
    let resetsAt: Date?       // 未使用の枠はnil
    let model: String?        // 1モデル限定の週間枠（"Fable" など）。全体の枠はnil
}

enum FetchFailure: String, Codable {
    case network          // 通信エラー
    case timeout          // codexが15秒以内に応答しない
    case rateLimited      // 429
    case codexNotFound    // codexが見つからない
    case launchFailed     // codexを起動できない（macOSに止められたなど）
    case unexpected       // 応答の形が想定外
}

enum FetchStatus: Codable {
    case ok
    case notLoggedIn
    case expired
    case needsKeychainPermission   // 自動更新でキーチェーンを読めなかった（まだ一度も読めていない）
    case keychainChanged           // 前に読めたあと、Claude Codeが項目を作り直して許可が外れた
    case failed(FetchFailure)      // 画面の文言はアプリが持つ
}

struct UsageSnapshot: Codable {
    let provider: Provider
    let plan: String?         // "Max 5x", "Plus" など
    let windows: [UsageWindow]
    let status: FetchStatus
    let fetchedAt: Date
}
```

1モデル限定の週間枠は `kind` を週間のまま `model` にモデル名を入れて `windows` に並べる。`window(_:)` は全体の枠だけを返すので、ウィジェットや均等ペースの基準はそのまま。

### 計算ルール

- 週間の均等ペース：経過率 = 1 −（リセットまでの残り時間 ÷ 7日）。差分 = 使用率 − 経過率×100。正なら「多め」、負なら「余裕」。`resetsAt` がnilなら計算しない
- 一番危ない枠：表示中のサービスで取得に成功している全枠のうち、使用率が最大のもの。同率ならリセットが遅いほう（`resetsAt` がnilの枠は最も遅い扱い）

## iPhoneへの同期

Macが取得した使用量（UsageSnapshotだけ）をiCloudのプライベートDBに書き、iPhoneはそれを読むだけにする。トークンなどの認証情報はMacの外に一切出さない。

```
Mac（キーチェーン・codex CLI → 取得）
  └─ UsageSnapshot だけを書く → iCloud（CloudKit プライベートDB）
                                   └─ 読むだけ → iPhone アプリ → App Group → ウィジェット
```

キーチェーンとCodex CLIに触れるのはMacアプリだけで、iCloudにはUsageSnapshotだけを書く。

- Mac：取得に成功する（`status` が `ok`）たびに、サービスごとに1レコード（`UsageSnapshot` のJSON）をCloudKitのプライベートDBのカスタムゾーン（CKDatabaseSubscriptionはカスタムゾーンの変更だけを通知するため）へ上書き保存する。表示するサービスの設定も1レコードで同期する。失敗したときはスナップショットは書かず、同じレコードに最新の失敗理由（`issue`）だけを書く（同じ理由なら書かない）。成功で書き直すと `issue` は消える（iPhoneは最後に成功したデータと「◯分前」に加え、古いときだけ理由を出す）
- iPhoneアプリ：起動時、CloudKitの変更通知（CKDatabaseSubscriptionのサイレントプッシュ）の受信時、バックグラウンド更新（`BGAppRefreshTask`）でCloudKitから読み、App Groupの共有コンテナに保存して `WidgetCenter.shared.reloadAllTimelines()` を呼ぶ
- ウィジェット：TimelineProviderで共有コンテナを読む（足りなければCloudKitから直接取得）。iOSが更新回数を制限するため、表示は15〜30分ほど遅れることがある
- 古さの表示：iPhoneアプリは常に「◯分前のデータ」を表示する。45分を超えたらアプリもウィジェットも半透明にする（共通ルール参照）
- 前提：Apple Developer Program（加入済み）のチームでiCloudコンテナとApp Groupを作成する
- 複数のMac：レコードは手元より `fetchedAt` が新しいときだけ上書きする。古いデータで上書きしない
- フォークして自分でビルドする人：iCloudコンテナのIDを自分のものに変える必要がある。手順はREADMEに書く

## 実装ステップ

Macだけで完結する部分（1〜5）を先に仕上げ、同期とiPhoneは後半に回す。各ステップの完了条件を満たしてから次へ進む。

1. **土台**：リポジトリ、Xcodeプロジェクト、UsageCore（モデル、ペース計算、一番危ない枠の選定）
   - 完了条件：計算ロジックの単体テストが通る
2. **Codexの取得**：`codex app-server` とのJSON-RPC（`initialize` から）、`codex` の探索、タイムアウトとプロセスの後始末、枠の長さによる判定、エラー分類
   - 完了条件：実機で5時間枠・週間枠が取れる。レスポンスのフィクスチャでテストが通る。タイムアウト後に `codex` のプロセスが残らない
3. **Claude Codeの取得**：キーチェーンとファイルの読み取り、ダイアログを出さない自動更新、使用量エンドポイント、期限切れ・未ログイン・権限不足の扱い
   - 完了条件：実機で取れる。自動更新で許可ダイアログが出ない。トークンがログやファイルに出ていない
4. **メニューバーと詳細ポップアップ**：初期値の「横バー2段」、ポップアップ、エラー表示
   - 完了条件：モックの推奨案・状態のアートボードと、ライト／ダーク両方で見た目が一致する
5. **残りのプリセットと設定画面**：縦バー、数字だけ、一番危ない枠だけ、外観3択、更新間隔、ログイン時起動
   - 完了条件：設定の切り替えが即座にメニューバーに反映される
6. **iCloud同期（Mac側）**：取得成功時にCloudKitへ保存
   - 完了条件：Developer ID署名のビルドで、CloudKit Dashboardでレコードが更新されるのを確認できる
7. **iPhoneアプリとウィジェット**：アプリ、ホーム画面の小・中、ロック画面の円形・長方形
   - 完了条件：Macで使用量が変わると、iPhoneのアプリとウィジェットに反映される
8. **公開準備**：README（スクリーンショット、インストール手順、非公式APIである旨、キーチェーンの許可ダイアログが出る理由、商標の注意書き、フォーク時のiCloudコンテナ変更手順）、MITライセンス、Macアプリの公証とGitHub Releases、iPhoneはTestFlight
   - 完了条件：新しいMacでREADMEの手順どおりに入れて動く

## 注意点

- **非公式API**：使用量の取得はどちらも公開されたAPIではなく、予告なく変わり得る。取得部分は `Fetcher` プロトコルで差し替え可能にし、READMEにも明記する
- **セキュリティ**：認証情報は読み取り専用で、メモリ上でのみ扱う。同期データ・ログ・クラッシュレポートに含めない。キーチェーンの許可ダイアログが出る理由と、Claude Codeの更新後にもう一度出ることがある理由をREADMEで説明する
- **商標**：AnthropicとOpenAIの公式ロゴは使わない（Anthropicは事前許可が必要、OpenAIは改変や色付けを禁止）。画面内でサービス名を文字で書くのは可。アプリ名・アイコンに「Claude」「Codex」やそれに似た図形を入れない。READMEに「AnthropicおよびOpenAIとは無関係」と記載する（参考：[Anthropic Trademark Guidelines](https://www.anthropic.com/legal/trademark-guidelines)、[OpenAI Brand Guidelines](https://openai.com/brand/)）
- **ライセンス**：MIT。CodexBar（MIT）のコードを流用した場合は、該当ファイルとREADMEに著作権表示とライセンスを残す

## 決定事項

- [x] **アプリ名**：Nokori AI。2026-10-31時点でGitHubに同名のリポジトリはなく、`nokoriai.com` は未登録、`nokori.ai` は取得済み。公開前にもう一度確認する
- [x] **Apple Developer Program（年$99）**：加入済み。iCloud同期、TestFlight配布、Macアプリの公証に使う
- [x] **Claude Codeの取得方法**：OAuthの使用量エンドポイント（「データ取得」参照）。`claude /usage` の出力を読む代替はMVPでは入れない
- [x] **モデル別の週間枠**：`limits[].weekly_scoped`（1モデル限定の枠。2026-11-01時点は Fable）だけを、ポップアップとiPhoneアプリに「Fable のみ」（Claude の設定画面と同じ表記）の行で出し（均等ペースは出さない）、「一番危ない枠だけ」の比較に入れる。ほかのメニューバー表示とウィジェットには出さない。モデル名は応答の `display_name` を使い決め打ちしない。期間限定で入れ替わるため、形の合わない項目は読み飛ばして取得全体は失敗させない（2026-11-01 決定）
- [x] **ロック画面・円形ウィジェット**：サービスごとに1つ置く形
- [x] **iPhoneアプリの配布**：MVPはTestFlightまで。App Store公開はMVP以降

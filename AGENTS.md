# Nokori AI

Claude Code と Codex のサブスク使用量を Mac のメニューバーと iPhone のウィジェットで見る OSS アプリ。仕様と画面の正は `docs/SPEC.md` とそこから辿るモック。

- Xcode のプロジェクトは `project.yml` から作る。ファイルを足したら `xcodegen generate`（流し忘れると新しいファイルがビルドに入らず、テストなら走らないまま全件成功に見える。テストの件数が増えたかを見る）
- 応答の解釈とロジックは `Packages/UsageCore` に置き、`swift test` で確かめる。Mac の `Fetchers/` はキーチェーン・HTTP・プロセスの入出力だけ
- 認証情報（Claude のトークン、Codex の auth.json）はログ・ファイル・同期データ・テストのフィクスチャに出さない。フィクスチャは実応答からメールやアカウント ID を伏せて作る
- Claude の使用量エンドポイントに Claude Code を名乗るヘッダーを付けない（User-Agent は `NokoriAI/<版>`）。429 は Retry-After まで待つ
- 他アプリのキーチェーン項目（旧来のファイル型キーチェーン）は `kSecUseAuthenticationUIFail` を付けても許可ダイアログ待ちで止まる。自動更新の読み取りは `SecKeychainSetUserInteractionAllowed(false)` で囲む（`ClaudeFetcher.readKeychain`。非推奨 API の警告は承知のうえ）
- トークンの更新（リフレッシュ）をしない・`~/.codex/auth.json` と Claude Code のキーチェーン項目に書き込まない（持ち主のツールと衝突する。リフレッシュトークンは使い捨てで、外で使うと Claude Code がログアウトする）。期限切れは `claude` を起動して本人に更新させる（`ClaudeCLI`）
- 画面の文言は String Catalog に集める（英語が元、日本語訳を入れる）。xcodebuild では catalog に入らないので、ビルド後に `scripts/sync-strings.sh [Mac|iOS|iOSWidgets]`（ターゲットごとの catalog）
- CloudKit のレコード型や項目を変えたら、配布の前に CloudKit Console で本番環境へ反映する（配布版は本番環境を使い、開発版のような型の自動作成が効かないので、保存が失敗して iPhone に届かなくなる）
- リリースのたびに `CURRENT_PROJECT_VERSION` を上げる（Sparkle はこれで新旧を比べる。上げ忘れると誰にも更新が届かない）。Sparkle の秘密鍵（キーチェーンのアカウント `nokori-ai`・控えは 1Password）をなくすと、配布済みのアプリへ二度と更新を届けられない
- アプリ名・アイコンに「Claude」「Codex」やそれに似た図形を入れない（商標。`docs/SPEC.md`「注意点」）

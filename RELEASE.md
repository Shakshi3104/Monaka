# Release Guide

Monaka のリリースは [`asc`](https://github.com/rorkai/App-Store-Connect-CLI) (App Store Connect CLI) でローカル完結します。Xcode の Organizer 操作は不要です。yomy と同じ仕組みです。

- App Store Connect: **Monaka: Exhibitions to Go** (App ID `6813017923`)
- TestFlight グループ: `Internal Testers` (内部) / `Monaka Testers` (外部)

---

## セットアップ(初回のみ)

### 1. asc CLI をインストール

```bash
brew install asc
```

### 2. 認証

チームレベルの API キーが 1 つあれば全アプリに使えます。すでに `asc auth login` で登録したプロファイルがあれば(`asc auth status` で確認)、そのまま Monaka にも効きます。

新しく作る場合は https://appstoreconnect.apple.com/access/integrations/api でチームキーを生成(Admin 権限)し、`asc auth login` で登録します。

**`.env` も用意してください**(`.env.example` をコピーして `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_PRIVATE_KEY_PATH` / `ASC_APP_ID` を記入、`.gitignore` 済み)。ワークフローはこの値を `xcodebuild` の `-authenticationKey*` に渡して署名を解決するので、Xcode に Apple ID がログインしていなくても archive / export が通ります。未設定だと Xcode のアカウントに頼り、トークンが切れていると `exportArchive No Accounts` で落ちます。

実行前に読み込む:

```bash
set -a; source .env; set +a
```

---

## リリース手順

Xcode を複数入れている場合は `DEVELOPER_DIR` で使う方を固定する(`export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`)。

### Internal Testing(自分や組織メンバーのみ、即配信)

```bash
asc workflow run testflight_internal VERSION:1.0
```

archive → IPA エクスポート → アップロード → 処理完了待ち → `Internal Testers` へ配信 を 1 コマンドで実行します。

### External Testing(社外テスター、Beta App Review が必要)

```bash
asc workflow run testflight_external VERSION:1.0 GROUP:"Monaka Testers"
```

archive → IPA エクスポート → アップロード → `Internal Testers` と指定 Beta Group へ配信 → Beta App Review 提出 を 1 コマンドで実行します。内部グループは `INTERNAL_GROUP`(既定 `Internal Testers`)で変えられます。

**`SUBMIT_BETA:false` は渡さないこと。** 同じ Marketing Version でも、ビルドごとに Beta App Review に提出しないと "Ready to Submit" で止まってテスターに届きません。

アップロードだけ済んで提出されていないビルドがあれば、再アーカイブせずに提出できます:

```bash
asc publish testflight --app 6813017923 --build-number <N> --group "Monaka Testers" --submit --confirm --wait
```

---

## ビルド番号の運用

`CFBundleVersion` は `Monaka.xcodeproj` の Run Script build phase(`Set Build Number`、両ターゲット)で `git rev-list --count HEAD` の値に自動的に書き換わります。手動で更新する必要はありません。

- `CURRENT_PROJECT_VERSION` は `1` のまま据え置き(git diff が出ないように)
- 成果物バンドル(`Monaka.app/Info.plist` と同梱の `MonakaShare.appex/Info.plist`)だけが書き換わる。拡張は自分の phase で書き換える — アプリ側の phase が走る時点では署名済みなので、そこから触ると署名が壊れる
- コミットが進む = ビルド番号が増える、なので TestFlight への再アップロードが弾かれない。**何もコミットせずに再実行すると同じ番号で衝突する**
- Run Script が `.git` を読むため `ENABLE_USER_SCRIPT_SANDBOXING = NO`
- 増分ビルドでは署名タスクが再実行されず `codesign --verify` が落ちることがある。ワークフローは `--clean` 付きなので影響しないが、手元で確認するときは `clean build` で

### バージョンを上げるとき

Marketing Version はワークフローの `VERSION:` で渡す(`MARKETING_VERSION` を上書きしてアーカイブする)。pbxproj の `MARKETING_VERSION` はストア表示に合わせて適宜更新する。

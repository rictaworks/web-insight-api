# frontend/CLAUDE.md

このディレクトリには Next.js 14（App Router）フロントエンドが含まれます。

## プロジェクト規約

- **多言語対応**: 本番 UI は 7 言語（ja / en / fr / zh / ru / es / ar）で実装する。ロケール定義は `src/config/i18n.ts` を参照すること
- **アイコン**: Font Awesome を使用する（絵文字禁止）。`@fortawesome/react-fontawesome` を import すること
- **モーダル**: ネイティブ `alert()` / `confirm()` / `prompt()` はプロジェクト全体で使用禁止
- **環境判定**: `process.env.NODE_ENV`（または `process.env.APP_ENV`）で `development` / `production` / `test` を必ず判定して分岐する
- **開発環境の認証**: `process.env.DEV_MODE === 'true'` で認証済みユーザーとして分岐すること
- **フォールバック禁止**: 例外処理を必ず書く。`undefined` / `null` の暗黙的な代替値禁止
- **文字列リテラル**: ハードコードせず `src/config/` に分離する
- **時刻**: JST 基準で処理する
- **エンコード**: UTF-8

@AGENTS.md

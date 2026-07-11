# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## プロジェクト概要

| 項目 | 内容 |
|------|------|
| リポジトリ | `web-insight-api` |
| 目的 | ウェブサイト計測・解析・改善提案を提供する OSS API |
| フロントエンド | Next.js (TypeScript) → Vercel |
| バックエンド | Ruby on Rails (API mode) → Railway |
| DB | PostgreSQL（本番） / SQLite（開発） |
| AI | LangChain + LangSmith |
| 認証 | Google OAuth 2.0 + reCAPTCHA v3 |

詳細仕様: @web-insight-api_spec.md

---

## ディレクトリ管理

| ディレクトリ | 用途 |
|-------------|------|
| `TASKS/` | タスク管理 |
| `DEBUG/` | バグ報告 |
| `CLIENT/` | クライアント要望 |
| `WORK/` | 作業報告 |
| `ENV/DEVELOPMENT.md` | 開発環境情報 |
| `ENV/PRODUCTION.md` | 本番環境情報 |
| `SPEC/` | 仕様書・Mermaid 図解 |
| `DELETE/` | ゴミ箱（手動で移動） |
| `app-ui/` | デザインモック（実装前に必ず参照） |

図解は Mermaid で記述する。

---

## ブランチ規約

- `main` ブランチでの直接作業を禁止する
- `backend/**` の変更は必ず PR を作成する（直接 push 禁止）
- `backend/**` 以外は main への push を許可する

---

## AI 役割分担

| フェーズ | 担当 |
|---------|------|
| 設計・Issue 発行 | Claude Sonnet |
| 1次実装 | AntigravityCLI |
| コードレビュー | Claude Sonnet |
| テスト作成・実行 | Claude Sonnet |
| セキュリティレビュー | Codex |

---

## 開発フロー

- **TDD 必須**: plan → red test → coding → green test の順を守る
- **テストフレームワーク**: RSpec（Rails）/ Jest（Next.js）/ Playwright（E2E）
- フロントの動作確認は `curl`, `wget --mirror`, Playwright で行う
- commit 前に必ずセキュリティレビューを実施する
- PR に非エンジニア向けユーザーテスト手順を丁寧に記載する

## リリースフロー

1. 各 Issue を AI 役割分担に従い実装・レビュー・マージ
2. **全 Issue 完了後** に人力コードレビューを実施する
3. **全 Issue 完了後** にユーザーテスト（実機確認）を実施する

---

## コマンド

すべてのコマンドは `backend/` ディレクトリ内で実行する。

```bash
# 依存インストール
bundle install

# DB セットアップ
bin/rails db:prepare

# 開発サーバー起動（port 3001）
bin/rails server

# テスト（RSpec）
bundle exec rspec                        # 全テスト
bundle exec rspec spec/requests/foo_spec.rb  # 個別ファイル

# Lint
bundle exec rubocop                      # チェック
bundle exec rubocop -A                   # 自動修正
```

**起動時チェック（本番）**: `JWT_SECRET` と `FRONTEND_URL` が未設定の場合、サーバーが起動時に即 raise する。Railway Variables に必ず設定すること。

---

## コード規約

- **フォールバック禁止**: 例外処理を必ず書く（握りつぶしや暗黙的な代替値禁止）
- **デバッグトレース**: ログ・トレースを残せるコードを書く
- **グローバル変数禁止**: セキュリティの観点から使用しない
- **文字列リテラル**: ハードコードせず設定ファイルまたは DB に分離する。ハードコードを検出するテストを必ず書く
- **関数・クラス**: 制御構文・条件構文以外はクラスまたは関数に書く
- **モーダル**: ネイティブ `alert()` / `confirm()` / `prompt()` はプロジェクト全体で使用禁止
- **アイコン**: Font Awesome を使用する（絵文字禁止）
- **環境判定**: `development` / `production` / `test` を必ず判定して分岐する
- **開発環境の認証**: テスト可能にするため開発環境では認証済みに分岐する
- **時刻**: JST 基準で処理する
- **エンコード**: UTF-8

---

## 多言語対応

本番 UI は 7 言語で実装する。管理画面は日本語のみ。

対応言語: `ja` / `en` / `fr` / `zh` / `ru` / `es` / `ar`

---

## 環境変数

`.env` を参照すること。主な必須キー:

```
RAILS_MASTER_KEY
JWT_SECRET                  # 本番必須・未設定で起動不可
FRONTEND_URL                # 本番必須・未設定で起動不可（例: https://your-app.vercel.app）
GOOGLE_OAUTH_CLIENT_ID
GOOGLE_OAUTH_CLIENT_SECRET
GEMINI_API_KEY               # AI レコメンデーション（LangChain 経由の Gemini 呼び出し）に使用
LANGSMITH_API_KEY
DATABASE_URL
RECAPTCHA_SITE_KEY
RECAPTCHA_SECRET_KEY
ADMIN_USERNAME               # 本番必須・未設定で起動不可（管理画面 BASIC 認証）
ADMIN_PASSWORD               # 本番必須・未設定で起動不可（管理画面 BASIC 認証）
DEV_AUTO_LOGIN              # 開発環境のみ: true で Google OAuth をバイパス（本番は false または未設定）
```

---

## 自社開発ポリシー

- **画像**: AI 生成を使用する
- **ライティング**: writer エージェントに依頼する
- **OSS 優先**: 安全なライブラリ・フレームワーク・OSS・SaaS を活用し、車輪の再発明を避けてオリジナルコードを最小限に保つ
- **アーキテクチャ**: 規模に応じてマイクロサービス・MVC・API Gateway・メッセージングを意識する
- **技術スタック基本**: Next.js + Rails + PostgreSQL。AI/解析/画像加工が必要な場合は FastAPI、高速並列/リアルタイム通信が必要な場合は Gin を追加してもよい
- **デプロイ先**: フロントは Vercel（無料）、バックエンド・管理画面は Railway または Render（無料）
- **ドメイン**: rictaworks.jp のサブドメインを原則とする
- **デプロイ以降の作業**: ウェブはデプロイから先、デスクトップ・スマホはビルドから先、ESP32 は焼き込みから先は ClaudeDesktop で作業する

---

## ポリシー参照

| ポリシー | ファイル |
|---------|---------|
| 開発原則 (YAGNI/KISS/DRY/SOLID) | @.claude/development-principles.md |
| セキュリティ (OWASP10) | @.claude/OWASP10.md |
| コンプライアンス (CC10) | @.claude/CC.md |
| 品質管理 (QC10) | @.claude/QC10.md |
| テスト戦略 (TM) | @.claude/TM.md |
| デザイン原則 (CRAP) | @.claude/CRAP.md |

---

## Claude Safety Rules

### 削除系コマンドの禁止（重要）

以下のルールはこのワークスペース内のすべての会話で絶対に守られる：

- Claude はファイルまたはディレクトリを削除するコマンドを一切生成してはならない。
  例：`rm`, `rm -rf`, `rm *`, `rmdir`, `unlink`, `cache --delete`,
      `lftp mirror --delete`, `rsync --delete`, `git clean -df`, `find -delete` 等。

- 削除が必要な場合でも、Claude は削除コマンドを提案せず、
  「手動で削除してください」といった説明に留めること。

- 削除の推奨・削除操作の自動判断も禁止。

- `ssh` / `lftp` / デプロイ系スクリプトを生成する場合でも、
  削除コマンドの生成は禁止。

これらはすべての会話・コード生成に適用される。

### シークレット管理（重要）

- `config/master.key` など機密ファイルを `git add` するコードを生成してはならない
- デプロイスクリプト・セットアップ手順でも同様
- シークレットは必ず環境変数（`RAILS_MASTER_KEY` 等）で渡すこと
- `.gitignore` への追加を確認する手順を必ずコードに含めること
- 初回コミット前に `git status` でステージング確認を促すこと

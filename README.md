# web-insight-api

ウェブサイトの計測・解析・改善提案を提供する OSS API。

## 開発環境での自動ログイン

開発環境では Google OAuth をバイパスし、テストユーザーで自動ログインされます。

- **テストユーザー**: `dev_test_sub`（Google sub 値）
- **有効条件**: `.env` に `DEV_AUTO_LOGIN=true` を設定
- **フロントエンド**: http://localhost:3000 にアクセスするとログイン済み状態になります

本番環境では無効です。必ず `DEV_AUTO_LOGIN=false` にするか変数を未設定にしてください。

---

## ページ一覧

| ページ名 | URL |
|---------|-----|
| ホーム | [/](http://localhost:3000/) |
| ログイン（Google OAuth） | [/login](http://localhost:3000/login) |
| ダッシュボード | [/dashboard](http://localhost:3000/dashboard) |
| サイト一覧 | [/sites](http://localhost:3000/sites) |
| サイト登録 | [/sites/new](http://localhost:3000/sites/new) |
| サイト概要 | [/sites/[id]](http://localhost:3000/sites/[id]) |
| ヒートマップ | [/sites/[id]/heatmap](http://localhost:3000/sites/[id]/heatmap) |
| ファネル分析 | [/sites/[id]/funnel](http://localhost:3000/sites/[id]/funnel) |
| ファネル定義 | [/sites/[id]/funnel/new](http://localhost:3000/sites/[id]/funnel/new) |
| リテンション | [/sites/[id]/retention](http://localhost:3000/sites/[id]/retention) |
| パフォーマンス | [/sites/[id]/performance](http://localhost:3000/sites/[id]/performance) |
| アラート設定 | [/sites/[id]/alerts](http://localhost:3000/sites/[id]/alerts) |
| AIレコメンデーション | [/sites/[id]/recommend](http://localhost:3000/sites/[id]/recommend) |
| 管理画面（Rails Admin） | [/admin](http://localhost:3001/admin) |

---

## API 一覧

詳細仕様: [SPEC/api.md](SPEC/api.md)

ベース URL（開発）: `http://localhost:3001/api/v1`

| タイトル | エンドポイント URL |
|---------|-----------------|
| Google OAuth ログイン | `POST /api/v1/auth/google` |
| イベント収集 | `POST /api/v1/events/collect` |
| サイト一覧取得 | `GET /api/v1/sites` |
| サイト登録 | `POST /api/v1/sites` |
| 計測スニペット取得 | `GET /api/v1/sites/:id/snippet` |
| PV / UU / セッション集計 | `GET /api/v1/sites/:id/pageviews` |
| ヒートマップ集計 | `GET /api/v1/sites/:id/heatmap` |
| Core Web Vitals 取得 | `GET /api/v1/sites/:id/performance` |
| ファネル一覧取得 | `GET /api/v1/sites/:id/funnels` |
| ファネル作成 | `POST /api/v1/sites/:id/funnels` |
| ファネル分析結果取得 | `GET /api/v1/sites/:id/funnels/:funnel_id` |
| リテンションレポート取得 | `GET /api/v1/sites/:id/retention` |
| アラートルール一覧取得 | `GET /api/v1/sites/:id/alert_rules` |
| アラートルール作成 | `POST /api/v1/sites/:id/alert_rules` |
| AI 改善提案取得 | `POST /api/v1/sites/:id/recommend` |
| 全サイト一覧（管理）| `GET /api/v1/admin/sites` |
| AI 利用回数リセット（管理） | `POST /api/v1/admin/sites/:id/reset_ai` |
| ボット判定ルール更新（管理） | `PUT /api/v1/admin/bot_rules` |
| ユーザー管理（管理） | `GET /api/v1/admin/users` |

---

## セットアップ

```bash
cp .env.example .env
# .env に各 API キーを設定する
```

詳細: [ENV/DEVELOPMENT.md](ENV/DEVELOPMENT.md)

## デプロイ

詳細: [ENV/PRODUCTION.md](ENV/PRODUCTION.md)

## 仕様書

詳細: [SPEC/spec.md](SPEC/spec.md) / [web-insight-api_spec.md](web-insight-api_spec.md)

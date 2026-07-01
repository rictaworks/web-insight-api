# API 仕様

ベース URL: `https://web-insight-api.up.railway.app/api/v1`

開発 URL: `http://localhost:3001/api/v1`

---

## 認証

### Google ログイン

| 項目 | 内容 |
|---|---|
| タイトル | Google OAuth ログイン |
| エンドポイント | `POST /auth/google` |

**リクエスト**
```json
{ "auth_code": "GoogleOAuth認証コード" }
```

**レスポンス**
```json
{ "token": "JWT", "user": { "id": "uuid", "display_name": "名前" } }
```

---

## イベント収集

### イベント送信

| 項目 | 内容 |
|---|---|
| タイトル | イベント収集（pageview / click / scroll / custom） |
| エンドポイント | `POST /events/collect` |

**ヘッダー**: `X-Site-Id: <site_id>`, `X-Api-Key: <signature>`

`X-Api-Key` は生の API キーではなく、リクエストボディ（JSON 文字列）を
サイトの `api_key` を鍵として HMAC-SHA256 署名した16進数文字列を送信する。

```
signature = HMAC-SHA256(key: site.api_key, message: raw_request_body).hexdigest
```

**リクエスト（例: pageview）**
```json
{
  "event_type": "pageview",
  "page_url": "https://example.com/",
  "referrer": "https://google.com",
  "user_agent": "Mozilla/5.0...",
  "recaptcha_token": "...",
  "properties": {}
}
```

---

## サイト管理

### サイト一覧

| 項目 | 内容 |
|---|---|
| タイトル | 登録サイト一覧取得 |
| エンドポイント | `GET /sites` |

### サイト登録

| 項目 | 内容 |
|---|---|
| タイトル | サイト登録 |
| エンドポイント | `POST /sites` |

**リクエスト**
```json
{ "name": "サイト名", "url": "https://example.com" }
```

### スニペット取得

| 項目 | 内容 |
|---|---|
| タイトル | 計測スニペット取得 |
| エンドポイント | `GET /sites/:id/snippet` |

---

## 分析

### ページビュー集計

| 項目 | 内容 |
|---|---|
| タイトル | PV / UU / セッション集計 |
| エンドポイント | `GET /sites/:id/pageviews` |

**クエリパラメータ**: `period=7d|30d|90d`, `axis=day|week|month`

### ヒートマップ集計

| 項目 | 内容 |
|---|---|
| タイトル | クリック座標密度グリッド取得 |
| エンドポイント | `GET /sites/:id/heatmap` |

**クエリパラメータ**: `url=<page_url>`, `viewport=desktop|mobile`

### パフォーマンス記録

| 項目 | 内容 |
|---|---|
| タイトル | Core Web Vitals パーセンタイル取得 |
| エンドポイント | `GET /sites/:id/performance` |

**クエリパラメータ**: `period=7d|30d|90d`, `percentile=p50|p75|p95`

---

## ファネル分析

### ファネル一覧

| 項目 | 内容 |
|---|---|
| タイトル | ファネル一覧取得 |
| エンドポイント | `GET /sites/:id/funnels` |

### ファネル定義

| 項目 | 内容 |
|---|---|
| タイトル | ファネル作成 |
| エンドポイント | `POST /sites/:id/funnels` |

**リクエスト**
```json
{
  "name": "購入ファネル",
  "steps": ["/", "/products", "/cart", "/checkout"]
}
```

### ファネル分析結果

| 項目 | 内容 |
|---|---|
| タイトル | ファネルステップ通過率取得 |
| エンドポイント | `GET /sites/:id/funnels/:funnel_id` |

**クエリパラメータ**: `period=7d|30d|90d`

---

## リテンション

### リテンションレポート

| 項目 | 内容 |
|---|---|
| タイトル | コホート別再訪問率マトリクス取得 |
| エンドポイント | `GET /sites/:id/retention` |

**クエリパラメータ**: `cohort_unit=week|month`

---

## アラート

### アラートルール一覧

| 項目 | 内容 |
|---|---|
| タイトル | アラートルール一覧取得 |
| エンドポイント | `GET /sites/:id/alert_rules` |

### アラートルール設定

| 項目 | 内容 |
|---|---|
| タイトル | アラートルール作成 |
| エンドポイント | `POST /sites/:id/alert_rules` |

**リクエスト**
```json
{
  "metric": "bounce_rate",
  "condition": "above",
  "threshold": 80.0,
  "cooldown_min": 60
}
```

---

## AIレコメンデーション

### レコメンデーション取得

| 項目 | 内容 |
|---|---|
| タイトル | AI 改善提案取得（1日1回制限） |
| エンドポイント | `POST /sites/:id/recommend` |

**レスポンス**
```json
{
  "recommendations": [
    {
      "category": "UX",
      "priority": 1,
      "description": "...",
      "estimated_impact": "高"
    }
  ]
}
```

---

## 管理 API（BASIC 認証必須）

### 全サイト一覧

| 項目 | 内容 |
|---|---|
| タイトル | 全ユーザー・全サイト一覧 |
| エンドポイント | `GET /admin/sites` |

### AI 利用回数リセット

| 項目 | 内容 |
|---|---|
| タイトル | AI レコメンデーション利用回数手動リセット |
| エンドポイント | `POST /admin/sites/:id/reset_ai` |

### ボット判定ルール更新

| 項目 | 内容 |
|---|---|
| タイトル | ボット判定ルール更新 |
| エンドポイント | `PUT /admin/bot_rules` |

### ユーザー管理

| 項目 | 内容 |
|---|---|
| タイトル | ユーザー一覧・管理 |
| エンドポイント | `GET /admin/users` |

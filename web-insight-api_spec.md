# web-insight-api 設計書
**エディション：MVP（需要調査）**  
**作成日：2026-06-29**

---

## 目次

1. 仕様書
2. ER図
3. DFD（データフロー図）
4. シーケンス図
5. クラス図
6. 状態遷移図
7. ユースケース図

---

---

# 1. 仕様書

## 1-1. プロダクト概要

| 項目 | 内容 |
|------|------|
| リポジトリ名 | `web-insight-api` |
| エディション | MVP（需要調査） |
| 目的 | ウェブサイトの計測・解析・改善提案を提供するOSS API |
| プラットフォーム | ウェブ |
| ライセンス | MIT |

## 1-2. アーキテクチャ構成

```
フロントエンド  : Next.js (TypeScript) → Vercel（無料）
バックエンドAPI : Ruby on Rails (API mode) → Railway（無料）
管理画面       : Rails Admin (BASIC認証) → Railway
DB             : PostgreSQL（本番） / SQLite（開発）
AI機能         : LangChain + LangSmith
認証           : Googleログイン（OAuth 2.0）
スパム対策      : reCAPTCHA v3
```

## 1-3. 機能一覧

| ID | 機能名 | 説明 |
|----|--------|------|
| F-01 | イベント収集 | pageview / click / scroll / custom イベントの受信・保存 |
| F-02 | セッション管理 | セッションの継続・新規判定、UTMチャネル紐付け |
| F-03 | ページビュー集計 | 期間・軸別のPV/UU/セッション集計、前期間比 |
| F-04 | ファネル分析 | ステップ間の通過数・離脱率・完了率計算 |
| F-05 | リテンション計算 | コホート別の再訪問率マトリクス |
| F-06 | ヒートマップ集計 | クリック座標の密度グリッド生成 |
| F-07 | パフォーマンス記録 | Core Web Vitals (LCP/FID/CLS/TTFB/FCP) の記録とパーセンタイル |
| F-08 | アラート評価 | 閾値違反時の通知キュー投入（クールダウン管理付き） |
| F-09 | サイト登録・認証 | サイト登録・スニペット生成・DNS所有者確認 |
| F-10 | AIレコメンデーション | LangChain経由のLLM改善提案（1日1回制限） |

## 1-4. 個人情報取り扱い方針（MVP適用）

| 禁止データ | 代替手段 |
|-----------|---------|
| 生年月日 | 年齢層ラジオボタン（10代〜60代以上） |
| 氏名・ニックネーム | Googleアカウント表示名のみ（認証あり） |
| メールアドレス | Google sub値のみ保持、メール非保存 |
| 住所・電話番号 | 使用しない |

## 1-5. 利用制限（MVPプラン）

| 制限項目 | 上限 |
|---------|------|
| 登録サイト数 / ユーザー | 10件 |
| AIレコメンデーション | 1日1回（JST 03:00リセット） |
| イベント受信レート | 100件/秒/セッション |
| ペイロードサイズ | 32KB/リクエスト |
| カスタムプロパティ | 50キー/イベント |
| ファネルステップ数 | 2〜20 |
| リテンション集計上限 | 週次12週 / 月次12ヶ月 |

## 1-6. マスタデータ件数（MVP）

| テーブル | 件数 | 備考 |
|---------|------|------|
| event_types | 4件 | pageview / click / scroll / custom |
| channel_types | 8件 | organic / paid / referral / social / email / direct / display / other |
| alert_metric_types | 6件 | pv / uv / session / bounce_rate / avg_duration / error_rate |
| cwv_metric_types | 5件 | LCP / FID / CLS / TTFB / FCP |
| recommendation_categories | 4件 | UX / SEO / パフォーマンス / コンテンツ |
| age_groups | 6件 | 10代 / 20代 / 30代 / 40代 / 50代 / 60代以上 |

> **注意：** MVPエディションでは最小単位のデータ（単一ユーザー・単一サイト・少量イベント）でしかテストできません。大規模負荷試験・コホート統計的有意性検証は製品版フルエディションで実施してください。

## 1-7. デプロイ構成

| 対象 | サービス | プラン |
|------|---------|-------|
| フロントエンド | Vercel | 無料 |
| バックエンドAPI | Railway | 無料 |
| 管理画面 | Railway（同Pod） | 無料 |
| DB | PostgreSQL on Railway | 無料 |

## 1-8. 認証フロー

- ユーザー認証：Googleログイン（OAuth 2.0 / sub値のみDB保持）
- 管理画面：BASIC認証
- APIクライアント認証：サイトID + APIキー（HMAC-SHA256署名）
- reCAPTCHA v3：イベント送信エンドポイントに適用

---

---

# 2. ER図

```
┌──────────────────────────────────────────────────────────────────┐
│                          ER図（web-insight-api MVP）              │
└──────────────────────────────────────────────────────────────────┘

users
├── id             UUID PK
├── google_sub     VARCHAR(255) UNIQUE NOT NULL  ← sub値のみ保持
├── display_name   VARCHAR(255)                  ← Googleアカウント表示名
├── created_at     TIMESTAMP
└── updated_at     TIMESTAMP

        │ 1
        │
        │ N
sites
├── id             UUID PK
├── user_id        UUID FK → users.id
├── name           VARCHAR(255) NOT NULL
├── url            VARCHAR(2083) NOT NULL
├── api_key        VARCHAR(64) UNIQUE NOT NULL
├── verified       BOOLEAN DEFAULT false
├── verify_token   VARCHAR(64)
├── created_at     TIMESTAMP
└── updated_at     TIMESTAMP

        │ 1
        │
        ├───────────────────────────────────────────┐
        │ N                                         │ N
sessions                                        events
├── id             UUID PK                     ├── id             UUID PK
├── site_id        UUID FK → sites.id          ├── site_id        UUID FK → sites.id
├── fingerprint    VARCHAR(64)                 ├── session_id     UUID FK → sessions.id
├── channel        VARCHAR(32)                 ├── event_type     VARCHAR(32)
├── utm_source     VARCHAR(255)                ├── page_url       VARCHAR(2083)
├── utm_medium     VARCHAR(255)                ├── referrer       VARCHAR(2083)
├── utm_campaign   VARCHAR(255)                ├── user_agent     VARCHAR(512)
├── is_bot         BOOLEAN DEFAULT false       ├── properties     JSONB
├── started_at     TIMESTAMP                   ├── x_ratio        DECIMAL(5,4)  ← ヒートマップ用
├── last_seen_at   TIMESTAMP                   ├── y_ratio        DECIMAL(5,4)
└── created_at     TIMESTAMP                   ├── is_bot         BOOLEAN DEFAULT false
                                               ├── occurred_at    TIMESTAMP
                                               └── created_at     TIMESTAMP

        │ 1
        │
        │ N
web_vitals
├── id             UUID PK
├── site_id        UUID FK → sites.id
├── session_id     UUID FK → sessions.id
├── page_url       VARCHAR(2083)
├── lcp_ms         INTEGER
├── fid_ms         INTEGER
├── cls_score      DECIMAL(6,4)
├── ttfb_ms        INTEGER
├── fcp_ms         INTEGER
├── created_at     TIMESTAMP
└── updated_at     TIMESTAMP

sites ──── 1 ──── N ──── funnels
funnels
├── id             UUID PK
├── site_id        UUID FK → sites.id
├── name           VARCHAR(255)
├── steps          JSONB   ← [{type: "url"|"event", value: "..."}] 順序付き配列
├── created_at     TIMESTAMP
└── updated_at     TIMESTAMP

sites ──── 1 ──── N ──── alert_rules
alert_rules
├── id             UUID PK
├── site_id        UUID FK → sites.id
├── metric         VARCHAR(32)
├── condition      VARCHAR(16)   ← "above" | "below" | "change_rate"
├── threshold      DECIMAL(12,4)
├── cooldown_min   INTEGER DEFAULT 60
├── last_fired_at  TIMESTAMP
├── created_at     TIMESTAMP
└── updated_at     TIMESTAMP

alert_rules ──── 1 ──── N ──── alert_logs
alert_logs
├── id             UUID PK
├── alert_rule_id  UUID FK → alert_rules.id
├── fired_at       TIMESTAMP
├── metric_value   DECIMAL(12,4)
└── created_at     TIMESTAMP

sites ──── 1 ──── N ──── ai_recommendations
ai_recommendations
├── id             UUID PK
├── site_id        UUID FK → sites.id
├── category       VARCHAR(32)
├── priority       INTEGER
├── description    TEXT
├── estimated_impact VARCHAR(64)
├── generated_at   TIMESTAMP
└── created_at     TIMESTAMP

sites ──── 1 ──── N ──── daily_ai_usage
daily_ai_usage
├── id             UUID PK
├── site_id        UUID FK → sites.id
├── usage_date     DATE
├── used_count     INTEGER DEFAULT 0
├── reset_at       TIMESTAMP
└── created_at     TIMESTAMP
```

---

---

# 3. DFD（データフロー図）

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    DFD Level 0（コンテキスト図）                          │
└─────────────────────────────────────────────────────────────────────────┘

  [サイト訪問者]                    [サイトオーナー]
       │                                  │
       │ 行動イベント                      │ 設定・分析要求
       ▼                                  ▼
  ┌─────────────────────────────────────────────┐
  │                                             │
  │           web-insight-api                   │
  │                                             │
  └─────────────────────────────────────────────┘
       │                                  │
       │ 分析レポート                      │ AIレコメンデーション
       ▼                                  ▼
  [ダッシュボード]               [LangChain / LLM]


┌─────────────────────────────────────────────────────────────────────────┐
│                    DFD Level 1（主要プロセス）                            │
└─────────────────────────────────────────────────────────────────────────┘

[訪問者ブラウザ]
  │
  │ イベントペイロード（type, url, session_id, properties）
  ▼
┌──────────────────┐
│ P1: イベント受付  │ ← reCAPTCHA検証
│   ボット判定      │
│   レートリミット  │
└──────────────────┘
  │                  │
  │ 正常イベント      │ ボット/不正
  ▼                  ▼
┌──────────────────┐  ┌──────────┐
│ P2: セッション   │  │ D0:拒否  │
│    管理          │  │  ログ   │
└──────────────────┘  └──────────┘
  │
  │ セッション確定イベント
  ├──────────────────────────────────────┐
  ▼                                      ▼
┌──────────────────┐             ┌──────────────────┐
│ D1: events       │             │ P3: Web Vitals    │
│    (PostgreSQL)  │             │    記録           │
└──────────────────┘             └──────────────────┘
  │                                      │
  │                                      ▼
  │                              ┌──────────────────┐
  │                              │ D2: web_vitals    │
  │                              └──────────────────┘
  │
  ├──────────────────────────────────────────────────┐
  ▼                                                  ▼
┌──────────────────┐                        ┌──────────────────┐
│ P4: 集計エンジン  │                        │ P8: アラート評価  │
│  ・PV/UU集計     │                        └──────────────────┘
│  ・ファネル分析   │                                 │
│  ・リテンション  │                                 ▼
│  ・ヒートマップ  │                        ┌──────────────────┐
└──────────────────┘                        │ D3: alert_logs   │
  │                                         └──────────────────┘
  │ 集計結果
  ▼
┌──────────────────┐
│ D4: 集計キャッシュ│ ← 5分間TTL
└──────────────────┘
  │
  │ レポートデータ
  ▼
[サイトオーナーUI]
  │
  │ AIレコメンデーション要求
  ▼
┌──────────────────┐
│ P5: AI利用制限   │
│    チェック      │
└──────────────────┘
  │
  │ 制限内
  ▼
┌──────────────────┐        ┌──────────────┐
│ P6: レコメンド   │──────▶ │  LangChain   │
│    プロンプト    │        │  / LLM       │
│    構築          │        └──────────────┘
└──────────────────┘                │
                                    │ 改善提案
                                    ▼
                           ┌──────────────────┐
                           │ D5:              │
                           │ ai_recommendations│
                           └──────────────────┘
```

---

---

# 4. シーケンス図

## 4-1. イベント収集シーケンス

```
訪問者ブラウザ    スニペットJS    API (Rails)    DB (PostgreSQL)    Redis
     │               │               │                 │              │
     │ ページ表示     │               │                 │              │
     │──────────────▶│               │                 │              │
     │               │ POST /collect │                 │              │
     │               │──────────────▶│                 │              │
     │               │               │ reCAPTCHA検証   │              │
     │               │               │─────────────────┼──────────────▶
     │               │               │◀─────────────────┼──────────────│
     │               │               │                 │              │
     │               │               │ レートリミット確認│              │
     │               │               │─────────────────┼──────────────▶
     │               │               │◀─────────────────┼──────────────│
     │               │               │                 │              │
     │               │               │ セッション確認   │              │
     │               │               │─────────────────┼──────────────▶
     │               │               │◀─────────────────┼──────────────│
     │               │               │                 │              │
     │               │               │ ボット判定      │              │
     │               │               │ INSERT events   │              │
     │               │               │────────────────▶│              │
     │               │               │◀────────────────│              │
     │               │               │                 │              │
     │               │ {id, status}  │                 │              │
     │               │◀──────────────│                 │              │
     │               │               │ アラート評価     │              │
     │               │               │────────────────▶│              │
```

## 4-2. Googleログインシーケンス

```
ユーザーブラウザ   Next.js (FE)   Rails API    Google OAuth    DB
     │               │               │               │           │
     │ ログインクリック│               │               │           │
     │──────────────▶│               │               │           │
     │               │ Googleリダイレクト            │           │
     │◀──────────────│               │               │           │
     │               │               │               │           │
     │ Google認証完了 │               │               │           │
     │──────────────────────────────────────────────▶│           │
     │◀──────────────────────────────────────────────│           │
     │               │               │               │           │
     │ authコード    │               │               │           │
     │──────────────▶│               │               │           │
     │               │ POST /auth/google              │           │
     │               │──────────────▶│               │           │
     │               │               │ トークン検証  │           │
     │               │               │──────────────▶│           │
     │               │               │◀──────────────│           │
     │               │               │ sub値でuser upsert        │
     │               │               │───────────────────────────▶
     │               │               │◀───────────────────────────
     │               │ JWT返却       │               │           │
     │               │◀──────────────│               │           │
     │ セッションCookie│              │               │           │
     │◀──────────────│               │               │           │
```

## 4-3. AIレコメンデーションシーケンス

```
オーナーUI   Rails API   daily_ai_usage    LangChain    LLM    DB
     │           │             │               │          │      │
     │ POST /recommend         │               │          │      │
     │──────────▶│             │               │          │      │
     │           │ 利用回数確認 │               │          │      │
     │           │────────────▶│               │          │      │
     │           │◀────────────│               │          │      │
     │           │             │               │          │      │
     │           │ [制限超過の場合] 429返却     │          │      │
     │◀──────────│             │               │          │      │
     │           │             │               │          │      │
     │           │ [制限内] 指標JSONを構築      │          │      │
     │           │──────────────────────────▶  │          │      │
     │           │             │               │ LLM呼出し│      │
     │           │             │               │─────────▶│      │
     │           │             │               │◀─────────│      │
     │           │             │               │ 提案パース│      │
     │           │◀──────────────────────────── │          │      │
     │           │ 利用回数インクリメント        │          │      │
     │           │────────────▶│               │          │      │
     │           │ 提案を保存   │               │          │      │
     │           │─────────────────────────────────────────────▶ │
     │           │◀────────────────────────────────────────────── │
     │ 提案リスト │             │               │          │      │
     │◀──────────│             │               │          │      │
```

---

---

# 5. クラス図

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        クラス図（主要ドメインクラス）                       │
└──────────────────────────────────────────────────────────────────────────┘

┌───────────────────┐
│      User         │
├───────────────────┤
│ +id: UUID         │
│ +google_sub: str  │
│ +display_name: str│
├───────────────────┤
│ +sites(): Site[]  │
│ +owns?(site): bool│
└────────┬──────────┘
         │ 1..* owns
         ▼
┌───────────────────┐         ┌───────────────────┐
│      Site         │ 1    N  │   Session         │
├───────────────────┤────────▶├───────────────────┤
│ +id: UUID         │         │ +id: UUID         │
│ +name: str        │         │ +site_id: UUID    │
│ +url: str         │         │ +fingerprint: str │
│ +api_key: str     │         │ +channel: str     │
│ +verified: bool   │         │ +is_bot: bool     │
├───────────────────┤         │ +started_at: Time │
│ +verify!()        │         │ +last_seen_at: Time│
│ +generate_snippet()│        ├───────────────────┤
│ +events(): Event[]│         │ +continue?(): bool│
│ +sessions(): Sess[]│        │ +refresh!(): void │
└───────────────────┘         └────────┬──────────┘
         │ 1..* has                    │ 1..* generates
         ▼                             ▼
┌───────────────────┐       ┌───────────────────┐
│     Event         │       │    WebVital        │
├───────────────────┤       ├───────────────────┤
│ +id: UUID         │       │ +id: UUID         │
│ +site_id: UUID    │       │ +session_id: UUID │
│ +session_id: UUID │       │ +page_url: str    │
│ +event_type: str  │       │ +lcp_ms: int      │
│ +page_url: str    │       │ +fid_ms: int      │
│ +properties: JSONB│       │ +cls_score: float │
│ +x_ratio: float   │       │ +ttfb_ms: int     │
│ +y_ratio: float   │       │ +fcp_ms: int      │
│ +is_bot: bool     │       ├───────────────────┤
├───────────────────┤       │ +percentile(m): int│
│ +bot?(): bool     │       └───────────────────┘
│ +normalize!(): void│
└───────────────────┘

┌───────────────────┐       ┌───────────────────┐
│     Funnel        │       │   AlertRule       │
├───────────────────┤       ├───────────────────┤
│ +id: UUID         │       │ +id: UUID         │
│ +site_id: UUID    │       │ +site_id: UUID    │
│ +name: str        │       │ +metric: str      │
│ +steps: JSONB[]   │       │ +condition: str   │
├───────────────────┤       │ +threshold: float │
│ +analyze(period)  │       │ +cooldown_min: int│
│   : FunnelResult  │       ├───────────────────┤
└───────────────────┘       │ +evaluate(val): bool│
                            │ +fire!(): void    │
                            │ +cooling_down?()  │
                            └───────────────────┘

┌──────────────────────────────────────────────┐
│              AiRecommendationService         │
├──────────────────────────────────────────────┤
│ -langchain_client: LangChainClient           │
│ -daily_usage: DailyAiUsage                   │
├──────────────────────────────────────────────┤
│ +recommend(site_id, summary): Recommendation[]│
│ -check_limit(site_id): bool                  │
│ -build_prompt(summary): str                  │
│ -parse_response(raw): Recommendation[]       │
│ -increment_usage(site_id): void              │
└──────────────────────────────────────────────┘

┌──────────────────────────────────────────────┐
│                EventCollector                │
├──────────────────────────────────────────────┤
│ -bot_detector: BotDetector                   │
│ -rate_limiter: RateLimiter                   │
│ -session_manager: SessionManager             │
├──────────────────────────────────────────────┤
│ +collect(payload): CollectResult             │
│ -validate(payload): ValidationResult        │
│ -sanitize(properties): JSONB                 │
│ -enqueue(event): void                        │
└──────────────────────────────────────────────┘

┌──────────────────────────────────────────────┐
│               AnalyticsEngine                │
├──────────────────────────────────────────────┤
│ -cache: CacheStore (TTL: 5min)               │
├──────────────────────────────────────────────┤
│ +pageviews(site, period, axis): PVResult     │
│ +funnel(funnel_id, period): FunnelResult     │
│ +retention(site, cohort_unit): RetentionMatrix│
│ +heatmap(site, url, viewport): HeatmapGrid   │
└──────────────────────────────────────────────┘
```

---

---

# 6. 状態遷移図

## 6-1. セッション状態遷移

```
                     ┌──────────────────────────────────────────────┐
                     │              セッション状態遷移                │
                     └──────────────────────────────────────────────┘

                           初回リクエスト
                                │
                                ▼
                          ┌──────────┐
                          │  NEW     │ ← セッション生成
                          └────┬─────┘
                               │ イベント受信
                               ▼
                          ┌──────────┐
                          │ ACTIVE   │◀──────────────┐
                          └────┬─────┘               │
                               │                     │ 30分以内に
                               │ 無操作30分           │ 新イベント
                               ▼                     │
                          ┌──────────┐               │
                          │ IDLE     │───────────────┘
                          └────┬─────┘
                               │ 無操作さらに継続
                               │ または日付変更（JST）
                               ▼
                          ┌──────────┐
                          │ EXPIRED  │
                          └──────────┘
                               │
                               │ 次回リクエスト
                               ▼
                          ┌──────────┐
                          │  NEW     │ ← 新セッション生成
                          └──────────┘

## 6-2. サイト認証状態遷移

                           サイト登録
                                │
                                ▼
                       ┌──────────────────┐
                       │ UNVERIFIED       │
                       │（スニペット未検証）│
                       └────────┬─────────┘
                                │ 初回イベント受信
                                │（スニペット埋め込み確認）
                                ▼
                       ┌──────────────────┐
                       │ VERIFIED         │
                       │（計測有効）       │
                       └────────┬─────────┘
                                │ サイト削除
                                ▼
                       ┌──────────────────┐
                       │ DELETED          │
                       └──────────────────┘

## 6-3. AIレコメンデーション利用制限状態遷移

                     ┌─────────────────────────────────┐
                     │ AVAILABLE（利用可能）            │
                     │ used_count = 0                  │
                     └────────────────┬────────────────┘
                                      │ レコメンデーション実行
                                      ▼
                     ┌─────────────────────────────────┐
                     │ USED（使用済み）                 │
                     │ used_count = 1                  │
                     └────────────────┬────────────────┘
                                      │ JST 03:00 自動リセット
                                      │ OR 管理者手動リセット
                                      ▼
                     ┌─────────────────────────────────┐
                     │ AVAILABLE（利用可能）            │
                     └─────────────────────────────────┘

## 6-4. アラートルール状態遷移

              ┌──────────┐   評価周期到来    ┌──────────────┐
              │ WATCHING │──────────────────▶│  EVALUATING  │
              └──────────┘                   └──────┬───────┘
                   ▲                                │
                   │                       ┌────────┴─────────┐
                   │                       │                  │
                   │                  閾値超過           閾値以内
                   │                       │                  │
                   │                       ▼                  │
                   │              ┌──────────────┐            │
                   │              │    FIRING    │            │
                   │              │（通知キュー   │            │
                   │              │  投入）       │            │
                   │              └──────┬───────┘            │
                   │                     │                    │
                   │                 クールダウン開始           │
                   │                     ▼                    │
                   │              ┌──────────────┐            │
                   └──────────────│  COOLING     │◀───────────┘
                   クールダウン終了 │  DOWN        │
                                  └──────────────┘
```

---

---

# 7. ユースケース図

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      ユースケース図（web-insight-api MVP）                 │
└─────────────────────────────────────────────────────────────────────────┘

アクター定義：
  [訪問者]   : サイトを訪問するエンドユーザー
  [オーナー]  : サイトを登録したGoogleログイン済みユーザー
  [管理者]   : システム管理者（BASIC認証）
  [スニペット]: 埋め込みJSコード（自動アクター）

                    ┌────────────────────────────────────────────────────────┐
                    │                    system: web-insight-api             │
                    │                                                        │
[訪問者]            │   UC-01: ページビュー送信                              │
  │                 │   UC-02: クリックイベント送信                           │
  │─────────────────▶  UC-03: スクロール深度送信                             │
  │                 │   UC-04: カスタムイベント送信                           │
  │                 │   UC-05: Core Web Vitals送信                           │
  │                 │                                                        │
[スニペット]        │                                                        │
  │─────────────────▶  UC-01〜UC-05（自動呼出し）                            │
  │                 │                                                        │
                    │   ─────────────────────────────────────               │
                    │                                                        │
[オーナー]          │   UC-06: Googleログイン                                │
  │                 │   UC-07: サイト登録                                    │
  │─────────────────▶  UC-08: スニペット取得                                 │
  │                 │   UC-09: ダッシュボード閲覧（PV/UU/セッション）         │
  │                 │   UC-10: ファネル定義・分析                             │
  │                 │   UC-11: リテンションレポート閲覧                       │
  │                 │   UC-12: ヒートマップ閲覧                               │
  │                 │   UC-13: パフォーマンスレポート閲覧                     │
  │                 │   UC-14: アラートルール設定                             │
  │                 │   UC-15: AIレコメンデーション取得（1日1回）             │
  │                 │   UC-16: サイト削除                                    │
  │                 │                                                        │
                    │   ─────────────────────────────────────               │
                    │                                                        │
[管理者]            │   UC-17: 全サイト一覧閲覧                              │
  │                 │   UC-18: AIリセット（手動）                             │
  │─────────────────▶  UC-19: ボット判定ルール更新                           │
  │                 │   UC-20: ユーザー管理（停止・削除）                     │
  │                 │                                                        │
                    └────────────────────────────────────────────────────────┘

─────────────────────────────────────────────────────────────
ユースケース依存関係（include / extend）

UC-09 閲覧           <<include>> UC-06 Googleログイン
UC-10 ファネル分析    <<include>> UC-06 Googleログイン
UC-15 AIレコメンド   <<include>> UC-06 Googleログイン
                     <<include>> UC-09 ダッシュボード（指標取得）
                     <<extend>>  AI制限チェック（1日1回）

UC-01〜05 イベント送信 <<include>> ボット判定
                      <<include>> レートリミット確認
                      <<include>> reCAPTCHA検証
```

---

---

# 付録：MVPエディション制約サマリー

| 制約項目 | 内容 |
|---------|------|
| テスト可能単位 | 最小単位データ（単一ユーザー・単一サイト）のみ |
| 大規模負荷試験 | 製品版フルエディションで実施 |
| コホート統計的有意性 | N=1では検証不可。製品版以降 |
| ファネル長期分析（30日超） | 性能保証なし |
| マルチリージョン | 非対応（Railway単一リージョン） |
| SLA | 定義なし（無料プラン） |
| バックアップ | Railway自動バックアップに依存 |

> **重要：** MVPエディションはデータが最小単位しか存在しない状態でのみ動作検証が可能です。本格的な統計精度（リテンション率・ファネル完了率等）はある程度のデータ蓄積（最低100セッション/日）が必要であり、それ以前の数値は参考値として扱ってください。

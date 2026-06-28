# DFD（データフロー図）

## Level 0（コンテキスト図）

```mermaid
flowchart LR
    V([サイト訪問者])
    O([サイトオーナー])
    API[[web-insight-api]]
    D[ダッシュボード]
    LLM[LangChain / LLM]

    V -->|行動イベント| API
    O -->|設定・分析要求| API
    API -->|分析レポート| D
    API -->|AIレコメンデーション| LLM
```

## Level 1（主要プロセス）

```mermaid
flowchart TD
    VB[訪問者ブラウザ]
    P1["P1: イベント受付\nボット判定 / レートリミット\nreCAPTCHA検証"]
    P2[P2: セッション管理]
    P3[P3: Web Vitals記録]
    P4["P4: 集計エンジン\nPV/UU・ファネル・リテンション・ヒートマップ"]
    P5[P5: AI利用制限チェック]
    P6[P6: レコメンドプロンプト構築]
    P8[P8: アラート評価]
    D0[(D0: 拒否ログ)]
    D1[(D1: events)]
    D2[(D2: web_vitals)]
    D3[(D3: alert_logs)]
    D4[("D4: 集計キャッシュ\n5分間TTL")]
    D5[(D5: ai_recommendations)]
    UI[サイトオーナーUI]
    LC[LangChain / LLM]

    VB -->|イベントペイロード| P1
    P1 -->|ボット/不正| D0
    P1 -->|正常イベント| P2
    P2 -->|セッション確定イベント| D1
    P2 -->|セッション確定イベント| P3
    P3 --> D2
    D1 --> P4
    D1 --> P8
    P8 --> D3
    P4 --> D4
    D4 -->|レポートデータ| UI
    UI -->|AIレコメンデーション要求| P5
    P5 -->|制限内| P6
    P6 --> LC
    LC -->|改善提案| D5
```

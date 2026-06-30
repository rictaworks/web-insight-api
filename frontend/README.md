# web-insight-api フロントエンド

Next.js 14（App Router / TypeScript）で構築されたフロントエンドです。

---

## セットアップ

```bash
cd frontend
cp .env.example .env.local
# .env.local に NEXT_PUBLIC_API_BASE_URL を設定する
npm install
```

## 開発サーバー起動

```bash
npm run dev
```

http://localhost:3000 にアクセスして確認。

バックエンド API（Rails）は別途 http://localhost:3001 で起動している必要があります。

---

## コマンド

```bash
npm run dev        # 開発サーバー起動（port 3000）
npm run build      # プロダクションビルド
npm run lint       # ESLint
npm test           # Jest（単体テスト）
npm run test:e2e   # Playwright（E2E テスト）
```

---

## 環境変数

`.env.example` をコピーして `.env.local` を作成:

| 変数名 | 説明 |
|--------|------|
| `NEXT_PUBLIC_API_BASE_URL` | バックエンド API の URL（例: `http://localhost:3001`） |

---

## 技術スタック

| ライブラリ | 用途 |
|-----------|------|
| Next.js 14 | フレームワーク（App Router） |
| TypeScript | 型安全 |
| next-intl | 多言語対応（ja / en / fr / zh / ru / es / ar） |
| next-auth | Google OAuth 認証 |
| Font Awesome 6 | アイコン |
| Recharts | グラフ描画 |
| Jest + React Testing Library | 単体テスト |
| Playwright | E2E テスト |

---

## デプロイ

Vercel へのデプロイ詳細: [ENV/PRODUCTION.md](../ENV/PRODUCTION.md)

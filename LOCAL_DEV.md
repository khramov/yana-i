# Running yana-i Locally

## Prerequisites
- Node.js 20+
- npm

## 1. Install dependencies
```bash
npm install
```

## 2. Configure environment
Copy or check `.env.local` (already present at repo root):
```env
BASE_CURRENCY=EUR
```

## 3. Database
No setup needed — `lib/db/index.ts` creates `data/yana.db` (SQLite, via better-sqlite3) and its tables automatically on first run.

## 4. Start the dev server
```bash
npm run dev
```
Site is served at http://localhost:3000

## 5. Lint
```bash
npm run lint
```

## 6. End-to-end tests (Playwright)
```bash
npx playwright install   # first time only, downloads browsers
npx playwright test
```
Playwright will need the dev server running at http://localhost:3000 (or configure `webServer` in a `playwright.config.ts` if one is added).

## 7. Production build (optional)
```bash
npm run build
npm run start
```

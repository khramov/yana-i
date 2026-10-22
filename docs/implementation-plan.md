# Personal Portfolio Tracker — Implementation Plan

---

## 1. Tech Stack

| Layer | Choice | Why |
|---|---|---|
| Framework | Next.js 14 (App Router) | Single repo for UI + API, React Server Components, strong ecosystem |
| Styling | Tailwind CSS + shadcn/ui | Pre-built accessible components (tables, dialogs, forms) save significant time |
| Charts | Recharts | Declarative React API, covers pie + line charts for both v1 and v2 |
| Database | SQLite via Drizzle ORM | Zero-ops for local use; one file to back up; Drizzle gives type-safe queries + migrations |
| Market data | `yahoo-finance2` npm package | No API key needed; returns real-time quotes, fundamentals, dividend history |
| Server state | SWR | Handles caching, deduplication, background refresh, loading states |
| Form state | React Hook Form + Zod | Zod schema shared between form validation and API route validation |
| UI state | React `useState` (local) | No Redux complexity needed for a personal app |
| Deployment | Self-hosted via `next start` or Docker Compose | Single container, SQLite file mounted as a volume |

**Why SQLite over PostgreSQL:** For local/personal use, SQLite is faster (no network round-trip), easier to back up (single file copy), and sufficient for thousands of transactions. Drizzle ORM lets you swap to PostgreSQL later by changing one adapter line — the schema stays identical.

---

## 2. Data Model

### `holdings` — master list of securities

```sql
holdings
  id          INTEGER PRIMARY KEY AUTOINCREMENT
  ticker      TEXT NOT NULL UNIQUE
  name        TEXT
  sector      TEXT
  asset_class TEXT DEFAULT 'stock'    -- stock | etf | bond | cash
  currency    TEXT DEFAULT 'USD'
  created_at  TEXT NOT NULL           -- ISO 8601
```

Sector and asset class are fetched once from Yahoo Finance on first ticker entry and cached here.

### `transactions`

```sql
transactions
  id          INTEGER PRIMARY KEY AUTOINCREMENT
  holding_id  INTEGER NOT NULL REFERENCES holdings(id)
  type        TEXT NOT NULL           -- buy | sell | dividend | fee
  date        TEXT NOT NULL           -- YYYY-MM-DD
  shares      REAL                    -- NULL for dividend/fee
  price       REAL                    -- price per share (or total for dividend)
  fee         REAL DEFAULT 0
  tax         REAL DEFAULT 0          -- tax withheld (relevant for dividend transactions)
  total       REAL GENERATED ALWAYS AS (
                CASE WHEN shares IS NOT NULL AND price IS NOT NULL
                     THEN shares * price + fee
                     ELSE fee END
              ) VIRTUAL
  currency    TEXT DEFAULT 'USD'
  notes       TEXT
  created_at  TEXT NOT NULL
```

`total` is a SQLite generated column — no application logic needed to keep it consistent.

### `price_cache`

```sql
price_cache
  ticker      TEXT PRIMARY KEY
  price       REAL NOT NULL
  currency    TEXT NOT NULL
  fetched_at  TEXT NOT NULL
```

Simple key-value cache. API routes check `fetched_at` age before hitting Yahoo Finance.

### `portfolio_snapshots` (for growth chart — start accumulating from day one)

```sql
portfolio_snapshots
  date    TEXT PRIMARY KEY    -- YYYY-MM-DD
  value   REAL NOT NULL       -- total portfolio value in base currency
```

### `dividend_metadata` (v2 — dividend calendar)

```sql
dividend_metadata
  id               INTEGER PRIMARY KEY AUTOINCREMENT
  holding_id       INTEGER NOT NULL REFERENCES holdings(id)
  ex_div_date      TEXT
  pay_date         TEXT
  amount_per_share REAL
  frequency        TEXT        -- annual | semi-annual | quarterly | monthly
  fetched_at       TEXT NOT NULL
```

### `fx_rates`

```sql
fx_rates
  base_currency   TEXT NOT NULL
  quote_currency  TEXT NOT NULL
  rate            REAL NOT NULL
  fetched_at      TEXT NOT NULL
  PRIMARY KEY (base_currency, quote_currency)
```

Fetched from Yahoo Finance using `EURUSD=X` ticker pattern.

### `settings`

```sql
settings
  key   TEXT PRIMARY KEY
  value TEXT NOT NULL
```

Single-row config. Stores `base_currency` (e.g. `USD`).

---

### Derived Metrics (computed in `lib/portfolio.ts`, never stored)

| Metric | Formula |
|---|---|
| Average cost basis | `SUM(shares * price + fee) / SUM(shares)` for all `buy` transactions |
| Total shares held | `SUM(shares)` for `buy` minus `SUM(shares)` for `sell` |
| Unrealized P&L | `(current_price - avg_cost) * shares_held` |
| Total return % | `(unrealized_pnl + total_dividends_received) / total_cost_basis * 100` |
| Yield on cost | `(annual_dividends_received / total_cost_basis) * 100` |
| Annual dividend income (trailing) | `SUM(total)` for `dividend` transactions in trailing 12 months |
| Forward annual income estimate | `SUM(shares_held × annual_dividend_per_share)` using `dividend_metadata.amount_per_share` + frequency; requires `dividend_metadata` to be populated via `/api/dividends/refresh` |

---

## 3. Directory Structure

```
/app
  /api
    /holdings/route.ts
    /transactions/route.ts
    /prices/route.ts
    /settings/route.ts
    /portfolio
      /summary/route.ts
      /holdings/route.ts
      /dividends/route.ts
      /allocation/route.ts        (v2)
      /history/route.ts           (v2)
      /income/route.ts            (v2) -- monthly breakdown + forward estimate
    /dividends
      /upcoming/route.ts          (v2)
      /refresh/route.ts           (v2)
  /(dashboard)/page.tsx           -- root dashboard
  /holdings/page.tsx
  /transactions/page.tsx
  /dividends/page.tsx
  /dividends/calendar/page.tsx    (v2)
  /income/page.tsx                (v2)
  /analytics/page.tsx             (v2)
  layout.tsx
/lib
  db.ts                           -- singleton SQLite connection
  schema.ts                       -- Drizzle ORM schema (single source of truth)
  portfolio.ts                    -- shared computation logic
  yahoo.ts                        -- Yahoo Finance wrapper with caching
  fx.ts                           -- FX rate fetching and conversion
  validations.ts                  -- Zod schemas shared by forms and API routes
/components
  /ui                             -- shadcn/ui components
  TransactionForm.tsx
  HoldingsTable.tsx
  DividendTable.tsx
  PortfolioSummaryCards.tsx
  PieChart.tsx                    (v2)
  GrowthChart.tsx                 (v2)
  IncomeBarChart.tsx              (v2)
  IncomeByHoldingTable.tsx        (v2)
/hooks
  usePortfolio.ts                 -- SWR hooks
/drizzle                          -- migration files (committed to git)
```

---

## 4. API Endpoints

### Holdings

```
GET  /api/holdings              list all holdings (for ticker combobox)
POST /api/holdings              create holding; triggers Yahoo Finance fetch for metadata
```

### Transactions

```
GET    /api/transactions        query: ?holdingId=&type=&from=&to=
POST   /api/transactions        body: { holdingId, type, date, shares, price, fee, notes }
PUT    /api/transactions/:id    partial update
DELETE /api/transactions/:id
```

### Prices

```
GET  /api/prices?tickers=AAPL,VTI    batch price fetch; reads cache first, fetches stale entries
```

### Portfolio (computed)

```
GET  /api/portfolio/summary     all dashboard KPIs in one response (includes total_return_pct, forward_annual_income)
GET  /api/portfolio/holdings    positions with avg_cost, shares_held, market_value, unrealized_pnl
GET  /api/portfolio/dividends   dividend history + aggregated totals; query: ?year=
GET  /api/portfolio/allocation  [{ label, value, percentage }]; query: ?by=sector|holding|asset_class  (v2)
GET  /api/portfolio/history     [{ date, value }] daily snapshots; query: ?from=&to=         (v2)
GET  /api/portfolio/income      { monthly: [{ month, amount }], byHolding: [...], forwardAnnual: number }  (v2)
```

### Dividends (v2)

```
GET  /api/dividends/upcoming    upcoming ex-div and pay dates with estimated income
POST /api/dividends/refresh     fetch dividend metadata from Yahoo Finance for all holdings
```

---

## 5. Pages & Screens

### Dashboard (`/`)
- Total portfolio value in base currency
- Total cost basis
- Total unrealized P&L (absolute + %)
- **Total return %** — `(unrealized_pnl + total_dividends) / cost_basis * 100`
- Total dividends received (all time + trailing 12 months)
- **Forward annual income estimate** — projected income based on current holdings × declared dividend rates
- Holdings count
- Top 5 positions by weight

### Holdings (`/holdings`)
Columns: Ticker | Name | Shares | Avg Cost | Current Price | Market Value | Unrealized P&L | P&L %
- Filter toggle: show/hide closed positions (shares = 0)

### Transactions (`/transactions`)
Full log table: Operation | Holding | Date | Shares | Price | Fee | Tax | Total | Notes
- Filter by type (buy/sell/dividend/fee) and date range
- Add/Edit as a slide-over Sheet panel (not a separate page)
- Tax field shown/required only when type = `dividend`

### Dividends (`/dividends`)
- Summary cards: total received (all time), trailing 12 months, portfolio yield on cost
- **Year filter** — dropdown to filter the table by calendar year
- Table: Ticker | Date | Amount | Shares | Per Share | Tax | Yield on Cost

### Diversification (`/analytics` — v2)
- Donut chart by sector
- Donut chart by holding weight
- **Donut chart by asset class** (stock / ETF / bond / cash) — data already in `holdings.asset_class`
- Toggle between the three views

### Growth Chart (`/analytics` — v2)
- Line chart: portfolio value over time
- Time range selector: 1M / 3M / 6M / 1Y / All

### Dividend Calendar (`/dividends/calendar` — v2)
- Monthly grid calendar with ex-div and pay date markers per ticker
- Clicking a ticker shows declared amount + estimated income

### Income (`/income` — v2)
- **Monthly bar chart** — dividend income received per month for the current year
- **Forward annual income estimate** — Σ(shares_held × annualized dividend per share) using `dividend_metadata`; requires `/api/dividends/refresh` to be run
- **Income by holding** — table: Ticker | Trailing 12m received | Forward annual estimate | % of total income
- Note: forward estimate accuracy depends on `dividend_metadata` being refreshed; show last-refreshed timestamp

---

## 6. Key Architectural Decisions

### Price Cache Strategy

1. `price_cache` stores price + `fetched_at` timestamp per ticker.
2. `lib/yahoo.ts:getPrices(tickers[])` partitions into fresh (< 15 min) and stale.
3. Stale tickers are fetched in a single `yahoo-finance2.quote()` batch call, cache is updated.
4. Dashboard uses `useSWR` with `refreshInterval: 60_000` — cache means Yahoo Finance is hit at most 4x/hour.
5. When market is closed (weekends, after-hours), skip fetches entirely — return stale cache.

### Growth Chart — Snapshot Approach

Option A (recommended): A background writer calls `lib/portfolio.ts` once per day on app startup and writes to `portfolio_snapshots`. The chart shows only days with snapshots — sparse initially but fills in over weeks.

Option B (accurate but complex): Replay transactions against Yahoo Finance historical price series. Avoid for v1; revisit if needed.

**Add `portfolio_snapshots` to the schema from day one so data starts accumulating immediately.**

### Multi-Currency

- Transactions store original `currency` for audit purposes.
- All aggregations convert to `BASE_CURRENCY` (set in `.env.local`) using `lib/fx.ts`.
- Conversion happens at aggregation time in `lib/portfolio.ts`, not at storage time.

### SQLite Config

Enable WAL mode explicitly for better concurrency:
```ts
db.pragma('journal_mode = WAL');
```

### No Authentication

For local use, no auth layer needed. If deployed to a VPS, add HTTP Basic Auth at the nginx level — no application code changes required.

---

## 7. Build Stages

See [plan.md](plan.md) for the full stage-by-stage breakdown (P1–P11).

---

## 8. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Yahoo Finance unofficial API breaks or rate-limits | Wrap all calls in try/catch; return cached data on failure; show "prices unavailable" banner. Alpha Vantage as manual fallback. |
| Average cost accuracy for partial sells | Use average cost method (not FIFO). Document this assumption in the UI. |
| SQLite concurrent writes | Enable WAL mode; single-user local access is fine. |
| Growth chart is empty on first use | Start accumulating `portfolio_snapshots` from day one. Chart fills in over time. |
| Dividend calendar accuracy | Yahoo `calendarEvents` only covers the next declared dividend. Show a disclaimer in the UI. |
| Schema evolution pain | Use Drizzle migrations from the start. Never alter the SQLite file manually. |

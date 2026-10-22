# Yana — Build Plan

| Stage | Summary | Status |
|---|---|---|
| P1 | Landing page — "Hello Yana" | — |
| P2 | Dashboard + Ticker Watchlist widget | — |
| P3 | Transaction log — buy/sell/dividend/fee CRUD | — |
| P4 | Holdings view — positions, avg cost, unrealized P&L | — |
| P5 | Dashboard KPI cards — total value, return %, top 5 | — |
| P6 | Dividends page — history, year filter, yield on cost | — |
| P7 | Multi-currency — FX conversion throughout | — |
| P8 | Growth chart — portfolio value over time | — |
| P9 | Diversification charts — by sector / holding / asset class | — |
| P10 | Income page + Dividend calendar | — |
| P11 | Goals & portfolio plan — dedicated targets workspace and rebalancing progress | — |

---

### P1 — Landing Page

**Goal:** running Next.js app, nothing on screen except "Hello Yana".

Deliverables:
- Next.js 14 project scaffolded (App Router, TypeScript, Tailwind, shadcn/ui initialized)
- Single root page `/` rendering "Hello Yana"
- App runs at `localhost:3000`

| Step | Work |
|---|---|
| 1 | `npx create-next-app` with TypeScript + Tailwind + App Router |
| 2 | Install and init shadcn/ui |
| 3 | Replace default page content with "Hello Yana" |
| 4 | Verify app runs at `localhost:3000` |

---

### P2 — Dashboard + Ticker Watchlist Widget

**Goal:** dashboard page with a widget showing a list of tickers and the ability to add a new one.

Deliverables:
- Dashboard page `/` with a Watchlist widget
- Widget displays a list of tickers with name and current price
- Add ticker input — type a symbol, press Enter or click Add, it appears in the list
- Tickers persisted in SQLite so they survive restarts
- Live prices from Yahoo Finance, auto-refreshed every 60 seconds

| Step | Work |
|---|---|
| 1 | Drizzle ORM + SQLite connection + `holdings` + `price_cache` table migrations |
| 2 | `GET /api/holdings` and `POST /api/holdings` API routes |
| 3 | `GET /api/prices?tickers=` route with 15-min cache |
| 4 | Watchlist widget component — renders tickers with live prices |
| 5 | Add ticker form — combobox input, calls `POST /api/holdings`, refreshes list |
| 6 | SWR auto-refresh of prices every 60 seconds |
| 7 | Empty state and loading skeleton |

---

### P3 — Transaction Log

**Goal:** ability to record every portfolio event — buys, sells, dividends, fees.

Deliverables:
- `/transactions` page with full transaction log table
- Columns: Operation | Holding | Date | Shares | Price | Fee | Tax | Total | Notes
- Filter by type (buy / sell / dividend / fee) and date range
- Add and edit via slide-over Sheet panel (no separate page)
- Delete with confirmation dialog
- Tax field visible only when type = `dividend`

| Step | Work |
|---|---|
| 1 | `transactions` table migration |
| 2 | `GET`, `POST`, `PUT`, `DELETE /api/transactions` routes |
| 3 | Zod validation schemas shared between form and API |
| 4 | Transaction table component with type + date filters |
| 5 | Add/Edit slide-over form (React Hook Form) |
| 6 | Delete confirmation dialog |
| 7 | Empty state and loading skeleton |

---

### P4 — Holdings View

**Goal:** see all current positions with cost basis, live price, and unrealized P&L.

Deliverables:
- `/holdings` page
- Columns: Ticker | Name | Shares | Avg Cost | Current Price | Market Value | Unrealized P&L | P&L %
- Color: green for positive P&L, red for negative
- Toggle to show/hide closed positions (shares = 0)
- Computed from transactions in `lib/portfolio.ts` — nothing stored

| Step | Work |
|---|---|
| 1 | `lib/portfolio.ts` — avg cost basis and shares held computation |
| 2 | `GET /api/portfolio/holdings` route |
| 3 | Holdings table component with P&L coloring |
| 4 | Show/hide closed positions toggle |
| 5 | Loading skeleton |

---

### P5 — Dashboard KPI Cards

**Goal:** top-level portfolio summary visible at a glance on the dashboard.

Deliverables:
- KPI cards on `/`: Total Value | Cost Basis | Unrealized P&L | Total Return % | Dividends Received | Holdings Count
- Top 5 positions by weight (small table or bar)
- All values in base currency

| Step | Work |
|---|---|
| 1 | `GET /api/portfolio/summary` route — all KPIs in one response |
| 2 | `PortfolioSummaryCards` component |
| 3 | Top 5 positions mini-table |
| 4 | Loading skeletons for all cards |

---

### P6 — Dividends Page

**Goal:** full dividend history with income totals and yield on cost.

Deliverables:
- `/dividends` page
- Summary cards: total received (all time) | trailing 12 months | yield on cost
- Year filter dropdown
- Table: Ticker | Date | Amount | Shares | Per Share | Tax | Yield on Cost

| Step | Work |
|---|---|
| 1 | `GET /api/portfolio/dividends?year=` route |
| 2 | Summary cards component |
| 3 | Year filter dropdown |
| 4 | Dividend history table |
| 5 | Empty state for years with no dividends |

---

### P7 — Multi-Currency Support

**Goal:** all portfolio totals converted to a single base currency regardless of what currency each holding trades in.

Deliverables:
- `fx_rates` table populated on app startup
- `lib/fx.ts` — converts any currency to `BASE_CURRENCY`
- All aggregations in `lib/portfolio.ts` go through FX conversion
- Base currency configurable via `BASE_CURRENCY` in `.env.local`

| Step | Work |
|---|---|
| 1 | `fx_rates` table migration |
| 2 | `lib/fx.ts` — fetch rates from Yahoo Finance (`EURUSD=X` pattern), cache in DB |
| 3 | Update `lib/portfolio.ts` to convert all values at aggregation time |
| 4 | Update all API routes to return converted totals |
| 5 | Display base currency label in UI next to all monetary values |

---

### P8 — Growth Chart

**Goal:** visualize portfolio value over time as a line chart.

Deliverables:
- Growth chart on `/analytics` page
- Time range selector: 1M / 3M / 6M / 1Y / All
- Daily snapshot writer runs on app startup, writes to `portfolio_snapshots`
- Chart fills in over time from day one of use

| Step | Work |
|---|---|
| 1 | `portfolio_snapshots` table migration |
| 2 | Daily snapshot writer in `lib/portfolio.ts` — runs on startup, writes today's value if not already recorded |
| 3 | `GET /api/portfolio/history?from=&to=` route |
| 4 | Line chart component (Recharts) with time range selector |
| 5 | Empty/sparse state message for early use |

---

### P9 — Diversification Charts

**Goal:** understand portfolio allocation across multiple dimensions.

Deliverables:
- Donut charts on `/analytics` page (alongside growth chart)
- Three views toggleable: by Sector | by Holding weight | by Asset Class
- Table below chart showing label, value, and percentage

| Step | Work |
|---|---|
| 1 | `GET /api/portfolio/allocation?by=sector\|holding\|asset_class` route |
| 2 | Donut chart component (Recharts) |
| 3 | View toggle (sector / holding / asset class) |
| 4 | Allocation table below chart |

---

### P10 — Income Page + Dividend Calendar

**Goal:** monthly income view and upcoming dividend event calendar.

Deliverables:
- `/income` page: monthly bar chart, forward annual income estimate, income by holding table
- `/dividends/calendar` page: monthly grid with ex-div and pay date markers per ticker
- `dividend_metadata` populated via `POST /api/dividends/refresh`

| Step | Work |
|---|---|
| 1 | `dividend_metadata` table migration |
| 2 | `POST /api/dividends/refresh` — fetch ex-div dates, pay dates, amount/share from Yahoo Finance for all holdings |
| 3 | `GET /api/dividends/upcoming` — upcoming events with estimated income |
| 4 | `GET /api/portfolio/income` — monthly breakdown + forward annual estimate |
| 5 | Income bar chart component (Recharts) |
| 6 | Income by holding table |
| 7 | Dividend calendar grid component |
| 8 | Last-refreshed timestamp + manual refresh button |

---

### P11 — Goals & Portfolio Plan

**Goal:** give investors a dedicated workspace to define allocation targets using the holdings already in the active portfolio, then understand progress toward that plan.

Deliverables:
- `/goals` page and primary navigation entry; allocation targets are no longer edited from the Analytics chart
- Holding and asset-class target views with current allocation, target allocation, and deviation
- Holding dropdown populated from the active portfolio's existing holdings; each option shows ticker and name, and already-selected holdings are excluded
- Selective target list: add only the holdings the investor wants to plan for, set a target percentage, and remove a target when it no longer applies
- Live total with 100% validation, explicit clear action, and clear saving/error feedback
- Server validation that prevents stale, unknown, duplicate, or cross-portfolio holdings from being saved as targets
- Analytics and recommendations retain read-only goal progress and link to `/goals` for edits

| Step | Work |
|---|---|
| 1 | Harden `PUT /api/goals`: validate target totals, duplicate keys, and holding membership in the active portfolio before replacing any saved targets |
| 2 | Add `/goals` route, navigation, and responsive goal-management workspace |
| 3 | Build the holding picker from `GET /api/holdings`; show ticker/name, exclude selected rows, and provide an empty portfolio state |
| 4 | Build target add/remove controls, percentage inputs, live total, clear action, and save/error states for holding and asset-class scopes |
| 5 | Display current, target, and deviation values; surface saved targets for holdings that later become unavailable |
| 6 | Replace the Analytics modal with a Goals link and update recommendation empty states to the same destination |
| 7 | Add API/component coverage and run lint, type-check, build, and responsive manual QA |

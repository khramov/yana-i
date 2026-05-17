# Snowball Analytics — Detailed Application Review

Source: https://snowball-analytics.com
Public portfolio example: https://snowball-analytics.com/public/portfolios/dpawdnmreb

---

## What It Is

Snowball Analytics is a web + mobile investment portfolio tracker aimed at **dividend-focused retail investors**. It consolidates holdings from multiple brokers into one dashboard and emphasizes income tracking (dividends, yield, payout calendars) on top of the standard performance metrics most trackers offer.

- Company: Snowball Analytics SAS, Lyon, France
- Mobile: iOS (4.8★, 4,200+ ratings) + Android (4.8★, 2,300+ ratings)
- Business model: Freemium, 14-day free trial, no credit card required
- Data providers: EODHD (market data), SnapTrade (broker connectivity), Yodlee (bank/broker aggregation)

---

## Core Feature Areas

### 1. Portfolio Management

- Track stocks, ETFs, and mutual funds across 70+ global exchanges
- Multi-portfolio support (separate tracking per account or strategy)
- Multi-currency support — 25+ currencies (USD, EUR, CAD, SAR, etc.), automatic conversion
- One-click rebalancing based on target allocations
- Category-based organization of holdings
- Public portfolio sharing (read-only shareable link)

### 2. Broker Integrations

- 1,000+ broker connections via Yodlee automation
- Direct import from 15+ specific brokers (CSV or API)
- Manual transaction entry as fallback

### 3. Transaction Tracking

Each transaction records:
- Operation type (buy, sell, dividend received, fee, tax)
- Holding (ticker/name)
- Date
- Number of shares
- Price per share
- Fee
- Total sum
- Total profit (for closed positions)

### 4. Diversification Analysis

Breakdown of portfolio allocation across multiple dimensions:
- **By sector** (Technology, Healthcare, Financials, Energy, etc.)
- **By country / region**
- **By asset class** (stocks, ETFs, bonds, cash)
- **By individual holding** (% weight per position)
- Fund composition transparency (what's inside an ETF)

Visualized as pie/donut charts and tables.

### 5. Dividend Tracking

The main differentiator of Snowball vs. generic trackers:

- **Dividend calendar** — shows upcoming ex-dividend and payout dates
- **Income forecast** — projected annual/monthly dividend income based on current holdings
- **Yield on cost** — dividend yield calculated against original purchase price
- **Dividend growth tracking** — year-over-year dividend growth per holding
- **Dividend rating** — proprietary score assessing company dividend health (consistency, payout ratio, coverage)
- **Per-share and total dividend** history per holding
- **Tax tracking** — records tax withheld on dividends per transaction

### 6. Performance & Growth

- Portfolio value over time (chart)
- Total return (absolute and %)
- Return accounting for broker fees and taxes
- **Benchmarking** against major indices: S&P 500, NASDAQ, FTSE, TSX
- Time-weighted return (TWR) to isolate performance from cash flow timing
- Profit/loss breakdown per holding and overall

### 7. Risk Metrics

- **Sharpe ratio** — risk-adjusted return
- Volatility metrics
- Sector concentration risk
- Currency exposure

### 8. Income View

- Monthly/annual income calendar
- Past vs. projected dividend income comparison
- Income by holding and by month
- Forward income estimate based on current yield

---

## UI Structure — Public Portfolio Page

The portfolio view is organized into **7 tabs**:

| Tab | What it shows |
|---|---|
| **Common** | Top-level KPIs, total value, total return, profit/loss summary |
| **Diversification** | Allocation charts by sector, country, asset class |
| **Dividends** | Dividend history, yield, upcoming payouts, dividend health ratings |
| **Growth** | Portfolio value over time, benchmarking chart |
| **Metrics** | Sharpe ratio, volatility, and other risk/return metrics |
| **Transactions** | Full transaction log with filtering |
| **Income** | Dividend income calendar and projections |

---

## Target Users

- Long-term retail investors with dividend-growth strategies
- People tracking portfolios across multiple brokers
- Investors moving away from spreadsheets
- Multi-currency investors (expats, international portfolios)

---

## What's NOT in Snowball (out of scope)

- Not a brokerage — no trading execution
- No crypto support (focused on traditional equities)
- No tax report generation (tracks tax per dividend but no full tax filing)
- No social/copy-trading features
- No screener or stock discovery tools

---

## Reduced-Scope Version — What to Build

For a personal-use clone with reduced functionality, the essential core is:

### Must Have
1. **Transaction log** — manual entry of buy/sell/dividend transactions (ticker, date, shares, price, fee)
2. **Holdings view** — current positions with avg cost, current price, unrealized P&L
3. **Dividend tracker** — record dividends received, show yield on cost, annual income
4. **Total portfolio value** — aggregated in one base currency

### Nice to Have (second iteration)
5. **Diversification chart** — simple pie chart by sector or holding weight
6. **Growth chart** — portfolio value over time
7. **Dividend calendar** — upcoming ex-div / pay dates

### Skip (not needed for personal use)
- Broker API integrations (manual entry is fine for personal use)
- Benchmarking against indices
- Sharpe ratio / advanced risk metrics
- Public portfolio sharing
- Multi-user / social features
- Mobile apps (web-only is fine)

---

## Suggested Tech Stack for Personal Build

- **Frontend:** Next.js + Tailwind CSS + Recharts (charts)
- **Backend:** Next.js API routes or a simple Express server
- **Database:** SQLite (local, zero-ops) or PostgreSQL
- **Market data:** Yahoo Finance unofficial API or Alpha Vantage free tier (for current prices)
- **Auth:** None needed (personal use, local or self-hosted)

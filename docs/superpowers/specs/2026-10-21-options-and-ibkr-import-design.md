# Options holdings and Interactive Brokers import (macOS app)

Status: draft for review · 2026-10-21 · scope: `apple/` only

## Why

The owner keeps their portfolio at Interactive Brokers and downloads Activity Statements as CSV, for whatever date
range they need at the time. Today the Mac app cannot read those files at all: its importer only understands
its own `ticker,type,date,…` format and rejects a statement because it has no `ticker` column. The account also
holds an equity option (`PBR 17DEC27 27 C`), which the app cannot represent.

Success: dropping any IBKR Activity Statement onto the app, in any order and with any overlap, leaves holdings
that match that broker's Open Positions, with no duplicate transactions, and the option shows its real value
(contracts × price × 100, so 4 contracts at 4.00 = 1,600 USD).

The owner's real statement lives in `sample data/`. It is personal account data: add `sample data/` to
`.gitignore` and never commit it. Test fixtures use made-up numbers in the same format.

## Goals

1. **Options are holdings.** A new asset class `option`, otherwise handled like stock, ETF, or bond: it appears
   in holdings, dashboard, transactions, allocation (under "option", at market value), and goals.
2. **Contract multiplier.** Holdings get a `multiplier` (default 1; options usually 100). Quantities are in
   contracts and prices are per share, exactly as IBKR shows them. Cost, average cost, market value, and gain
   are scaled by the multiplier, so the app matches the statement.
3. **Hand entry.** Options can be added in the holding form, not only imported.
4. **IBKR Activity Statement import**: stock/ETF and option trades, dividends with withholding tax, positions
   held before the statement period, IBKR exchanges mapped to Yahoo symbols.
5. **Re-import overrides.** Importing a file that overlaps earlier imports replaces the earlier rows for that
   date range instead of duplicating them. This applies to the app's own CSV format too.

## Non-goals

No change to the web (Next.js) app. No automatic handling of option expiry or exercise: the owner records a
sale, an expiry (sell at 0), or an exercise (sell the option, buy the shares) as ordinary transactions, by hand
or by a later import. See "Possible improvements" for everything else deliberately left out.

## Anti-goals

- Holdings that silently disagree with the broker after an import.
- Duplicate transactions after importing overlapping statements.
- The app inventing transactions the owner did not make (other than the labelled opening balance below).

## Design

### Data model

**Holding** gains:

| Field | Type | Notes |
|---|---|---|
| `assetClass` | adds `option` | |
| `multiplier` | decimal > 0, optional | Omitted means 1. |

For an option, `ticker` is the OCC symbol without padding (`PBR271217C00027000`), which is also its Yahoo
symbol, and `name` is the readable form (`PBR 17DEC27 27 C`). Lists show `name` when present. Underlying,
strike, expiry, and right are not separate fields (decided: the symbol and name carry them).

**Transaction** gains:

| Field | Type | Notes |
|---|---|---|
| `importSource` | `ibkr` \| `csv`, optional | Set on rows created by an import; omitted for hand entries. |
| `openingBalance` | object, optional | Present only on the importer's opening-balance buy, see below. |

`openingBalance` = `{ asOf: LocalDate, targetQuantity: decimal, targetCostBasis: decimal, coveredFrom: LocalDate }`.

Editing an imported transaction by hand keeps its `importSource`, so a later import over that date replaces it
(the file wins).

**Sync format.** There is no other reader yet (decided), so these fields are added to sync payload v1 in place
rather than introducing v2: update `apple/docs/sync-payload-v1.md`, `PayloadCodec`, the golden files, the
SwiftData schema, and the CloudKit record mapping. Optional fields are omitted when absent, as the contract
already requires, so existing records keep their exact bytes. *Builder's call:* whether the SwiftData change
needs a migration stage or is purely additive.

### Money math

In `PositionCalculator`, a buy's lot cost becomes `quantity × unitPrice × multiplier + fee`, and in
`PortfolioValuation` market value becomes `shares × price × multiplier`. Average cost stays per share (what the
broker shows), and cost basis is `shares × averageCost × multiplier`. Multiplier 1 leaves every existing number
unchanged; existing tests must pass untouched. Allocation, top positions, and goals use these values.

### Hand entry (holding form)

Picking asset class **Option** replaces the ticker field with: underlying, expiry date, call/put, strike, and
multiplier (default 100). The app builds the OCC ticker and readable name from them and shows both before
saving. *Builder's call:* exact layout, following the existing form's style. Transactions on an option use the
normal transaction form, labelled "Contracts" and "Price per share".

### Market data

Option prices come from the same Yahoo `v8/finance/chart` endpoint using the OCC symbol. If Yahoo has no quote,
the holding shows no price, as for any other unknown ticker.

### Importing an IBKR Activity Statement

**Detection.** After stripping a UTF-8 BOM (now also stripped for the app's own CSV format), a file whose first
row starts with `Statement,Header` is an IBKR statement; anything else goes to the existing importer.

**Parsing.** The file is a set of sections. Each row starts with the section name and `Header`, `Data`,
`SubTotal`, or `Total`. A section can repeat its `Header` with different columns (one per asset category), so
each `Data` row is read against the most recent `Header` of its section. Only `Data` rows are used.

| Section | Used for |
|---|---|
| `Statement` | `Period` gives the covered range (`August 3, 2026 - October 19, 2026`). |
| `Financial Instrument Information` | Listing exchange and multiplier per symbol; ISIN for matching dividends; option OCC symbol (`PBR   271217C00027000`, collapse spaces) and description. |
| `Trades` | Asset category `Stocks` and `Equity and Index Options` become buys (quantity > 0) or sells (quantity < 0, stored positive). Price is `T. Price`, fee is the absolute `Comm/Fee`, date is the date part of `Date/Time`. `Forex` rows are ignored without a message. |
| `Open Positions` | `Summary` rows give quantity and cost basis per symbol at the period end. |
| `Dividends`, `Withholding Tax` | A dividend per symbol and date, with withholding as its `tax` (absolute value). The symbol comes from the description prefix `VWCE(IE00BK5BQT80) …`, matched by ISIN. The sample has no such rows, so tests need a hand-made fixture. |
| anything else | Ignored. Rows in `Corporate Actions` are listed in the summary as unsupported. |

**Symbols.** Stocks and ETFs map IBKR's listing exchange to a Yahoo suffix: `IBIS`/`IBIS2` → `.DE`,
`AEB` → `.AS`, `LSE`/`LSEETF` → `.L`, `SBF` → `.PA`, `BVME`/`BVME.ETF` → `.MI`, `EBS` → `.SW`, and US
exchanges (`NASDAQ`, `NYSE`, `ARCA`, `BATS`, `AMEX`) → none. An unknown exchange keeps the bare symbol and the
summary warns about it. *Builder's call:* adding more exchanges. Holding identity follows the mapped ticker,
so a hand-made `VWCE` holding and an imported `VWCE.DE` holding are separate; the import summary names any
such pair so the owner can merge them by hand (my call; there is no merge feature). Asset class is `etf` when the instrument
`Type` is `ETF`, `stock` for other stocks, and `option` for options. The holding's name comes from the
description.

**Currencies.** Rows in a currency the app does not support (anything but EUR, USD, RUB) are listed as failed
lines, not silently converted to EUR.

### Re-import: the file is the authority for its date range

Each import has a range: the statement `Period` for IBKR, or the earliest to latest row date for the app's own
CSV. Applied in one save, per portfolio:

1. **Replace earlier imports.** Delete (tombstone) every transaction with the same `importSource` dated inside
   the range. For the app's own CSV, only for tickers that appear in the file. Opening-balance rows are not
   deleted here (step 4 handles them).
2. **Absorb matching hand entries.** A hand-entered transaction (no `importSource`) inside the range is replaced
   when a file row "looks the same": same holding, type, and date, and the same quantity (buy/sell) or the same
   amount (dividend/fee). Price and fees may differ. Each file row absorbs at most one hand entry. All other
   hand entries are kept.
3. **Insert** the file's rows with `importSource` set.
4. **Recompute opening balances** (IBKR only), see below.

Outside the range nothing changes. The import summary reports added, replaced, absorbed-hand-entry, failed, and
unsupported counts, with line numbers for failures.

### Opening balances that correct themselves (IBKR only)

Positions held before a statement's period have no trades in it. Each holding has at most one opening-balance
buy, recomputed after every IBKR import, so that holdings always match the **most recent** statement imported
(the one with the latest period end) regardless of import order.

- `coveredFrom` = the earliest period start of any IBKR import that included the holding, and the opening buy
  is dated on it.
- `asOf`, `targetQuantity`, and `targetCostBasis` come from the Open Positions of the most recent statement that
  covered the holding. A holding missing from that statement's Open Positions has a target of 0. An import
  whose period ends earlier than the stored `asOf` does not change the target.
- Quantity = `targetQuantity` minus the net quantity of all real (non-opening) transactions up to `asOf`.
- Price is solved so that the calculated cost basis at `asOf` equals `targetCostBasis`. Under the average-cost
  method, cost basis at `asOf` is linear in the opening lot's cost, so this has a closed form.
- If the quantity comes out as 0, there is no opening buy (delete any existing one). If it comes out negative,
  delete it and warn in the summary that the trades imported so far do not reconcile with the statement.

Gaps between imported periods are absorbed into the opening balance: totals stay correct and only the dates
of the missing months are off, until those months are imported (accepted).

Worked example (made-up numbers): VWCE has 30 shares and a cost basis of 2801.25 at Oct 19, and 10 were bought
on Aug 14 for 1001.25 including the fee. The opening buy is therefore 20 VWCE on Aug 3 at 90 (cost 1800). Later importing a Jun–Sep statement that contains those 20 shares' purchases shrinks the opening buy
to 0 and removes it.

## Testing

- Domain tests (YanaKit) for multiplier math, IBKR parsing (sample-shaped fixtures with anonymised account data),
  exchange mapping, range replacement, hand-entry absorption, and opening-balance recompute across import orders
  (A then B, B then A, overlapping, with a gap) all producing the same holdings.
- Golden payload files for an option holding and an opening-balance transaction.
- Run the app tests in Release as well as Debug. The SwiftData predicate crash fixed in `9b79ac5` only showed up
  in optimized builds.

## Possible improvements

Left out on purpose. Candidates for later:

- Other brokers' statement formats.
- Options and IBKR import in the web app.
- Automatic handling at expiry: flag expired options or record their outcome.
- Option analytics: Greeks, implied volatility, days to expiry, underlying exposure.
- Corporate actions: splits, mergers, spin-offs.
- Standalone fees and interest from the statement's `Fees` and `Interest` sections, which are not tied to a
  holding.
- Currencies beyond EUR, USD, and RUB.

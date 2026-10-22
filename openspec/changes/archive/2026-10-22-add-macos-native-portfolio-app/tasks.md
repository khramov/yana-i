# Tasks

## 1. Project scaffolding

- [x] 1.1 Create the `apple/YanaKit` Swift package (macOS 14, Swift 5.10+) with `YanaDomain`, `YanaSync`, and `YanaMarketData` library targets and matching test targets; verify `swift build` and `swift test` succeed from `apple/YanaKit` with one placeholder test per target.
- [x] 1.2 Create the `apple/YanaMac` Xcode project (SwiftUI app, macOS 14 deployment target, unit-test target) depending on the local package, with bundle ID, team, and CloudKit container read from a `Config/Signing.xcconfig` (placeholder values plus a `.example` file); verify `xcodebuild -scheme YanaMac build` succeeds with signing disabled.
- [x] 1.3 Add entitlements for App Sandbox, outgoing network client, user-selected read-only files, iCloud/CloudKit, and Push Notifications, plus an `apple/README.md` covering build, test, and signing setup; verify the entitlements file lists exactly these capabilities and the README commands run as written.
- [x] 1.4 Make sure the Next.js tooling ignores `apple/` (ESLint ignores, `tsconfig` exclude if needed) and add Xcode build artifacts to `.gitignore`; verify `npm run lint` and `npm run build` still pass unchanged.

## 2. Portable domain model and validation (YanaDomain)

- [x] 2.1 Implement `Currency`, `AssetClass`, `TransactionKind`, `GoalScope`, `LocalDate`, `RecordVersion` (lexicographically `Comparable`), and the four `Codable` record structs with `Decimal` money and `deletedAt` tombstones; verify unit tests cover `RecordVersion` ordering and `LocalDate` parsing and rejection.
- [x] 2.2 Implement UUIDv5 generation and the derived holding and goal identities (normalized ticker, portfolio, scope, key); verify tests against RFC 4122 test vectors, and that " aapl " and "AAPL" in one portfolio produce the same ID while different portfolios produce different IDs.
- [x] 2.3 Implement validation for portfolios (non-empty name, supported currency, EUR default), holdings, transactions (buy/sell quantity and price, positive dividend/fee amount, non-negative fee and tax), and goal scopes (each target > 0, sum 100 ± 0.5, message with the current sum); verify tests cover every validation scenario in `native-portfolio-storage`.

## 3. Portfolio calculations (YanaDomain)

- [x] 3.1 Implement `PositionCalculator` (date-then-creation order, average cost including buy fees, sells keep average cost, clamp at zero); verify golden tests for the 10@100+5 / 10@110 / sell 5 scenarios (avg 105.25, basis 2105 then 1578.75), the oversell clamp, and the exact 0.1+0.2 shares case.
- [x] 3.2 Implement `MarketSnapshot` and `PortfolioValuation` (market value, base-currency cost basis, unrealized gain, return %, dividends received, holdings count, top 5), with a missing price excluded from value but kept in cost basis and a missing FX rate producing unavailable values; verify golden tests for the mixed-currency, missing-price, and missing-FX scenarios.
- [x] 3.3 Implement `AllocationCalculator` (holding/sector/asset class, "Unknown" sector, unpriced positions excluded) and `RebalanceCalculator` (current %, target %, drift, non-negative buy amount, buy shares); verify golden tests for the VTI underweight scenario (drift −10, buy 1,000, 4 shares), an overweight holding, and percentages adding up to 100.
- [x] 3.4 Implement `IncomeCalculator` (monthly gross income, trailing 12 months, forward annual from annual rate × shares, per-holding breakdown) and `DividendAnalytics` (per-share amount, yield on cost, all-time/trailing totals, portfolio yield on cost, upcoming-event estimates) with an injected clock and calendar; verify golden tests for the March/June, yield-on-cost (0.50 / 2.00%), forward-unavailable, and upcoming-dividend scenarios.

## 4. CSV import (YanaDomain)

- [x] 4.1 Port the RFC 4180-style parser and decimal-comma number parsing from `app/api/transactions/import/route.ts`; verify tests ported from the web importer's behavior cover quoted fields, `""` escapes, CRLF, blank lines, and decimal commas.
- [x] 4.2 Implement `CSVImportPlanner`, which maps header columns (with `price` → `amount` for dividend/fee rows and unsupported currency → EUR), validates each row before creating a holding, and returns holdings to create, transactions to insert, and per-line errors; verify tests for the 20-row/3-ticker import, a bad `type` row that creates no holding, and missing required columns.

## 5. Sync contract and merge (YanaSync)

- [x] 5.1 Implement the canonical payload codec (sorted keys, `Decimal` as strings, ISO-8601 UTC timestamps, `YYYY-MM-DD` dates, `schemaVersion` = 1) for all four record types, and document it in `apple/docs/sync-payload-v1.md`; verify round-trip tests and byte-equal comparison against checked-in golden JSON files.
- [x] 5.2 Implement `Merge.decide(local:incoming:)` (apply, keep local, or defer for an unknown schema) and the local-edit version bump (stored revision + 1, now, own device ID), including re-creation over a known tombstone; verify a merge-matrix test covering update vs update, delete vs stale update in both orders, equal revisions with timestamp/device tiebreaks, and newer-schema deferral.
- [x] 5.3 Define the `SyncTransport` and `SyncRecordStore` protocols and a `SyncCoordinator` that handles outbox re-enqueueing, applying incoming records, server-conflict resolution, portfolio-tombstone child cascade, and orphan tolerance, plus an in-memory transport fake; verify a two-device simulation test where concurrent offline edits, a delete vs a stale edit, the same ticker added on both devices, and a transaction arriving before its holding all converge to identical record sets.

## 6. Market data (YanaMarketData)

- [x] 6.1 Define `MarketDataProvider` (quotes, security details, FX, dividend events, `requiresCredential`, per-item `Result`s) and the `CredentialStore` protocol; verify the package compiles with a test-only keyed provider and an in-memory credential store.
- [x] 6.2 Implement the `MarketDataService` actor (15-minute quote and 1-hour FX TTLs, same-currency rate 1, per-key in-flight coalescing, concurrency cap of 4, exponential backoff with jitter on 429/5xx, partial-failure reporting that keeps the previous cached values) over a cache protocol; verify stub-provider tests for fresh vs stale reuse, coalescing, backoff on 429, and 9-of-10 partial success.
- [x] 6.3 Implement `YahooFinanceProvider` (chart endpoint for price/currency/name/asset class and `XXXYYY=X` FX, cookie+crumb `quoteSummary` for sector and dividend calendar, `events=div` fallback for annual rate/frequency, the ported `detectFrequency`, ephemeral cookie-isolated session); verify `URLProtocol`-stubbed tests using fixture responses (hardcoded in the endpoints' JSON shape; `apple/scripts/record-yahoo-fixtures.sh` can replace them with live captures), that requests contain only symbols, and the crumb-failure fallback.

## 7. Local persistence (YanaMac)

- [x] 7.1 Implement the SwiftData `@Model` types and repositories for `Portfolio.store` (records with UUID foreign keys, `needsUpload`, `pendingRemotePayload`, device identity, engine state) using a single `ModelActor` for writes; verify in-memory repository tests for CRUD round-trips to domain structs, holding uniqueness, the holding-delete guard message, portfolio cascade tombstones, and goal-scope replacement as upserts plus tombstones.
- [x] 7.2 Implement `MarketCache.store` repositories (quotes, FX, dividend events, one value snapshot per portfolio per local day) conforming to the market-data cache protocol; verify in-memory tests for snapshot uniqueness per day and for deleting and rebuilding the cache without touching `Portfolio.store`.

## 8. iCloud sync (YanaMac)

- [x] 8.3 Expose a `SyncStatus` model (up to date, syncing, pending count, offline, error with reason, last successful sync, read-only notice for records needing an app update) and a Sync Now action; verify unit tests derive each status from coordinator state.

## 9. macOS workspace UI (YanaMac)

- [x] 9.1 Build the app shell: `NavigationSplitView` sidebar sections, portfolio switcher, onboarding/create-portfolio flow, restoration of selected portfolio and section, and menu commands (⌘N, ⇧⌘N, ⌘I, ⌘R, ⌘,); verify a UI test that creates a first portfolio from the empty state and that relaunch restores the last selection.
- [x] 9.2 Build the Dashboard (summary metrics, top 5, fetch time, empty state) and the Holdings `Table` (sortable columns, unavailable cells for missing prices, show-closed toggle, add by ticker with provider lookup, unknown-ticker error, offline manual entry, edit, guarded delete); verify view-model tests and a UI test adding, sorting, and deleting a holding against a stub provider.
- [x] 9.3 Build the Transactions view (newest-first `Table`, ticker/type/year filters, create/edit sheet with inline validation, delete confirmation) and the CSV import (open panel and window drop, result sheet with per-line errors); verify a UI test that edits a buy and sees holdings update, and an import test with a fixture CSV containing one bad row.
- [x] 9.4 Build the Income view (monthly bar chart, trailing 12 months, forward annual with an unavailable state, per-holding table) and the Dividends view (year filter, totals, yield on cost, upcoming calendar); verify view-model tests against calculator fixtures and accessibility labels on the chart marks.
- [x] 9.5 Build the Analytics view (allocation chart with holding/sector/asset-class grouping, goals editor with sum validation, recommendations table, value-history chart with range selection) and daily snapshot writing; verify view-model tests for range filtering and goal-save errors, and VoiceOver labels per allocation slice.
- [x] 9.7 Apply locale-aware `FormatStyle` formatting for currency, percent, number, and date across every view, and check light/dark appearance; verify snapshot or UI tests in light and dark mode and with a non-English locale (e.g. `de_DE` decimal comma).

## 10. Integration verification

- [x] 10.1 Run `swift test` in `apple/YanaKit`, `xcodebuild test -scheme YanaMac`, `npm run lint`, and `npm run build`; verify all pass and that no file outside `apple/`, `.gitignore`, and lint configuration changed in the web app, except fixing pre-existing lint errors (`components/analytics/growth-chart.tsx`) so `npm run lint` passes.

## Deferred

Tasks 7.3, 8.1, 8.2, 9.6, 10.2 and 10.3 have code but still need verification on a signed build or manual iCloud runs. They moved to `apple/docs/possible-improvements.md`, along with the signing setup follow-up.

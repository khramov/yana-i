# Design

## Context

See `proposal.md` for motivation. Behavior contracts are in `specs/native-portfolio-storage`, `specs/icloud-portfolio-sync`, `specs/macos-portfolio-workspace`, and `specs/native-market-data`.

The repository today is a Next.js 16 app (`app/`, `components/`, `lib/`) backed by `better-sqlite3`/Drizzle at `data/yana.db`. The portfolio domain lives in a few places:

- `lib/db/schema.ts`: portfolios, holdings (unique per portfolio + ticker), transactions (`buy | sell | dividend | fee`; a dividend's total amount is stored in `price`), goals (`holding | asset_class` scope; the PUT replaces a whole scope), price/FX caches, dividend metadata, and daily snapshots. All IDs are autoincrement integers.
- `lib/portfolio.ts`: average-cost position math. A buy folds its lot cost plus fee into the average; a sell only reduces shares, clamped at 0.
- `app/api/portfolio/*`: summary, allocation, income, dividends, and recommendations, all computed per request with JS floats. An FX rate that cannot be fetched silently falls back to `1`.
- `lib/yahoo.ts` and `lib/fx.ts`: `yahoo-finance2` with 15-minute quote and 1-hour FX caches.
- `app/api/transactions/import/route.ts`: an RFC 4180-style CSV parser with per-row validation.

The native app shares no code or data with the web app. It ports the domain semantics to Swift and changes them only where the specs require it (decimal arithmetic, missing FX shown as unavailable).

## Goals / Non-Goals

**Goals:**

- Keep the domain model, calculations, CSV parsing, merge rules, and sync payload codec in a UI-free, CloudKit-free, SwiftData-free Swift package that runs under `swift test` without signing or an iCloud account.
- Keep SwiftData and CloudKit as thin adapters behind protocols, so a later PostgreSQL-backed API can replace the CloudKit adapter while reusing the payload contract and merge logic.
- Make every local write durable and immediately visible, with sync as a background reconciliation that can always be retried.

**Non-Goals:**

- iOS/iPadOS targets, widgets, menu-bar extras, Shortcuts, or multiple windows per portfolio.
- Shared or collaborative portfolios, CloudKit sharing, or end-to-end encryption beyond what the iCloud private database provides.
- Changes to the Next.js app, its database, or the `add-local-first-folder-sync` change.
- CSV export, undo/redo history, and tombstone garbage collection. Tombstones are retained indefinitely, which is acceptable at personal-portfolio scale.

## Decisions

### Repository layout: a Swift package plus a thin Xcode app

```
apple/
  YanaKit/                      Swift package (macOS 14+)
    Sources/YanaDomain/         records, validation, calculations, CSV import
    Sources/YanaSync/           payload codec, ordering/merge, sync coordinator protocols
    Sources/YanaMarketData/     provider protocol, Yahoo adapter, cache policy, throttling
    Tests/…                     golden fixtures, merge matrix, codec round-trips, stubbed HTTP
  YanaMac/                      Xcode project: SwiftUI app, SwiftData store, CloudKit + Keychain adapters
  docs/sync-payload-v1.md       the portable payload contract
```

The app target depends on the local package. Everything testable without Apple services lives in `YanaKit`. The Xcode project is committed as-is rather than generated.

*Alternatives:* An XcodeGen/Tuist-generated project avoids `.pbxproj` merge noise but adds a toolchain dependency that a single-developer repo does not need. A single app target with no package would make the domain untestable without a signing host and would invite SwiftUI and SwiftData types into the domain.

### Domain records are plain value types with decimal money and calendar dates

`PortfolioRecord`, `HoldingRecord`, `TransactionRecord`, and `GoalRecord` are `Codable, Sendable, Equatable` structs. Each one carries:

- `id: UUID`
- `version: RecordVersion`, where `RecordVersion` is `(revision: Int64, modifiedAt: Date, deviceID: UUID)` and is `Comparable` lexicographically
- `deletedAt: Date?`, which marks a tombstone

Money, quantities, and rates use `Decimal`. Transaction dates use a `LocalDate` (`YYYY-MM-DD`) type, so a date never shifts with the time zone. Enumerations are `Currency` (EUR, USD, RUB), `AssetClass`, `TransactionKind`, and `GoalScope`.

The transaction model is cleaner than the web schema:

- `quantity` and `unitPrice` for buy and sell
- `amount` for dividend and fee
- `fee`, `tax`, `currency`, `notes`
- `holdingID` and `portfolioID` as UUIDs

The CSV importer maps the web's `price` column to `amount` for dividend and fee rows.

*Alternative:* `Double` would match the web app's numbers exactly but breaks the exact-arithmetic requirement (0.1 + 0.2). Display rounding happens only in the view layer.

### Calculations are pure functions over records

`YanaDomain` exposes deterministic functions that take records plus a `MarketSnapshot` (quotes and FX rates with their fetch times) and return value types:

- `PositionCalculator`
- `PortfolioValuation`: summary and top 5
- `AllocationCalculator`: by holding, sector, or asset class
- `IncomeCalculator`: monthly, trailing 12 months, forward annual
- `DividendAnalytics`: per-share amount, yield on cost, all-time and trailing-12-month totals
- `RebalanceCalculator`: drift, buy amount, buy shares

They port the web formulas (see Context), with two documented changes:

- A missing FX rate makes the dependent value `nil` instead of converting at rate 1.
- A missing price excludes the position from value but not from cost basis.

Each function gets golden-fixture tests built from the spec scenarios. "Trailing 12 months" and "today" come from an injected clock and calendar.

### Holding and goal identities are derived; others are random

Holding IDs are `UUIDv5(namespace, "holding|<portfolioID>|<NORMALIZED_TICKER>")`. Goal IDs are `UUIDv5(namespace, "goal|<portfolioID>|<scope>|<key>")`. Portfolio and transaction IDs are random `UUIDv4`.

Two Macs that create the same ticker or goal key offline therefore produce the same record ID, and the ordinary merge rule converges them to one record. A goal-scope save is turned into one upsert per kept key and one tombstone per removed key. Re-adding a deleted holding locally bumps its revision above the known tombstone.

*Alternative:* Random IDs plus a post-sync duplicate-merge pass that re-parents transactions. That needs a multi-record repair protocol that would itself have to sync. Derived IDs make the collision impossible. The cost is that tickers are immutable, which the spec already states.

### Local persistence: two SwiftData stores behind repository protocols

`YanaMac` defines `@Model` classes that mirror the records one-to-one. They use `@Attribute(.unique) var id: UUID` and plain UUID foreign-key fields, not `@Relationship`, so orphans that arrive before their parent are representable and harmless. Repositories (`PortfolioRepository`, `MarketCacheRepository`) convert between models and domain structs. Views and services never touch `@Model` types directly.

There are two `ModelConfiguration`s, each with `cloudKitDatabase: .none`:

- `Portfolio.store`: user records plus local-only sync bookkeeping (`DeviceIdentity`, `SyncEngineState`, and per-record `needsUpload` and `pendingRemotePayload`).
- `MarketCache.store`: quotes, FX rates, dividend events, and value snapshots. It can be deleted and rebuilt at any time.

Both files live in the app's sandboxed Application Support directory.

*Alternatives:*
- GRDB/SQLite gives more control and maps more naturally to a future SQL backend, but the proposal names SwiftData and it integrates with SwiftUI observation.
- Letting SwiftData mirror to CloudKit automatically is covered in the next decision.

### Sync transport: `CKSyncEngine` with opaque versioned payloads, not SwiftData/CloudKit mirroring

Sync uses `CKSyncEngine` (macOS 14+) against the private database, in one custom zone named `Portfolio`.

Each record becomes one `CKRecord` whose record type is the entity name and whose `recordName` is the UUID. Its fields are:

- `payload: Bytes`: canonical JSON of the record per `docs/sync-payload-v1.md`. Keys are sorted, `Decimal` values are strings, timestamps are ISO-8601 UTC, and `LocalDate` is `YYYY-MM-DD`.
- `schemaVersion: Int64`
- `revision: Int64`, `modifiedAt: Date`, `deviceID: String`
- `deleted: Int64`

Only those scalar fields are added to the CloudKit schema. New domain fields change the payload and its `schemaVersion`, never the production CloudKit schema, which can only grow.

Built-in SwiftData/`NSPersistentCloudKitContainer` mirroring was rejected because it:
- forbids unique constraints and requires every attribute to be optional,
- resolves conflicts per field with an opaque last-writer-wins rule,
- turns deletes into hard deletes that a stale edit can resurrect,
- gives no portable payload to reuse with a future API,
- and would sync whatever configuration it is attached to.

### Merge rule and durable outbox

`YanaSync.Merge.decide(local:incoming:)` is a pure function with three outcomes: apply incoming, keep local, or defer for an unknown schema. Incoming wins only if its `RecordVersion` is greater. A tombstone is just a record with `deletedAt`, so it competes under the same ordering and stale edits cannot resurrect it.

A local edit sets `revision = stored.revision + 1`, `modifiedAt = now`, `deviceID = self`, and `needsUpload = true` in the same SwiftData save as the edit itself. That flag is the durable outbox. On launch and on account availability, every `needsUpload` record is re-added to the engine's pending changes, so a crash between the save and engine-state persistence loses nothing. A successful send clears the flag only if the sent revision still matches the stored one.

On `serverRecordChanged`, the server record goes through the same merge. If the server version wins, it is applied locally. If the local version wins, it is re-sent on top of the server record's change tag.

Deleting a portfolio tombstones its children locally with bumped revisions, and each tombstone uploads. When a portfolio tombstone is received, any live children the Mac knows about are also tombstoned and uploaded. That covers children created offline on another Mac.

A payload whose `schemaVersion` is newer than the app supports is stored in `pendingRemotePayload` and is never decoded or overwritten. The local copy is locked read-only in the UI with an "Update the app" notice.

*Alternative:* the Lamport clock used by the folder-sync change. Per-record revisions with a timestamp and device tiebreak converge just as deterministically for single-record conflicts and need no global counter. Clock skew only affects ties between equal revisions.

### Account changes and push

`CKSyncEngine` account events drive the sync state machine:

| Event | Action |
|---|---|
| `signIn` | Re-enqueue all records, so data created while signed out uploads to the new account. |
| `signOut` / `switchAccounts` | Count the `needsUpload` records, show a blocking warning sheet, then delete all user records and the engine state from `Portfolio.store`. |
| `CKContainer.accountStatus` (`noAccount`, `restricted`, `temporarilyUnavailable`, `couldNotDetermine`) | Map to the visible status reasons. |

The app registers for remote notifications. The engine's automatic zone subscription delivers changes while the app runs, and the engine fetches on launch. Entitlements:
- iCloud (CloudKit) with container `iCloud.<bundle-id>`
- Push Notifications
- App Sandbox with outgoing network client
- User-selected read-only file access for CSV

### Market data: provider protocol, a caching actor, and a Yahoo adapter

`YanaMarketData` defines a `MarketDataProvider` protocol with:
- `quotes`
- `securityDetails`
- `fxRates`
- `dividendEvents`
- `requiresCredential`

Every call returns per-item `Result`s, so one failing ticker never fails the batch.

`MarketDataService` is an actor on top of the provider. It:
- applies the TTLs (15 minutes for quotes, 1 hour for FX),
- coalesces in-flight requests per ticker or pair through a dictionary of `Task`s,
- caps concurrency at 4,
- retries HTTP 429 and 5xx with exponential backoff and jitter,
- writes through to `MarketCache.store`,
- refreshes only on foreground triggers.

`YahooFinanceProvider` uses `URLSession` with an ephemeral, cookie-isolated configuration:

| Data | Endpoint |
|---|---|
| Price, currency, name, instrument type → asset class | `v8/finance/chart/<SYMBOL>` (no crumb) |
| FX rates | the same endpoint with `<FROM><TO>=X` symbols |
| Sector, ex/pay dates, annual rate, last amount | `v10/finance/quoteSummary` (`assetProfile`, `calendarEvents`, `summaryDetail`), after the cookie + `getcrumb` handshake |

If the handshake fails, the annual rate and frequency are estimated from the chart endpoint's `events=div` history. Requests contain only symbols. The frequency thresholds port `detectFrequency` from `app/api/dividends/refresh/route.ts`.

`CredentialStore` is a protocol with a Keychain implementation that uses:
- `kSecClassGenericPassword`
- `kSecAttrSynchronizable = false`
- `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`

Settings shows credential fields only for a provider whose `requiresCredential` is true. No shipping provider needs one yet, so this path is covered by a test-only keyed provider.

*Alternatives:*
- Bundling a Swift Yahoo library: none is maintained well enough, and the adapter is small.
- An official keyed API: deferred by the user's decision. The protocol keeps it a drop-in later.

### UI architecture

The UI is a SwiftUI `App` with:
- one `WindowGroup` holding a `NavigationSplitView` (sidebar sections plus a portfolio switcher),
- a `Settings` scene,
- `.commands` for the menu shortcuts.

`@Observable` models (`AppModel`, plus one per section) call repositories and the domain calculators and expose view-ready values. Holdings and transactions use `Table` with `KeyPathComparator` sorting. Charts use Swift Charts with `accessibilityLabel` and `accessibilityValue` per mark. Selection is restored from `@SceneStorage` and `@AppStorage` UUID strings. Formatting uses `FormatStyle` (`.currency(code:)`, `.percent`, `Date.FormatStyle`) with the person's locale.

The CSV import accepts both `fileImporter` and `onDrop` and shows a result sheet. Value snapshots are written once per portfolio per local calendar day, when a valuation has a non-nil total.

### Testing strategy

- **`swift test` (YanaKit):**
  - Golden fixtures for every calculation scenario in the specs.
  - CSV parser cases ported from the web importer: quotes, `""`, CRLF, decimal comma, unsupported currency → EUR.
  - UUIDv5 vectors.
  - Merge-decision matrix covering update vs update, delete vs stale update, both orders, equal revisions, and unknown schema.
  - Payload codec round-trips against checked-in golden JSON.
  - Market data through a stub `URLProtocol` covering partial failure, 429 backoff, coalescing, and TTLs.
- **Xcode tests (YanaMac):**
  - Repository tests on in-memory `ModelConfiguration`s.
  - A two-device sync simulation in which two coordinators exchange records through an in-memory `SyncTransport` fake that stands in for `CKSyncEngine`.
  - Keychain store tests.
- **Manual pre-release:** two Macs on one development-environment iCloud account, then a CloudKit schema deploy to production.

## Risks / Trade-offs

- **[Yahoo endpoints are unofficial and the crumb handshake changes periodically]** → Isolate everything in one adapter. Keep the chart endpoint, which needs no crumb, as the price/FX path and a degraded fallback for dividends. Surface "market data offline" rather than wrong numbers. The provider protocol allows a keyed provider later.
- **[SwiftData on macOS 14 has known bugs with unique attributes and background contexts]** → Use a single `ModelActor` for writes, keep SwiftData behind repositories, and test repositories against in-memory stores. Swapping to GRDB later is a contained change.
- **[`CKSyncEngine` is new on macOS 14 and its state must be persisted correctly]** → The `needsUpload` flag is the source of truth for pending work, and the engine state is only an optimization. Re-enqueueing on launch is idempotent because merges are idempotent.
- **[Deriving IDs from the ticker makes ticker renames, such as corporate symbol changes, impossible]** → Documented as unsupported. The workaround is a new holding plus a sell/buy pair. A future migration could add an alias record.
- **[Clock skew between Macs affects tie-breaking at equal revisions]** → Revision dominates. Skew only picks between two edits made concurrently from the same base, and either result is acceptable.
- **[Account switching deletes unsent local changes]** → A blocking warning shows the pending count before deletion. This follows Apple's guidance not to mix accounts.
- **[Re-importing the same CSV creates duplicate transactions, as the web app also does]** → The result summary makes imports visible. Deduplication is left to a future change.
- **[CloudKit production schema is additive-only]** → Only six record fields exist. All evolution happens inside the versioned payload.

## Migration Plan

This is greenfield, with no data migration: the app starts empty (spec: Empty initial state), and existing history is brought in through CSV import.

1. Develop against the CloudKit development environment with a dedicated container.
2. Before the first release, deploy the record types to CloudKit production and test on two Macs with a production-signed build.
3. Rollback means shipping a previous build. Payloads are versioned and unknown versions are preserved, so an older build cannot corrupt newer records. Deleting the app leaves the iCloud data intact.

## Open Questions

- Bundle identifier, Apple Developer team, and CloudKit container name. These are configuration values and don't change the design.
- Distribution channel: Mac App Store or Developer ID with notarization. CloudKit and push work with both, so the decision can wait until the release checklist.

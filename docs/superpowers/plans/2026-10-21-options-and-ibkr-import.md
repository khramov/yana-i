# Options Holdings and IBKR Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Options as holdings with a contract multiplier, entered by hand or imported from Interactive Brokers Activity Statements, with re-imports that override earlier imports for their date range and opening balances that keep holdings equal to the latest statement.

**Architecture:** All parsing and reconciliation is pure code in `YanaDomain` (testable with `swift test`). A statement or the app's own CSV becomes a neutral `ImportBatch`. `ImportReconciler` turns a batch plus the portfolio's current records into an `ImportPlan` (records to save). The Mac app's repository commits that plan in one save through the existing `SyncCoordinator`. New record fields are optional and added to sync payload v1 in place.

**Tech Stack:** Swift 5.10, Swift Testing, SwiftData, SwiftUI, macOS 14.

**Spec:** `docs/superpowers/specs/2026-10-21-options-and-ibkr-import-design.md`

## Global Constraints

- Scope is `apple/` only. No change to the Next.js app.
- New payload fields are optional and **omitted when absent**, so every existing golden file keeps its exact bytes. Sync payload stays `schemaVersion` 1.
- Decimals are `Decimal` in code, canonical strings in payloads and SwiftData (`StoredDecimal.string`). Never `Double`.
- Multiplier 1 (or absent) must leave every existing calculation unchanged: all existing tests pass without edits, except the `CSVImportPlanner` call sites that Task 6 moves to the new API.
- `sample data/` is personal account data: git-ignored, never committed. Test fixtures are hand-made, anonymised copies.
- Package tests: `cd apple/YanaKit && ./test.sh`. App tests: `cd apple/YanaMac && xcodebuild test -scheme YanaMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`, run in Debug **and** with `-configuration Release ENABLE_TESTABILITY=YES`.
- Commit messages follow the repo style: `feat(apple): …`, `test(apple): …`, `docs(apple): …`.

## Review Focus

1. **Import order independence.** Importing statements A then B, or B then A, must leave identical positions. Pinned in Task 7 (`openingIsOrderIndependent`).
2. **The same file imported twice** must change nothing the second time: no duplicates, no new opening row, counts show everything replaced. Pinned in Task 6 (`reimportingSameBatchIsIdempotent`).
3. **Same-day trades vs. the opening balance.** An opening buy dated on the period start must sort before a real trade on that same day. Pinned in Task 7 (`openingSortsBeforeSameDayTrade`).
4. **A BOM and Windows line endings** in either format must import normally. Pinned in Task 5 (`parsesWithBOMAndCRLF`) and Task 6 (`simpleCSVWithBOMImports`).
5. **A statement where a holding was fully sold** (absent from Open Positions) must end at 0 shares, with no negative opening. Pinned in Task 7 (`soldOutHoldingTargetsZero`).

---

### Task 1: Record fields, payload, and sync doc

**Files:**
- Modify: `apple/YanaKit/Sources/YanaDomain/Enums.swift`, `apple/YanaKit/Sources/YanaDomain/Records.swift`
- Modify: `apple/YanaKit/Sources/YanaSync/PayloadCodec.swift`
- Modify: `apple/YanaKit/Tests/YanaSyncTests/Fixtures.swift`. Golden: add `apple/YanaKit/Tests/YanaSyncTests/Golden/option-holding.json` and `opening-transaction.json`
- Modify: `apple/docs/sync-payload-v1.md`

**Interfaces:**
- Produces:
  - `AssetClass.option` (raw value `"option"`)
  - `public enum ImportSource: String, Codable, Sendable, Hashable { case ibkr, csv }`
  - `public struct OpeningBalance: Equatable, Hashable, Sendable { var asOf: LocalDate; var targetQuantity: Decimal; var targetCostBasis: Decimal; var coveredFrom: LocalDate }` with a memberwise public init
  - `HoldingRecord.multiplier: Decimal?` (init param `multiplier: Decimal? = nil`, after `currency`), and `var effectiveMultiplier: Decimal { multiplier ?? 1 }`
  - `TransactionRecord.importSource: ImportSource?` and `openingBalance: OpeningBalance?` (init params with `nil` defaults, after `notes`)
  - Payload keys: holding `multiplier` (decimal string). Transaction `importSource` (string) and `openingBalance` = object `{asOf, coveredFrom, targetCostBasis, targetQuantity}` (dates `YYYY-MM-DD`, decimals as strings)

- [ ] **Step 1: Write the failing tests.** In `Fixtures.swift` add `Sample.optionHolding` (ticker `PBR271217C00027000`, name `PBR 17DEC27 27 C`, `.option`, `.usd`, multiplier `100`) and `Sample.openingTransaction` (buy, quantity `20`, unitPrice `90`, `importSource: .ibkr`, `openingBalance: OpeningBalance(asOf: 2026-10-19, targetQuantity: 30, targetCostBasis: 2801.25, coveredFrom: 2026-08-03)`), and append both to `Sample.all` as `"option-holding"` and `"opening-transaction"`. The existing parameterised `matchesGoldenBytes` and `roundTrips` tests cover them.
- [ ] **Step 2: Run to see them fail.** Run `cd apple/YanaKit && ./test.sh --filter PayloadCodecTests`. Expected: compile errors for the missing members.
- [ ] **Step 3: Implement** the enum case, structs, and record fields, then encode and decode the new keys in `PayloadCodec` using its existing `put`/`optionalDecimal` helpers (an absent key decodes as `nil`).
- [ ] **Step 4: Record the golden files.** Run `YANA_RECORD_GOLDEN=1 ./test.sh --filter PayloadCodecTests`, then `./test.sh`. Expected: all pass, and `git diff --stat -- Tests/YanaSyncTests/Golden` shows **only the two new files**.
- [ ] **Step 5: Update the doc.** In `apple/docs/sync-payload-v1.md`, add `option` to `assetClass`, add `multiplier` to Holding ("decimal > 0, optional; omitted means 1"), and add `importSource` and `openingBalance` to Transaction with one line each on their meaning (from the spec's Data model section).
- [ ] **Step 6: Commit.** `git commit -m "feat(apple): option asset class, multiplier, and import provenance fields"`

### Task 2: Mac persistence and labels for the new fields

**Files:**
- Modify: `apple/YanaMac/YanaMac/Persistence/PortfolioSchema.swift` (`StoredHolding`, `StoredTransaction`)
- Modify: `apple/YanaMac/YanaMac/Persistence/PortfolioStore.swift:42` (`transactions(inPortfolio:)`)
- Modify: `apple/YanaMac/YanaMac/Formatting/Formatting.swift:60` (`Fmt.assetClass`)
- Modify: `apple/YanaMac/YanaMac/Persistence/PortfolioRepository.swift` (`updateHolding` copies `multiplier`)
- Test: `apple/YanaMac/YanaMacTests/PortfolioRepositoryTests.swift`

**Interfaces:**
- Consumes: Task 1 fields.
- Produces: `PortfolioStore.transactions(inPortfolio:includingDeleted: Bool = false)`. `StoredHolding.multiplier: String?`. `StoredTransaction.importSource: String?` plus `openingAsOf: String?`, `openingCoveredFrom: String?`, `openingTargetQuantity: String?`, `openingTargetCostBasis: String?` (all four set together, or all nil). `Fmt.assetClass(.option) == "Option"`.

- [ ] **Step 1: Write the failing test** `optionHoldingAndOpeningRoundTrip()`: create a portfolio, then commit (through `repo.coordinator.commitLocalEdits`) an option holding with multiplier 100 and a transaction carrying `importSource` and `openingBalance`, and read both back with `store.holding(_:)` and `store.transaction(_:)`. Expect them equal to what was written, apart from the version.
- [ ] **Step 2: Run it.** Use the app test command from the Global Constraints with `-only-testing:YanaMacTests/PortfolioRepositoryTests`. Expected: FAIL to compile.
- [ ] **Step 3: Implement** the optional stored attributes (an additive SwiftData change, no migration stage) and their mapping in `init(_:)`, `update(from:)`, and `record`. Add the `includingDeleted` parameter, the `Fmt` case, and the `multiplier` copy in `updateHolding`.
- [ ] **Step 4: Run all app tests in Debug and in Release.** Expected: all pass.
- [ ] **Step 5: Commit.** `git commit -m "feat(apple): persist option and import fields"`

### Task 3: Multiplier in positions and valuation

**Files:**
- Modify: `apple/YanaKit/Sources/YanaDomain/PositionCalculator.swift`, `apple/YanaKit/Sources/YanaDomain/PortfolioValuation.swift:75`
- Test: `apple/YanaKit/Tests/YanaDomainTests/PositionCalculatorTests.swift`, `PortfolioValuationTests.swift`; add `multiplier: Decimal? = nil` to the `holding(...)` helper in `TestSupport.swift`

**Interfaces:**
- Produces: `Position.costBasis` includes the multiplier, and `Position.averageCost` stays per share. `PositionValuation.marketValue = shares × priceBase × multiplier`.

- [ ] **Step 1: Write the failing tests.** `optionCostUsesMultiplier()`: holding with multiplier 100, buys of 1 @ 2 with fee 1 and 3 @ 2.5 with fee 1. Expect shares `4`, costBasis `952`, averageCost `2.38`. `optionValueUsesMultiplier()`: the same position, quote 4 USD, base USD. Expect marketValue `1600` and unrealizedGain `648`.
- [ ] **Step 2: Run** `./test.sh --filter "PositionCalculatorTests|PortfolioValuationTests"`. Expected: FAIL (cost 2.8382358, value 6.45).
- [ ] **Step 3: Implement.** Use `lotCost = quantity × price × m + fee`, keep `averageCost` per share as `totalCost / (shares × m)`, and set `costBasis = shares × averageCost × m`, where `m = holding.effectiveMultiplier`. In the valuation, multiply market value by the holding's multiplier.
- [ ] **Step 4: Run** `./test.sh`. Expected: all pass, with the existing tests unchanged.
- [ ] **Step 5: Commit.** `git commit -m "feat(apple): contract multiplier in cost and market value"`

### Task 4: Option contract symbols

**Files:**
- Create: `apple/YanaKit/Sources/YanaDomain/OptionContract.swift`
- Test: `apple/YanaKit/Tests/YanaDomainTests/OptionContractTests.swift`

**Interfaces:**
- Produces:
  - `public enum OptionRight: String, Sendable, CaseIterable { case call = "C", put = "P" }`
  - `public struct OptionContract: Equatable, Sendable { var underlying: String; var expiry: LocalDate; var right: OptionRight; var strike: Decimal }`
  - `var occSymbol: String`: underlying upper-cased, `yyMMdd`, `C`/`P`, and strike × 1000 zero-padded to 8 digits
  - `var displayName: String`: `"<UNDERLYING> <dd><MMM upper-cased, English><yy> <strike without trailing zeros> <C|P>"`
  - `init?(occSymbol: String)`: accepts IBKR's space-padded form (`"PBR   271217C00027000"`) and returns nil for anything else

- [ ] **Step 1: Write the failing tests.** `occSymbolForPBRCall`: `OptionContract(underlying: "pbr", expiry: 2027-12-17, right: .call, strike: 27).occSymbol == "PBR271217C00027000"` and `displayName == "PBR 17DEC27 27 C"`. `fractionalStrike`: strike `27.5`, put, gives `"PBR271217P00027500"` and `"PBR 17DEC27 27.5 P"`. `parsesPaddedIBKRSymbol`: `OptionContract(occSymbol: "PBR   271217C00027000")` equals the first contract. `rejectsGarbage`: `OptionContract(occSymbol: "VWCE") == nil`.
- [ ] **Step 2: Run** `./test.sh --filter OptionContractTests`. Expected: FAIL to compile.
- [ ] **Step 3: Implement** in `OptionContract.swift`. Format the month with a fixed `en_US_POSIX` formatter, never the current locale.
- [ ] **Step 4: Run** the filter again. Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat(apple): OCC option symbols"`

### Task 5: IBKR Activity Statement parser

**Files:**
- Create: `apple/YanaKit/Sources/YanaDomain/ImportBatch.swift`, `apple/YanaKit/Sources/YanaDomain/IBKRStatementParser.swift`
- Create fixtures: `apple/YanaKit/Tests/YanaDomainTests/Fixtures/ibkr-aug-oct.csv` and `ibkr-dividends.csv`. Register them with `resources: [.copy("Fixtures")]` on `YanaDomainTests` in `Package.swift`.
- Test: `apple/YanaKit/Tests/YanaDomainTests/IBKRStatementParserTests.swift`
- Modify: `.gitignore` (add `sample data/`)

**Interfaces:**
- Produces, in `ImportBatch.swift`:
  ```swift
  public struct ImportedHolding: Equatable, Sendable { ticker: String; name: String?; assetClass: AssetClass; currency: Currency; multiplier: Decimal? }
  public struct ImportedRow: Equatable, Sendable { line: Int; ticker: String; kind: TransactionKind; date: LocalDate
      quantity: Decimal?; unitPrice: Decimal?; amount: Decimal?; fee: Decimal; tax: Decimal; currency: Currency; notes: String? }
  public struct ImportedPosition: Equatable, Sendable { ticker: String; quantity: Decimal; costBasis: Decimal }
  public struct ImportBatch: Equatable, Sendable { source: ImportSource; range: ClosedRange<LocalDate>
      holdings: [ImportedHolding]; rows: [ImportedRow]
      positions: [ImportedPosition]?   // IBKR only: Open Positions at range.upperBound
      errors: [CSVLineError]; warnings: [CSVLineError] }
  ```
  (all with public memberwise inits)
- Produces, in `IBKRStatementParser.swift`: `public enum IBKRStatementParser { static func isStatement(_ text: String) -> Bool; static func batch(from text: String) throws -> ImportBatch }`, which throws `CSVImportError("Statement period not found")` when `Statement,Data,Period` is missing. Also `static func yahooSuffix(exchange: String) -> String?`, which returns `nil` for an unknown exchange and `""` for US exchanges.
- Consumes: `CSVParser.parse`, `CSVParser.number`, `OptionContract(occSymbol:)`.

Parsing rules are in the spec's "Parsing", "Symbols" and "Currencies" sections. Additional decisions:
- Strip a leading U+FEFF before anything else, in `isStatement` and `batch` alike.
- Period: parse `"August 3, 2026 - October 19, 2026"` with an `en_US_POSIX` `MMMM d, yyyy` formatter.
- Trades in `Stocks` and `Equity and Index Options` only, with `DataDiscriminator == "Order"`. An option's ticker is `OptionContract(occSymbol:)` of the instrument's `Symbol` column in Financial Instrument Information (the row whose `Description` equals the trade's `Symbol`), and its name is the trade symbol (`PBR 17DEC27 27 C`). A trade without a matching instrument row is a line error.
- Stock tickers are `Symbol + yahooSuffix(exchange)`. An unknown exchange keeps the bare symbol and adds a warning `"<SYMBOL>: unknown exchange <X>, using the bare symbol"`.
- `Corporate Actions` data rows each add a warning `"Corporate actions are not supported"`.
- Positions come from `Open Positions` `Summary` rows. Quantity is `Quantity`, and cost basis is the `Cost Basis` column.
- Dividends: `Dividends` rows (`Currency,Date,Description,Amount`) join the `Withholding Tax` rows with the same date and ISIN. The ISIN is the text in parentheses in `Description`, which is matched to `Security ID` in Financial Instrument Information. Lines whose description starts with `Total` are skipped.

- [ ] **Step 1: Create the fixtures.** `ibkr-aug-oct.csv` has the sample file's Statement, Trades, Open Positions and Financial Instrument Information sections, in its exact format (BOM, CRLF, repeated headers, SubTotal/Total rows, forex rows), but with made-up quantities, prices and costs and no account information. `ibkr-dividends.csv` is a small hand-made statement with a period of `January 1, 2026 - March 31, 2026`, one VWCE instrument (`Security ID IE00BK5BQT80`, exchange `IBIS2`), a `Dividends` row `EUR,2026-03-25,VWCE(IE00BK5BQT80) Cash Dividend EUR 0.5 per Share (Ordinary Dividend),14`, a `Withholding Tax` row `EUR,2026-03-25,VWCE(IE00BK5BQT80) Cash Dividend EUR 0.5 per Share - IE Tax,-2.1,`, a GBP trade row, and a `Corporate Actions` row.
- [ ] **Step 2: Write the failing tests.**
  - `parsesWithBOMAndCRLF`: `isStatement` is true, and `range == 2026-08-03...2026-10-19`.
  - `stockTradesMapToYahooTickers`: the rows include `VWCE.DE buy 2026-08-14 qty 10 price 100 fee 1.25 EUR` and `XEON.DE buy 2026-10-07 qty 4 price 140 fee 1`.
  - `optionTradesUseOCCSymbol`: two buys for `PBR271217C00027000` (qty 1 @ 2 fee 1, qty 3 @ 2.5 fee 1, USD), and a holding with `.option`, multiplier 100, name `PBR 17DEC27 27 C`.
  - `forexIgnoredSilently`: no row for `EUR.USD`, and no error or warning mentions it.
  - `instrumentsGiveAssetClassAndExchange`: `EMIM.AS`, `SXR8.DE`, `AIFS.DE`, all `.etf`, with names from the descriptions.
  - `openPositions`: `VWCE.DE` 30 / 2801.25, `PBR271217C00027000` 4 / 952, and 6 positions in total.
  - `dividendWithWithholding`: one `.dividend` row for VWCE.DE on 2026-03-25 with amount 14 and tax 2.1.
  - `unsupportedCurrencyIsLineError`: the GBP trade's line number is in `errors`.
  - `corporateActionWarns`: its line number is in `warnings`.
  - `missingPeriodThrows`.
  - `exchangeSuffixes`: `IBIS2→".DE"`, `AEB→".AS"`, `LSEETF→".L"`, `NASDAQ→""`, `XYZ→nil`.
- [ ] **Step 3: Run** `./test.sh --filter IBKRStatementParserTests`. Expected: FAIL to compile.
- [ ] **Step 4: Implement** the parser. Read each section's `Data` rows against its most recent `Header`, keyed by column name.
- [ ] **Step 5: Run** the filter, then `./test.sh`. Expected: PASS.
- [ ] **Step 6: Commit,** checking that `git status` does not list `sample data/`. `git commit -m "feat(apple): parse IBKR activity statements"`

### Task 6: Reconciling a batch (range override, hand-entry absorption) and the simple CSV

**Files:**
- Create: `apple/YanaKit/Sources/YanaDomain/ImportReconciler.swift`
- Modify: `apple/YanaKit/Sources/YanaDomain/CSVImportPlanner.swift`, which becomes the producer of a simple-CSV `ImportBatch`
- Test: `apple/YanaKit/Tests/YanaDomainTests/ImportReconcilerTests.swift`. Update `CSVImportPlannerTests.swift` to the new API.

**Interfaces:**
- Consumes: `ImportBatch` (Task 5), `RecordIdentity.holdingID`, `TransactionDraft.validated()`.
- Produces:
  ```swift
  public struct ImportPlan: Equatable, Sendable {
      public var holdings: [HoldingRecord]          // created, revived, or filled-in holdings
      public var transactions: [TransactionRecord]  // inserts, tombstones, opening-balance rows
      public var added: Int, replaced: Int, absorbed: Int
      public var errors: [CSVLineError], warnings: [CSVLineError]
  }
  public enum ImportReconciler {
      /// `holdings` and `transactions` are the portfolio's records, tombstones included.
      public static func plan(_ batch: ImportBatch, portfolioID: UUID, holdings: [HoldingRecord],
                              transactions: [TransactionRecord], now: Date, deviceID: UUID) -> ImportPlan
      /// Detects the format (after stripping a BOM) and plans the import.
      public static func plan(text: String, portfolioID: UUID, holdings: [HoldingRecord],
                              transactions: [TransactionRecord], now: Date, deviceID: UUID) throws -> ImportPlan
  }
  extension CSVImportPlanner { public static func batch(csv: String) throws -> ImportBatch }  // source .csv, range = min...max row date
  ```
  The old `CSVImportPlanner.plan(...)` and `CSVImportPlan` are removed.

Rules come from the spec's "Re-import" section, steps 1–3. Additional decisions:
- New and changed records carry the version `.initial(at: now, deviceID:)` or `existing.version.bumped(at: now, deviceID:)`, as the current planner does. Tombstones set `deletedAt = now`.
- `replaced` counts the earlier imported rows tombstoned in step 1. `absorbed` counts hand entries tombstoned in step 2. `added` is the number of rows inserted.
- Holdings: create, or revive a tombstone, for each ticker the rows or positions need. On an existing live holding, fill only `name` and `multiplier` when they are nil, and never overwrite the owner's values.
- Inserted rows keep file order through `createdAt = now + index ms`, as today.
- With `positions == nil` (simple CSV), step 4 is skipped.
- When a batch ticker has a suffix (`VWCE.DE`) and a live holding exists with the bare symbol (`VWCE`), add the warning `"VWCE.DE: you also have a holding VWCE; merge them by hand"`.

- [ ] **Step 1: Write the failing tests.**
  - `insertsBatchRows`.
  - `replacesEarlierImportInRange`: an earlier `.ibkr` row dated inside the range is tombstoned, and one outside the range is untouched.
  - `otherSourceUntouched`: a `.csv` row is not replaced by an `.ibkr` batch.
  - `simpleCSVReplacesOnlyItsTickers`.
  - `absorbsLookAlikeHandEntry`: a hand buy with the same holding, date and quantity but a different price is tombstoned, and `absorbed == 1`.
  - `keepsDifferentHandEntry`: different quantity, so it's kept.
  - `oneFileRowAbsorbsOneHandEntry`: two identical hand entries and one file row give `absorbed == 1`.
  - `reimportingSameBatchIsIdempotent`: plan, apply the result to the inputs, plan again. The second plan has `added == replaced` and the live transaction count is unchanged.
  - `simpleCSVWithBOMImports`: `plan(text:)` on `"\u{FEFF}ticker,type,date,shares,price\r\nVTI,buy,2024-01-10,1,240\r\n"` adds 1.
  - `detectsIBKR`: `plan(text:)` on the Task 5 fixture adds 4 rows (2 stock trades, 2 option trades).
  - `warnsAboutBareTickerTwin`: with a live `VWCE` holding, the warning above is present.
- [ ] **Step 2: Run** `./test.sh --filter "ImportReconcilerTests|CSVImportPlannerTests"`. Expected: FAIL to compile.
- [ ] **Step 3: Implement** `ImportReconciler` steps 1–3. Rework `CSVImportPlanner` to emit a batch, keeping its existing validation and messages, then port `CSVImportPlannerTests` to `batch(csv:)` + `ImportReconciler.plan`, with the same expectations.
- [ ] **Step 4: Run** `./test.sh`. Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat(apple): imports override their date range and absorb matching hand entries"`

### Task 7: Self-correcting opening balances

**Files:**
- Modify: `apple/YanaKit/Sources/YanaDomain/ImportReconciler.swift` (step 4)
- Test: `apple/YanaKit/Tests/YanaDomainTests/OpeningBalanceTests.swift`

**Interfaces:**
- Consumes: `OpeningBalance`, `ImportPlan`, the spec's "Opening balances" section.
- Produces: no new API. Opening rows are `.buy` transactions with `importSource: .ibkr`, `openingBalance` set, `notes: "Opening balance"`, and `createdAt = Date(timeIntervalSince1970: 0)`, so they sort before any same-day trade under `PositionCalculator.chronological`.

The holdings in scope are those in `batch.positions`, plus those with any IBKR transaction (live or tombstoned) in the portfolio. For each one:
- The existing opening is the holding's transaction with a non-nil `openingBalance`, **tombstoned ones included**. A zero or negative opening is written as a tombstone that keeps its metadata, so the target survives.
- Target: if there's no existing opening or `batch.range.upperBound >= existing.asOf`, use `asOf = batch.range.upperBound` and take quantity and cost from the batch position, or 0 if the holding is absent. Otherwise keep the existing target.
- `coveredFrom` = min(existing `coveredFrom`, `batch.range.lowerBound`, earliest live IBKR row date of the holding).
- Quantity `q0` = targetQuantity − net quantity (buys − sells) of the holding's live non-opening transactions dated ≤ `asOf`, counting the rows being inserted by this plan as well.
- Price: solve for the opening lot cost `C0` so that the average-cost replay up to `asOf` ends at `targetCostBasis`:

```text
a = 1, b = 0, shares = q0                    // cost = a*C0 + b
for each live non-opening transaction ≤ asOf, chronological:
  buy  q@p fee f:  b += q*p*m + f; shares += q
  sell q:          k = (shares - q) / shares; a *= k; b *= k; shares -= q
C0 = a != 0 ? (targetCostBasis - b) / a : targetCostBasis
unitPrice = C0 / (q0 * m)
```

- `q0 == 0` writes or keeps a tombstone. `q0 < 0` also writes a tombstone, plus a warning `"<TICKER>: imported trades don't reconcile with the statement (<q0> shares)"`. If the result equals the existing opening (same quantity, price, metadata and deleted state), it's left out of the plan.

- [ ] **Step 1: Write the failing tests** using the Task 5 fixture plus hand-built batches:
  - `vwceOpeningFromSample`: 20 VWCE.DE on 2026-08-03 at `(2801.25 − 1001.25) / 20` = 90. The resulting position has 30 shares and cost basis 2801.25.
  - `heldOnlyPositionsGetFullOpening`: SXR8.DE 2 @ 500.
  - `optionOpeningIsZero`: PBR has no opening row, or only a tombstone.
  - `earlierStatementShrinksOpening`: a Jun–Sep batch containing a buy of 20 VWCE.DE leaves VWCE's opening tombstoned, with 30 shares still held.
  - `openingIsOrderIndependent`: (Aug–Oct, then Jun–Sep) and (Jun–Sep, then Aug–Oct) give equal shares and cost basis for every holding.
  - `olderStatementKeepsNewerTarget`.
  - `soldOutHoldingTargetsZero`: a holding with an earlier imported buy of 5, absent from the latest positions, ends at 0 shares with no warning.
  - `negativeOpeningWarns`.
  - `openingSortsBeforeSameDayTrade`: a trade on the period start date doesn't change the cost basis result.
  - `gapFoldsIntoOpening`: Jan–Mar and Jun–Aug imported, Apr–May missing, and the totals equal the Jun–Aug positions.
- [ ] **Step 2: Run** `./test.sh --filter OpeningBalanceTests`. Expected: FAIL.
- [ ] **Step 3: Implement** step 4 of `ImportReconciler.plan`.
- [ ] **Step 4: Run** `./test.sh`. Expected: all pass.
- [ ] **Step 5: Commit.** `git commit -m "feat(apple): opening balances keep holdings equal to the latest statement"`

### Task 8: Import in the app

**Files:**
- Modify: `apple/YanaMac/YanaMac/Persistence/PortfolioRepository.swift:198` (`importCSV`)
- Modify: `apple/YanaMac/YanaMac/App/AppModel.swift:57,297` (`CSVImportOutcome`, `importCSV(from:)`)
- Modify: `apple/YanaMac/YanaMac/Features/Transactions/TransactionsView.swift:209` (`CSVImportResultSheet`)
- Test: `apple/YanaMac/YanaMacTests/PortfolioRepositoryTests.swift`, `ViewModelTests.swift`; fixture `apple/YanaMac/YanaMacTests/Fixtures/ibkr-aug-oct.csv` (a copy of Task 5's)

**Interfaces:**
- Consumes: `ImportReconciler.plan(text:…)` (Task 6), `PortfolioStore.transactions(inPortfolio:includingDeleted:)` (Task 2).
- Produces: `PortfolioRepository.importFile(_ text: String, into portfolioID: UUID) async throws -> ImportPlan`, which replaces `importCSV` and commits `plan.holdings` + `plan.transactions` in one `commitLocalEdits` call. `CSVImportOutcome` gains `replaced: Int`, `absorbed: Int` and `warnings: [CSVLineError]`, and `imported` becomes `plan.added`.

- [ ] **Step 1: Write the failing tests.**
  - Repository `ibkrImportTwiceIsStable`: import the fixture twice. There are 4 live trades plus the openings, and positions match the fixture's Open Positions.
  - Repository `handEditedImportIsOverwritten`.
  - View model: the outcome for the fixture shows `imported == 4`, and the second run shows `replaced == 4`.
- [ ] **Step 2: Run** the app tests for these suites. Expected: FAIL to compile.
- [ ] **Step 3: Implement.** In the result sheet, show "N added, N replaced, N matched hand entries", then errors and then warnings with line numbers, in the sheet's existing style. Zero openings are tombstones, so the transaction lists already hide them and need no change.
- [ ] **Step 4: Run all app tests in Debug and in Release.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat(apple): import IBKR statements and re-import over earlier imports"`

### Task 9: Entering options by hand

**Files:**
- Modify: `apple/YanaKit/Sources/YanaDomain/Validation.swift` (`HoldingDraft`)
- Modify: `apple/YanaMac/YanaMac/Features/Holdings/HoldingsModel.swift` (`HoldingFormModel`), `HoldingFormSheet.swift`
- Modify: `apple/YanaMac/YanaMac/Features/Transactions/TransactionsView.swift` (field labels)
- Modify: `apple/YanaMac/YanaMac/Persistence/PortfolioRepository.swift` (`addHolding` passes `multiplier`)
- Test: `apple/YanaKit/Tests/YanaDomainTests/ValidationTests.swift`, `apple/YanaMac/YanaMacTests/ViewModelTests.swift`

**Interfaces:**
- Consumes: `OptionContract` (Task 4).
- Produces: `HoldingDraft.multiplier: Decimal?` (init param, default nil). `validated()` throws `ValidationIssue(.multiplier, "Multiplier must be greater than 0")` for values ≤ 0 (add the `.multiplier` case to `ValidationField`) and keeps nil as nil. `HoldingFormModel` gains `optionUnderlying: String`, `optionExpiry: Date`, `optionRight: OptionRight`, `optionStrike: String` and `optionMultiplier: String` (default `"100"`), plus `var optionPreview: OptionContract?`. When `assetClass == .option`, submit builds the draft from `optionPreview` (ticker `occSymbol`, name `displayName`, multiplier) and skips the market-data lookup for the name.

- [ ] **Step 1: Write the failing tests.**
  - `multiplierMustBePositive`: 0 and -1 throw, 100 passes, nil stays nil.
  - View model `optionFormBuildsOCCTicker`: underlying "pbr", expiry 2027-12-17, call, strike "27" and multiplier "100" add a holding with ticker `PBR271217C00027000`, name `PBR 17DEC27 27 C`, `.option` and multiplier 100.
  - `optionFormRequiresStrike`: an empty strike sets a field error and saves nothing.
- [ ] **Step 2: Run** the package and app tests for these suites. Expected: FAIL.
- [ ] **Step 3: Implement.** In the sheet, choosing Option shows underlying, expiry, call/put, strike and multiplier in place of the ticker, with a line previewing `displayName` and `occSymbol`. For an option holding, the transaction form labels quantity "Contracts" and price "Price per share".
- [ ] **Step 4: Run all package and app tests (Debug and Release).** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat(apple): add options by hand"`

### Task 10: Release testing and docs

**Files:**
- Modify: `apple/README.md` (Test section)

- [ ] **Step 1:** Under "App tests", add the Release command `xcodebuild test -scheme YanaMac -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES`, with one sentence explaining why: some SwiftData predicate failures only show up in optimized builds.
- [ ] **Step 2: Verify end to end.** Run `./test.sh` in `apple/YanaKit`, then the app tests in both configurations. Expected: all pass.
- [ ] **Step 3: Manual check.** Build Release, ad-hoc signed as in `test-ui.sh`, launch with `-YanaStoreDirectory <scratch dir>`, create a portfolio, and import the owner's statement from `sample data/` twice. Expected: holdings equal to its Open Positions, the PBR option valued at contracts × live price × 100, and the second import reports everything replaced and nothing added.
- [ ] **Step 4: Commit.** `git commit -m "docs(apple): run app tests in Release too"`

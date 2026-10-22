# native-portfolio-storage Specification

## Purpose
Stores a person's portfolios, holdings, transactions, and allocation goals locally on the Mac with portable identities, validates them, and derives portfolio calculations from them deterministically while offline.

## Requirements

### Requirement: Empty initial state
On first launch the native application SHALL start with no portfolios and SHALL NOT read, import, or depend on the web application's SQLite database or any of its files.

#### Scenario: First launch on a new Mac
- **WHEN** a person opens the app for the first time and no synchronized data exists in their iCloud account
- **THEN** the app presents an empty state that offers to create a first portfolio, and no portfolio, holding, transaction, or goal exists locally

#### Scenario: Web app data present on the same Mac
- **WHEN** the web application's `data/yana.db` exists on the same Mac
- **THEN** the native app neither opens nor imports it, and its records do not appear in the native app

### Requirement: Portable record identity
Every portfolio, holding, transaction, and allocation goal SHALL have a UUID identity assigned once at creation and never changed. Relationships between records SHALL refer to those UUIDs, never to store-specific row identifiers.

#### Scenario: Record created offline
- **WHEN** a person creates a transaction while the Mac has no network connection
- **THEN** the transaction receives its permanent UUID immediately and references its holding and portfolio by their UUIDs

#### Scenario: Identity survives a store rebuild
- **WHEN** the local store is deleted and rebuilt from synchronized records
- **THEN** every rebuilt record keeps the UUID it had before the rebuild

### Requirement: Portfolio records
A portfolio SHALL have a non-empty name and a base currency from the supported set (EUR, USD, RUB). The default base currency SHALL be EUR. A person SHALL be able to rename a portfolio, change its base currency, and delete it.

#### Scenario: Create a portfolio with defaults
- **WHEN** a person creates a portfolio named "Long term" without choosing a currency
- **THEN** the portfolio is stored with base currency EUR

#### Scenario: Reject an empty name
- **WHEN** a person saves a portfolio whose trimmed name is empty
- **THEN** the portfolio is not saved and the name field shows a validation error

#### Scenario: Delete a portfolio
- **WHEN** a person confirms deletion of a portfolio
- **THEN** the portfolio and all of its holdings, transactions, and goals are deleted together

### Requirement: Holding uniqueness per portfolio
A holding SHALL be identified within its portfolio by its ticker, normalized by trimming and upper-casing. A portfolio SHALL contain at most one live holding per normalized ticker, and the ticker of an existing holding SHALL NOT be editable.

#### Scenario: Add a ticker that already exists
- **WHEN** a person adds " aapl " to a portfolio that already holds AAPL
- **THEN** no second holding is created and the existing AAPL holding is shown

#### Scenario: Same ticker in different portfolios
- **WHEN** a person adds AAPL to two different portfolios
- **THEN** each portfolio has its own independent AAPL holding

### Requirement: Holding attributes
A holding SHALL store an optional display name, an optional sector, an asset class from the set stock, etf, bond, cash, and a trading currency. When no asset class is known, the holding SHALL use stock. A person SHALL be able to edit every attribute except the ticker.

#### Scenario: Edit holding metadata
- **WHEN** a person changes a holding's asset class from stock to etf
- **THEN** the change is saved and the allocation views group the holding as ETF

### Requirement: Holding deletion guard
The system SHALL refuse to delete a holding that still has transactions and SHALL tell the person how many transactions block the deletion.

#### Scenario: Delete a holding with transactions
- **WHEN** a person deletes a holding that has 3 transactions
- **THEN** the holding is kept and the person is told that 3 transactions must be deleted first

#### Scenario: Delete an unused holding
- **WHEN** a person deletes a holding with no transactions
- **THEN** the holding is deleted

### Requirement: Transaction validation
A transaction SHALL belong to one holding and SHALL have a type (buy, sell, dividend, fee), a calendar date, and a currency from the supported set. Fee and tax SHALL be zero or positive. Buy and sell SHALL require a positive share quantity and a positive price per share.

#### Scenario: Buy without a price
- **WHEN** a person saves a buy transaction with 10 shares and no price
- **THEN** the transaction is not saved and the price field shows a validation error

#### Scenario: Negative fee
- **WHEN** a person enters a fee of -1
- **THEN** the transaction is not saved and the fee field shows a validation error

### Requirement: Dividend and fee amounts
A dividend transaction SHALL record its total gross cash amount and SHALL accept an optional number of shares it was paid on and an optional tax withheld. A fee transaction SHALL record its total amount. Both amounts SHALL be positive.

#### Scenario: Record a dividend
- **WHEN** a person records a dividend of 12.50 USD on 50 shares with 1.88 tax withheld
- **THEN** the dividend is stored with gross amount 12.50, shares 50, tax 1.88, and currency USD

### Requirement: Exact monetary arithmetic
Quantities, prices, amounts, fees, taxes, and FX rates SHALL be stored and calculated with decimal arithmetic rather than binary floating point. Calculation results SHALL be identical for identical inputs on every run and every device.

#### Scenario: Fractional shares
- **WHEN** a holding has buys of 0.1 and 0.2 shares and no sells
- **THEN** the shares held are exactly 0.3

### Requirement: Position calculation
For each holding the system SHALL process buys and sells in date order (creation order breaking ties). A buy SHALL update the average cost per share to include the lot cost plus its fee. A sell SHALL reduce shares held without changing the average cost, and shares held SHALL NOT go below zero.

#### Scenario: Average cost includes fees
- **WHEN** a holding has a buy of 10 shares at 100 with a fee of 5, then a buy of 10 shares at 110 with no fee
- **THEN** shares held is 20, average cost is 105.25, and cost basis is 2105

#### Scenario: Sell keeps average cost
- **WHEN** the same holding then has a sell of 5 shares at 130
- **THEN** shares held is 15, average cost stays 105.25, and cost basis is 1578.75

#### Scenario: Oversell is clamped
- **WHEN** a holding with 5 shares has a sell of 8 shares
- **THEN** shares held is 0 and the holding is treated as closed

### Requirement: Base-currency valuation
The system SHALL value each open position as shares held × latest cached price × FX rate from the position's price currency to the portfolio's base currency. Total value, cost basis, unrealized gain, and return percentage SHALL be calculated in the base currency.

#### Scenario: Mixed-currency portfolio
- **WHEN** a EUR portfolio holds 10 shares of a USD-priced stock at a cached price of 200 and the cached USD→EUR rate is 0.9
- **THEN** that position's market value is 1800 EUR

#### Scenario: Price never fetched
- **WHEN** an open position has no cached price
- **THEN** its market value is shown as unavailable, it is excluded from total value, and its cost basis still counts toward total cost basis

### Requirement: Offline calculations
All portfolio calculations SHALL work without a network connection, using the most recently cached prices and FX rates, and SHALL show when those cached values were fetched.

#### Scenario: Open the app offline
- **WHEN** a person opens the dashboard with no network connection after prices were last fetched yesterday
- **THEN** the dashboard shows values from yesterday's cached prices together with their fetch time

### Requirement: Allocation goals
A portfolio SHALL have independent goal sets for two scopes: holding (keyed by ticker) and asset class. Saving a scope SHALL replace all of its targets. Each target SHALL be greater than zero, and non-empty target sets SHALL add up to 100% within ±0.5 percentage points.

#### Scenario: Targets do not add up
- **WHEN** a person saves asset-class targets of 60% stock and 30% bond
- **THEN** the targets are not saved and the person is told they currently add up to 90.0%

#### Scenario: Clear a scope
- **WHEN** a person saves an empty holding-scope target list
- **THEN** all holding goals for that portfolio are removed and asset-class goals are unchanged

#### Scenario: One target per key
- **WHEN** a portfolio already has a 40% stock asset-class goal and the person saves 50% stock
- **THEN** the portfolio has exactly one stock asset-class goal, at 50%

### Requirement: CSV transaction import
The system SHALL import transactions from a CSV file with a header row containing at least `ticker`, `type`, and `date`, and optionally `shares`, `price`, `fee`, `tax`, `currency`, and `notes`. Unknown tickers SHALL create holdings, and each row SHALL be validated with the same rules as manual entry.

#### Scenario: Import a valid file
- **WHEN** a person imports a CSV with 20 valid rows for 3 tickers into an empty portfolio
- **THEN** 3 holdings and 20 transactions are created and the import result reports 20 imported and 0 failed

#### Scenario: Import with bad rows
- **WHEN** a CSV row has the type "transfer"
- **THEN** that row is skipped, no holding is created for it, the result lists its line number and reason, and the other valid rows are still imported

#### Scenario: Missing required columns
- **WHEN** a CSV header has no `date` column
- **THEN** nothing is imported and the person is told which columns are required

#### Scenario: Web app CSV compatibility
- **WHEN** a person imports a CSV that the web application's importer accepts, including quoted fields, `""` escapes, CRLF line endings, and decimal commas
- **THEN** the native app accepts the same rows with the same values

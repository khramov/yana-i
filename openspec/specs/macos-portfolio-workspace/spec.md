# macos-portfolio-workspace Specification

## Purpose
Provides the macOS-native portfolio workspace: desktop navigation, data entry, sortable tables, and charts for the dashboard, holdings, transactions, income, dividends, allocation, and settings, covering the analysis the web application offers today.

## Requirements

### Requirement: Supported platform
The application SHALL run on macOS 14 or later as a native Mac app. iPhone and iPad builds are out of scope for this change.

#### Scenario: Launch on a supported Mac
- **WHEN** a person launches the app on macOS 14
- **THEN** the app opens its main window with full functionality

### Requirement: Desktop navigation
The main window SHALL provide a sidebar with Dashboard, Holdings, Transactions, Income, Dividends, and Analytics sections, plus a portfolio switcher. It SHALL restore the last selected portfolio and section on relaunch.

#### Scenario: Switch portfolio
- **WHEN** a person selects a different portfolio in the switcher
- **THEN** every section shows that portfolio's data in its base currency

#### Scenario: Relaunch restores place
- **WHEN** a person quits while viewing Dividends for "Long term" and relaunches
- **THEN** the app opens on Dividends for "Long term"

### Requirement: Onboarding an empty portfolio
When no portfolio exists, the app SHALL guide the person to create one (name and base currency) and then to add holdings, enter transactions, or import a CSV.

#### Scenario: First portfolio
- **WHEN** a person with no portfolios completes the create-portfolio form
- **THEN** the new portfolio is selected and its empty dashboard offers to add a transaction or import a CSV

### Requirement: Menu commands and shortcuts
The app SHALL expose its main actions in the menu bar with standard macOS keyboard shortcuts, including New Transaction (⌘N), New Portfolio (⇧⌘N), Import CSV (⌘I), Refresh Market Data (⌘R), and Settings (⌘,).

#### Scenario: New transaction from the keyboard
- **WHEN** a person presses ⌘N in the main window
- **THEN** the new-transaction form opens for the selected portfolio

### Requirement: Dashboard summary
The dashboard SHALL show, in the base currency, total value, cost basis, unrealized gain and return percentage, dividends received to date, number of open holdings, the five largest positions with weight and return, and the market-data fetch time.

#### Scenario: Portfolio with open positions
- **WHEN** a person opens the dashboard for a portfolio with 8 open positions
- **THEN** the summary values are shown and the top-5 list contains the 5 positions with the largest market value

#### Scenario: Portfolio with no positions
- **WHEN** the selected portfolio has no open positions
- **THEN** the dashboard shows an empty state instead of zero-valued charts

### Requirement: Holdings table
The holdings view SHALL show one row per open position with ticker, name, asset class, shares, average cost, current price, market value, unrealized gain, and return percentage. Columns SHALL be sortable, and the view SHALL let the person show closed holdings and add, edit, or delete holdings.

#### Scenario: Sort by market value
- **WHEN** a person clicks the Market Value column header
- **THEN** rows are ordered by market value, and clicking again reverses the order

#### Scenario: Missing price
- **WHEN** a position has no cached price
- **THEN** its price, market value, and gain cells show as unavailable rather than zero

### Requirement: Adding a holding by ticker
When a person adds a holding by ticker, the app SHALL look up its name, asset class, sector, and currency through the market-data provider and SHALL reject tickers the provider cannot find. When the provider is unreachable, the app SHALL let the person enter those attributes manually.

#### Scenario: Unknown ticker
- **WHEN** a person adds the ticker "ZZZZQ" and the provider reports no match
- **THEN** no holding is created and the person is told that the ticker was not found

#### Scenario: Offline add
- **WHEN** a person adds a ticker while offline
- **THEN** the app offers to create the holding with manually entered name, asset class, and currency

### Requirement: Transactions view
The transactions view SHALL list the selected portfolio's transactions, newest first, with date, ticker, type, shares, price or amount, fee, tax, currency, and notes. It SHALL support filtering by ticker, type, and year, and SHALL support creating, editing, and deleting transactions after confirmation.

#### Scenario: Edit a transaction
- **WHEN** a person changes a buy's share count and saves
- **THEN** the transaction list, holdings, and dashboard reflect the new value without reopening the window

#### Scenario: Confirm deletion
- **WHEN** a person deletes a transaction
- **THEN** the app asks for confirmation and deletes it only after the person confirms

#### Scenario: Validation messages inline
- **WHEN** a person saves a sell without a share count
- **THEN** the form stays open and shows the error next to the shares field

### Requirement: CSV import workflow
The app SHALL let a person choose a CSV file through the standard open panel or by dropping it on the window, and SHALL show the number of imported and failed rows with each failure's line number and reason.

#### Scenario: Drop a CSV file
- **WHEN** a person drops a CSV file on the transactions view
- **THEN** the file is imported into the selected portfolio and the result summary is shown

### Requirement: Income view
The income view SHALL show dividend income per month as a chart, trailing-12-month income, forward annual income estimated from shares held × the provider's annual dividend rate, and a per-holding breakdown of trailing and forward income, all in the base currency.

#### Scenario: Monthly income
- **WHEN** a portfolio has dividends in March and June of this year
- **THEN** the chart shows bars for those months whose heights equal the converted gross amounts

#### Scenario: Forward estimate unavailable
- **WHEN** dividend rates have never been fetched
- **THEN** forward annual income is shown as unavailable with an option to refresh market data

### Requirement: Dividends view
The dividends view SHALL list received dividends with date, ticker, gross amount, per-share amount, tax, and yield on cost, and SHALL support filtering by year. It SHALL show all-time and trailing-12-month totals, portfolio yield on cost, and an upcoming-dividends calendar from cached ex-dividend and payment dates.

#### Scenario: Yield on cost
- **WHEN** a dividend of 10 was paid on 20 shares of a holding whose average cost is 25
- **THEN** its per-share amount is 0.50 and its yield on cost is 2.00%

#### Scenario: Upcoming dividend
- **WHEN** a held position has a cached ex-dividend date after today
- **THEN** the calendar shows the event with estimated income of shares held × amount per share, converted to the base currency

### Requirement: Allocation analysis
The analytics view SHALL show allocation of market value in the base currency grouped by holding, sector, or asset class, with each group's value and percentage. Positions without a price SHALL be excluded, and holdings without a sector SHALL be grouped as "Unknown".

#### Scenario: Group by asset class
- **WHEN** a person chooses the asset-class grouping
- **THEN** the chart shows one slice per asset class and the percentages add up to 100%

### Requirement: Goals and rebalancing recommendations
The analytics view SHALL include an editor for holding and asset-class goals. For each key it SHALL show current %, target %, drift, and the base-currency amount to buy to reach the target (never negative). For holdings with a price, it SHALL also show the share count that amount buys.

#### Scenario: Underweight holding
- **WHEN** a portfolio worth 10,000 has VTI at 30% and a VTI target of 40%, and VTI costs 250 in the base currency
- **THEN** VTI shows drift −10%, buy amount 1,000, and 4 shares

#### Scenario: Overweight holding
- **WHEN** a holding is above its target
- **THEN** its buy amount is 0 and its drift is positive

### Requirement: Value history chart
The app SHALL record at most one value snapshot per portfolio per calendar day (total value, cost basis, base currency) whenever the portfolio has a valuation. It SHALL chart value and cost basis over a selectable date range. Snapshots SHALL remain local to each Mac.

#### Scenario: Daily snapshot
- **WHEN** a person opens the app twice on the same day with prices available
- **THEN** exactly one snapshot exists for that portfolio and day

#### Scenario: Range selection
- **WHEN** a person selects the last 3 months
- **THEN** the chart shows only snapshots in that range

### Requirement: Settings window
The Settings window SHALL let the person manage portfolios (rename, change base currency, delete), see iCloud sync status with Sync Now, and see the market-data provider, its status, and its last refresh time.

#### Scenario: Change base currency
- **WHEN** a person changes a portfolio's base currency from EUR to USD
- **THEN** all views of that portfolio recalculate and display values in USD

### Requirement: Native appearance and accessibility
The app SHALL follow the system light/dark appearance and accent color, format numbers, currencies, and dates using the person's locale, and give every interactive control and chart an accessible label for VoiceOver.

#### Scenario: Dark mode
- **WHEN** the system appearance switches to dark
- **THEN** the app's windows, tables, and charts switch to dark appearance without a restart

#### Scenario: VoiceOver on a chart
- **WHEN** a VoiceOver user focuses the allocation chart
- **THEN** each slice is announced with its label, value, and percentage

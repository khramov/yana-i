# Spec Delta

## Purpose

Fetches and caches quotes, FX rates, security metadata, and dividend events through a replaceable provider interface, so portfolio data never depends on one market-data vendor and the app keeps working offline from its cache.

## ADDED Requirements

### Requirement: Provider-independent market data
The system SHALL obtain prices, FX rates, security metadata (name, asset class, sector, currency), and dividend events only through a provider interface. Portfolio, holding, transaction, and goal records SHALL NOT store provider-specific identifiers or fields.

#### Scenario: Provider replaced
- **WHEN** a later release switches the app to a different market-data provider
- **THEN** existing portfolio records stay unchanged and are valued with data from the new provider

### Requirement: Default keyless provider
The first release SHALL ship one provider that uses Yahoo Finance public endpoints without requiring an account or credential. The Settings window SHALL state that this source is unofficial and might stop working.

#### Scenario: Fresh install pricing
- **WHEN** a person adds AAPL on a fresh install with a network connection and no credentials entered
- **THEN** AAPL's name, currency, asset class, and current price are fetched

### Requirement: Minimal data disclosure
Requests to a market-data provider SHALL contain only the tickers and currency pairs being looked up. They SHALL NOT contain share quantities, amounts, portfolio names, iCloud identity, or other portfolio contents.

#### Scenario: Price refresh request
- **WHEN** the app refreshes prices for a portfolio holding 12 shares of MSFT
- **THEN** the outgoing request identifies MSFT but does not include the quantity 12 or the portfolio name

### Requirement: Cached quotes
The system SHALL cache the latest quote per ticker, with its price, currency, and fetch time, in local storage that is not synchronized. A cached quote SHALL be considered fresh for 15 minutes.

#### Scenario: Fresh cache reused
- **WHEN** the dashboard is opened 5 minutes after prices were fetched
- **THEN** no new quote request is made and the cached prices are used

#### Scenario: Stale cache refreshed
- **WHEN** the dashboard is opened 20 minutes after prices were fetched, with a network connection
- **THEN** prices for open positions are re-fetched and the fetch time updates

### Requirement: Cached FX rates
The system SHALL cache FX rates per currency pair with their fetch time, consider them fresh for 1 hour, and treat a same-currency conversion as rate 1. When no rate has ever been fetched for a needed pair, affected values SHALL be shown as unavailable rather than converted at rate 1.

#### Scenario: Missing FX rate
- **WHEN** a EUR portfolio holds a RUB-priced position and no RUB→EUR rate has ever been fetched
- **THEN** that position's base-currency value is shown as unavailable and is excluded from total value

#### Scenario: Stale FX used offline
- **WHEN** the USD→EUR rate was fetched 2 days ago and the Mac is offline
- **THEN** the 2-day-old rate is used and its age is shown

### Requirement: Dividend events
The system SHALL fetch, for each held ticker, the next ex-dividend date, payment date, last amount per share, annual dividend rate, and payment frequency (annual, semi-annual, quarterly, monthly, or unknown), and cache them locally with their fetch time.

#### Scenario: Refresh dividend data
- **WHEN** a person refreshes market data
- **THEN** dividend events are updated for every held ticker that has them, and the refresh time is shown in the income and dividends views

### Requirement: Refresh triggers
The system SHALL refresh stale market data automatically when the app launches and when a section needing it is shown, and SHALL refresh all market data on the Refresh Market Data command. Automatic refreshes SHALL NOT run while the app is in the background.

#### Scenario: Manual refresh
- **WHEN** a person chooses Refresh Market Data
- **THEN** quotes, FX rates, and dividend events for all holdings in the selected portfolio are re-fetched regardless of age

### Requirement: Partial failure tolerance
A failure to fetch data for one ticker or currency pair SHALL NOT prevent other results from being saved. The system SHALL keep the previous cached value for failed items and SHALL report which items failed.

#### Scenario: One ticker fails
- **WHEN** a refresh of 10 tickers succeeds for 9 and fails for 1
- **THEN** the 9 new prices are saved, the failed ticker keeps its previous price and fetch time, and the person sees which ticker failed

#### Scenario: Provider unreachable
- **WHEN** the provider cannot be reached at all
- **THEN** all views keep using cached values, show their age, and show that market data is offline

### Requirement: Request throttling
The system SHALL limit concurrent provider requests, retry rate-limited or transient failures with exponential backoff, and SHALL NOT send more than one in-flight request for the same ticker or currency pair.

#### Scenario: Rate limited
- **WHEN** the provider responds that the request rate is exceeded
- **THEN** the app waits before retrying and does not start additional requests for the same items in the meantime

### Requirement: Secure credential storage
When a provider needs a credential, the system SHALL store it only in the macOS Keychain, scoped to this app and this Mac and excluded from iCloud Keychain sync. It SHALL never write the credential to logs, the local store, or synchronized records, and SHALL let the person replace or remove it.

#### Scenario: Remove a credential
- **WHEN** a person removes a saved provider credential in Settings
- **THEN** it is deleted from the Keychain and providers that need it report that a credential is required

#### Scenario: Credential not synced
- **WHEN** a credential is saved on one Mac
- **THEN** a second Mac signed in to the same iCloud account does not receive it

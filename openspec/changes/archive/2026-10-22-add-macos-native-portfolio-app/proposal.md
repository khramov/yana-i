# Proposal

## Why

Yana is currently a browser-hosted, local SQLite application. A dedicated macOS application can provide a faster, desktop-native portfolio workflow while keeping financial data available offline and synchronized privately across a person's Apple devices.

The new app starts with an empty portfolio, avoiding a fragile dependency on the browser app's local database. Its data boundary and sync contracts must remain portable so a future authenticated API backed by PostgreSQL can replace CloudKit without rewriting the portfolio domain or the offline experience.

## What Changes

- Add a standalone, macOS-first SwiftUI application; iPhone and iPad clients are explicitly deferred rather than constraining the initial desktop experience.
- Add local-first portfolio persistence for portfolios, holdings, transactions, allocation goals, and calculation inputs using stable UUID-based records.
- Synchronize user-authored portfolio data through the signed-in user's private CloudKit database, while preserving offline access on the Mac.
- Provide macOS-native workflows for onboarding an empty portfolio; entering, editing, and deleting portfolio records; and viewing dashboard, holdings, transaction, income, dividend, and allocation insights.
- Provide CSV transaction import using the web application's column format, so existing transaction history can be brought into the empty native portfolio without reading the web app's database.
- Add a market-data abstraction for quotes and foreign-exchange rates, including locally cached results and secure storage of any user-supplied provider credential.
- Keep the persisted domain model and sync payloads independent of CloudKit and SwiftData so the app can later synchronize through an authenticated API backed by PostgreSQL.
- Do not import the existing web application's local SQLite data, alter its Next.js APIs, or modify the in-progress local-folder-sync change.

## Capabilities

### New Capabilities

- `native-portfolio-storage`: Stores and validates a person's portfolio records locally using portable identities and supports reliable offline portfolio calculations.
- `icloud-portfolio-sync`: Keeps user-authored portfolio records synchronized across devices signed in to the same iCloud account without exposing cached data or preferences to CloudKit.
- `macos-portfolio-workspace`: Provides the macOS-native portfolio-management and analysis experience, including desktop navigation, data entry, tables, and charts.
- `native-market-data`: Refreshes and caches quote and FX data through a replaceable provider interface without coupling portfolio data to a single market-data vendor.

### Modified Capabilities

None.

## Impact

- Adds a native Xcode/Swift project and shared Swift modules alongside, but independent from, the existing Next.js application.
- Requires macOS 14 or later, SwiftUI, SwiftData, iCloud/CloudKit, Background Modes for remote sync notifications, and Apple code-signing/CloudKit-container configuration.
- Introduces an Apple-private-data model and user-facing iCloud availability/synchronization states; app-specific email/password authentication is not used by the native application.
- Requires deterministic portfolio-calculation tests, separate local-store and sync test fixtures, and CloudKit development-schema validation before release.
- Future iPhone/iPad and PostgreSQL/API work will consume the same portable domain contracts but are not delivered by this change.

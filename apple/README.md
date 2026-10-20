# Yana for macOS

Native SwiftUI app that keeps portfolios on the Mac and syncs them through the user's private iCloud database. It lives next to the Next.js app and shares none of its build tooling.

```
apple/
  YanaKit/     Swift package: domain model, calculations, CSV import, sync contract and status, market data
  YanaMac/     Xcode project: SwiftUI app, SwiftData store, CloudKit and Keychain adapters
  docs/        sync payload contract and verification notes
  scripts/     fixture recording helpers
```

Inside `YanaMac/YanaMac`:

- `App/`: launch wiring (`AppEnvironment`), the main window's `AppModel`, and the sample market-data provider
- `Features/`: one folder per sidebar section plus the shell and Settings; each pairs its views with a testable model
- `Persistence/`: the two SwiftData stores behind repositories
- `Sync/`: the `CKSyncEngine` adapter, CloudKit record mapping, and `SyncController` (account changes and sync status)

## Requirements

- macOS 14 or later
- Xcode 16 or later, selected with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

## Build

From the repository root:

```sh
cd apple/YanaMac
xcodebuild -scheme YanaMac -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

`CODE_SIGNING_ALLOWED=NO` builds without an Apple Developer account. An unsigned build cannot use iCloud. To run the app with sync, set up signing as described below and open `YanaMac/YanaMac.xcodeproj` in Xcode.

## Test

Package tests (no signing or iCloud account needed):

```sh
cd apple/YanaKit
./test.sh
```

`test.sh` wraps `swift test` and passes the Swift Testing macro plugin path explicitly. Without it, Command Line Tools-only setups intermittently fail with "plugin for module 'TestingMacros' not found". Extra arguments go to `swift test`, for example `./test.sh --filter MergeTests`.

App tests (repositories, sync adapter, view models, formatting):

```sh
cd apple/YanaMac
xcodebuild test -scheme YanaMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

The Keychain tests skip themselves in an unsigned build: the data-protection Keychain needs a host signed with a development team. They run once `Config/Signing.xcconfig` names a team.

UI tests (their own `YanaMacUITests` scheme):

```sh
cd apple/YanaMac
./test-ui.sh
```

XCUITest needs a signed test runner. Without a development team, `test-ui.sh` signs ad hoc and leaves out the iCloud entitlements, which need a provisioning profile. The first run may ask to let Xcode control the Mac (System Settings › Privacy & Security › Accessibility).

The UI tests launch the app with these test-only arguments, which also work from Xcode's scheme editor:

| Argument | Effect |
|---|---|
| `-YanaStoreDirectory <path>` | Keep `Portfolio.store` and `MarketCache.store` in `<path>`; iCloud sync stays off |
| `-YanaInMemoryStore YES` | Keep both stores in memory; iCloud sync stays off |
| `-YanaDefaultsSuite <name>` | Store selection and other preferences in a separate defaults suite |
| `-YanaStubMarketData YES` | Use fixed sample prices (AAPL, MSFT, VTI, KO, SAP.DE) instead of Yahoo Finance |
| `-YanaStubOffline YES` | Make the sample provider behave as if the network were down |
| `-YanaAppearance light\|dark` | Force an appearance regardless of the system setting |

## Signing and iCloud

Signing values live in `YanaMac/Config/Signing.xcconfig`, which is git-ignored. `Config/Base.xcconfig` includes it when present and otherwise falls back to placeholders (`com.example.yana`, no team).

```sh
cd apple/YanaMac
cp Config/Signing.xcconfig.example Config/Signing.xcconfig
```

Then edit `Config/Signing.xcconfig`:

| Setting | Meaning |
|---|---|
| `YANA_BUNDLE_ID` | App bundle identifier, for example `com.yourname.yana` |
| `YANA_DEVELOPMENT_TEAM` | 10-character Apple Developer team ID |
| `YANA_CLOUDKIT_CONTAINER` | CloudKit container, conventionally `iCloud.<bundle id>` |

The container must exist in the developer account (Certificates, Identifiers & Profiles → iCloud Containers) and be assigned to the bundle ID. Xcode's automatic signing then creates the provisioning profile.

`Config/YanaMac.entitlements` declares:

- App Sandbox
- Outgoing network connections (market data)
- User-selected files, read-only (CSV import)
- iCloud with CloudKit, using `$(YANA_CLOUDKIT_CONTAINER)`
- Push Notifications (`aps-environment`), so the sync engine receives change notifications

`aps-environment` is `development`. Archiving for distribution re-signs it for production. Before the first production release, deploy the CloudKit schema from development to production in CloudKit Console.

## Market data fixtures

The Yahoo Finance provider tests replay recorded responses from `YanaKit/Tests/YanaMarketDataTests/Fixtures`. To re-record them from a network that Yahoo does not rate-limit:

```sh
apple/scripts/record-yahoo-fixtures.sh
```

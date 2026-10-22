# Possible improvements

Open items left over from the `add-macos-native-portfolio-app` change (archived as `openspec/changes/archive/2026-10-22-add-macos-native-portfolio-app`). The code for each item exists. What's missing is the verification, which needs an Apple signing team or manual iCloud runs on signed builds.

## Prerequisite

- Fill in the real bundle ID, team, and CloudKit container in `apple/YanaMac/Config/Signing.xcconfig`, and choose the distribution channel. Items below that need a signed build depend on this.

## Keychain credentials

- **Keychain `CredentialStore` (was 7.3).** Generic password, non-synchronizable, this-device-only accessibility, with save/replace/remove. Verify Keychain tests in the app test target, and check that the item attributes report `kSecAttrSynchronizable` false. These tests currently skip themselves without a signing identity.
- **Settings scene (was 9.6).** Portfolio rename, base currency, and delete; iCloud status and Sync Now; market-data provider name, unofficial-source notice, and last refresh; credential fields shown only for providers that need one. Verify a UI test showing that changing the base currency recalculates values, and a test with the keyed test provider showing that saving and removing a credential updates the Keychain.

## iCloud sync

- **`CKSyncEngine` adapter (was 8.1).** Private database, `Portfolio` zone, and record mapping of `payload`/`schemaVersion`/`revision`/`modifiedAt`/`deviceID`/`deleted`. Also engine-state persistence, send/fetch handling, and routing `serverRecordChanged` through `Merge`. Verify mapping unit tests and a manual development-environment run where a record created offline uploads after relaunch.
- **Account status and events (was 8.2).** No account, restricted, temporarily unavailable, re-enqueue on sign-in, and sign-out/switch with a blocking pending-changes warning followed by local removal. Also register for remote notifications. Verify state-machine unit tests for every event, and check manually that switching iCloud accounts never shows or uploads the previous account's data.

## End-to-end verification

- **Two-Mac checklist (was 10.2).** On one development-environment iCloud account, check:
  - an empty first launch
  - a CSV import on Mac A appearing on Mac B
  - concurrent offline edits converging
  - a delete versus a stale edit staying deleted
  - the same ticker added on both Macs merging into one holding
  - offline editing uploading after relaunch
  - caches and credentials being absent from CloudKit Dashboard

  Record the results in `apple/docs/sync-verification.md`.
- **Production CloudKit (was 10.3).** Deploy the CloudKit schema from development to production, then verify sync between two Macs with a production-signed build. Record the result in `apple/docs/sync-verification.md`.

# Proposal

## Why

Yana already keeps its state in a local SQLite database, but each installation is isolated and copying the database file is unsafe while WAL mode is active. Personal users need a vendor-neutral way to keep selected portfolio data aligned between their own devices without introducing a hosted database or synchronization service.

## What Changes

- Add opt-in, folder-based synchronization for user-owned portfolios, holdings, transactions, and allocation goals.
- Record every synced local mutation atomically with an immutable outbox operation that has a stable device ID, UUID operation ID, logical clock, UTC timestamp, entity identity, action, and payload.
- Add durable local sync metadata: stable entity IDs, device identity and logical clock, outbox, applied-operation ledger, per-entity versions, delete tombstones, settings, and visible sync errors.
- Export operations as immutable JSON files below `ops/<device-id>/` using a same-directory temporary file followed by rename; never copy, export, or import SQLite database, WAL, SHM, or database-directory files.
- Add safe, idempotent import scanning with JSON validation, retryable dependency handling, whole-record last-write-wins conflict resolution with a visible conflict log, and delete tombstones that prevent stale updates from restoring deleted entities.
- Add a minimal per-local-user sync-folder setting and a manual Sync now action that reports exported, imported, skipped, conflicts/deferred operations, and errors.
- Preserve local authentication and existing UI/API behavior. Users, passwords, sessions, price/FX/dividend caches, and generated snapshots remain local and are not synchronized.
- Document pairing two installations through the same locally mounted folder and add automated multi-device and filesystem-atomicity tests.

## Capabilities

### New Capabilities

- `local-folder-sync`: Vendor-neutral, operation-file synchronization of portfolio data between independent local SQLite installations.

### Modified Capabilities

None.

## Impact

- Affects the SQLite schema and migration startup path in `lib/db`, portfolio/holding/transaction/goal mutations, settings UI, and new sync API/service modules.
- Adds a local filesystem dependency only; the selected folder must be accessible on the host running Next.js and may be supplied by iCloud Drive, Syncthing, a WebDAV mount, Dropbox, or an ordinary directory.
- Requires a test runner and temporary-directory test fixtures for synchronization service tests.
- Updates local development and architecture documentation, including the explicit prohibition on syncing `data/yana.db`, `yana.db-wal`, and `yana.db-shm`.

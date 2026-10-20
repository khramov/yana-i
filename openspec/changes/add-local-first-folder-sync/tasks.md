# Tasks

## 1. Sync foundation and safe migration

- [ ] 1.1 Add a TypeScript test runner, `npm run test` command, and isolated temporary SQLite/database-folder fixtures; verify a representative fixture test runs without touching `data/yana.db`.
- [ ] 1.2 Add a forward-only migration ledger and the sync metadata schema (`sync_id` backfills, device/clock, settings, outbox, applied ledger, per-entity versions, tombstones, and errors); verify an upgrade fixture preserves legacy rows and numeric IDs while assigning unique portable IDs.
- [ ] 1.3 Define versioned operation schemas, entity payload types, ordering-tuple comparison, and mounted-folder path validation that rejects the database directory/files; verify unit tests cover invalid operations and forbidden paths.

## 2. Atomic local mutation recording

- [ ] 2.1 Implement the server-only sync mutation service that atomically mutates a synced entity, advances the persistent logical clock, writes the entity's new version, and queues an outbox operation; verify rollback leaves neither entity nor outbox row changed on an injected failure.
- [ ] 2.2 Route portfolio and holding create/update/delete behavior through the mutation service while retaining current numeric route IDs and responses; verify CRUD route/service tests cover portable parent identities and local-only behavior when sync is disabled.
- [ ] 2.3 Route transaction create/update/delete and CSV import through the mutation service, including automatically created holdings; verify tests cover one operation per mutation and transaction-to-holding portable references.
- [ ] 2.4 Decompose goal scope replacement and portfolio cascades into correctly ordered create/update/delete operations with descendant tombstones; verify tests cover goal replacement and portfolio deletion without stale resurrection.

## 3. Folder transport and convergence

- [ ] 3.1 Implement outbox export to `ops/<device-id>/<operation-id>.json` with same-directory temporary files, close/flush, rename, retry handling, and immutable final-file verification; verify atomic-export and collision tests pass.
- [ ] 3.2 Implement recursive device-folder scanning, operation validation, persistent malformed-file errors, applied-operation idempotency, and dependency-aware repeated import passes; verify tests cover repeated import, malformed files, and delayed parent delivery.
- [ ] 3.3 Implement whole-record LWW application, tombstone comparison, and the conflict-log entry for superseded records using `(logicalClock, createdAt, deviceId)`; verify two-device simultaneous-update and delete-versus-update convergence tests pass in either import order.
- [ ] 3.4 Implement empty-folder baseline export and non-empty-folder import-before-export behavior for existing data; verify two isolated device databases reconstruct an existing portfolio through one shared temporary folder.

## 4. Sync API, settings, and guidance

- [ ] 4.1 Add authenticated settings and Sync now API endpoints that configure/clear a validated local path and return exported, imported, skipped, deferred/conflict, and error counts; verify endpoint tests enforce user scoping and return error details without aborting valid work.
- [ ] 4.2 Add a minimal Settings UI for the server-local sync path, status/errors, and manual Sync now action while preserving the existing settings/password behavior; verify the UI displays successful and malformed-file outcomes.
- [ ] 4.3 Update `LOCAL_DEV.md` and architecture documentation with two-device pairing steps, trusted-folder/server-path limitations, supported mounted-folder examples, and the explicit warning never to sync SQLite, WAL, SHM, or `data/`; verify the documented setup matches the shipped settings flow.

## 5. Integration verification

- [ ] 5.1 Run the complete sync test suite, `npm run lint`, and a production build; verify the existing portfolio, authentication, and dashboard flows still compile and synchronization remains opt-in.

## Workflow follow-up

- Archive the change after implementation and review are complete.

# Design

## Context

See `proposal.md` for motivation and `specs/local-folder-sync/spec.md` for the behavior contract. The current application already uses `better-sqlite3` and Drizzle against `data/yana.db` in WAL mode. Migrations are currently inline at module initialization, numeric autoincrement IDs are used for all relationships, and the app has local users and sessions even though it is intended for personal use.

The design must allow two independently initialized databases to exchange data without relying on matching numeric IDs or direct database-file copies. The current browser UI is served by a Node/Next.js host, so filesystem paths refer to the server host, not the browser device.

## Goals / Non-Goals

**Goals:**

- Preserve existing records, integer IDs, routes, and local sign-in behavior while adding portable identities and synchronization metadata.
- Make local commits independent of shared-folder availability, with retryable export and idempotent import.
- Converge supported user data deterministically despite reordering, duplicate reads, and eventually consistent folder providers.

**Non-Goals:**

- Syncing SQLite, credentials, sessions, cached market data, or generated snapshots.
- Hosted synchronization, provider SDKs, encryption/key exchange, real-time watching, collaborative access control, or automatic conflict prompts.
- Changing the application into a multi-user shared-folder collaboration product. A shared folder is a trusted personal-data boundary.

## Decisions

### Add forward-only SQLite migrations and portable IDs

Add a `schema_migrations` ledger and execute a new sync migration after the existing compatibility setup. The migration adds nullable `sync_id` columns to `portfolios`, `holdings`, `transactions`, and `goals`, backfills UUIDs transactionally, then creates unique indexes. Integer IDs and current foreign keys remain in place for API/UI compatibility.

New metadata tables are `sync_device`, `sync_settings`, `sync_outbox`, `sync_applied_operations`, `sync_entity_versions`, `sync_tombstones`, and `sync_errors`. `sync_settings` and outbox records are scoped to the local `user_id`; device identity and logical clock are installation-wide. This separates portable entity identity from local ownership identity.

Alternative considered: changing primary and foreign keys to UUIDs. It would require destructive table rebuilds and broad API/UI changes, so it does not preserve existing data safely.

### Route synced mutations through one service

Create a server-only mutation service and update portfolio, holding, transaction, transaction-import, and goal routes to call it. It performs the normal mutation, increments the persistent Lamport clock, writes the entity's new version into `sync_entity_versions`, and inserts an outbox row in one `better-sqlite3` transaction.

Each create and update payload carries the entity's portable ID and its full syncable fields; whole-record optimistic versioning means updates replace the record rather than patching individual fields. Delete payloads identify the entity only. Relationship payloads use portable parent IDs rather than local integer IDs. Goal replacement is decomposed into individual create/update/delete entity operations so each goal has an independent identity and tombstone.

Alternative considered: database triggers. They cannot reliably compose portable relationship payloads or distinguish remote imports from local user mutations, making application-level transactions clearer and safer.

### Sync only primary user-authored portfolio state

Sync `portfolios`, `holdings`, `transactions`, and `goals`. Keep `users`, `sessions`, cookies, sync preferences, price and FX caches, dividend metadata, and portfolio snapshots local. A remote portfolio is associated with the user who invokes Sync now on that installation; no user IDs, credentials, or cache values cross devices.

Alternative considered: syncing the full database or user records. That would expose credentials, collide with local numeric IDs, and violate the SQLite-file safety requirement.

### Use immutable JSON operations in a generic mounted folder

The folder layout is `ops/<device-id>/<operation-id>.json`. Operation JSON is versioned and includes `operationId`, `deviceId`, `logicalClock`, ISO-8601 UTC `createdAt`, `entityType`, `entityId`, `action`, and payload. Export writes a randomly named temporary file in the final operation directory with exclusive creation, flushes and closes it, then renames it to the final path. A pre-existing final path is parsed and compared; a matching operation is marked exported, while a mismatch is surfaced as an integrity error and never overwritten.

The setting accepts only a server-local path. It resolves and rejects the app's `data` directory, its database files, and paths that would include them. This works with ordinary directories and any provider that presents a mounted filesystem, without provider-specific code. A native folder picker is intentionally not promised for this browser-hosted app.

Alternative considered: syncing a single JSON snapshot or using filesystem/database locks. Snapshots lose concurrent changes; shared-folder locks are unreliable across cloud providers. Immutable operations tolerate duplicate and reordered delivery.

### Import in dependency-aware repeated passes

Sync now first scans all `ops/*/*.json` files. It validates JSON and schema before mutation, ignores temporary files, logs malformed files in `sync_errors`, and continues. For each unseen valid operation, import translates portable parent IDs to local rows and writes the entity update, entity version/tombstone, applied-operation ledger entry, and logical-clock advancement in one transaction.

Operations with unavailable live parents are deferred rather than marked applied. Scanning repeats while progress is made so a holding or transaction can follow its portfolio even when filesystem enumeration is unordered. Remaining deferred operations appear in the result summary. The applied ledger makes repeats idempotent.

Alternative considered: filename ordering or requiring exports to be delivered in order. Folder replication does not guarantee either.

### Resolve records and deletion with whole-record optimistic versioning

Convergence uses whole-record last-write-wins (optimistic concurrency control), not field-level resolution. `sync_entity_versions` stores one version tuple `(logicalClock, createdAt, deviceId)` per `(entityType, entityId)`. An incoming create or update replaces the entire local record only if its tuple is lexicographically greater than the stored tuple; otherwise the operation is skipped as stale. A tombstone stores the same tuple per entity; a create or update older than a winning tombstone is ignored, and a delete older than the live record's version is ignored. Deletes of a portfolio emit ordered delete operations and tombstones for every synced descendant, matching the current explicit cascade behavior.

Incoming operations advance the local logical clock to at least the received clock; the next local mutation increments it before creating an operation. This makes future local operations causally newer without trusting wall-clock monotonicity, and the `deviceId` component breaks ties when two installations reach the same clock value independently.

When a losing update differs from the value it is discarded against, the import records the overwritten record in `sync_errors` as a visible conflict entry so a silently superseded edit is still inspectable.

Alternative considered: field-level LWW with a version per `(entity, field)`. It preserves unrelated concurrent field edits, but given the small, mostly single-writer usage of this app it adds a version row per field, field-patch update payloads, and per-field merge logic for a case that rarely occurs. Whole-record versioning is materially simpler and the conflict log mitigates the one lost-update case (two devices editing different fields of the same record before syncing).

### Bootstrap safely when pairing

Changing to an empty sync folder marks the local user's current live entities for baseline create operations. For a non-empty folder, Sync now imports before exporting pending local operations. Documentation will instruct a new installation to log into its local account, configure the shared folder before adding data, then use Sync now. The existing auto-created default portfolio is not silently deleted if the user has already created it; this avoids destructive implicit cleanup.

## Risks / Trade-offs

- [Folder propagation delay or offline provider] → SQLite commits remain local and outbox entries retry on the next manual sync.
- [Malformed or manually edited operation file] → preserve the file, record a visible error, and continue other imports.
- [Partial dependency arrival] → use repeated passes and report unresolved operations as deferred.
- [Shared folder accessible to another person] → document that operations are plaintext personal financial data and require a trusted folder; no security claims are made.
- [Current inline migration history] → introduce the ledger forward-only and test upgrades from the existing schema; do not rewrite or drop populated tables.
- [No filesystem picker in a web browser] → clearly label the field as a server-host path and document mounted-folder setup.
- [Very large operation history] → retain immutable history for correctness in this change; compaction/checkpointing is a future explicit migration, not silent cleanup.

## Migration Plan

1. Add migration infrastructure and a tested sync migration that only creates tables, adds columns/indexes, and backfills portable IDs. Back up the database before deployment and retain the current `data/yana.db` location.
2. Deploy the mutation service before enabling the settings UI so every new synced local mutation gets an outbox record.
3. Deploy the filesystem import/export service, Sync API, and settings UI behind the opt-in folder setting. Disabled users retain existing behavior.
4. On first Sync now, inspect the folder: import first when operations exist; otherwise enqueue and export a baseline. No database or WAL files are moved.
5. Validate upgrades and two-device convergence with isolated temporary databases and folders. Roll back application code by disabling sync; do not roll back or delete sync metadata/tombstones, since retained metadata preserves safe future import behavior.

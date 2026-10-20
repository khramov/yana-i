# Spec Delta

## Purpose

Enable trusted personal devices to converge selected portfolio data through a shared local folder while each installation retains its own SQLite database.

## ADDED Requirements

### Requirement: Opt-in portable sync folder
The system SHALL let each local user configure or clear one server-accessible sync folder and SHALL operate normally with synchronization disabled. The folder format SHALL be vendor-neutral and work with any locally mounted directory.

#### Scenario: Configure a shared folder
- **WHEN** an authenticated user saves an accessible folder path
- **THEN** the system validates or creates its sync operation directory and reports that path as configured for that user

#### Scenario: No configured folder
- **WHEN** a user changes portfolio data before configuring synchronization
- **THEN** the change remains available locally and no synchronization error prevents the mutation

### Requirement: SQLite files remain local
The system SHALL never copy, export, import, scan as sync data, or instruct users to synchronize the SQLite database file, WAL file, SHM file, or database directory.

#### Scenario: Pairing guidance
- **WHEN** the user views sync setup documentation or settings guidance
- **THEN** it instructs the user to share only the configured operation-folder contents and explicitly warns against syncing `yana.db`, `yana.db-wal`, and `yana.db-shm`

### Requirement: Durable operation recording
For every user-originated mutation of a synced portfolio, holding, transaction, or goal, the system SHALL atomically persist the data change and one immutable operation with a UUID operation ID, stable device ID, logical clock, UTC creation timestamp, entity type, entity ID, action, and JSON payload.

#### Scenario: Local transaction creation
- **WHEN** a user creates a transaction while synchronization is configured
- **THEN** the transaction and its corresponding pending operation are both committed, or neither is committed

#### Scenario: Existing data migration
- **WHEN** an installation with existing portfolio data is upgraded
- **THEN** existing synced entities receive durable portable identities without changing their current visible records or numeric API identifiers

### Requirement: Initial data bootstrap
When a user synchronizes existing local data with an empty configured operation folder, the system SHALL enqueue portable create operations for all live synced entities. When a configured folder already contains operations, the system SHALL import before creating any bootstrap operation.

#### Scenario: First device pairs an existing portfolio
- **WHEN** a user runs Sync now against an empty configured folder
- **THEN** the folder receives operations sufficient for a second installation to reconstruct the user's live portfolios, holdings, transactions, and goals

#### Scenario: Second device joins an existing folder
- **WHEN** a user runs Sync now against a folder that already contains operations
- **THEN** the system imports available operations before exporting that user's pending local operations

### Requirement: Immutable atomic operation export
The system SHALL export each pending operation as exactly one JSON document at `ops/<device-id>/<operation-id>.json`. It SHALL make a completed document visible only after closing a temporary file in the target directory and renaming it to the final path, and SHALL not overwrite a final operation file.

#### Scenario: Successful export
- **WHEN** Sync now exports a pending operation
- **THEN** the final JSON document is valid and the operation is recorded as exported locally

#### Scenario: Interrupted export
- **WHEN** writing an operation fails before the rename completes
- **THEN** no incomplete final `.json` operation is visible and the operation remains retryable

### Requirement: Safe idempotent import
The system SHALL scan all device folders for operation JSON, validate each document, and apply each unseen valid operation at most once. It SHALL retain malformed files, surface a visible error, and continue processing other files.

#### Scenario: Repeated scan
- **WHEN** the same valid operation is encountered after it was previously applied
- **THEN** the system skips it without duplicating or changing the synchronized entity

#### Scenario: Malformed operation
- **WHEN** a device folder contains invalid JSON or a document missing required operation fields
- **THEN** the system does not apply that file and reports a visible validation error while importing other valid files

### Requirement: Deterministic convergence and deletes
The system SHALL resolve competing records using the greatest `(logicalClock, createdAt, deviceId)` tuple stored per entity, applying an incoming create or update as a whole-record replacement only when its tuple outranks the stored tuple. It SHALL retain delete tombstones using the same ordering and SHALL not allow an older create or update to restore a deleted entity. When a losing update differs from the record it is discarded against, the system SHALL record the superseded record as a visible conflict entry.

#### Scenario: Simultaneous updates
- **WHEN** two devices independently change the same entity before synchronizing
- **THEN** both installations converge on the record selected by the deterministic ordering tuple

#### Scenario: Delete versus stale update
- **WHEN** a delete operation outranks an update operation for the same entity
- **THEN** the entity stays deleted after either import order and the stale update is not applied

#### Scenario: Superseded edit is recorded
- **WHEN** an incoming update outranks and replaces a local record whose value differs
- **THEN** the system applies the incoming record and records the overwritten record as a visible conflict entry

### Requirement: Manual synchronization outcome
The system SHALL provide a manual Sync now action or command that reports counts for exported, imported, skipped, conflicts or deferred operations, and errors for the requesting user.

#### Scenario: User-triggered synchronization
- **WHEN** an authenticated user runs Sync now
- **THEN** the system exports pending local operations, imports available remote operations, and returns a complete outcome summary

### Requirement: Local-only authentication and derived state
The system SHALL synchronize only portfolios, holdings, transactions, and goals. Users, password hashes, sessions, cookies, device settings, price caches, FX rates, dividend metadata, and generated portfolio snapshots SHALL remain local.

#### Scenario: Import onto another installation
- **WHEN** a second installation imports operations from a configured shared folder
- **THEN** imported portfolio data is associated with its active local user and no remote password, session, or market-cache state is created

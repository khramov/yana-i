# icloud-portfolio-sync Specification

## Purpose
Keeps a person's user-authored portfolio records synchronized privately across their Macs signed in to the same iCloud account, while every Mac stays fully usable offline and caches, preferences, and credentials never leave the device.

## Requirements

### Requirement: Private iCloud database only
The system SHALL store synchronized records only in the signed-in person's private CloudKit database in the app's own container. It SHALL NOT use public or shared databases and SHALL NOT send portfolio data to any other server.

#### Scenario: Records are private
- **WHEN** a person creates a portfolio while signed in to iCloud
- **THEN** the portfolio's synchronized record is written only to that person's private database and no other iCloud account can read it

### Requirement: Synchronized record types
The system SHALL synchronize portfolios, holdings, transactions, and allocation goals. It SHALL NOT synchronize price or FX caches, dividend-event data, value-history snapshots, UI preferences, sync bookkeeping, or market-data credentials.

#### Scenario: Cache stays local
- **WHEN** one Mac refreshes prices and dividend events
- **THEN** no price, FX, or dividend-event record appears in iCloud and a second Mac fetches its own market data

#### Scenario: Credential stays local
- **WHEN** a market-data credential is saved on one Mac
- **THEN** it is not present in any synchronized record

### Requirement: Offline-first local writes
Every create, edit, and delete SHALL be committed locally and shown immediately whether or not iCloud is reachable. Pending changes SHALL be kept across app restarts and sent automatically once iCloud becomes available.

#### Scenario: Edit while offline
- **WHEN** a person adds a transaction with no network connection and then quits the app
- **THEN** after relaunching with a connection, the transaction is uploaded without any further action from the person

#### Scenario: iCloud failure does not block editing
- **WHEN** an upload fails because of a network or server error
- **THEN** the local change stays visible and the upload is retried later

### Requirement: Receive changes from other Macs
The system SHALL apply records changed on other Macs signed in to the same iCloud account without requiring a restart, both while the app is running (via push notifications) and when the app next launches.

#### Scenario: Change made on another Mac
- **WHEN** a transaction is added on Mac A while the app is open on Mac B
- **THEN** the transaction appears on Mac B without a restart once Mac B receives the change

#### Scenario: Second Mac joins
- **WHEN** a person installs the app on a second Mac signed in to the same iCloud account
- **THEN** all existing portfolios, holdings, transactions, and goals are downloaded and the calculated values match the first Mac once prices are fetched

### Requirement: Deterministic conflict resolution
When the same record is changed on two Macs before they synchronize, every Mac SHALL converge on the same whole-record version. The winner SHALL be the version with the greatest (revision, modified-at timestamp, device ID) tuple.

#### Scenario: Concurrent edits to one transaction
- **WHEN** Mac A changes a transaction's price to 101 and Mac B, offline, changes its fee to 2, and both then synchronize
- **THEN** both Macs show the same single version of the transaction, chosen by the ordering tuple

### Requirement: Deletes are not resurrected
A deletion SHALL be synchronized as a tombstone that outranks any create or edit with a lower ordering tuple, so an older edit received later cannot restore a deleted record. Deleting a portfolio SHALL also delete its holdings, transactions, and goals on every Mac.

#### Scenario: Delete versus stale edit
- **WHEN** Mac A deletes a transaction and Mac B, offline, had edited it earlier, and both then synchronize
- **THEN** the transaction stays deleted on both Macs

#### Scenario: Portfolio delete cascades remotely
- **WHEN** a portfolio is deleted on Mac A
- **THEN** after synchronization Mac B no longer shows that portfolio or any of its holdings, transactions, or goals

### Requirement: Concurrent creates of the same key converge
Two Macs that independently create a holding for the same normalized ticker in the same portfolio, or a goal for the same portfolio, scope, and key, SHALL converge on exactly one record.

#### Scenario: Same ticker added on two Macs
- **WHEN** a person adds MSFT to the same portfolio on two offline Macs and adds a buy on each
- **THEN** after synchronization each Mac shows one MSFT holding containing both buys

### Requirement: Out-of-order delivery
The system SHALL accept a record whose parent has not yet arrived and SHALL show it once the parent arrives. It SHALL NOT discard or duplicate records because of delivery order.

#### Scenario: Transaction before holding
- **WHEN** a transaction record arrives before the holding it belongs to
- **THEN** the transaction is kept and appears under the holding as soon as the holding arrives

### Requirement: Versioned portable payloads
Each synchronized record SHALL carry a payload schema version and the record's UUID, and SHALL encode its fields in a store-independent format that a future authenticated API can accept without changes to the domain model. Records with an unsupported newer schema version SHALL be kept unchanged rather than overwritten.

#### Scenario: Newer schema from an updated Mac
- **WHEN** a Mac running an older app version receives a record written with a newer payload schema version
- **THEN** it does not overwrite or delete that record and it tells the person that an app update is needed to show it

### Requirement: iCloud account states
The system SHALL detect when iCloud is unavailable, restricted, temporarily unavailable, or signed out, show the reason, and keep local data usable. Synchronization SHALL resume automatically when the account becomes available.

#### Scenario: Not signed in to iCloud
- **WHEN** a person opens the app while signed out of iCloud
- **THEN** the app works fully on local data and shows that sync is off because no iCloud account is signed in

#### Scenario: iCloud access disabled for the app
- **WHEN** the app's iCloud access is turned off in System Settings
- **THEN** the sync status explains that iCloud access is disabled and where to enable it

### Requirement: Account change isolation
When the signed-in iCloud account changes to a different account, the system SHALL NOT upload the previous account's records to the new account. It SHALL remove the previous account's synchronized records from the Mac before downloading the new account's records, and SHALL first warn about any changes not yet uploaded.

#### Scenario: Switch iCloud accounts
- **WHEN** a person signs out of iCloud account A and signs in to account B
- **THEN** account A's portfolios are no longer shown, account B's portfolios are downloaded, and nothing from A is written to B

#### Scenario: Unsent changes at account change
- **WHEN** the account changes while local changes are still pending upload
- **THEN** the app warns that those changes were not synchronized before removing them

### Requirement: Visible sync status
The system SHALL show the current sync state (up to date, syncing, pending changes waiting, offline, or error), the time of the last successful sync, and the most recent error with its reason. It SHALL also offer a manual "Sync Now" action.

#### Scenario: Pending changes while offline
- **WHEN** a person has made 2 changes while offline
- **THEN** the sync status shows that changes are waiting to upload and the last successful sync time

#### Scenario: Manual sync
- **WHEN** a person chooses Sync Now while online
- **THEN** pending changes are uploaded, remote changes are fetched, and the last-sync time updates

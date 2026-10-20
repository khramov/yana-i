import CloudKit
import Foundation
import OSLog
import YanaSync

/// What the CloudKit adapter reports to the sync controller.
enum CloudKitTransportEvent: Sendable {
    case account(SyncAccountEvent)
    case fetchStarted
    case fetchFinished
    case sendStarted
    case sendFinished
    case issue(SyncIssue)
    /// Records from the server were applied to the local store.
    case recordsChanged
    /// The person erased Yana's iCloud data (System Settings › iCloud › Manage); local copies go too.
    case serverDataErased
}

/// `SyncTransport` over `CKSyncEngine` and the private database. Merging stays in `SyncCoordinator`: this type
/// only moves canonical payloads between the engine and the coordinator and keeps each record's server
/// system fields so saves build on the server's change tag.
actor CloudKitSyncTransport: SyncTransport, CKSyncEngineDelegate {
    private static let log = Logger(subsystem: "Yana", category: "CloudKitSync")

    private let database: CKDatabase
    private let store: PortfolioStore
    private let coordinator: SyncCoordinator
    private let report: @Sendable (CloudKitTransportEvent) async -> Void
    private var engine: CKSyncEngine?
    /// While set, nothing is sent or applied (an account change is being handled).
    private var suspended = false

    init(database: CKDatabase, store: PortfolioStore, coordinator: SyncCoordinator,
         report: @escaping @Sendable (CloudKitTransportEvent) async -> Void) {
        self.database = database
        self.store = store
        self.coordinator = coordinator
        self.report = report
    }

    /// Creates the engine from the persisted state and queues the outbox. Starts suspended if asked.
    func start(suspended: Bool) async throws {
        self.suspended = suspended
        let saved = try await store.syncEngineState()
        let state = saved.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        makeEngine(state: state)
        try await coordinator.attach(self)
    }

    private func makeEngine(state: CKSyncEngine.State.Serialization?) {
        let engine = CKSyncEngine(CKSyncEngine.Configuration(database: database, stateSerialization: state, delegate: self))
        if state == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudKitRecordMapping.zoneID))])
        }
        self.engine = engine
    }

    // MARK: - Control

    func suspend() async {
        suspended = true
        await engine?.cancelOperations()
    }

    /// Removes every synchronized record and the engine state, then starts a fresh engine for the current account.
    func resetLocalData() async throws {
        await engine?.cancelOperations()
        engine = nil
        try await store.removeAllRecords()
        makeEngine(state: nil)
        suspended = false
    }

    func resume() async throws {
        suspended = false
        try await coordinator.requeueOutbox()
    }

    func uploadAllRecords() async throws {
        try await store.flagAllForUpload()
        try await coordinator.requeueOutbox()
    }

    /// Fetches, then sends, right away.
    func syncNow() async {
        guard let engine, !suspended else { return }
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
        } catch let error as CKError {
            if let issue = SyncIssue(error) { await report(.issue(issue)) }
        } catch {
            await report(.issue(.failed(reason: error.localizedDescription)))
        }
    }

    // MARK: - SyncTransport

    func addPendingUploads(_ keys: [RecordKey]) async {
        guard let engine, !suspended else { return }
        engine.state.add(pendingRecordZoneChanges: keys.map { .saveRecord(CloudKitRecordMapping.recordID(for: $0)) })
    }

    // MARK: - CKSyncEngineDelegate

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard !suspended, syncEngine === engine else { return nil }
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await self.recordToSend(recordID, engine: syncEngine)
        }
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        // An engine replaced by `resetLocalData` may still deliver events; its state is gone.
        guard syncEngine === engine else { return }
        do {
            switch event {
            case .stateUpdate(let update):
                try await store.saveSyncEngineState(try JSONEncoder().encode(update.stateSerialization))
            case .accountChange(let change):
                await report(.account(Self.accountEvent(change.changeType)))
            case .fetchedDatabaseChanges(let changes):
                try await handleZoneDeletions(changes.deletions, engine: syncEngine)
            case .fetchedRecordZoneChanges(let changes):
                try await applyFetched(changes)
            case .sentRecordZoneChanges(let sent):
                try await handleSent(sent, engine: syncEngine)
            case .sentDatabaseChanges(let sent):
                for failure in sent.failedZoneSaves {
                    if let issue = SyncIssue(failure.error) { await report(.issue(issue)) }
                }
            case .willFetchChanges:
                await report(.fetchStarted)
            case .didFetchChanges:
                await report(.fetchFinished)
            case .didFetchRecordZoneChanges(let done):
                if let error = done.error, let issue = SyncIssue(error) { await report(.issue(issue)) }
            case .willSendChanges:
                await report(.sendStarted)
            case .didSendChanges:
                await report(.sendFinished)
            case .willFetchRecordZoneChanges:
                break
            @unknown default:
                break
            }
        } catch {
            Self.log.error("Handling \(String(describing: event), privacy: .public) failed: \(error, privacy: .public)")
            await report(.issue(.failed(reason: error.localizedDescription)))
        }
    }

    // MARK: - Sending

    private func recordToSend(_ recordID: CKRecord.ID, engine: CKSyncEngine) async -> CKRecord? {
        do {
            guard let key = try await store.key(forRecordID: try CloudKitRecordMapping.uuid(of: recordID)),
                  let outgoing = try await coordinator.outgoingRecord(for: key)
            else {
                engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            return CloudKitRecordMapping.record(for: outgoing, serverMetadata: try await store.serverMetadata(for: key))
        } catch {
            Self.log.error("Could not prepare \(recordID.recordName, privacy: .public): \(error, privacy: .public)")
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) async throws {
        for record in sent.savedRecords {
            let key = try CloudKitRecordMapping.key(of: record)
            try await store.saveServerMetadata(CloudKitRecordMapping.encodeSystemFields(of: record), for: key)
            let header = try PayloadCodec.header(try CloudKitRecordMapping.payload(of: record))
            try await coordinator.didUpload(key, version: header.version)
        }
        for failure in sent.failedRecordSaves {
            let key = try CloudKitRecordMapping.key(of: failure.record)
            let retry = CKSyncEngine.PendingRecordZoneChange.saveRecord(failure.record.recordID)
            switch failure.error.code {
            case .serverRecordChanged:
                guard let server = failure.error.serverRecord else { break }
                try await store.saveServerMetadata(CloudKitRecordMapping.encodeSystemFields(of: server), for: key)
                // Merge decides; if the local version still wins, the coordinator queues it again on top of `server`.
                try await coordinator.didConflict(key, serverPayload: try CloudKitRecordMapping.payload(of: server))
                await report(.recordsChanged)
            case .zoneNotFound:
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudKitRecordMapping.zoneID))])
                try await store.removeServerMetadata(for: key)
                engine.state.add(pendingRecordZoneChanges: [retry])
            case .unknownItem:
                // The server lost the record; send it again as new.
                try await store.removeServerMetadata(for: key)
                engine.state.add(pendingRecordZoneChanges: [retry])
            default:
                // The engine retries network and throttling failures by itself.
                if let issue = SyncIssue(failure.error) { await report(.issue(issue)) }
            }
        }
    }

    // MARK: - Fetching

    private func applyFetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) async throws {
        guard !suspended else { return }
        var applied = false
        for modification in changes.modifications {
            let record = modification.record
            do {
                let key = try CloudKitRecordMapping.key(of: record)
                try await store.saveServerMetadata(CloudKitRecordMapping.encodeSystemFields(of: record), for: key)
                if try await coordinator.receive(try CloudKitRecordMapping.payload(of: record)) != .keepLocal {
                    applied = true
                }
            } catch {
                Self.log.error("Skipped \(record.recordID.recordName, privacy: .public): \(error, privacy: .public)")
            }
        }
        // Yana never hard-deletes (deletes are tombstones), so a server-side deletion only invalidates metadata.
        for deletion in changes.deletions {
            if let id = try? CloudKitRecordMapping.uuid(of: deletion.recordID),
               let entity = RecordEntity(rawValue: deletion.recordType) {
                try await store.removeServerMetadata(for: RecordKey(entity: entity, id: id))
            }
        }
        if applied { await report(.recordsChanged) }
    }

    private func handleZoneDeletions(_ deletions: [CKDatabase.DatabaseChange.Deletion], engine: CKSyncEngine) async throws {
        for deletion in deletions where deletion.zoneID == CloudKitRecordMapping.zoneID {
            switch deletion.reason {
            case .purged:
                await report(.serverDataErased)
            default:
                // The zone vanished or was reset (encryption keys lost): upload everything again.
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudKitRecordMapping.zoneID))])
                try await uploadAllRecords()
            }
        }
    }

    static func accountEvent(_ change: CKSyncEngine.Event.AccountChange.ChangeType) -> SyncAccountEvent {
        switch change {
        case .signIn: return .signedIn
        case .signOut: return .signedOut
        case .switchAccounts: return .switchedAccounts
        @unknown default: return .switchedAccounts
        }
    }
}

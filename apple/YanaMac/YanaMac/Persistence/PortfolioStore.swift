import Foundation
import SwiftData
import YanaDomain
import YanaSync

/// The single writer for `Portfolio.store`. Every call runs on this actor's context and saves before returning,
/// so each call is one transaction.
@ModelActor
actor PortfolioStore {
    static let fileName = "Portfolio.store"

    static func makeContainer(inMemory: Bool = false, directory: URL? = nil) throws -> ModelContainer {
        let schema = Schema(PortfolioSchema.models)
        let configuration = inMemory
            ? ModelConfiguration("Portfolio", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            : ModelConfiguration("Portfolio", schema: schema,
                                 url: try StoreLocation.url(for: fileName, in: directory), cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: - Reads

    func portfolios(includingDeleted: Bool = false) throws -> [PortfolioRecord] {
        try modelContext.fetch(FetchDescriptor<StoredPortfolio>(sortBy: [SortDescriptor(\.createdAt)]))
            .map(\.record).filter { includingDeleted || !$0.isDeleted }
    }

    func portfolio(_ id: UUID) throws -> PortfolioRecord? {
        try fetch(StoredPortfolio.self, id)?.record
    }

    func holdings(inPortfolio portfolioID: UUID, includingDeleted: Bool = false) throws -> [HoldingRecord] {
        try modelContext.fetch(FetchDescriptor<StoredHolding>(predicate: #Predicate { $0.portfolioID == portfolioID },
                                                              sortBy: [SortDescriptor(\.ticker)]))
            .map(\.record).filter { includingDeleted || !$0.isDeleted }
    }

    func holding(_ id: UUID) throws -> HoldingRecord? {
        try fetch(StoredHolding.self, id)?.record
    }

    func transactions(inPortfolio portfolioID: UUID) throws -> [TransactionRecord] {
        try modelContext.fetch(FetchDescriptor<StoredTransaction>(
            predicate: #Predicate { $0.portfolioID == portfolioID && $0.deletedAt == nil }))
            .map(\.record)
    }

    func transactions(ofHolding holdingID: UUID) throws -> [TransactionRecord] {
        try modelContext.fetch(FetchDescriptor<StoredTransaction>(
            predicate: #Predicate { $0.holdingID == holdingID && $0.deletedAt == nil }))
            .map(\.record)
    }

    func transaction(_ id: UUID) throws -> TransactionRecord? {
        try fetch(StoredTransaction.self, id)?.record
    }

    func goals(inPortfolio portfolioID: UUID, includingDeleted: Bool = false) throws -> [GoalRecord] {
        try modelContext.fetch(FetchDescriptor<StoredGoal>(predicate: #Predicate { $0.portfolioID == portfolioID },
                                                           sortBy: [SortDescriptor(\.key)]))
            .map(\.record).filter { includingDeleted || !$0.isDeleted }
    }

    // MARK: - Local-only bookkeeping

    /// This installation's device ID, created and saved on first use.
    func deviceID() throws -> UUID {
        if let existing = try modelContext.fetch(FetchDescriptor<StoredDeviceIdentity>()).first {
            return existing.deviceID
        }
        let identity = StoredDeviceIdentity(deviceID: UUID())
        modelContext.insert(identity)
        try modelContext.save()
        return identity.deviceID
    }

    func syncEngineState() throws -> Data? {
        try modelContext.fetch(FetchDescriptor<StoredSyncEngineState>()).first?.data
    }

    func saveSyncEngineState(_ data: Data?) throws {
        let existing = try modelContext.fetch(FetchDescriptor<StoredSyncEngineState>()).first
        switch (existing, data) {
        case let (row?, data?): row.data = data
        case let (nil, data?): modelContext.insert(StoredSyncEngineState(data: data))
        case let (row?, nil): modelContext.delete(row)
        case (nil, nil): return
        }
        try modelContext.save()
    }

    /// Removes every record and all sync bookkeeping except the device ID (used after an iCloud account change).
    func removeAllRecords() throws {
        try modelContext.delete(model: StoredPortfolio.self)
        try modelContext.delete(model: StoredHolding.self)
        try modelContext.delete(model: StoredTransaction.self)
        try modelContext.delete(model: StoredGoal.self)
        try modelContext.delete(model: StoredPendingRemotePayload.self)
        try modelContext.delete(model: StoredSyncEngineState.self)
        try modelContext.delete(model: StoredServerRecordMetadata.self)
        try modelContext.save()
    }

    /// Flags every record for upload and forgets all server metadata, so each record is sent fresh
    /// (after signing in to an account, or when the server zone was deleted). Locked records stay unflagged.
    func flagAllForUpload() throws {
        let locked = Set(try keysAwaitingAppUpdate())
        func flag<M: StoredRecord>(_ type: M.Type, _ entity: RecordEntity) throws {
            for row in try modelContext.fetch(FetchDescriptor<M>()) where !locked.contains(RecordKey(entity: entity, id: row.id)) {
                row.needsUpload = true
            }
        }
        try flag(StoredPortfolio.self, .portfolio)
        try flag(StoredHolding.self, .holding)
        try flag(StoredTransaction.self, .transaction)
        try flag(StoredGoal.self, .goal)
        try modelContext.delete(model: StoredServerRecordMetadata.self)
        try saveOrRollback()
    }

    /// The key of the local record with this ID, in whichever table holds it. IDs are unique across entities.
    func key(forRecordID id: UUID) throws -> RecordKey? {
        for entity in RecordEntity.allCases {
            let key = RecordKey(entity: entity, id: id)
            if try storedRecord(for: key) != nil || pendingRemote(for: key) != nil { return key }
        }
        return nil
    }

    // MARK: - Server record metadata

    func serverMetadata(for key: RecordKey) throws -> Data? {
        try serverMetadataRow(for: key)?.data
    }

    func saveServerMetadata(_ data: Data, for key: RecordKey) throws {
        if let row = try serverMetadataRow(for: key) {
            row.data = data
        } else {
            modelContext.insert(StoredServerRecordMetadata(key: key, data: data))
        }
        try saveOrRollback()
    }

    func removeServerMetadata(for key: RecordKey) throws {
        guard let row = try serverMetadataRow(for: key) else { return }
        modelContext.delete(row)
        try saveOrRollback()
    }

    private func serverMetadataRow(for key: RecordKey) throws -> StoredServerRecordMetadata? {
        let storedKey = key.description
        var descriptor = FetchDescriptor<StoredServerRecordMetadata>(predicate: #Predicate { $0.key == storedKey })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Helpers

    private func fetch<M: StoredRecord>(_ type: M.Type, _ id: UUID) throws -> M? {
        var descriptor = FetchDescriptor<M>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func storedRecord(for key: RecordKey) throws -> (any StoredRecord)? {
        switch key.entity {
        case .portfolio: return try fetch(StoredPortfolio.self, key.id)
        case .holding: return try fetch(StoredHolding.self, key.id)
        case .transaction: return try fetch(StoredTransaction.self, key.id)
        case .goal: return try fetch(StoredGoal.self, key.id)
        }
    }

    private func pendingRemote(for key: RecordKey) throws -> StoredPendingRemotePayload? {
        let storedKey = key.description
        var descriptor = FetchDescriptor<StoredPendingRemotePayload>(predicate: #Predicate { $0.key == storedKey })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Inserts or overwrites the stored mirror of `record` and returns it.
    @discardableResult
    private func upsert(_ record: AnyRecord) throws -> any StoredRecord {
        switch record {
        case .portfolio(let r):
            if let row = try fetch(StoredPortfolio.self, r.id) { row.update(from: r); return row }
            let row = StoredPortfolio(r); modelContext.insert(row); return row
        case .holding(let r):
            if let row = try fetch(StoredHolding.self, r.id) { row.update(from: r); return row }
            let row = StoredHolding(r); modelContext.insert(row); return row
        case .transaction(let r):
            if let row = try fetch(StoredTransaction.self, r.id) { row.update(from: r); return row }
            let row = StoredTransaction(r); modelContext.insert(row); return row
        case .goal(let r):
            if let row = try fetch(StoredGoal.self, r.id) { row.update(from: r); return row }
            let row = StoredGoal(r); modelContext.insert(row); return row
        }
    }

    private func saveOrRollback() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

extension PortfolioStore: SyncRecordStore {
    func state(for key: RecordKey) throws -> LocalRecordState? {
        let local = try storedRecord(for: key)
        let pending = try pendingRemote(for: key).flatMap { try? PayloadCodec.header($0.pendingRemotePayload) }
        if local == nil && pending == nil { return nil }
        return LocalRecordState(version: local?.version, pendingRemoteVersion: pending?.version)
    }

    func record(for key: RecordKey) throws -> AnyRecord? {
        try storedRecord(for: key)?.anyRecord
    }

    func saveLocal(_ records: [AnyRecord]) throws {
        for record in records {
            try upsert(record).needsUpload = true
        }
        try saveOrRollback()
    }

    func applyRemote(_ record: AnyRecord) throws {
        try upsert(record).needsUpload = false
        if let pending = try pendingRemote(for: record.key) { modelContext.delete(pending) }
        try saveOrRollback()
    }

    func storePendingRemote(_ payload: Data, header: PayloadHeader) throws {
        if let pending = try pendingRemote(for: header.key) {
            pending.pendingRemotePayload = payload
        } else {
            modelContext.insert(StoredPendingRemotePayload(key: header.key, payload: payload))
        }
        try storedRecord(for: header.key)?.needsUpload = false
        try saveOrRollback()
    }

    func keysNeedingUpload() throws -> [RecordKey] {
        var keys: [RecordKey] = []
        keys += try modelContext.fetch(FetchDescriptor<StoredPortfolio>(predicate: #Predicate { $0.needsUpload }))
            .map { RecordKey(entity: .portfolio, id: $0.id) }
        keys += try modelContext.fetch(FetchDescriptor<StoredHolding>(predicate: #Predicate { $0.needsUpload }))
            .map { RecordKey(entity: .holding, id: $0.id) }
        keys += try modelContext.fetch(FetchDescriptor<StoredTransaction>(predicate: #Predicate { $0.needsUpload }))
            .map { RecordKey(entity: .transaction, id: $0.id) }
        keys += try modelContext.fetch(FetchDescriptor<StoredGoal>(predicate: #Predicate { $0.needsUpload }))
            .map { RecordKey(entity: .goal, id: $0.id) }
        return keys.sorted { $0.description < $1.description }
    }

    func markUploaded(_ key: RecordKey, version: RecordVersion) throws {
        guard let row = try storedRecord(for: key), row.version == version, row.needsUpload else { return }
        row.needsUpload = false
        try saveOrRollback()
    }

    func liveChildren(ofPortfolio portfolioID: UUID) throws -> [AnyRecord] {
        try holdings(inPortfolio: portfolioID).map(AnyRecord.holding)
            + transactions(inPortfolio: portfolioID).map(AnyRecord.transaction)
            + goals(inPortfolio: portfolioID).map(AnyRecord.goal)
    }

    func keysAwaitingAppUpdate() throws -> [RecordKey] {
        try modelContext.fetch(FetchDescriptor<StoredPendingRemotePayload>()).compactMap { RecordKey(storedKey: $0.key) }
    }
}

enum StoreLocation {
    /// `<directory>/<file>`, defaulting to the sandboxed
    /// `~/Library/Containers/<bundle id>/Data/Library/Application Support`.
    static func url(for fileName: String, in directory: URL? = nil) throws -> URL {
        let directory = directory ?? URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: fileName)
    }
}

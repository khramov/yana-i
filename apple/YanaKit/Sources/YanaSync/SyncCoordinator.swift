import Foundation
import YanaDomain

/// Store-independent sync logic: the durable outbox, merging incoming records, server conflicts,
/// portfolio-delete cascades, and tolerance for children that arrive before their parents.
public actor SyncCoordinator {
    public let deviceID: UUID
    private let store: any SyncRecordStore
    private let now: @Sendable () -> Date
    private var transport: (any SyncTransport)?

    public init(deviceID: UUID, store: any SyncRecordStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.deviceID = deviceID
        self.store = store
        self.now = now
    }

    /// Connects a transport and re-enqueues every record still flagged for upload, so a crash between a local
    /// save and the transport's own state persistence loses nothing.
    public func attach(_ transport: any SyncTransport) async throws {
        self.transport = transport
        try await requeueOutbox()
    }

    public func detach() {
        transport = nil
    }

    public func requeueOutbox() async throws {
        let keys = try await store.keysNeedingUpload()
        if !keys.isEmpty { await transport?.addPendingUploads(keys) }
    }

    // MARK: - Local writes

    /// Stamps each record with the next local version, saves them together, and queues them for upload.
    @discardableResult
    public func commitLocalEdits(_ records: [AnyRecord]) async throws -> [AnyRecord] {
        let at = now()
        var stamped: [AnyRecord] = []
        for var record in records {
            record.version = Merge.localEditVersion(stored: try await store.state(for: record.key), now: at, deviceID: deviceID)
            stamped.append(record)
        }
        try await store.saveLocal(stamped)
        await transport?.addPendingUploads(stamped.map(\.key))
        return stamped
    }

    // MARK: - Transport callbacks

    /// The payload to send for `key`, or `nil` when there is nothing this device may send
    /// (unknown record, or one locked behind a newer-schema payload).
    public func outgoingRecord(for key: RecordKey) async throws -> OutgoingRecord? {
        guard let record = try await store.record(for: key) else { return nil }
        if let pending = try await store.state(for: key)?.pendingRemoteVersion, pending >= record.version { return nil }
        return OutgoingRecord(key: key, payload: PayloadCodec.encode(record), schemaVersion: PayloadCodec.schemaVersion,
                              version: record.version, deleted: record.isDeleted)
    }

    public func didUpload(_ key: RecordKey, version: RecordVersion) async throws {
        try await store.markUploaded(key, version: version)
    }

    /// The server already held a different version. Merge it; if the local record still wins, send it again
    /// (the transport re-sends on top of the server record it just reported).
    public func didConflict(_ key: RecordKey, serverPayload: Data) async throws {
        let decision = try await receive(serverPayload)
        if decision == .keepLocal {
            await transport?.addPendingUploads([key])
        }
    }

    /// Applies one record fetched from the server.
    @discardableResult
    public func receive(_ payload: Data) async throws -> MergeDecision {
        let header = try PayloadCodec.header(payload)
        let decision = Merge.decide(local: try await store.state(for: header.key), incoming: header)
        switch decision {
        case .keepLocal:
            break
        case .deferUnknownSchema:
            try await store.storePendingRemote(payload, header: header)
        case .applyIncoming:
            let record = try PayloadCodec.decode(payload)
            try await store.applyRemote(record)
            try await enforcePortfolioDeletion(after: record)
        }
        return decision
    }

    /// A deleted portfolio takes its children with it on every device: when a portfolio tombstone arrives, tombstone
    /// the live children known here; when a live child arrives for a portfolio already tombstoned here (it was
    /// created offline elsewhere), tombstone it too. Each new tombstone is uploaded.
    private func enforcePortfolioDeletion(after record: AnyRecord) async throws {
        var orphans: [AnyRecord] = []
        switch record {
        case .portfolio(let p) where p.isDeleted:
            orphans = try await store.liveChildren(ofPortfolio: p.id)
        case .portfolio:
            return
        default:
            guard !record.isDeleted,
                  let parent = try await store.record(for: RecordKey(entity: .portfolio, id: record.portfolioID)),
                  parent.isDeleted
            else { return }
            orphans = [record]
        }
        guard !orphans.isEmpty else { return }
        let at = now()
        try await commitLocalEdits(orphans.map { var r = $0; r.deletedAt = at; return r })
    }
}

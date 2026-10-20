import Foundation
import YanaDomain

/// A fake private database that behaves like CloudKit for sync purposes: each save must name the change tag it
/// is based on, a mismatch is reported as a conflict carrying the server record, and devices fetch changes
/// since their last token.
public actor InMemoryCloud {
    public struct ServerRecord: Sendable {
        public var payload: Data
        public var changeTag: Int
    }

    public private(set) var records: [RecordKey: ServerRecord] = [:]
    private var log: [(sequence: Int, key: RecordKey)] = []
    private var sequence = 0

    public init() {}

    public enum SaveResult: Sendable {
        case saved(changeTag: Int)
        case conflict(ServerRecord)
    }

    func save(_ key: RecordKey, payload: Data, basedOn tag: Int?) -> SaveResult {
        if let current = records[key], current.changeTag != tag { return .conflict(current) }
        sequence += 1
        records[key] = ServerRecord(payload: payload, changeTag: sequence)
        log.append((sequence, key))
        return .saved(changeTag: sequence)
    }

    func changes(since token: Int) -> (records: [(RecordKey, ServerRecord)], token: Int) {
        let keys = log.filter { $0.sequence > token }.map(\.key)
        var seen = Set<RecordKey>()
        let unique = keys.reversed().filter { seen.insert($0).inserted }.reversed()
        return (unique.compactMap { k in records[k].map { (k, $0) } }, sequence)
    }

    /// Decoded server contents, for assertions.
    public func decodedRecords() throws -> [RecordKey: AnyRecord] {
        try records.mapValues { try PayloadCodec.decode($0.payload) }
    }
}

/// One device's connection to an `InMemoryCloud`. Nothing moves until `sync()` is called, so a test controls
/// exactly when each device is "online".
public actor InMemorySyncTransport: SyncTransport {
    private let cloud: InMemoryCloud
    private var coordinator: SyncCoordinator?
    private var pending: [RecordKey] = []
    private var knownTags: [RecordKey: Int] = [:]
    private var token = 0

    public init(cloud: InMemoryCloud) {
        self.cloud = cloud
    }

    public func connect(_ coordinator: SyncCoordinator) async throws {
        self.coordinator = coordinator
        try await coordinator.attach(self)
    }

    public func addPendingUploads(_ keys: [RecordKey]) {
        for k in keys where !pending.contains(k) { pending.append(k) }
    }

    public var pendingCount: Int { pending.count }

    /// Sends pending records (resolving conflicts until none remain), then fetches remote changes.
    public func sync() async throws {
        guard let coordinator else { return }
        var rounds = 0
        while !pending.isEmpty {
            rounds += 1
            precondition(rounds < 100, "sync did not settle")
            let batch = pending
            pending = []
            for key in batch {
                guard let out = try await coordinator.outgoingRecord(for: key) else { continue }
                switch await cloud.save(key, payload: out.payload, basedOn: knownTags[key]) {
                case .saved(let tag):
                    knownTags[key] = tag
                    try await coordinator.didUpload(key, version: out.version)
                case .conflict(let server):
                    knownTags[key] = server.changeTag
                    try await coordinator.didConflict(key, serverPayload: server.payload)
                }
            }
        }
        let (changes, newToken) = await cloud.changes(since: token)
        for (key, server) in changes {
            knownTags[key] = server.changeTag
            try await coordinator.receive(server.payload)
        }
        token = newToken
        // Receiving can create new local tombstones (portfolio cascade); send those too.
        if !pending.isEmpty { try await sync() }
    }
}

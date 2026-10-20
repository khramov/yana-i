import Foundation
import YanaDomain

/// A `SyncRecordStore` held in memory, for tests and previews.
public actor InMemoryRecordStore: SyncRecordStore {
    public struct Entry: Equatable, Sendable {
        public var record: AnyRecord?
        public var needsUpload = false
        public var pendingRemotePayload: Data?
        public var pendingRemoteHeader: PayloadHeader?
    }

    public private(set) var entries: [RecordKey: Entry] = [:]

    public init() {}

    /// All decoded records, for comparing devices.
    public var records: [RecordKey: AnyRecord] { entries.compactMapValues(\.record) }

    public func liveRecords() -> [AnyRecord] {
        entries.values.compactMap(\.record).filter { !$0.isDeleted }
    }

    public func state(for key: RecordKey) -> LocalRecordState? {
        guard let e = entries[key] else { return nil }
        return LocalRecordState(version: e.record?.version, pendingRemoteVersion: e.pendingRemoteHeader?.version)
    }

    public func record(for key: RecordKey) -> AnyRecord? { entries[key]?.record }

    public func saveLocal(_ records: [AnyRecord]) {
        for r in records {
            entries[r.key, default: Entry()].record = r
            entries[r.key]!.needsUpload = true
        }
    }

    public func applyRemote(_ record: AnyRecord) {
        entries[record.key] = Entry(record: record)
    }

    public func storePendingRemote(_ payload: Data, header: PayloadHeader) {
        var e = entries[header.key, default: Entry()]
        e.pendingRemotePayload = payload
        e.pendingRemoteHeader = header
        e.needsUpload = false
        entries[header.key] = e
    }

    public func keysNeedingUpload() -> [RecordKey] {
        entries.filter(\.value.needsUpload).map(\.key).sorted { $0.description < $1.description }
    }

    public func markUploaded(_ key: RecordKey, version: RecordVersion) {
        if entries[key]?.record?.version == version { entries[key]!.needsUpload = false }
    }

    public func liveChildren(ofPortfolio portfolioID: UUID) -> [AnyRecord] {
        liveRecords().filter { $0.entity != .portfolio && $0.portfolioID == portfolioID }
    }

    public func keysAwaitingAppUpdate() -> [RecordKey] {
        entries.filter { $0.value.pendingRemotePayload != nil }.map(\.key)
    }
}

import Foundation
import YanaDomain

/// Local persistence as the sync engine sees it. Implementations must make each call atomic.
public protocol SyncRecordStore: Sendable {
    func state(for key: RecordKey) async throws -> LocalRecordState?
    /// The decoded local record, tombstones included.
    func record(for key: RecordKey) async throws -> AnyRecord?
    /// Saves records written on this device and marks each as needing upload, in one transaction.
    func saveLocal(_ records: [AnyRecord]) async throws
    /// Saves a record received from another device, clearing its upload flag and any preserved newer payload.
    func applyRemote(_ record: AnyRecord) async throws
    /// Preserves a payload this app cannot decode, unchanged, and clears the record's upload flag.
    func storePendingRemote(_ payload: Data, header: PayloadHeader) async throws
    /// The durable outbox.
    func keysNeedingUpload() async throws -> [RecordKey]
    /// Clears the upload flag only if the stored version still equals `version`.
    func markUploaded(_ key: RecordKey, version: RecordVersion) async throws
    /// Live (non-tombstoned) holdings, transactions, and goals of a portfolio.
    func liveChildren(ofPortfolio portfolioID: UUID) async throws -> [AnyRecord]
    /// Keys of records locked read-only because a newer-schema payload is preserved for them.
    func keysAwaitingAppUpdate() async throws -> [RecordKey]
}

/// The sending side of a sync backend (CloudKit's `CKSyncEngine` in the app, a fake in tests).
/// The transport pulls payloads from `SyncCoordinator.outgoingRecord(for:)` when it sends.
public protocol SyncTransport: Sendable {
    func addPendingUploads(_ keys: [RecordKey]) async
}

/// One record ready to send.
public struct OutgoingRecord: Equatable, Sendable {
    public var key: RecordKey
    public var payload: Data
    public var schemaVersion: Int
    public var version: RecordVersion
    public var deleted: Bool
}

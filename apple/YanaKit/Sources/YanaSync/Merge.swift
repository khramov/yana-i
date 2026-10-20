import Foundation
import YanaDomain

/// What this device knows about one record before a merge.
public struct LocalRecordState: Equatable, Sendable {
    /// Version of the decoded local record, if any (tombstones included).
    public var version: RecordVersion?
    /// Version of a preserved payload from a newer schema, if one is held for this record.
    public var pendingRemoteVersion: RecordVersion?

    public init(version: RecordVersion?, pendingRemoteVersion: RecordVersion? = nil) {
        self.version = version
        self.pendingRemoteVersion = pendingRemoteVersion
    }

    /// The greatest version known locally in either form.
    public var effectiveVersion: RecordVersion? {
        [version, pendingRemoteVersion].compactMap { $0 }.max()
    }
}

public enum MergeDecision: Equatable, Sendable {
    /// Replace the local record with the incoming one.
    case applyIncoming
    /// The local record is at least as new; ignore the incoming one (and re-send local if it won a server conflict).
    case keepLocal
    /// The incoming record wins but uses a payload schema this app cannot decode: store its bytes unchanged
    /// and lock the record read-only.
    case deferUnknownSchema
}

public enum Merge {
    /// Whole-record last-writer-wins by `RecordVersion`. Tombstones compete like any other version,
    /// so a stale edit can never resurrect a delete. Equal versions keep local, which makes re-delivery idempotent.
    public static func decide(local: LocalRecordState?, incoming: PayloadHeader,
                              supportedSchema: Int = PayloadCodec.schemaVersion) -> MergeDecision {
        if let known = local?.effectiveVersion, incoming.version <= known {
            return .keepLocal
        }
        return incoming.schemaVersion > supportedSchema ? .deferUnknownSchema : .applyIncoming
    }

    /// Version for a local create, edit, delete, or re-creation over a known tombstone:
    /// `stored.revision + 1`, now, this device. A record never seen before starts at revision 1.
    public static func localEditVersion(stored: LocalRecordState?, now: Date, deviceID: UUID) -> RecordVersion {
        guard let known = stored?.effectiveVersion else { return .initial(at: now, deviceID: deviceID) }
        return known.bumped(at: now, deviceID: deviceID)
    }
}

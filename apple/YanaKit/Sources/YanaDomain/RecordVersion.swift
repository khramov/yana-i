import Foundation

/// Ordering tuple for one record's state. The greater version wins a sync conflict.
///
/// Compared lexicographically by revision, then modification time, then device ID
/// (by lowercase UUID string, so every platform orders it the same way).
public struct RecordVersion: Codable, Hashable, Comparable, Sendable {
    public var revision: Int64
    public var modifiedAt: Date
    public var deviceID: UUID

    /// `modifiedAt` is truncated to whole milliseconds, the precision sync payloads carry, so a
    /// version compares equal to itself after a round trip through another device.
    public init(revision: Int64, modifiedAt: Date, deviceID: UUID) {
        self.revision = revision
        self.modifiedAt = modifiedAt.truncatedToMilliseconds
        self.deviceID = deviceID
    }

    /// The version for a record's first local save.
    public static func initial(at now: Date, deviceID: UUID) -> RecordVersion {
        RecordVersion(revision: 1, modifiedAt: now, deviceID: deviceID)
    }

    /// The version for a local edit on top of this one.
    public func bumped(at now: Date, deviceID: UUID) -> RecordVersion {
        RecordVersion(revision: revision + 1, modifiedAt: now, deviceID: deviceID)
    }

    public static func < (lhs: RecordVersion, rhs: RecordVersion) -> Bool {
        if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt < rhs.modifiedAt }
        return lhs.deviceID.uuidString.lowercased() < rhs.deviceID.uuidString.lowercased()
    }
}

extension Date {
    /// This date rounded down to a whole millisecond since 1970.
    public var truncatedToMilliseconds: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 * 1000).rounded(.down) / 1000)
    }
}

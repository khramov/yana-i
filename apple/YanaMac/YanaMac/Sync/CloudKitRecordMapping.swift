import CloudKit
import Foundation
import YanaSync

enum CloudKitMappingError: Error, Equatable {
    case unknownRecordType(String)
    case invalidRecordName(String)
    case missingPayload
    /// The payload's own entity and ID disagree with the CloudKit record it arrived in.
    case payloadMismatch
}

/// How synchronized records are stored in CloudKit: one `CKRecord` per record in the private database's
/// `Portfolio` zone, with the entity name as record type and the lowercase UUID as record name. The record
/// itself travels as the opaque canonical payload; the scalar fields beside it only aid inspection and indexing,
/// so the CloudKit schema never has to change when the payload does.
enum CloudKitRecordMapping {
    static let zoneID = CKRecordZone.ID(zoneName: "Portfolio", ownerName: CKCurrentUserDefaultName)

    enum Field {
        static let payload = "payload"
        static let schemaVersion = "schemaVersion"
        static let revision = "revision"
        static let modifiedAt = "modifiedAt"
        static let deviceID = "deviceID"
        static let deleted = "deleted"
        static let all = [payload, schemaVersion, revision, modifiedAt, deviceID, deleted]
    }

    static func recordID(for key: RecordKey) -> CKRecord.ID {
        CKRecord.ID(recordName: key.id.uuidString.lowercased(), zoneID: zoneID)
    }

    static func recordID(_ id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString.lowercased(), zoneID: zoneID)
    }

    static func uuid(of recordID: CKRecord.ID) throws -> UUID {
        guard let id = UUID(uuidString: recordID.recordName) else {
            throw CloudKitMappingError.invalidRecordName(recordID.recordName)
        }
        return id
    }

    static func key(of record: CKRecord) throws -> RecordKey {
        guard let entity = RecordEntity(rawValue: record.recordType) else {
            throw CloudKitMappingError.unknownRecordType(record.recordType)
        }
        return RecordKey(entity: entity, id: try uuid(of: record.recordID))
    }

    /// The record to send: the last known server record (so the save carries its change tag) or a new one,
    /// with every field set from `outgoing`.
    static func record(for outgoing: OutgoingRecord, serverMetadata: Data?) -> CKRecord {
        let id = recordID(for: outgoing.key)
        let known = serverMetadata.flatMap(decodeSystemFields)
        let record = known.flatMap { $0.recordType == outgoing.key.entity.rawValue && $0.recordID == id ? $0 : nil }
            ?? CKRecord(recordType: outgoing.key.entity.rawValue, recordID: id)
        apply(outgoing, to: record)
        return record
    }

    static func apply(_ outgoing: OutgoingRecord, to record: CKRecord) {
        record[Field.payload] = outgoing.payload as NSData
        record[Field.schemaVersion] = Int64(outgoing.schemaVersion) as NSNumber
        record[Field.revision] = outgoing.version.revision as NSNumber
        record[Field.modifiedAt] = outgoing.version.modifiedAt as NSDate
        record[Field.deviceID] = outgoing.version.deviceID.uuidString.lowercased() as NSString
        record[Field.deleted] = Int64(outgoing.deleted ? 1 : 0) as NSNumber
    }

    /// The canonical payload carried by `record`, checked against the record's type and name.
    static func payload(of record: CKRecord) throws -> Data {
        guard let payload = record[Field.payload] as? Data else { throw CloudKitMappingError.missingPayload }
        let header = try PayloadCodec.header(payload)
        guard header.key == (try key(of: record)) else { throw CloudKitMappingError.payloadMismatch }
        return payload
    }

    // MARK: - System fields

    static func encodeSystemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}

extension SyncIssue {
    /// How a CloudKit error is shown, or `nil` for errors the sync engine handles silently (cancellations, and
    /// conflicts and missing zones, which the adapter resolves itself).
    init?(_ error: CKError) {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            self = .offline
        case .operationCancelled, .serverRecordChanged, .zoneNotFound, .unknownItem, .batchRequestFailed:
            return nil
        case .notAuthenticated:
            self = .failed(reason: SyncAccountStatus.noAccount.reason!)
        case .quotaExceeded:
            self = .failed(reason: "Your iCloud storage is full. Free up space to resume syncing.")
        case .permissionFailure, .managedAccountRestricted:
            self = .failed(reason: SyncAccountStatus.restricted.reason!)
        case .incompatibleVersion:
            self = .failed(reason: "This version of Yana can no longer sync. Update the app.")
        default:
            self = .failed(reason: error.localizedDescription)
        }
    }
}

extension SyncAccountStatus {
    init(_ status: CKAccountStatus) {
        switch status {
        case .available: self = .available
        case .noAccount: self = .noAccount
        case .restricted: self = .restricted
        case .temporarilyUnavailable: self = .temporarilyUnavailable
        default: self = .couldNotDetermine
        }
    }
}

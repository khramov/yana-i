import Foundation
import YanaDomain

/// Envelope fields readable from any payload version, so a record from a newer app can still be
/// ordered and preserved without being decoded.
public struct PayloadHeader: Equatable, Sendable {
    public var schemaVersion: Int
    public var entity: RecordEntity
    public var id: UUID
    public var version: RecordVersion
    public var deleted: Bool

    public var key: RecordKey { RecordKey(entity: entity, id: id) }
}

public enum PayloadError: Error, Equatable, Sendable {
    case malformed(String)
    case unsupportedSchema(Int)
}

/// Canonical JSON for synchronized records (see `apple/docs/sync-payload-v1.md`): sorted keys, no
/// insignificant whitespace, decimals as strings, UTC ISO-8601 timestamps with milliseconds,
/// `YYYY-MM-DD` dates, lowercase UUIDs, and absent optionals omitted.
public enum PayloadCodec {
    public static let schemaVersion = 1

    public static func encode(_ record: AnyRecord) -> Data {
        var object: [String: Any] = [
            "schemaVersion": schemaVersion,
            "entity": record.entity.rawValue,
            "id": uuid(record.id),
            "version": [
                "revision": NSNumber(value: record.version.revision),
                "modifiedAt": timestamp(record.version.modifiedAt),
                "deviceID": uuid(record.version.deviceID),
            ] as [String: Any],
        ]
        if let d = record.deletedAt { object["deletedAt"] = timestamp(d) }

        var fields: [String: Any] = [:]
        func put(_ key: String, _ value: Any?) { if let value { fields[key] = value } }
        switch record {
        case .portfolio(let r):
            put("name", r.name)
            put("baseCurrency", r.baseCurrency.code)
            put("createdAt", timestamp(r.createdAt))
        case .holding(let r):
            put("portfolioID", uuid(r.portfolioID))
            put("ticker", r.ticker)
            put("name", r.name)
            put("sector", r.sector)
            put("assetClass", r.assetClass.rawValue)
            put("currency", r.currency.code)
            put("createdAt", timestamp(r.createdAt))
        case .transaction(let r):
            put("portfolioID", uuid(r.portfolioID))
            put("holdingID", uuid(r.holdingID))
            put("kind", r.kind.rawValue)
            put("date", r.date.description)
            put("quantity", r.quantity.map(decimal))
            put("unitPrice", r.unitPrice.map(decimal))
            put("amount", r.amount.map(decimal))
            put("fee", decimal(r.fee))
            put("tax", decimal(r.tax))
            put("currency", r.currency.code)
            put("notes", r.notes)
            put("createdAt", timestamp(r.createdAt))
        case .goal(let r):
            put("portfolioID", uuid(r.portfolioID))
            put("scope", r.scope.rawValue)
            put("key", r.key)
            put("targetPercent", decimal(r.targetPercent))
            put("createdAt", timestamp(r.createdAt))
        }
        object["fields"] = fields
        // Inputs are only strings, numbers, and dictionaries, so serialization cannot fail.
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    public static func encode<R: SyncableRecord>(_ record: R) -> Data { encode(AnyRecord(record)) }

    /// Reads the envelope of a payload of any schema version.
    public static func header(_ data: Data) throws -> PayloadHeader {
        let o = try object(data)
        guard let schema = o["schemaVersion"] as? Int else { throw PayloadError.malformed("schemaVersion") }
        let r = Reader(o, path: "")
        let v = Reader(try r.object("version"), path: "version.")
        return PayloadHeader(schemaVersion: schema,
                             entity: try r.enumValue("entity"),
                             id: try r.uuid("id"),
                             version: RecordVersion(revision: try v.int64("revision"),
                                                    modifiedAt: try v.timestamp("modifiedAt"),
                                                    deviceID: try v.uuid("deviceID")),
                             deleted: try r.optionalTimestamp("deletedAt") != nil)
    }

    /// Decodes a payload, throwing `.unsupportedSchema` for versions newer than this app understands.
    public static func decode(_ data: Data) throws -> AnyRecord {
        let head = try header(data)
        guard head.schemaVersion <= schemaVersion else { throw PayloadError.unsupportedSchema(head.schemaVersion) }
        let o = try object(data)
        let deletedAt = try Reader(o, path: "").optionalTimestamp("deletedAt")
        let f = Reader(try Reader(o, path: "").object("fields"), path: "fields.")

        switch head.entity {
        case .portfolio:
            return .portfolio(PortfolioRecord(id: head.id, name: try f.string("name"),
                                              baseCurrency: try f.enumValue("baseCurrency"),
                                              createdAt: try f.timestamp("createdAt"), version: head.version,
                                              deletedAt: deletedAt))
        case .holding:
            return .holding(HoldingRecord(id: head.id, portfolioID: try f.uuid("portfolioID"), ticker: try f.string("ticker"),
                                          name: try f.optionalString("name"), sector: try f.optionalString("sector"),
                                          assetClass: try f.enumValue("assetClass"), currency: try f.enumValue("currency"),
                                          createdAt: try f.timestamp("createdAt"), version: head.version,
                                          deletedAt: deletedAt))
        case .transaction:
            return .transaction(TransactionRecord(
                id: head.id, portfolioID: try f.uuid("portfolioID"), holdingID: try f.uuid("holdingID"),
                kind: try f.enumValue("kind"), date: try f.localDate("date"),
                quantity: try f.optionalDecimal("quantity"), unitPrice: try f.optionalDecimal("unitPrice"),
                amount: try f.optionalDecimal("amount"), fee: try f.decimal("fee"), tax: try f.decimal("tax"),
                currency: try f.enumValue("currency"), notes: try f.optionalString("notes"),
                createdAt: try f.timestamp("createdAt"), version: head.version, deletedAt: deletedAt))
        case .goal:
            return .goal(GoalRecord(id: head.id, portfolioID: try f.uuid("portfolioID"), scope: try f.enumValue("scope"),
                                    key: try f.string("key"), targetPercent: try f.decimal("targetPercent"),
                                    createdAt: try f.timestamp("createdAt"), version: head.version, deletedAt: deletedAt))
        }
    }

    // MARK: - Canonical scalar formats

    static func uuid(_ id: UUID) -> String { id.uuidString.lowercased() }

    static func decimal(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }

    static func timestamp(_ date: Date) -> String {
        timestampFormatter().string(from: date.truncatedToMilliseconds)
    }

    static func timestampFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PayloadError.malformed("not a JSON object")
        }
        return o
    }

    /// Typed field access that reports the failing key path.
    private struct Reader {
        let o: [String: Any]
        let path: String

        init(_ o: [String: Any], path: String) {
            self.o = o
            self.path = path
        }

        func fail(_ key: String) -> PayloadError { .malformed(path + key) }

        func object(_ key: String) throws -> [String: Any] {
            guard let v = o[key] as? [String: Any] else { throw fail(key) }
            return v
        }

        func optionalString(_ key: String) throws -> String? {
            guard let raw = o[key] else { return nil }
            guard let s = raw as? String else { throw fail(key) }
            return s
        }

        func string(_ key: String) throws -> String {
            guard let s = try optionalString(key) else { throw fail(key) }
            return s
        }

        func int64(_ key: String) throws -> Int64 {
            guard let n = o[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { throw fail(key) }
            return n.int64Value
        }

        func uuid(_ key: String) throws -> UUID {
            guard let id = UUID(uuidString: try string(key)) else { throw fail(key) }
            return id
        }

        func enumValue<E: RawRepresentable>(_ key: String) throws -> E where E.RawValue == String {
            guard let v = E(rawValue: try string(key)) else { throw fail(key) }
            return v
        }

        func optionalTimestamp(_ key: String) throws -> Date? {
            guard let s = try optionalString(key) else { return nil }
            guard let d = PayloadCodec.timestampFormatter().date(from: s) else { throw fail(key) }
            return d
        }

        func timestamp(_ key: String) throws -> Date {
            guard let d = try optionalTimestamp(key) else { throw fail(key) }
            return d
        }

        func localDate(_ key: String) throws -> LocalDate {
            guard let d = LocalDate(string: try string(key)) else { throw fail(key) }
            return d
        }

        func optionalDecimal(_ key: String) throws -> Decimal? {
            guard let s = try optionalString(key) else { return nil }
            guard case .value(let d) = CSVParser.number(s), !s.contains(",") else { throw fail(key) }
            return d
        }

        func decimal(_ key: String) throws -> Decimal {
            guard let d = try optionalDecimal(key) else { throw fail(key) }
            return d
        }
    }
}

import Foundation
import SwiftData
import YanaDomain
import YanaSync

// SwiftData mirrors of the synchronized records, stored in `Portfolio.store`.
// Foreign keys are plain UUIDs (no `@Relationship`) so a child that syncs in before its parent is storable.
// Decimals are stored as canonical strings so values round-trip exactly.

enum PortfolioSchema {
    static let models: [any PersistentModel.Type] = [
        StoredPortfolio.self, StoredHolding.self, StoredTransaction.self, StoredGoal.self,
        StoredPendingRemotePayload.self, StoredDeviceIdentity.self, StoredSyncEngineState.self,
        StoredServerRecordMetadata.self,
    ]
}

/// Version and outbox bookkeeping shared by the four record models.
protocol StoredRecord: PersistentModel {
    var id: UUID { get }
    var revision: Int64 { get set }
    var modifiedAt: Date { get set }
    var deviceID: UUID { get set }
    var deletedAt: Date? { get set }
    var needsUpload: Bool { get set }
    var anyRecord: AnyRecord { get }
    /// Matches the row with `id`. Each model builds it on its concrete type: a `#Predicate` written in generic
    /// code reaches `id` through this protocol, which SwiftData cannot translate once the optimizer specializes it.
    static func withID(_ id: UUID) -> Predicate<Self>
}

extension StoredPortfolio {
    static func withID(_ id: UUID) -> Predicate<StoredPortfolio> { #Predicate { $0.id == id } }
}

extension StoredHolding {
    static func withID(_ id: UUID) -> Predicate<StoredHolding> { #Predicate { $0.id == id } }
}

extension StoredTransaction {
    static func withID(_ id: UUID) -> Predicate<StoredTransaction> { #Predicate { $0.id == id } }
}

extension StoredGoal {
    static func withID(_ id: UUID) -> Predicate<StoredGoal> { #Predicate { $0.id == id } }
}

extension StoredRecord {
    var version: RecordVersion {
        get { RecordVersion(revision: revision, modifiedAt: modifiedAt, deviceID: deviceID) }
        set {
            revision = newValue.revision
            modifiedAt = newValue.modifiedAt
            deviceID = newValue.deviceID
        }
    }
}

@Model
final class StoredPortfolio: StoredRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var baseCurrency: String
    var createdAt: Date
    var revision: Int64
    var modifiedAt: Date
    var deviceID: UUID
    var deletedAt: Date?
    var needsUpload: Bool = false

    init(_ r: PortfolioRecord) {
        id = r.id
        name = r.name
        baseCurrency = r.baseCurrency.rawValue
        createdAt = r.createdAt
        revision = r.version.revision
        modifiedAt = r.version.modifiedAt
        deviceID = r.version.deviceID
        deletedAt = r.deletedAt
    }

    func update(from r: PortfolioRecord) {
        name = r.name
        baseCurrency = r.baseCurrency.rawValue
        createdAt = r.createdAt
        version = r.version
        deletedAt = r.deletedAt
    }

    var record: PortfolioRecord {
        PortfolioRecord(id: id, name: name, baseCurrency: Currency(rawValue: baseCurrency) ?? .default,
                        createdAt: createdAt, version: version, deletedAt: deletedAt)
    }

    var anyRecord: AnyRecord { .portfolio(record) }
}

@Model
final class StoredHolding: StoredRecord {
    @Attribute(.unique) var id: UUID
    var portfolioID: UUID
    var ticker: String
    var name: String?
    var sector: String?
    var assetClass: String
    var currency: String
    var multiplier: String?
    var createdAt: Date
    var revision: Int64
    var modifiedAt: Date
    var deviceID: UUID
    var deletedAt: Date?
    var needsUpload: Bool = false

    init(_ r: HoldingRecord) {
        id = r.id
        portfolioID = r.portfolioID
        ticker = r.ticker
        name = r.name
        sector = r.sector
        assetClass = r.assetClass.rawValue
        currency = r.currency.rawValue
        multiplier = r.multiplier.map(StoredDecimal.string)
        createdAt = r.createdAt
        revision = r.version.revision
        modifiedAt = r.version.modifiedAt
        deviceID = r.version.deviceID
        deletedAt = r.deletedAt
    }

    func update(from r: HoldingRecord) {
        portfolioID = r.portfolioID
        ticker = r.ticker
        name = r.name
        sector = r.sector
        assetClass = r.assetClass.rawValue
        currency = r.currency.rawValue
        multiplier = r.multiplier.map(StoredDecimal.string)
        createdAt = r.createdAt
        version = r.version
        deletedAt = r.deletedAt
    }

    var record: HoldingRecord {
        HoldingRecord(id: id, portfolioID: portfolioID, ticker: ticker, name: name, sector: sector,
                      assetClass: AssetClass(rawValue: assetClass) ?? .default,
                      currency: Currency(rawValue: currency) ?? .default,
                      multiplier: multiplier.flatMap(StoredDecimal.decimal),
                      createdAt: createdAt, version: version, deletedAt: deletedAt)
    }

    var anyRecord: AnyRecord { .holding(record) }
}

@Model
final class StoredTransaction: StoredRecord {
    @Attribute(.unique) var id: UUID
    var portfolioID: UUID
    var holdingID: UUID
    var kind: String
    var date: String
    var quantity: String?
    var unitPrice: String?
    var amount: String?
    var fee: String
    var tax: String
    var currency: String
    var notes: String?
    var importSource: String?
    /// The four `opening*` fields mirror `OpeningBalance`: all set, or all nil.
    var openingAsOf: String?
    var openingCoveredFrom: String?
    var openingTargetQuantity: String?
    var openingTargetCostBasis: String?
    var createdAt: Date
    var revision: Int64
    var modifiedAt: Date
    var deviceID: UUID
    var deletedAt: Date?
    var needsUpload: Bool = false

    init(_ r: TransactionRecord) {
        id = r.id
        portfolioID = r.portfolioID
        holdingID = r.holdingID
        kind = r.kind.rawValue
        date = r.date.description
        quantity = r.quantity.map(StoredDecimal.string)
        unitPrice = r.unitPrice.map(StoredDecimal.string)
        amount = r.amount.map(StoredDecimal.string)
        fee = StoredDecimal.string(r.fee)
        tax = StoredDecimal.string(r.tax)
        currency = r.currency.rawValue
        notes = r.notes
        createdAt = r.createdAt
        revision = r.version.revision
        modifiedAt = r.version.modifiedAt
        deviceID = r.version.deviceID
        deletedAt = r.deletedAt
        setImportFields(r)
    }

    func update(from r: TransactionRecord) {
        portfolioID = r.portfolioID
        holdingID = r.holdingID
        kind = r.kind.rawValue
        date = r.date.description
        quantity = r.quantity.map(StoredDecimal.string)
        unitPrice = r.unitPrice.map(StoredDecimal.string)
        amount = r.amount.map(StoredDecimal.string)
        fee = StoredDecimal.string(r.fee)
        tax = StoredDecimal.string(r.tax)
        currency = r.currency.rawValue
        notes = r.notes
        setImportFields(r)
        createdAt = r.createdAt
        version = r.version
        deletedAt = r.deletedAt
    }

    var record: TransactionRecord {
        TransactionRecord(id: id, portfolioID: portfolioID, holdingID: holdingID,
                          kind: TransactionKind(rawValue: kind) ?? .buy,
                          date: LocalDate(string: date) ?? LocalDate(createdAt, calendar: .current),
                          quantity: quantity.flatMap(StoredDecimal.decimal),
                          unitPrice: unitPrice.flatMap(StoredDecimal.decimal),
                          amount: amount.flatMap(StoredDecimal.decimal),
                          fee: StoredDecimal.decimal(fee) ?? 0, tax: StoredDecimal.decimal(tax) ?? 0,
                          currency: Currency(rawValue: currency) ?? .default, notes: notes,
                          importSource: importSource.flatMap(ImportSource.init(rawValue:)),
                          openingBalance: openingBalance,
                          createdAt: createdAt, version: version, deletedAt: deletedAt)
    }

    private func setImportFields(_ r: TransactionRecord) {
        importSource = r.importSource?.rawValue
        openingAsOf = r.openingBalance?.asOf.description
        openingCoveredFrom = r.openingBalance?.coveredFrom.description
        openingTargetQuantity = r.openingBalance.map { StoredDecimal.string($0.targetQuantity) }
        openingTargetCostBasis = r.openingBalance.map { StoredDecimal.string($0.targetCostBasis) }
    }

    private var openingBalance: OpeningBalance? {
        guard let asOf = openingAsOf.flatMap(LocalDate.init(string:)),
              let coveredFrom = openingCoveredFrom.flatMap(LocalDate.init(string:)),
              let quantity = openingTargetQuantity.flatMap(StoredDecimal.decimal),
              let cost = openingTargetCostBasis.flatMap(StoredDecimal.decimal)
        else { return nil }
        return OpeningBalance(asOf: asOf, targetQuantity: quantity, targetCostBasis: cost, coveredFrom: coveredFrom)
    }

    var anyRecord: AnyRecord { .transaction(record) }
}

@Model
final class StoredGoal: StoredRecord {
    @Attribute(.unique) var id: UUID
    var portfolioID: UUID
    var scope: String
    var key: String
    var targetPercent: String
    var createdAt: Date
    var revision: Int64
    var modifiedAt: Date
    var deviceID: UUID
    var deletedAt: Date?
    var needsUpload: Bool = false

    init(_ r: GoalRecord) {
        id = r.id
        portfolioID = r.portfolioID
        scope = r.scope.rawValue
        key = r.key
        targetPercent = StoredDecimal.string(r.targetPercent)
        createdAt = r.createdAt
        revision = r.version.revision
        modifiedAt = r.version.modifiedAt
        deviceID = r.version.deviceID
        deletedAt = r.deletedAt
    }

    func update(from r: GoalRecord) {
        portfolioID = r.portfolioID
        scope = r.scope.rawValue
        key = r.key
        targetPercent = StoredDecimal.string(r.targetPercent)
        createdAt = r.createdAt
        version = r.version
        deletedAt = r.deletedAt
    }

    var record: GoalRecord {
        GoalRecord(id: id, portfolioID: portfolioID, scope: GoalScope(rawValue: scope) ?? .holding, key: key,
                   targetPercent: StoredDecimal.decimal(targetPercent) ?? 0,
                   createdAt: createdAt, version: version, deletedAt: deletedAt)
    }

    var anyRecord: AnyRecord { .goal(record) }
}

/// A newer-schema payload kept verbatim until the app can decode it; the record is read-only meanwhile.
@Model
final class StoredPendingRemotePayload {
    /// `RecordKey.description`, e.g. `Holding/<uuid>`.
    @Attribute(.unique) var key: String
    var pendingRemotePayload: Data

    init(key: RecordKey, payload: Data) {
        self.key = key.description
        pendingRemotePayload = payload
    }
}

/// This installation's sync device ID, created once.
@Model
final class StoredDeviceIdentity {
    @Attribute(.unique) var singleton: Int = 0
    var deviceID: UUID

    init(deviceID: UUID) {
        self.deviceID = deviceID
    }
}

/// The sync engine's serialized state. Only an optimization: `needsUpload` is the source of truth.
@Model
final class StoredSyncEngineState {
    @Attribute(.unique) var singleton: Int = 0
    var data: Data

    init(data: Data) {
        self.data = data
    }
}

/// The sync server's system fields for one record (CloudKit's archived `CKRecord` system fields), so the next
/// save is based on the server's current change tag instead of conflicting.
@Model
final class StoredServerRecordMetadata {
    /// `RecordKey.description`.
    @Attribute(.unique) var key: String
    var data: Data

    init(key: RecordKey, data: Data) {
        self.key = key.description
        self.data = data
    }
}

enum StoredDecimal {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func string(_ value: Decimal) -> String { value.description }
    static func decimal(_ string: String) -> Decimal? { Decimal(string: string, locale: posix) }
}

extension RecordKey {
    init?(storedKey: String) {
        let parts = storedKey.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let entity = RecordEntity(rawValue: parts[0]), let id = UUID(uuidString: parts[1])
        else { return nil }
        self.init(entity: entity, id: id)
    }
}

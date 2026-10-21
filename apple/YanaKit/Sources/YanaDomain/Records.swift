import Foundation

/// Fields shared by every synchronized record.
public protocol SyncableRecord: Codable, Sendable, Equatable, Identifiable where ID == UUID {
    static var entityName: String { get }
    var id: UUID { get }
    var version: RecordVersion { get set }
    /// Set when the record is a tombstone.
    var deletedAt: Date? { get set }
}

extension SyncableRecord {
    public var isDeleted: Bool { deletedAt != nil }
}

public struct PortfolioRecord: SyncableRecord {
    public static let entityName = "Portfolio"

    public var id: UUID
    public var name: String
    public var baseCurrency: Currency
    public var createdAt: Date
    public var version: RecordVersion
    public var deletedAt: Date?

    public init(id: UUID, name: String, baseCurrency: Currency = .default, createdAt: Date,
                version: RecordVersion, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.baseCurrency = baseCurrency
        self.createdAt = createdAt
        self.version = version
        self.deletedAt = deletedAt
    }
}

public struct HoldingRecord: SyncableRecord {
    public static let entityName = "Holding"

    public var id: UUID
    public var portfolioID: UUID
    /// Normalized (trimmed, upper-cased) and immutable; part of the derived `id`.
    public var ticker: String
    public var name: String?
    public var sector: String?
    public var assetClass: AssetClass
    public var currency: Currency
    /// Contract size for options (usually 100); `nil` means 1.
    public var multiplier: Decimal?
    public var createdAt: Date
    public var version: RecordVersion
    public var deletedAt: Date?

    public var effectiveMultiplier: Decimal { multiplier ?? 1 }

    public init(id: UUID, portfolioID: UUID, ticker: String, name: String? = nil, sector: String? = nil,
                assetClass: AssetClass = .default, currency: Currency, multiplier: Decimal? = nil, createdAt: Date,
                version: RecordVersion, deletedAt: Date? = nil) {
        self.id = id
        self.portfolioID = portfolioID
        self.ticker = ticker
        self.name = name
        self.sector = sector
        self.assetClass = assetClass
        self.currency = currency
        self.multiplier = multiplier
        self.createdAt = createdAt
        self.version = version
        self.deletedAt = deletedAt
    }
}

public struct TransactionRecord: SyncableRecord {
    public static let entityName = "Transaction"

    public var id: UUID
    public var portfolioID: UUID
    public var holdingID: UUID
    public var kind: TransactionKind
    public var date: LocalDate
    /// Shares traded (buy/sell), or the optional shares a dividend was paid on.
    public var quantity: Decimal?
    /// Price per share (buy/sell only).
    public var unitPrice: Decimal?
    /// Total gross cash amount (dividend/fee only).
    public var amount: Decimal?
    public var fee: Decimal
    public var tax: Decimal
    public var currency: Currency
    public var notes: String?
    /// Set on rows an import created; hand-entered rows have none.
    public var importSource: ImportSource?
    /// Present only on the importer's opening-balance buy.
    public var openingBalance: OpeningBalance?
    public var createdAt: Date
    public var version: RecordVersion
    public var deletedAt: Date?

    public init(id: UUID, portfolioID: UUID, holdingID: UUID, kind: TransactionKind, date: LocalDate,
                quantity: Decimal? = nil, unitPrice: Decimal? = nil, amount: Decimal? = nil,
                fee: Decimal = 0, tax: Decimal = 0, currency: Currency, notes: String? = nil,
                importSource: ImportSource? = nil, openingBalance: OpeningBalance? = nil,
                createdAt: Date, version: RecordVersion, deletedAt: Date? = nil) {
        self.id = id
        self.portfolioID = portfolioID
        self.holdingID = holdingID
        self.kind = kind
        self.date = date
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.amount = amount
        self.fee = fee
        self.tax = tax
        self.currency = currency
        self.notes = notes
        self.importSource = importSource
        self.openingBalance = openingBalance
        self.createdAt = createdAt
        self.version = version
        self.deletedAt = deletedAt
    }
}

/// What an opening-balance buy was computed from: the latest statement's position for the holding, and the
/// earliest imported statement start it is dated on.
public struct OpeningBalance: Codable, Equatable, Hashable, Sendable {
    public var asOf: LocalDate
    public var targetQuantity: Decimal
    public var targetCostBasis: Decimal
    public var coveredFrom: LocalDate

    public init(asOf: LocalDate, targetQuantity: Decimal, targetCostBasis: Decimal, coveredFrom: LocalDate) {
        self.asOf = asOf
        self.targetQuantity = targetQuantity
        self.targetCostBasis = targetCostBasis
        self.coveredFrom = coveredFrom
    }
}

public struct GoalRecord: SyncableRecord {
    public static let entityName = "Goal"

    public var id: UUID
    public var portfolioID: UUID
    public var scope: GoalScope
    /// Normalized ticker for `.holding`, asset-class raw value for `.assetClass`.
    public var key: String
    public var targetPercent: Decimal
    public var createdAt: Date
    public var version: RecordVersion
    public var deletedAt: Date?

    public init(id: UUID, portfolioID: UUID, scope: GoalScope, key: String, targetPercent: Decimal,
                createdAt: Date, version: RecordVersion, deletedAt: Date? = nil) {
        self.id = id
        self.portfolioID = portfolioID
        self.scope = scope
        self.key = key
        self.targetPercent = targetPercent
        self.createdAt = createdAt
        self.version = version
        self.deletedAt = deletedAt
    }
}

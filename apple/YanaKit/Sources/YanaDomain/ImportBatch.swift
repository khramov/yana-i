import Foundation

/// A holding an import needs, as the file describes it.
public struct ImportedHolding: Equatable, Sendable {
    public var ticker: String
    public var name: String?
    public var assetClass: AssetClass
    public var currency: Currency
    public var multiplier: Decimal?

    public init(ticker: String, name: String?, assetClass: AssetClass, currency: Currency, multiplier: Decimal?) {
        self.ticker = ticker
        self.name = name
        self.assetClass = assetClass
        self.currency = currency
        self.multiplier = multiplier
    }
}

/// One validated transaction from a file, before it is bound to a portfolio.
public struct ImportedRow: Equatable, Sendable {
    public var line: Int
    public var ticker: String
    public var kind: TransactionKind
    public var date: LocalDate
    public var quantity: Decimal?
    public var unitPrice: Decimal?
    public var amount: Decimal?
    public var fee: Decimal
    public var tax: Decimal
    public var currency: Currency
    public var notes: String?

    public init(line: Int, ticker: String, kind: TransactionKind, date: LocalDate, quantity: Decimal?,
                unitPrice: Decimal?, amount: Decimal?, fee: Decimal, tax: Decimal, currency: Currency, notes: String?) {
        self.line = line
        self.ticker = ticker
        self.kind = kind
        self.date = date
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.amount = amount
        self.fee = fee
        self.tax = tax
        self.currency = currency
        self.notes = notes
    }
}

/// A broker-reported position at the end of the import's range.
public struct ImportedPosition: Equatable, Sendable {
    public var ticker: String
    public var quantity: Decimal
    public var costBasis: Decimal

    public init(ticker: String, quantity: Decimal, costBasis: Decimal) {
        self.ticker = ticker
        self.quantity = quantity
        self.costBasis = costBasis
    }
}

/// Everything one file says, in a format-neutral shape. The file is authoritative for `range`.
public struct ImportBatch: Equatable, Sendable {
    public var source: ImportSource
    public var range: ClosedRange<LocalDate>
    public var holdings: [ImportedHolding]
    public var rows: [ImportedRow]
    /// Open positions at `range.upperBound`; IBKR statements only.
    public var positions: [ImportedPosition]?
    public var errors: [CSVLineError]
    public var warnings: [CSVLineError]

    public init(source: ImportSource, range: ClosedRange<LocalDate>, holdings: [ImportedHolding], rows: [ImportedRow],
                positions: [ImportedPosition]?, errors: [CSVLineError], warnings: [CSVLineError]) {
        self.source = source
        self.range = range
        self.holdings = holdings
        self.rows = rows
        self.positions = positions
        self.errors = errors
        self.warnings = warnings
    }
}

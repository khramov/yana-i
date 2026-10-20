import Foundation

/// Shares held and average cost for one holding, in the currency its buys were paid in.
public struct Position: Equatable, Sendable {
    public var holdingID: UUID
    public var ticker: String
    public var shares: Decimal
    /// Average cost per share including buy fees; `nil` once the position is closed.
    public var averageCost: Decimal?
    /// `shares × averageCost`, or 0 when closed.
    public var costBasis: Decimal
    /// Currency of the most recent buy, falling back to the holding's trading currency.
    public var costCurrency: Currency

    public var isOpen: Bool { shares > 0 }
}

public enum PositionCalculator {
    /// Order in which trades are applied: date, then creation time, then ID for full determinism.
    public static func chronological(_ a: TransactionRecord, _ b: TransactionRecord) -> Bool {
        if a.date != b.date { return a.date < b.date }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }

    /// One position per live holding. Tombstoned holdings and transactions are ignored.
    public static func positions(holdings: [HoldingRecord], transactions: [TransactionRecord]) -> [Position] {
        let byHolding = Dictionary(grouping: transactions.filter { !$0.isDeleted }, by: \.holdingID)
        return holdings.filter { !$0.isDeleted }.map { position(for: $0, transactions: byHolding[$0.id] ?? []) }
    }

    public static func position(for holding: HoldingRecord, transactions: [TransactionRecord]) -> Position {
        var shares: Decimal = 0
        var averageCost: Decimal = 0
        var currency = holding.currency

        for t in transactions.filter({ $0.holdingID == holding.id && !$0.isDeleted }).sorted(by: chronological) {
            switch t.kind {
            case .buy:
                guard let quantity = t.quantity, let price = t.unitPrice else { continue }
                currency = t.currency
                let lotCost = quantity * price + t.fee
                let newShares = shares + quantity
                averageCost = newShares > 0 ? (shares * averageCost + lotCost) / newShares : 0
                shares = newShares
            case .sell:
                guard let quantity = t.quantity else { continue }
                shares = max(0, shares - quantity)
            case .dividend, .fee:
                continue
            }
        }

        let open = shares > 0
        return Position(holdingID: holding.id, ticker: holding.ticker, shares: shares,
                        averageCost: open ? averageCost : nil,
                        costBasis: open ? shares * averageCost : 0,
                        costCurrency: currency)
    }
}

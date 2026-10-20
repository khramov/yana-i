import Foundation

public enum AllocationGrouping: String, CaseIterable, Sendable {
    case holding
    case sector
    case assetClass = "asset_class"
}

public struct AllocationSlice: Equatable, Sendable {
    public var key: String
    public var value: Decimal
    public var percent: Decimal
}

public enum AllocationCalculator {
    public static let unknownSector = "Unknown"

    /// Market value per group, largest first. Positions without a base-currency value are excluded.
    public static func slices(_ valuation: PortfolioValuation, by grouping: AllocationGrouping) -> [AllocationSlice] {
        var grouped: [String: Decimal] = [:]
        for p in valuation.positions {
            guard let value = p.marketValue else { continue }
            let key: String
            switch grouping {
            case .holding: key = p.ticker
            case .sector: key = p.holding.sector ?? unknownSector
            case .assetClass: key = p.holding.assetClass.rawValue
            }
            grouped[key, default: 0] += value
        }
        let total = grouped.values.reduce(Decimal(0), +)
        return grouped
            .map { AllocationSlice(key: $0.key, value: $0.value, percent: total > 0 ? $0.value / total * 100 : 0) }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
    }
}

public struct RebalanceRow: Equatable, Sendable {
    public var key: String
    public var name: String?
    public var currentValue: Decimal
    public var currentPercent: Decimal
    public var targetPercent: Decimal?
    /// `current − target` in percentage points; positive when overweight.
    public var driftPercent: Decimal?
    /// Base-currency amount to buy to reach the target; never negative.
    public var buyAmount: Decimal
    /// Shares that `buyAmount` buys at the current base-currency price (holding scope only).
    public var buyShares: Decimal?
}

public enum RebalanceCalculator {
    /// One row per goal key and per currently held key in `scope`, largest buy amount first.
    public static func rows(_ valuation: PortfolioValuation, goals: [GoalRecord], scope: GoalScope) -> [RebalanceRow] {
        let total = valuation.totalValue ?? 0
        let targets = Dictionary(
            goals.filter { !$0.isDeleted && $0.scope == scope }.map { ($0.key, $0.targetPercent) },
            uniquingKeysWith: { $1 })

        var current: [String: Decimal] = [:]
        var price: [String: Decimal] = [:]
        var names: [String: String] = [:]
        for p in valuation.positions {
            let key = scope == .holding ? p.ticker : p.holding.assetClass.rawValue
            current[key, default: 0] += p.marketValue ?? 0
            if scope == .holding {
                if let pb = p.priceBase { price[key] = pb }
                if let n = p.holding.name { names[key] = n }
            }
        }

        let keys = Set(targets.keys).union(current.keys)
        return keys.map { key in
            let value = current[key] ?? 0
            let pct = total > 0 ? value / total * 100 : 0
            let target = targets[key]
            let buy = target.map { max(0, $0 / 100 * total - value) } ?? 0
            let shares: Decimal? = price[key].flatMap { $0 > 0 ? buy / $0 : nil }
            return RebalanceRow(key: key, name: names[key], currentValue: value, currentPercent: pct,
                                targetPercent: target, driftPercent: target.map { pct - $0 },
                                buyAmount: buy, buyShares: shares)
        }
        .sorted { ($0.buyAmount, $0.currentValue, $1.key) > ($1.buyAmount, $1.currentValue, $0.key) }
    }
}

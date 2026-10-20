import Foundation

/// One open position valued in the portfolio's base currency.
public struct PositionValuation: Equatable, Sendable {
    public var holding: HoldingRecord
    public var position: Position
    /// Latest cached price in its quote currency.
    public var price: Decimal?
    public var priceCurrency: Currency
    public var priceFetchedAt: Date?
    /// Price converted to base; `nil` without a price or FX rate.
    public var priceBase: Decimal?
    /// `nil` without a price or FX rate; such positions are excluded from total value.
    public var marketValue: Decimal?
    /// `nil` only when the cost currency has no FX rate to base.
    public var costBasis: Decimal?
    public var unrealizedGain: Decimal?
    /// Percentage, e.g. 12.5 for +12.5%.
    public var returnPercent: Decimal?

    public var ticker: String { holding.ticker }
}

public struct TopPosition: Equatable, Sendable {
    public var ticker: String
    public var name: String?
    public var marketValue: Decimal
    public var weightPercent: Decimal?
    public var returnPercent: Decimal?
}

/// Dashboard summary for one portfolio.
public struct PortfolioValuation: Equatable, Sendable {
    public var baseCurrency: Currency
    public var positions: [PositionValuation]
    /// Sum of available market values; `nil` when no open position could be valued.
    public var totalValue: Decimal?
    /// Sum of convertible cost bases (includes unpriced positions).
    public var costBasis: Decimal
    public var unrealizedGain: Decimal?
    public var returnPercent: Decimal?
    /// Dividends received to date, gross, converted to base. Dividends without an FX rate are skipped.
    public var dividendsReceived: Decimal
    public var holdingsCount: Int
    public var top5: [TopPosition]
    /// Tickers whose value could not be computed (no price, or no FX rate).
    public var unavailableTickers: [String]
    /// Currency pairs needed but never fetched.
    public var missingRates: [CurrencyPair]
    /// Oldest quote fetch time among open positions.
    public var pricesFetchedAt: Date?

    public init(portfolio: PortfolioRecord, holdings: [HoldingRecord], transactions: [TransactionRecord],
                market: MarketSnapshot) {
        let base = portfolio.baseCurrency
        let liveHoldings = holdings.filter { !$0.isDeleted && $0.portfolioID == portfolio.id }
        let liveTransactions = transactions.filter { !$0.isDeleted && $0.portfolioID == portfolio.id }
        let positions = PositionCalculator.positions(holdings: liveHoldings, transactions: liveTransactions)
        let holdingByID = Dictionary(uniqueKeysWithValues: liveHoldings.map { ($0.id, $0) })

        var missing = Set<CurrencyPair>()
        func rate(_ from: Currency) -> Decimal? {
            let r = market.rate(from: from, to: base)
            if r == nil { missing.insert(CurrencyPair(from, base)) }
            return r
        }

        var valued: [PositionValuation] = []
        for p in positions where p.isOpen {
            guard let h = holdingByID[p.holdingID] else { continue }
            let quote = market.quotes[h.ticker]
            let priceCurrency = quote?.currency ?? h.currency
            let priceRate = quote == nil ? nil : rate(priceCurrency)
            let priceBase = quote.flatMap { q in priceRate.map { q.price * $0 } }
            let marketValue = priceBase.map { p.shares * $0 }
            let costBasis = rate(p.costCurrency).map { p.costBasis * $0 }
            let gain = marketValue.flatMap { mv in costBasis.map { mv - $0 } }
            let ret = gain.flatMap { g in costBasis.flatMap { $0 > 0 ? g / $0 * 100 : nil } }
            valued.append(PositionValuation(holding: h, position: p, price: quote?.price, priceCurrency: priceCurrency,
                                            priceFetchedAt: quote?.fetchedAt, priceBase: priceBase,
                                            marketValue: marketValue, costBasis: costBasis,
                                            unrealizedGain: gain, returnPercent: ret))
        }

        let total: Decimal? = valued.contains { $0.marketValue != nil }
            ? valued.reduce(Decimal(0)) { $0 + ($1.marketValue ?? 0) } : nil
        let cost = valued.reduce(Decimal(0)) { $0 + ($1.costBasis ?? 0) }
        let gain = total.map { $0 - cost }

        var dividends: Decimal = 0
        for t in liveTransactions where t.kind == .dividend {
            if let amount = t.amount, let converted = rate(t.currency).map({ amount * $0 }) { dividends += converted }
        }

        self.baseCurrency = base
        self.positions = valued
        self.totalValue = total
        self.costBasis = cost
        self.unrealizedGain = gain
        self.returnPercent = gain.flatMap { cost > 0 ? $0 / cost * 100 : nil }
        self.dividendsReceived = dividends
        self.holdingsCount = valued.count
        self.top5 = valued
            .filter { $0.marketValue != nil }
            .sorted { ($0.marketValue!, $1.ticker) > ($1.marketValue!, $0.ticker) }
            .prefix(5)
            .map { v in
                TopPosition(ticker: v.ticker, name: v.holding.name, marketValue: v.marketValue!,
                            weightPercent: total.flatMap { $0 > 0 ? v.marketValue! / $0 * 100 : nil },
                            returnPercent: v.returnPercent)
            }
        self.unavailableTickers = valued.filter { $0.marketValue == nil }.map(\.ticker).sorted()
        self.missingRates = missing.sorted { $0.description < $1.description }
        self.pricesFetchedAt = market.oldestQuoteFetch(for: valued.map(\.ticker))
    }
}

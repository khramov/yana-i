import Foundation

public struct DividendRow: Equatable, Sendable {
    public var transactionID: UUID
    public var date: LocalDate
    public var ticker: String
    /// Gross amount in `currency`.
    public var gross: Decimal
    public var currency: Currency
    /// Gross converted to base; `nil` without an FX rate.
    public var grossBase: Decimal?
    public var shares: Decimal?
    public var perShare: Decimal?
    public var tax: Decimal
    /// Per-share amount ÷ the holding's current average cost, as a percentage.
    public var yieldOnCost: Decimal?
}

public struct UpcomingDividend: Equatable, Sendable {
    public var ticker: String
    public var name: String?
    public var exDividendDate: LocalDate?
    public var paymentDate: LocalDate?
    public var amountPerShare: Decimal?
    public var frequency: DividendFrequency
    public var shares: Decimal
    /// Shares held × amount per share, in `currency`.
    public var estimatedIncome: Decimal?
    public var currency: Currency
    public var estimatedIncomeBase: Decimal?
    public var fetchedAt: Date
}

public struct DividendAnalytics: Equatable, Sendable {
    public var baseCurrency: Currency
    /// Newest first, filtered to `year` when one was given.
    public var rows: [DividendRow]
    /// Years with dividends, newest first (unfiltered).
    public var years: [Int]
    public var totalAllTime: Decimal
    public var trailingTwelveMonths: Decimal
    /// All-time dividends ÷ current base-currency cost basis, as a percentage.
    public var portfolioYieldOnCost: Decimal?
    /// Cached events for open positions with an ex-dividend or payment date today or later, soonest first.
    public var upcoming: [UpcomingDividend]

    public init(portfolio: PortfolioRecord, holdings: [HoldingRecord], transactions: [TransactionRecord],
                market: MarketSnapshot, clock: CalculationClock, year: Int? = nil) {
        let base = portfolio.baseCurrency
        let valuation = PortfolioValuation(portfolio: portfolio, holdings: holdings, transactions: transactions, market: market)
        let liveHoldings = holdings.filter { !$0.isDeleted && $0.portfolioID == portfolio.id }
        let liveTxns = transactions.filter { !$0.isDeleted && $0.portfolioID == portfolio.id }
        let holdingByID = Dictionary(uniqueKeysWithValues: liveHoldings.map { ($0.id, $0) })
        let positions = Dictionary(uniqueKeysWithValues: PositionCalculator
            .positions(holdings: liveHoldings, transactions: liveTxns).map { ($0.holdingID, $0) })
        let cutoff = clock.trailingTwelveMonthsStart
        let today = clock.today

        var all: [DividendRow] = []
        var total: Decimal = 0
        var trailing: Decimal = 0
        for t in liveTxns.filter({ $0.kind == .dividend }).sorted(by: PositionCalculator.chronological) {
            guard let h = holdingByID[t.holdingID], let gross = t.amount else { continue }
            let grossBase = market.convert(gross, from: t.currency, to: base)
            let perShare: Decimal? = t.quantity.flatMap { $0 > 0 ? gross / $0 : nil }
            var yieldOnCost: Decimal?
            if let perShare, let p = positions[h.id], let avg = p.averageCost, avg > 0,
               let perShareInCost = market.convert(perShare, from: t.currency, to: p.costCurrency) {
                yieldOnCost = perShareInCost / avg * 100
            }
            if let grossBase {
                total += grossBase
                if t.date >= cutoff { trailing += grossBase }
            }
            all.append(DividendRow(transactionID: t.id, date: t.date, ticker: h.ticker, gross: gross, currency: t.currency,
                                   grossBase: grossBase, shares: t.quantity, perShare: perShare, tax: t.tax,
                                   yieldOnCost: yieldOnCost))
        }

        var upcoming: [UpcomingDividend] = []
        for v in valuation.positions {
            guard let e = market.dividendEvents[v.ticker] else { continue }
            let isAhead = [e.exDividendDate, e.paymentDate].contains { $0.map { $0 >= today } ?? false }
            guard isAhead else { continue }
            let estimate = e.amountPerShare.map { v.position.shares * $0 }
            upcoming.append(UpcomingDividend(ticker: v.ticker, name: v.holding.name, exDividendDate: e.exDividendDate,
                                             paymentDate: e.paymentDate, amountPerShare: e.amountPerShare,
                                             frequency: e.frequency, shares: v.position.shares, estimatedIncome: estimate,
                                             currency: e.currency,
                                             estimatedIncomeBase: estimate.flatMap { market.convert($0, from: e.currency, to: base) },
                                             fetchedAt: e.fetchedAt))
        }

        self.baseCurrency = base
        self.rows = all.reversed().filter { year == nil || $0.date.year == year }
        self.years = Set(all.map(\.date.year)).sorted(by: >)
        self.totalAllTime = total
        self.trailingTwelveMonths = trailing
        self.portfolioYieldOnCost = valuation.costBasis > 0 ? total / valuation.costBasis * 100 : nil
        self.upcoming = upcoming.sorted {
            (($0.exDividendDate ?? $0.paymentDate)!, $0.ticker) < (($1.exDividendDate ?? $1.paymentDate)!, $1.ticker)
        }
    }
}

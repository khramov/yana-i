import Foundation

/// "Now" plus the calendar that turns it into a local day; injected so results are reproducible.
public struct CalculationClock: Sendable {
    public var now: Date
    public var calendar: Calendar

    public init(now: Date, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
    }

    public static var current: CalculationClock { CalculationClock(now: Date(), calendar: .current) }

    public var today: LocalDate { LocalDate(now, calendar: calendar) }

    /// First day included in "trailing 12 months": the same day one year ago.
    public var trailingTwelveMonthsStart: LocalDate { today.adding(months: -12, calendar: calendar) }
}

public struct MonthlyIncome: Equatable, Sendable {
    public var year: Int
    public var month: Int
    public var amount: Decimal
}

public struct HoldingIncome: Equatable, Sendable {
    public var ticker: String
    public var name: String?
    public var trailingTwelveMonths: Decimal
    /// `nil` when no annual rate is cached for the holding (or its FX rate is missing).
    public var forwardAnnual: Decimal?
}

public struct IncomeSummary: Equatable, Sendable {
    public var baseCurrency: Currency
    /// Gross dividends per calendar month in base currency, oldest first.
    public var monthly: [MonthlyIncome]
    public var trailingTwelveMonths: Decimal
    /// Shares held × annual dividend rate, summed; `nil` when no open position has a cached rate.
    public var forwardAnnual: Decimal?
    public var byHolding: [HoldingIncome]
    /// Latest dividend-event fetch among open positions.
    public var lastRefreshed: Date?
    public var missingRates: [CurrencyPair]
}

public enum IncomeCalculator {
    public static func summary(portfolio: PortfolioRecord, holdings: [HoldingRecord], transactions: [TransactionRecord],
                               market: MarketSnapshot, clock: CalculationClock) -> IncomeSummary {
        let base = portfolio.baseCurrency
        let liveHoldings = holdings.filter { !$0.isDeleted && $0.portfolioID == portfolio.id }
        let liveTxns = transactions.filter { !$0.isDeleted && $0.portfolioID == portfolio.id }
        let holdingByID = Dictionary(uniqueKeysWithValues: liveHoldings.map { ($0.id, $0) })
        let cutoff = clock.trailingTwelveMonthsStart

        var missing = Set<CurrencyPair>()
        func toBase(_ amount: Decimal, _ from: Currency) -> Decimal? {
            let converted = market.convert(amount, from: from, to: base)
            if converted == nil { missing.insert(CurrencyPair(from, base)) }
            return converted
        }

        var monthly: [String: MonthlyIncome] = [:]
        var trailingTotal: Decimal = 0
        var trailingByTicker: [String: Decimal] = [:]
        for t in liveTxns where t.kind == .dividend {
            guard let h = holdingByID[t.holdingID], let amount = t.amount, let value = toBase(amount, t.currency)
            else { continue }
            let key = String(t.date.description.prefix(7))
            monthly[key, default: MonthlyIncome(year: t.date.year, month: t.date.month, amount: 0)].amount += value
            if t.date >= cutoff {
                trailingTotal += value
                trailingByTicker[h.ticker, default: 0] += value
            }
        }

        var forwardTotal: Decimal?
        var forwardByTicker: [String: Decimal] = [:]
        var lastRefreshed: Date?
        let positions = PositionCalculator.positions(holdings: liveHoldings, transactions: liveTxns).filter(\.isOpen)
        for p in positions {
            guard let h = holdingByID[p.holdingID], let event = market.dividendEvents[h.ticker] else { continue }
            lastRefreshed = max(lastRefreshed ?? event.fetchedAt, event.fetchedAt)
            guard let rate = event.annualRate, rate > 0, let annual = toBase(p.shares * rate, event.currency)
            else { continue }
            forwardByTicker[h.ticker] = annual
            forwardTotal = (forwardTotal ?? 0) + annual
        }

        let names = Dictionary(liveHoldings.map { ($0.ticker, $0.name) }, uniquingKeysWith: { $1 })
        let byHolding = Set(trailingByTicker.keys).union(forwardByTicker.keys)
            .map { HoldingIncome(ticker: $0, name: names[$0] ?? nil, trailingTwelveMonths: trailingByTicker[$0] ?? 0,
                                 forwardAnnual: forwardByTicker[$0]) }
            .filter { $0.trailingTwelveMonths > 0 || ($0.forwardAnnual ?? 0) > 0 }
            .sorted { ($0.trailingTwelveMonths, $0.forwardAnnual ?? 0, $1.ticker) > ($1.trailingTwelveMonths, $1.forwardAnnual ?? 0, $0.ticker) }

        return IncomeSummary(baseCurrency: base,
                             monthly: monthly.values.sorted { ($0.year, $0.month) < ($1.year, $1.month) },
                             trailingTwelveMonths: trailingTotal, forwardAnnual: forwardTotal, byHolding: byHolding,
                             lastRefreshed: lastRefreshed,
                             missingRates: missing.sorted { $0.description < $1.description })
    }
}

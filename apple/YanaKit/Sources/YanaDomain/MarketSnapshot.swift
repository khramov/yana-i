import Foundation

public struct Quote: Codable, Equatable, Sendable {
    public var ticker: String
    public var price: Decimal
    public var currency: Currency
    public var fetchedAt: Date

    public init(ticker: String, price: Decimal, currency: Currency, fetchedAt: Date) {
        self.ticker = ticker
        self.price = price
        self.currency = currency
        self.fetchedAt = fetchedAt
    }
}

public struct CurrencyPair: Codable, Hashable, Sendable, CustomStringConvertible {
    public var from: Currency
    public var to: Currency

    public init(_ from: Currency, _ to: Currency) {
        self.from = from
        self.to = to
    }

    public var description: String { "\(from.code)\(to.code)" }
}

public struct FXRate: Codable, Equatable, Sendable {
    public var pair: CurrencyPair
    public var rate: Decimal
    public var fetchedAt: Date

    public init(pair: CurrencyPair, rate: Decimal, fetchedAt: Date) {
        self.pair = pair
        self.rate = rate
        self.fetchedAt = fetchedAt
    }
}

public enum DividendFrequency: String, Codable, Sendable, CaseIterable {
    case annual
    case semiAnnual = "semi-annual"
    case quarterly
    case monthly
    case unknown

    /// Ported from the web app's `detectFrequency`: payments per year ≈ annual rate ÷ last amount.
    public static func detect(annualRate: Decimal?, lastAmount: Decimal?) -> DividendFrequency {
        guard let annualRate, let lastAmount, annualRate > 0, lastAmount > 0 else { return .unknown }
        let ratio = annualRate / lastAmount
        if ratio < Decimal(string: "1.5")! { return .annual }
        if ratio < 3 { return .semiAnnual }
        if ratio < 6 { return .quarterly }
        return .monthly
    }
}

/// Cached dividend data for one ticker.
public struct DividendEvent: Codable, Equatable, Sendable {
    public var ticker: String
    public var exDividendDate: LocalDate?
    public var paymentDate: LocalDate?
    public var amountPerShare: Decimal?
    public var annualRate: Decimal?
    public var frequency: DividendFrequency
    /// Currency the amounts are paid in.
    public var currency: Currency
    public var fetchedAt: Date

    public init(ticker: String, exDividendDate: LocalDate? = nil, paymentDate: LocalDate? = nil,
                amountPerShare: Decimal? = nil, annualRate: Decimal? = nil, frequency: DividendFrequency = .unknown,
                currency: Currency, fetchedAt: Date) {
        self.ticker = ticker
        self.exDividendDate = exDividendDate
        self.paymentDate = paymentDate
        self.amountPerShare = amountPerShare
        self.annualRate = annualRate
        self.frequency = frequency
        self.currency = currency
        self.fetchedAt = fetchedAt
    }
}

/// The cached market data a calculation runs against. Calculations never fetch.
public struct MarketSnapshot: Equatable, Sendable {
    public var quotes: [String: Quote]
    public var fxRates: [CurrencyPair: FXRate]
    public var dividendEvents: [String: DividendEvent]

    public init(quotes: [Quote] = [], fxRates: [FXRate] = [], dividendEvents: [DividendEvent] = []) {
        self.quotes = Dictionary(quotes.map { ($0.ticker, $0) }, uniquingKeysWith: { $1 })
        self.fxRates = Dictionary(fxRates.map { ($0.pair, $0) }, uniquingKeysWith: { $1 })
        self.dividendEvents = Dictionary(dividendEvents.map { ($0.ticker, $0) }, uniquingKeysWith: { $1 })
    }

    public static let empty = MarketSnapshot()

    /// 1 for the same currency, the cached rate otherwise, or `nil` when none was ever fetched.
    public func rate(from: Currency, to: Currency) -> Decimal? {
        if from == to { return 1 }
        return fxRates[CurrencyPair(from, to)]?.rate
    }

    public func convert(_ amount: Decimal, from: Currency, to: Currency) -> Decimal? {
        rate(from: from, to: to).map { amount * $0 }
    }

    /// Oldest fetch time among the quotes for `tickers`, for "prices as of" display.
    public func oldestQuoteFetch(for tickers: [String]) -> Date? {
        tickers.compactMap { quotes[$0]?.fetchedAt }.min()
    }
}

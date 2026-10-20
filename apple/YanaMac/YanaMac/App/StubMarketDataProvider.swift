import Foundation
import YanaDomain
import YanaMarketData

/// Fixed market data for UI tests and previews (`-YanaStubMarketData YES`). Knows a few symbols, reports any
/// other as not found, and fails everything with `.offline` when asked to.
struct StubMarketDataProvider: MarketDataProvider {
    let id = "stub"
    let displayName = "Sample data"
    let isUnofficial = false
    let requiresCredential = false
    var offline = false
    var now: @Sendable () -> Date = { Date() }

    struct Security {
        var name: String
        var currency: Currency
        var assetClass: AssetClass
        var sector: String?
        var price: Decimal
        var annualDividend: Decimal?
    }

    static let securities: [String: Security] = [
        "AAPL": Security(name: "Apple Inc.", currency: .usd, assetClass: .stock, sector: "Technology", price: 200,
                         annualDividend: 1),
        "MSFT": Security(name: "Microsoft Corporation", currency: .usd, assetClass: .stock, sector: "Technology",
                         price: 400, annualDividend: 3),
        "VTI": Security(name: "Vanguard Total Stock Market ETF", currency: .usd, assetClass: .etf, sector: nil, price: 250,
                        annualDividend: Decimal(string: "3.6")),
        "KO": Security(name: "Coca-Cola Company", currency: .usd, assetClass: .stock, sector: "Consumer Defensive",
                       price: 60, annualDividend: Decimal(string: "1.94")),
        "SAP.DE": Security(name: "SAP SE", currency: .eur, assetClass: .stock, sector: "Technology", price: 180,
                           annualDividend: Decimal(string: "2.2")),
    ]

    static let rates: [CurrencyPair: Decimal] = [
        CurrencyPair(.usd, .eur): Decimal(string: "0.9")!, CurrencyPair(.eur, .usd): Decimal(string: "1.1")!,
        CurrencyPair(.rub, .eur): Decimal(string: "0.01")!, CurrencyPair(.eur, .rub): 100,
        CurrencyPair(.usd, .rub): 90, CurrencyPair(.rub, .usd): Decimal(string: "0.011")!,
    ]

    private func lookup<T>(_ keys: [String], _ make: (String, Security) -> T) -> [String: Result<T, MarketDataError>] {
        Dictionary(uniqueKeysWithValues: keys.map { key in
            if offline { return (key, .failure(.offline)) }
            guard let s = Self.securities[key] else { return (key, .failure(.notFound)) }
            return (key, .success(make(key, s)))
        })
    }

    func quotes(for tickers: [String]) async -> [String: Result<Quote, MarketDataError>] {
        lookup(tickers) { Quote(ticker: $0, price: $1.price, currency: $1.currency, fetchedAt: now()) }
    }

    func securityDetails(for tickers: [String]) async -> [String: Result<SecurityDetails, MarketDataError>] {
        lookup(tickers) { SecurityDetails(ticker: $0, name: $1.name, currency: $1.currency, assetClass: $1.assetClass,
                                          sector: $1.sector) }
    }

    func fxRates(for pairs: [CurrencyPair]) async -> [CurrencyPair: Result<FXRate, MarketDataError>] {
        Dictionary(uniqueKeysWithValues: pairs.map { pair in
            if offline { return (pair, .failure(.offline)) }
            let rate = pair.from == pair.to ? 1 : Self.rates[pair]
            return (pair, rate.map { .success(FXRate(pair: pair, rate: $0, fetchedAt: now())) } ?? .failure(.notFound))
        })
    }

    func dividendEvents(for tickers: [String]) async -> [String: Result<DividendEvent, MarketDataError>] {
        let today = LocalDate(now(), calendar: .current)
        return lookup(tickers) { ticker, s in
            let perPayment = s.annualDividend.map { $0 / 4 }
            return DividendEvent(ticker: ticker, exDividendDate: today.adding(months: 1, calendar: .current),
                                 paymentDate: today.adding(months: 2, calendar: .current), amountPerShare: perPayment,
                                 annualRate: s.annualDividend,
                                 frequency: .detect(annualRate: s.annualDividend, lastAmount: perPayment),
                                 currency: s.currency, fetchedAt: now())
        }
    }
}

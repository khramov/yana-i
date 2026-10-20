import Foundation
import YanaDomain

/// Local, never-synchronized storage for fetched market data (`MarketCache.store` in the app).
public protocol MarketDataCache: Sendable {
    func quotes(for tickers: [String]) async throws -> [String: Quote]
    func save(quotes: [Quote]) async throws
    func fxRates(for pairs: [CurrencyPair]) async throws -> [CurrencyPair: FXRate]
    func save(fxRates: [FXRate]) async throws
    func dividendEvents(for tickers: [String]) async throws -> [String: DividendEvent]
    func save(dividendEvents: [DividendEvent]) async throws
}

/// A `MarketDataCache` held in memory, for tests and previews.
public actor InMemoryMarketDataCache: MarketDataCache {
    public private(set) var quoteStore: [String: Quote] = [:]
    public private(set) var fxStore: [CurrencyPair: FXRate] = [:]
    public private(set) var eventStore: [String: DividendEvent] = [:]

    public init(quotes: [Quote] = [], fxRates: [FXRate] = [], dividendEvents: [DividendEvent] = []) {
        for q in quotes { quoteStore[q.ticker] = q }
        for r in fxRates { fxStore[r.pair] = r }
        for e in dividendEvents { eventStore[e.ticker] = e }
    }

    public func quotes(for tickers: [String]) -> [String: Quote] { quoteStore.filter { tickers.contains($0.key) } }
    public func save(quotes: [Quote]) { for q in quotes { quoteStore[q.ticker] = q } }
    public func fxRates(for pairs: [CurrencyPair]) -> [CurrencyPair: FXRate] { fxStore.filter { pairs.contains($0.key) } }
    public func save(fxRates: [FXRate]) { for r in fxRates { fxStore[r.pair] = r } }
    public func dividendEvents(for tickers: [String]) -> [String: DividendEvent] { eventStore.filter { tickers.contains($0.key) } }
    public func save(dividendEvents: [DividendEvent]) { for e in dividendEvents { eventStore[e.ticker] = e } }
}

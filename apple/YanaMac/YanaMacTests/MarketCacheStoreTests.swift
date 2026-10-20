import Foundation
import SwiftData
import Testing
import YanaDomain
import YanaMarketData
@testable import YanaMac

private let t0 = Date(timeIntervalSince1970: 1_729_300_000)

private func makeCache() throws -> MarketCacheStore {
    MarketCacheStore(modelContainer: try MarketCacheStore.makeContainer(inMemory: true))
}

private func snapshot(_ portfolioID: UUID, _ day: String, value: Decimal, at: Date = t0) -> ValueSnapshot {
    ValueSnapshot(portfolioID: portfolioID, day: LocalDate(string: day)!, totalValue: value, costBasis: 1000,
                  baseCurrency: .eur, recordedAt: at)
}

@Suite struct MarketCacheStoreTests {
    @Test func cachedValuesRoundTripAndReplace() async throws {
        let cache = try makeCache()
        let aapl = Quote(ticker: "AAPL", price: Decimal(string: "235.123456")!, currency: .usd, fetchedAt: t0)
        let usdEur = FXRate(pair: CurrencyPair(.usd, .eur), rate: Decimal(string: "0.9213")!, fetchedAt: t0)
        let ko = DividendEvent(ticker: "KO", exDividendDate: LocalDate(string: "2024-11-29"), paymentDate: nil,
                               amountPerShare: Decimal(string: "0.485"), annualRate: Decimal(string: "1.94"),
                               frequency: .quarterly, currency: .usd, fetchedAt: t0)
        try await cache.save(quotes: [aapl])
        try await cache.save(fxRates: [usdEur])
        try await cache.save(dividendEvents: [ko])

        #expect(try await cache.quotes(for: ["AAPL", "MSFT"]) == ["AAPL": aapl])
        #expect(try await cache.fxRates(for: [CurrencyPair(.usd, .eur), CurrencyPair(.rub, .eur)]) == [usdEur.pair: usdEur])
        #expect(try await cache.dividendEvents(for: ["KO"]) == ["KO": ko])

        var newer = aapl
        newer.price = 240
        newer.fetchedAt = t0.addingTimeInterval(900)
        try await cache.save(quotes: [newer])
        #expect(try await cache.quotes(for: ["AAPL"]) == ["AAPL": newer])
    }

    @Test func serviceRunsOnTheSwiftDataCache() async throws {
        let cache = try makeCache()
        try await cache.save(quotes: [Quote(ticker: "VTI", price: 280, currency: .usd, fetchedAt: t0)])
        let service = MarketDataService(provider: SilentProvider(), cache: cache, now: { t0.addingTimeInterval(60) })
        _ = await service.refresh(tickers: ["VTI"], currencies: [.usd], base: .usd)
        let snapshot = try await service.snapshot(tickers: ["VTI"], currencies: [.usd], base: .usd)
        #expect(snapshot.quotes["VTI"]?.price == 280)
    }

    @Test func oneSnapshotPerPortfolioPerDay() async throws {
        let cache = try makeCache()
        let p = UUID(), q = UUID()
        try await cache.record(snapshot(p, "2024-10-19", value: 1500))
        try await cache.record(snapshot(p, "2024-10-19", value: 1600, at: t0.addingTimeInterval(3600)))
        try await cache.record(snapshot(q, "2024-10-19", value: 10))
        try await cache.record(snapshot(p, "2024-10-20", value: 1700))

        let history = try await cache.snapshots(for: p)
        #expect(history.map(\.day.description) == ["2024-10-19", "2024-10-20"])
        #expect(history[0].totalValue == 1600 && history[0].recordedAt == t0.addingTimeInterval(3600))
        #expect(try await cache.snapshots(for: q).count == 1)
    }

    @Test func snapshotRangeIsInclusive() async throws {
        let cache = try makeCache()
        let p = UUID()
        for day in ["2024-06-30", "2024-07-01", "2024-08-15", "2024-10-01", "2024-10-02"] {
            try await cache.record(snapshot(p, day, value: 1))
        }
        let range = try await cache.snapshots(for: p, from: LocalDate(string: "2024-07-01"), to: LocalDate(string: "2024-10-01"))
        #expect(range.map(\.day.description) == ["2024-07-01", "2024-08-15", "2024-10-01"])
    }

    @Test func cacheCanBeDeletedAndRebuiltWithoutTouchingPortfolios() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "yana-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let portfolioContainer = try PortfolioStore.makeContainer(directory: directory)
        let repo = try await PortfolioRepository.make(container: portfolioContainer)
        let p = try await repo.createPortfolio(PortfolioDraft(name: "Kept"))
        try await repo.addHolding(HoldingDraft(ticker: "AAPL", currency: .usd), to: p.id)

        do {
            let cache = MarketCacheStore(modelContainer: try MarketCacheStore.makeContainer(directory: directory))
            try await cache.save(quotes: [Quote(ticker: "AAPL", price: 1, currency: .usd, fetchedAt: t0)])
            try await cache.record(snapshot(p.id, "2024-10-19", value: 1))
        }
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: MarketCacheStore.fileName).path))

        try MarketCacheStore.deleteStoreFiles(in: directory)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: MarketCacheStore.fileName).path))

        let rebuilt = MarketCacheStore(modelContainer: try MarketCacheStore.makeContainer(directory: directory))
        #expect(try await rebuilt.quotes(for: ["AAPL"]).isEmpty)
        #expect(try await rebuilt.snapshots(for: p.id).isEmpty)
        try await rebuilt.save(quotes: [Quote(ticker: "AAPL", price: 2, currency: .usd, fetchedAt: t0)])
        #expect(try await rebuilt.quotes(for: ["AAPL"])["AAPL"]?.price == 2)

        // Portfolio.store, reopened from disk, still has everything.
        let reopened = PortfolioStore(modelContainer: try PortfolioStore.makeContainer(directory: directory))
        #expect(try await reopened.portfolios().map(\.name) == ["Kept"])
        #expect(try await reopened.holdings(inPortfolio: p.id).map(\.ticker) == ["AAPL"])
    }

    @Test func removeAllEmptiesTheCacheInPlace() async throws {
        let cache = try makeCache()
        try await cache.save(quotes: [Quote(ticker: "AAPL", price: 1, currency: .usd, fetchedAt: t0)])
        try await cache.record(snapshot(UUID(), "2024-10-19", value: 1))
        try await cache.removeAll()
        #expect(try await cache.quotes(for: ["AAPL"]).isEmpty)
    }
}

/// A provider that is never reached because the cache is fresh.
private struct SilentProvider: MarketDataProvider {
    let id = "silent"
    let displayName = "Silent"
    let isUnofficial = false
    let requiresCredential = false

    func quotes(for tickers: [String]) async -> [String: Result<Quote, MarketDataError>] {
        Issue.record("unexpected quote fetch")
        return [:]
    }
    func securityDetails(for tickers: [String]) async -> [String: Result<SecurityDetails, MarketDataError>] { [:] }
    func fxRates(for pairs: [CurrencyPair]) async -> [CurrencyPair: Result<FXRate, MarketDataError>] { [:] }
    func dividendEvents(for tickers: [String]) async -> [String: Result<DividendEvent, MarketDataError>] { [:] }
}

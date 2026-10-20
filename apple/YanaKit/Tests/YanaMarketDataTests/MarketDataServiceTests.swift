import Foundation
import Testing
import YanaDomain
@testable import YanaMarketData

let t0 = Date(timeIntervalSince1970: 1_700_000_000)

final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
}

/// Scriptable provider that counts calls and can delay, fail, or rate-limit per symbol.
actor StubProvider: MarketDataProvider {
    nonisolated let id = "stub"
    nonisolated let displayName = "Stub"
    nonisolated let isUnofficial = false
    nonisolated let requiresCredential = false

    var calls: [String] = []
    var maxConcurrent = 0
    private var current = 0
    var prices: [String: Decimal] = [:]
    var failing: [String: MarketDataError] = [:]
    /// Errors returned for the first N calls of a symbol before succeeding.
    var scriptedErrors: [String: [MarketDataError]] = [:]
    var delayNanos: UInt64 = 0
    let clock: MutableClock

    init(clock: MutableClock) { self.clock = clock }

    func set(price: Decimal, for t: String) { prices[t] = price }
    func fail(_ t: String, with e: MarketDataError) { failing[t] = e }
    func script(_ t: String, _ errors: [MarketDataError]) { scriptedErrors[t] = errors }
    func setDelay(_ n: UInt64) { delayNanos = n }

    private func answer(_ key: String) async -> MarketDataError? {
        calls.append(key)
        current += 1
        maxConcurrent = max(maxConcurrent, current)
        if delayNanos > 0 { try? await Task.sleep(nanoseconds: delayNanos) }
        current -= 1
        if var script = scriptedErrors[key], !script.isEmpty {
            let e = script.removeFirst()
            scriptedErrors[key] = script
            return e
        }
        return failing[key]
    }

    func quotes(for tickers: [String]) async -> [String: Result<Quote, MarketDataError>] {
        var out: [String: Result<Quote, MarketDataError>] = [:]
        for t in tickers {
            if let e = await answer(t) { out[t] = .failure(e); continue }
            out[t] = .success(Quote(ticker: t, price: prices[t] ?? 1, currency: .usd, fetchedAt: clock.now))
        }
        return out
    }

    func securityDetails(for tickers: [String]) async -> [String: Result<SecurityDetails, MarketDataError>] {
        var out: [String: Result<SecurityDetails, MarketDataError>] = [:]
        for t in tickers {
            if let e = await answer(t) { out[t] = .failure(e); continue }
            out[t] = .success(SecurityDetails(ticker: t, name: t, currency: .usd, assetClass: .stock, sector: nil))
        }
        return out
    }

    func fxRates(for pairs: [CurrencyPair]) async -> [CurrencyPair: Result<FXRate, MarketDataError>] {
        var out: [CurrencyPair: Result<FXRate, MarketDataError>] = [:]
        for p in pairs {
            if let e = await answer(p.description) { out[p] = .failure(e); continue }
            out[p] = .success(FXRate(pair: p, rate: Decimal(string: "0.9")!, fetchedAt: clock.now))
        }
        return out
    }

    func dividendEvents(for tickers: [String]) async -> [String: Result<DividendEvent, MarketDataError>] {
        var out: [String: Result<DividendEvent, MarketDataError>] = [:]
        for t in tickers {
            if let e = await answer("div:" + t) { out[t] = .failure(e); continue }
            out[t] = .success(DividendEvent(ticker: t, currency: .usd, fetchedAt: clock.now))
        }
        return out
    }
}

actor SleepRecorder {
    var delays: [TimeInterval] = []
    func record(_ d: TimeInterval) { delays.append(d) }
}

@Suite struct MarketDataServiceTests {
    let clock = MutableClock(t0)

    func makeService(_ provider: StubProvider, cache: InMemoryMarketDataCache = InMemoryMarketDataCache(),
                     sleeps: SleepRecorder = SleepRecorder()) -> MarketDataService {
        MarketDataService(provider: provider, cache: cache, now: { [clock] in clock.now },
                          sleep: { await sleeps.record($0) }, jitter: { 0.5 })
    }

    @Test func freshCacheIsReused() async throws {
        let provider = StubProvider(clock: clock)
        let cache = InMemoryMarketDataCache(quotes: [Quote(ticker: "MSFT", price: 400, currency: .usd, fetchedAt: t0)])
        let service = makeService(provider, cache: cache)
        clock.advance(5 * 60)
        let report = await service.refreshQuotes(["MSFT"])
        #expect(report.skippedFresh == ["MSFT"])
        #expect(await provider.calls.isEmpty)
    }

    @Test func staleCacheIsRefetched() async throws {
        let provider = StubProvider(clock: clock)
        await provider.set(price: 410, for: "MSFT")
        let cache = InMemoryMarketDataCache(quotes: [Quote(ticker: "MSFT", price: 400, currency: .usd, fetchedAt: t0)])
        let service = makeService(provider, cache: cache)
        clock.advance(20 * 60)
        let report = await service.refreshQuotes(["MSFT"])
        #expect(report.updated == ["MSFT"])
        let q = await cache.quoteStore["MSFT"]
        #expect(q?.price == 410 && q?.fetchedAt == t0.addingTimeInterval(20 * 60))
    }

    @Test func forceRefetchesFreshData() async {
        let provider = StubProvider(clock: clock)
        let cache = InMemoryMarketDataCache(quotes: [Quote(ticker: "MSFT", price: 400, currency: .usd, fetchedAt: t0)])
        let report = await makeService(provider, cache: cache).refreshQuotes(["MSFT"], force: true)
        #expect(report.updated == ["MSFT"])
    }

    @Test func concurrentRequestsForOneTickerAreCoalesced() async {
        let provider = StubProvider(clock: clock)
        await provider.setDelay(50_000_000)
        let service = makeService(provider)
        async let r1 = service.refreshQuotes(["AAPL"])
        async let r2 = service.refreshQuotes(["AAPL"])
        async let r3 = service.refreshQuotes(["AAPL", "AAPL"])
        let reports = await [r1, r2, r3]
        #expect(reports.allSatisfy { $0.updated == ["AAPL"] })
        #expect(await provider.calls == ["AAPL"])
    }

    @Test func concurrencyIsCappedAtFour() async {
        let provider = StubProvider(clock: clock)
        await provider.setDelay(20_000_000)
        let report = await makeService(provider).refreshQuotes((1...12).map { "T\($0)" })
        #expect(report.updated.count == 12)
        #expect(await provider.maxConcurrent == 4)
    }

    @Test func rateLimitBacksOffThenSucceeds() async {
        let provider = StubProvider(clock: clock)
        await provider.script("AAPL", [.rateLimited, .http(503)])
        let sleeps = SleepRecorder()
        let report = await makeService(provider, sleeps: sleeps).refreshQuotes(["AAPL"])
        #expect(report.updated == ["AAPL"])
        #expect(await provider.calls == ["AAPL", "AAPL", "AAPL"])
        #expect(await sleeps.delays == [1.5, 3.0])
    }

    @Test func retriesStopAfterLimitAndNonTransientErrorsAreNotRetried() async {
        let provider = StubProvider(clock: clock)
        await provider.fail("AAPL", with: .rateLimited)
        await provider.fail("ZZZZQ", with: .notFound)
        let report = await makeService(provider).refreshQuotes(["AAPL", "ZZZZQ"])
        #expect(report.failed == ["AAPL": .rateLimited, "ZZZZQ": .notFound])
        let calls = await provider.calls
        #expect(calls.filter { $0 == "AAPL" }.count == 4)
        #expect(calls.filter { $0 == "ZZZZQ" }.count == 1)
    }

    @Test func nineOfTenSucceedAndFailureKeepsOldValue() async {
        let provider = StubProvider(clock: clock)
        let tickers = (1...10).map { "T\($0)" }
        for t in tickers { await provider.set(price: 2, for: t) }
        await provider.fail("T7", with: .invalidResponse("bad"))
        let old = tickers.map { Quote(ticker: $0, price: 1, currency: .usd, fetchedAt: t0) }
        let cache = InMemoryMarketDataCache(quotes: old)
        clock.advance(3600)
        let report = await makeService(provider, cache: cache).refreshQuotes(tickers)
        #expect(report.updated.count == 9)
        #expect(Array(report.failed.keys) == ["T7"])
        let stored = await cache.quoteStore
        #expect(stored["T7"] == old[6])
        #expect(stored["T1"]?.price == 2)
        #expect(!report.providerUnreachable)
    }

    @Test func offlineProviderIsReported() async {
        let provider = StubProvider(clock: clock)
        await provider.fail("A", with: .offline)
        await provider.fail("B", with: .offline)
        let report = await makeService(provider).refreshQuotes(["A", "B"])
        #expect(report.providerUnreachable)
    }

    @Test func sameCurrencyNeedsNoFXRequest() async throws {
        let provider = StubProvider(clock: clock)
        let service = makeService(provider)
        let report = await service.refresh(tickers: [], currencies: [.eur, .usd], base: .eur)
        #expect(await provider.calls == ["USDEUR"])
        #expect(report.updated == ["USDEUR"])
        let snap = try await service.snapshot(tickers: [], currencies: [.eur, .usd], base: .eur)
        #expect(snap.rate(from: .eur, to: .eur) == 1)
        #expect(snap.rate(from: .usd, to: .eur) == Decimal(string: "0.9"))
        #expect(await service.lastRefresh == t0)
    }

    @Test func fxUsesOneHourTTL() async {
        let provider = StubProvider(clock: clock)
        let cache = InMemoryMarketDataCache(fxRates: [FXRate(pair: CurrencyPair(.usd, .eur), rate: 1, fetchedAt: t0)])
        let service = makeService(provider, cache: cache)
        clock.advance(30 * 60)
        #expect(await service.refreshFXRates([CurrencyPair(.usd, .eur)]).skippedFresh == ["USDEUR"])
        clock.advance(31 * 60)
        #expect(await service.refreshFXRates([CurrencyPair(.usd, .eur)]).updated == ["USDEUR"])
    }
}

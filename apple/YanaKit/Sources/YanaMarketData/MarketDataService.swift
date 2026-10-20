import Foundation
import YanaDomain

/// Outcome of one refresh: what was fetched, what failed (and kept its previous cached value), and what was skipped
/// because the cache was still fresh.
public struct RefreshReport: Equatable, Sendable {
    public var updated: Set<String> = []
    public var failed: [String: MarketDataError] = [:]
    public var skippedFresh: Set<String> = []

    public init() {}

    /// Every attempted item failed because the provider could not be reached.
    public var providerUnreachable: Bool {
        !failed.isEmpty && updated.isEmpty && failed.values.allSatisfy { $0 == .offline }
    }

    mutating func merge(_ other: RefreshReport) {
        updated.formUnion(other.updated)
        failed.merge(other.failed) { $1 }
        skippedFresh.formUnion(other.skippedFresh)
    }
}

public struct MarketDataPolicy: Sendable {
    public var quoteTTL: TimeInterval = 15 * 60
    public var fxTTL: TimeInterval = 60 * 60
    public var dividendTTL: TimeInterval = 24 * 60 * 60
    public var maxConcurrentRequests = 4
    public var maxRetries = 3
    public var baseBackoff: TimeInterval = 1

    public init() {}
}

/// Caching front for a `MarketDataProvider`: TTL checks, per-item coalescing of in-flight requests, a cap on
/// concurrent provider calls, exponential backoff with jitter for rate limits and 5xx, and write-through to the
/// cache. Failed items keep their previous cached values.
public actor MarketDataService {
    public nonisolated let provider: any MarketDataProvider
    private let cache: any MarketDataCache
    private let policy: MarketDataPolicy
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let jitter: @Sendable () -> Double

    private var inFlight: [String: Task<Result<Void, MarketDataError>, Never>] = [:]
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    public private(set) var lastRefresh: Date?

    public init(provider: any MarketDataProvider, cache: any MarketDataCache, policy: MarketDataPolicy = MarketDataPolicy(),
                now: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1e9)) },
                jitter: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }) {
        self.provider = provider
        self.cache = cache
        self.policy = policy
        self.now = now
        self.sleep = sleep
        self.jitter = jitter
    }

    // MARK: - Reading

    /// Cached data for valuing a portfolio; never touches the network.
    public func snapshot(tickers: [String], currencies: Set<Currency>, base: Currency) async throws -> MarketSnapshot {
        let pairs = currencies.filter { $0 != base }.map { CurrencyPair($0, base) }
        return MarketSnapshot(quotes: Array(try await cache.quotes(for: tickers).values),
                              fxRates: Array(try await cache.fxRates(for: pairs).values),
                              dividendEvents: Array(try await cache.dividendEvents(for: tickers).values))
    }

    // MARK: - Refreshing

    /// Refreshes stale (or, with `force`, all) quotes, FX rates into `base`, and dividend events.
    public func refresh(tickers: [String], currencies: Set<Currency>, base: Currency, force: Bool = false) async -> RefreshReport {
        var report = await refreshQuotes(tickers, force: force)
        report.merge(await refreshFXRates(currencies.filter { $0 != base }.map { CurrencyPair($0, base) }, force: force))
        report.merge(await refreshDividendEvents(tickers, force: force))
        if !report.updated.isEmpty { lastRefresh = now() }
        return report
    }

    public func refreshQuotes(_ tickers: [String], force: Bool = false) async -> RefreshReport {
        let cached = (try? await cache.quotes(for: tickers)) ?? [:]
        return await refresh(Array(Set(tickers)), label: { $0 }, kind: "quote",
                             isFresh: { !force && self.isFresh(cached[$0]?.fetchedAt, ttl: self.policy.quoteTTL) },
                             fetch: { t in
                                 let r = await self.provider.quotes(for: [t])[t] ?? .failure(.notFound)
                                 return await self.store(r) { try await self.cache.save(quotes: [$0]) }
                             })
    }

    public func refreshFXRates(_ pairs: [CurrencyPair], force: Bool = false) async -> RefreshReport {
        let needed = Array(Set(pairs.filter { $0.from != $0.to }))
        let cached = (try? await cache.fxRates(for: needed)) ?? [:]
        return await refresh(needed, label: \.description, kind: "fx",
                             isFresh: { !force && self.isFresh(cached[$0]?.fetchedAt, ttl: self.policy.fxTTL) },
                             fetch: { p in
                                 let r = await self.provider.fxRates(for: [p])[p] ?? .failure(.notFound)
                                 return await self.store(r) { try await self.cache.save(fxRates: [$0]) }
                             })
    }

    public func refreshDividendEvents(_ tickers: [String], force: Bool = false) async -> RefreshReport {
        let cached = (try? await cache.dividendEvents(for: tickers)) ?? [:]
        return await refresh(Array(Set(tickers)), label: { $0 }, kind: "div",
                             isFresh: { !force && self.isFresh(cached[$0]?.fetchedAt, ttl: self.policy.dividendTTL) },
                             fetch: { t in
                                 let r = await self.provider.dividendEvents(for: [t])[t] ?? .failure(.notFound)
                                 return await self.store(r) { try await self.cache.save(dividendEvents: [$0]) }
                             })
    }

    /// Looks up a symbol's attributes for adding a holding (not cached).
    public func details(for ticker: String) async -> Result<SecurityDetails, MarketDataError> {
        await withRetries { await self.provider.securityDetails(for: [ticker])[ticker] ?? .failure(.notFound) }
    }

    // MARK: - Machinery

    private nonisolated func isFresh(_ fetchedAt: Date?, ttl: TimeInterval) -> Bool {
        guard let fetchedAt else { return false }
        return now().timeIntervalSince(fetchedAt) < ttl
    }

    private func store<T>(_ result: Result<T, MarketDataError>, _ save: (T) async throws -> Void) async -> Result<Void, MarketDataError> {
        switch result {
        case .success(let value):
            do { try await save(value) } catch { return .failure(.invalidResponse("cache write failed: \(error)")) }
            return .success(())
        case .failure(let e):
            return .failure(e)
        }
    }

    private func refresh<Item: Sendable>(_ items: [Item], label: @escaping @Sendable (Item) -> String, kind: String,
                                         isFresh: @escaping @Sendable (Item) -> Bool,
                                         fetch: @escaping @Sendable (Item) async -> Result<Void, MarketDataError>) async -> RefreshReport {
        var report = RefreshReport()
        var tasks: [(String, Task<Result<Void, MarketDataError>, Never>)] = []
        for item in items {
            let name = label(item)
            if isFresh(item) { report.skippedFresh.insert(name); continue }
            let key = "\(kind):\(name)"
            if let existing = inFlight[key] {
                tasks.append((name, existing))
                continue
            }
            let task = Task { await self.limited { await self.withRetries { await fetch(item) } } }
            inFlight[key] = task
            tasks.append((name, task))
            Task { _ = await task.value; self.finish(key, task) }
        }
        for (name, task) in tasks {
            switch await task.value {
            case .success: report.updated.insert(name)
            case .failure(let e): report.failed[name] = e
            }
        }
        return report
    }

    private func finish(_ key: String, _ task: Task<Result<Void, MarketDataError>, Never>) {
        if inFlight[key] == task { inFlight[key] = nil }
    }

    /// Retries transient failures with delays of base × 2^attempt × (1 + jitter). The item stays in flight while
    /// waiting, so no parallel request for it can start.
    private func withRetries<T>(_ attempt: @Sendable () async -> Result<T, MarketDataError>) async -> Result<T, MarketDataError> {
        var tries = 0
        while true {
            let result = await attempt()
            guard case .failure(let e) = result, e.isTransient, tries < policy.maxRetries else { return result }
            await sleep(policy.baseBackoff * pow(2, Double(tries)) * (1 + jitter()))
            tries += 1
        }
    }

    private func limited<T>(_ body: @Sendable () async -> T) async -> T {
        if running >= policy.maxConcurrentRequests {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            running += 1
        }
        defer {
            if waiters.isEmpty { running -= 1 } else { waiters.removeFirst().resume() }
        }
        return await body()
    }
}

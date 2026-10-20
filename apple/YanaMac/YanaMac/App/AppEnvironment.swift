import Foundation
import SwiftData
import YanaMarketData

/// Launch arguments read through `UserDefaults` (e.g. `-YanaStoreDirectory /tmp/x`). UI tests use them to run
/// against throwaway stores, a separate preferences domain, and a stub market-data provider.
struct LaunchOptions {
    /// Keep both stores in memory.
    var inMemory = false
    /// Where to put `Portfolio.store` and `MarketCache.store` instead of Application Support.
    var storeDirectory: URL?
    /// A preferences suite to use instead of the app's standard defaults.
    var defaultsSuite: String?
    /// Use `StubMarketDataProvider` instead of Yahoo Finance.
    var stubMarketData = false
    /// Make the stub provider behave as if the network were down.
    var stubOffline = false

    static func current(_ defaults: UserDefaults = .standard) -> LaunchOptions {
        LaunchOptions(inMemory: defaults.bool(forKey: "YanaInMemoryStore"),
                      storeDirectory: defaults.string(forKey: "YanaStoreDirectory").map { URL(fileURLWithPath: $0) },
                      defaultsSuite: defaults.string(forKey: "YanaDefaultsSuite"),
                      stubMarketData: defaults.bool(forKey: "YanaStubMarketData"),
                      stubOffline: defaults.bool(forKey: "YanaStubOffline"))
    }
}

/// Everything the app's models need, built once at launch.
struct AppEnvironment {
    var repository: PortfolioRepository
    var cache: MarketCacheStore
    var market: MarketDataService
    var credentials: any CredentialStore
    var defaults: UserDefaults

    @MainActor
    static func make(_ options: LaunchOptions = .current()) async throws -> (AppEnvironment, SyncController) {
        let portfolioContainer = try PortfolioStore.makeContainer(inMemory: options.inMemory, directory: options.storeDirectory)
        let cacheContainer = try MarketCacheStore.makeContainer(inMemory: options.inMemory, directory: options.storeDirectory)
        let repository = try await PortfolioRepository.make(container: portfolioContainer)
        let cache = MarketCacheStore(modelContainer: cacheContainer)
        let credentials = KeychainCredentialStore()
        let provider: any MarketDataProvider = options.stubMarketData
            ? StubMarketDataProvider(offline: options.stubOffline)
            : YahooFinanceProvider()
        let defaults = options.defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        let environment = AppEnvironment(repository: repository, cache: cache,
                                         market: MarketDataService(provider: provider, cache: cache),
                                         credentials: credentials, defaults: defaults)
        let sync = options.inMemory || options.storeDirectory != nil
            ? SyncController(store: repository.store, defaults: defaults, accountStatus: { .unsupportedBuild })
            : SyncController.live(store: repository.store, coordinator: repository.coordinator)
        return (environment, sync)
    }
}

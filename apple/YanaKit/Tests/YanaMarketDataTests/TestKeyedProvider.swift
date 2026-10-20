import Foundation
import Testing
import YanaDomain
@testable import YanaMarketData

/// A provider that only answers when a credential is stored, for exercising the credential path.
struct TestKeyedProvider: MarketDataProvider {
    let credentials: any CredentialStore
    let id = "test-keyed"
    let displayName = "Test Keyed Provider"
    let isUnofficial = false
    let requiresCredential = true
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func authorized<T: Sendable>(_ keys: [String], _ value: (String) -> T) -> [String: Result<T, MarketDataError>] {
        let hasKey = (try? credentials.credential(for: id)) != nil
        return Dictionary(uniqueKeysWithValues: keys.map { ($0, hasKey ? .success(value($0)) : .failure(.credentialRequired)) })
    }

    func quotes(for tickers: [String]) async -> [String: Result<Quote, MarketDataError>] {
        authorized(tickers) { Quote(ticker: $0, price: 1, currency: .usd, fetchedAt: now) }
    }

    func securityDetails(for tickers: [String]) async -> [String: Result<SecurityDetails, MarketDataError>] {
        authorized(tickers) { SecurityDetails(ticker: $0, name: nil, currency: .usd, assetClass: .stock, sector: nil) }
    }

    func fxRates(for pairs: [CurrencyPair]) async -> [CurrencyPair: Result<FXRate, MarketDataError>] {
        let r = authorized(pairs.map(\.description)) { _ in Decimal(1) }
        return Dictionary(uniqueKeysWithValues: pairs.map { p in (p, r[p.description]!.map { FXRate(pair: p, rate: $0, fetchedAt: now) }) })
    }

    func dividendEvents(for tickers: [String]) async -> [String: Result<DividendEvent, MarketDataError>] {
        authorized(tickers) { DividendEvent(ticker: $0, currency: .usd, fetchedAt: now) }
    }
}

@Suite struct CredentialTests {
    @Test func keyedProviderNeedsCredential() async throws {
        let store = InMemoryCredentialStore()
        let provider = TestKeyedProvider(credentials: store)
        #expect(provider.requiresCredential)
        #expect(await provider.quotes(for: ["AAPL"])["AAPL"] == .failure(.credentialRequired))
        store.save("secret", for: provider.id)
        #expect(try await provider.quotes(for: ["AAPL"])["AAPL"]?.get().price == 1)
        store.save("replaced", for: provider.id)
        #expect(store.credential(for: provider.id) == "replaced")
        store.remove(for: provider.id)
        #expect(await provider.quotes(for: ["AAPL"])["AAPL"] == .failure(.credentialRequired))
    }
}

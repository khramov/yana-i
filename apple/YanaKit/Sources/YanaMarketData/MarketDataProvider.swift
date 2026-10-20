import Foundation
import YanaDomain

public enum MarketDataError: Error, Equatable, Sendable {
    /// The provider has no such symbol.
    case notFound
    /// HTTP 429; retry later.
    case rateLimited
    /// Another non-success HTTP status (5xx is retried).
    case http(Int)
    /// The provider could not be reached.
    case offline
    case unsupportedCurrency(String)
    case credentialRequired
    case invalidResponse(String)

    /// Worth retrying with backoff.
    public var isTransient: Bool {
        switch self {
        case .rateLimited: return true
        case .http(let status): return (500...599).contains(status)
        default: return false
        }
    }
}

/// Name, currency, asset class, and sector of a symbol, as reported by a provider.
public struct SecurityDetails: Equatable, Sendable {
    public var ticker: String
    public var name: String?
    public var currency: Currency
    public var assetClass: AssetClass
    public var sector: String?

    public init(ticker: String, name: String?, currency: Currency, assetClass: AssetClass, sector: String?) {
        self.ticker = ticker
        self.name = name
        self.currency = currency
        self.assetClass = assetClass
        self.sector = sector
    }
}

/// A source of market data. Every call returns one result per requested item, so a single failure never fails
/// the batch. Requests may contain only the symbols and currency pairs being looked up.
public protocol MarketDataProvider: Sendable {
    /// Stable identifier, also used as the credential key.
    var id: String { get }
    var displayName: String { get }
    /// Shown in Settings when the source is not an official, supported API.
    var isUnofficial: Bool { get }
    var requiresCredential: Bool { get }

    func quotes(for tickers: [String]) async -> [String: Result<Quote, MarketDataError>]
    func securityDetails(for tickers: [String]) async -> [String: Result<SecurityDetails, MarketDataError>]
    func fxRates(for pairs: [CurrencyPair]) async -> [CurrencyPair: Result<FXRate, MarketDataError>]
    func dividendEvents(for tickers: [String]) async -> [String: Result<DividendEvent, MarketDataError>]
}

/// Secret storage for provider credentials (the Keychain in the app).
public protocol CredentialStore: Sendable {
    func credential(for providerID: String) throws -> String?
    /// Saves or replaces the credential.
    func save(_ credential: String, for providerID: String) throws
    func remove(for providerID: String) throws
}

/// A `CredentialStore` held in memory, for tests and previews.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    public init() {}

    public func credential(for providerID: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[providerID]
    }

    public func save(_ credential: String, for providerID: String) {
        lock.lock(); defer { lock.unlock() }
        values[providerID] = credential
    }

    public func remove(for providerID: String) {
        lock.lock(); defer { lock.unlock() }
        values[providerID] = nil
    }
}

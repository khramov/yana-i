import Foundation
import SwiftData
import YanaDomain
import YanaMarketData

// `MarketCache.store`: fetched market data and daily value snapshots. Never synchronized, and safe to delete:
// it is rebuilt by the next refresh and holds nothing `Portfolio.store` depends on.

enum MarketCacheSchema {
    static let models: [any PersistentModel.Type] = [
        CachedQuote.self, CachedFXRate.self, CachedDividendEvent.self, StoredValueSnapshot.self,
    ]
}

@Model
final class CachedQuote {
    @Attribute(.unique) var ticker: String
    var price: String
    var currency: String
    var fetchedAt: Date

    init(_ q: Quote) {
        ticker = q.ticker
        price = StoredDecimal.string(q.price)
        currency = q.currency.rawValue
        fetchedAt = q.fetchedAt
    }

    func update(from q: Quote) {
        price = StoredDecimal.string(q.price)
        currency = q.currency.rawValue
        fetchedAt = q.fetchedAt
    }

    var quote: Quote? {
        guard let price = StoredDecimal.decimal(price), let currency = Currency(rawValue: currency) else { return nil }
        return Quote(ticker: ticker, price: price, currency: currency, fetchedAt: fetchedAt)
    }
}

@Model
final class CachedFXRate {
    /// `CurrencyPair.description`, e.g. `USDEUR`.
    @Attribute(.unique) var pair: String
    var from: String
    var to: String
    var rate: String
    var fetchedAt: Date

    init(_ r: FXRate) {
        pair = r.pair.description
        from = r.pair.from.rawValue
        to = r.pair.to.rawValue
        rate = StoredDecimal.string(r.rate)
        fetchedAt = r.fetchedAt
    }

    func update(from r: FXRate) {
        rate = StoredDecimal.string(r.rate)
        fetchedAt = r.fetchedAt
    }

    var fxRate: FXRate? {
        guard let from = Currency(rawValue: from), let to = Currency(rawValue: to),
              let rate = StoredDecimal.decimal(rate) else { return nil }
        return FXRate(pair: CurrencyPair(from, to), rate: rate, fetchedAt: fetchedAt)
    }
}

@Model
final class CachedDividendEvent {
    @Attribute(.unique) var ticker: String
    var exDividendDate: String?
    var paymentDate: String?
    var amountPerShare: String?
    var annualRate: String?
    var frequency: String
    var currency: String
    var fetchedAt: Date

    init(_ e: DividendEvent) {
        ticker = e.ticker
        frequency = e.frequency.rawValue
        currency = e.currency.rawValue
        fetchedAt = e.fetchedAt
        update(from: e)
    }

    func update(from e: DividendEvent) {
        exDividendDate = e.exDividendDate?.description
        paymentDate = e.paymentDate?.description
        amountPerShare = e.amountPerShare.map(StoredDecimal.string)
        annualRate = e.annualRate.map(StoredDecimal.string)
        frequency = e.frequency.rawValue
        currency = e.currency.rawValue
        fetchedAt = e.fetchedAt
    }

    var event: DividendEvent? {
        guard let currency = Currency(rawValue: currency) else { return nil }
        return DividendEvent(ticker: ticker, exDividendDate: exDividendDate.flatMap(LocalDate.init(string:)),
                             paymentDate: paymentDate.flatMap(LocalDate.init(string:)),
                             amountPerShare: amountPerShare.flatMap(StoredDecimal.decimal),
                             annualRate: annualRate.flatMap(StoredDecimal.decimal),
                             frequency: DividendFrequency(rawValue: frequency) ?? .unknown,
                             currency: currency, fetchedAt: fetchedAt)
    }
}

/// A portfolio's value on one local calendar day, kept on this Mac only.
struct ValueSnapshot: Equatable, Sendable {
    var portfolioID: UUID
    var day: LocalDate
    var totalValue: Decimal
    var costBasis: Decimal
    var baseCurrency: Currency
    var recordedAt: Date
}

@Model
final class StoredValueSnapshot {
    /// `<portfolio uuid>|<YYYY-MM-DD>`: at most one snapshot per portfolio per day.
    @Attribute(.unique) var key: String
    var portfolioID: UUID
    var day: String
    var totalValue: String
    var costBasis: String
    var baseCurrency: String
    var recordedAt: Date

    init(_ s: ValueSnapshot) {
        key = Self.key(s.portfolioID, s.day)
        portfolioID = s.portfolioID
        day = s.day.description
        totalValue = StoredDecimal.string(s.totalValue)
        costBasis = StoredDecimal.string(s.costBasis)
        baseCurrency = s.baseCurrency.rawValue
        recordedAt = s.recordedAt
    }

    func update(from s: ValueSnapshot) {
        totalValue = StoredDecimal.string(s.totalValue)
        costBasis = StoredDecimal.string(s.costBasis)
        baseCurrency = s.baseCurrency.rawValue
        recordedAt = s.recordedAt
    }

    static func key(_ portfolioID: UUID, _ day: LocalDate) -> String {
        "\(portfolioID.uuidString.lowercased())|\(day)"
    }

    var snapshot: ValueSnapshot? {
        guard let day = LocalDate(string: day), let totalValue = StoredDecimal.decimal(totalValue),
              let costBasis = StoredDecimal.decimal(costBasis), let currency = Currency(rawValue: baseCurrency)
        else { return nil }
        return ValueSnapshot(portfolioID: portfolioID, day: day, totalValue: totalValue, costBasis: costBasis,
                             baseCurrency: currency, recordedAt: recordedAt)
    }
}

@ModelActor
actor MarketCacheStore {
    static let fileName = "MarketCache.store"

    static func makeContainer(inMemory: Bool = false, directory: URL? = nil) throws -> ModelContainer {
        let schema = Schema(MarketCacheSchema.models)
        let configuration = inMemory
            ? ModelConfiguration("MarketCache", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            : ModelConfiguration("MarketCache", schema: schema,
                                 url: try StoreLocation.url(for: fileName, in: directory), cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Deletes the cache files (store plus SQLite sidecars). Call only when no container has the store open.
    static func deleteStoreFiles(in directory: URL? = nil) throws {
        let url = try StoreLocation.url(for: fileName, in: directory)
        for suffix in ["", "-shm", "-wal"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }

    /// Empties every cached value and snapshot in place.
    func removeAll() throws {
        try modelContext.delete(model: CachedQuote.self)
        try modelContext.delete(model: CachedFXRate.self)
        try modelContext.delete(model: CachedDividendEvent.self)
        try modelContext.delete(model: StoredValueSnapshot.self)
        try modelContext.save()
    }

    // MARK: - Value snapshots

    /// Records the portfolio's value for `snapshot.day`, replacing that day's earlier snapshot.
    func record(_ snapshot: ValueSnapshot) throws {
        let key = StoredValueSnapshot.key(snapshot.portfolioID, snapshot.day)
        if let existing = try modelContext.fetch(FetchDescriptor<StoredValueSnapshot>(predicate: #Predicate { $0.key == key })).first {
            existing.update(from: snapshot)
        } else {
            modelContext.insert(StoredValueSnapshot(snapshot))
        }
        try modelContext.save()
    }

    /// Snapshots of one portfolio, oldest first, optionally limited to `from...to` (inclusive).
    func snapshots(for portfolioID: UUID, from: LocalDate? = nil, to: LocalDate? = nil) throws -> [ValueSnapshot] {
        try modelContext.fetch(FetchDescriptor<StoredValueSnapshot>(predicate: #Predicate { $0.portfolioID == portfolioID },
                                                                    sortBy: [SortDescriptor(\.day)]))
            .compactMap(\.snapshot)
            .filter { s in (from.map { s.day >= $0 } ?? true) && (to.map { s.day <= $0 } ?? true) }
    }

    func deleteSnapshots(for portfolioID: UUID) throws {
        try modelContext.delete(model: StoredValueSnapshot.self, where: #Predicate { $0.portfolioID == portfolioID })
        try modelContext.save()
    }
}

extension MarketCacheStore: MarketDataCache {
    func quotes(for tickers: [String]) throws -> [String: Quote] {
        let rows = try modelContext.fetch(FetchDescriptor<CachedQuote>(predicate: #Predicate { tickers.contains($0.ticker) }))
        return Dictionary(rows.compactMap(\.quote).map { ($0.ticker, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func save(quotes: [Quote]) throws {
        for q in quotes {
            let ticker = q.ticker
            if let row = try modelContext.fetch(FetchDescriptor<CachedQuote>(predicate: #Predicate { $0.ticker == ticker })).first {
                row.update(from: q)
            } else {
                modelContext.insert(CachedQuote(q))
            }
        }
        try modelContext.save()
    }

    func fxRates(for pairs: [CurrencyPair]) throws -> [CurrencyPair: FXRate] {
        let names = pairs.map(\.description)
        let rows = try modelContext.fetch(FetchDescriptor<CachedFXRate>(predicate: #Predicate { names.contains($0.pair) }))
        return Dictionary(rows.compactMap(\.fxRate).map { ($0.pair, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func save(fxRates: [FXRate]) throws {
        for r in fxRates {
            let name = r.pair.description
            if let row = try modelContext.fetch(FetchDescriptor<CachedFXRate>(predicate: #Predicate { $0.pair == name })).first {
                row.update(from: r)
            } else {
                modelContext.insert(CachedFXRate(r))
            }
        }
        try modelContext.save()
    }

    func dividendEvents(for tickers: [String]) throws -> [String: DividendEvent] {
        let rows = try modelContext.fetch(FetchDescriptor<CachedDividendEvent>(predicate: #Predicate { tickers.contains($0.ticker) }))
        return Dictionary(rows.compactMap(\.event).map { ($0.ticker, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func save(dividendEvents: [DividendEvent]) throws {
        for e in dividendEvents {
            let ticker = e.ticker
            if let row = try modelContext.fetch(FetchDescriptor<CachedDividendEvent>(predicate: #Predicate { $0.ticker == ticker })).first {
                row.update(from: e)
            } else {
                modelContext.insert(CachedDividendEvent(e))
            }
        }
        try modelContext.save()
    }
}

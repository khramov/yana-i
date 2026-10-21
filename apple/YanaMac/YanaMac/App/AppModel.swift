import Foundation
import Observation
import YanaDomain
import YanaMarketData
import YanaSync

enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case dashboard, holdings, transactions, income, dividends, analytics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .holdings: return "Holdings"
        case .transactions: return "Transactions"
        case .income: return "Income"
        case .dividends: return "Dividends"
        case .analytics: return "Analytics"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .holdings: return "tablecells"
        case .transactions: return "list.bullet.rectangle"
        case .income: return "chart.bar"
        case .dividends: return "banknote"
        case .analytics: return "chart.pie"
        }
    }
}

/// Sheets the main window can present.
enum AppSheet: Identifiable, Equatable {
    case newPortfolio
    case addHolding
    case editHolding(HoldingRecord)
    case newTransaction
    case editTransaction(TransactionRecord)
    case importResult(CSVImportOutcome)

    var id: String {
        switch self {
        case .newPortfolio: return "newPortfolio"
        case .addHolding: return "addHolding"
        case .editHolding(let h): return "editHolding-\(h.id)"
        case .newTransaction: return "newTransaction"
        case .editTransaction(let t): return "editTransaction-\(t.id)"
        case .importResult: return "importResult"
        }
    }
}

/// What a CSV import did, for the result sheet.
struct CSVImportOutcome: Equatable {
    var fileName: String
    /// Rows added from the file.
    var imported: Int
    var holdingsCreated: Int
    /// Earlier imported rows in the file's range that it replaced.
    var replaced = 0
    /// Hand-entered rows replaced by a matching file row.
    var absorbed = 0
    var errors: [CSVLineError]
    var warnings: [CSVLineError] = []
    /// Set when the whole file was rejected (missing columns, unreadable file).
    var fileError: String?
}

/// Result of the last market-data refresh, for "as of" and "offline" notices.
struct MarketStatus: Equatable {
    var lastRefresh: Date?
    var failedItems: [String: MarketDataError] = [:]
    var isOffline = false
    var isRefreshing = false
}

/// The main window's state: the selected portfolio and section, that portfolio's records and cached market data,
/// and every write. Views read from it; section models derive their rows from it.
@MainActor @Observable
final class AppModel {
    let environment: AppEnvironment
    let sync: SyncController
    @ObservationIgnored var clock: () -> CalculationClock = { .current }

    private(set) var isLoaded = false
    private(set) var portfolios: [PortfolioRecord] = []
    private(set) var holdings: [HoldingRecord] = []
    private(set) var transactions: [TransactionRecord] = []
    private(set) var goals: [GoalRecord] = []
    private(set) var market: MarketSnapshot = .empty
    private(set) var valuation: PortfolioValuation?
    private(set) var marketStatus = MarketStatus()
    /// Bumped whenever records or market data change, so dependent views can reload derived data.
    private(set) var dataVersion = 0

    var sheet: AppSheet?
    var isImportingCSV = false
    var errorMessage: String?
    /// Automatic refreshes run only while the app is frontmost.
    @ObservationIgnored var isActive = true

    /// Set by the portfolio switcher; code that must wait for the reload calls `select(_:)` instead.
    var selectedPortfolioID: UUID? {
        didSet {
            guard oldValue != selectedPortfolioID else { return }
            defaults.set(selectedPortfolioID?.uuidString, forKey: Key.portfolio)
            if !isSelecting { Task { await reloadPortfolio(); await refreshMarketData() } }
        }
    }
    @ObservationIgnored private var isSelecting = false

    var section: AppSection {
        didSet {
            guard oldValue != section else { return }
            defaults.set(section.rawValue, forKey: Key.section)
            Task { await refreshMarketData() }
        }
    }

    var selectedPortfolio: PortfolioRecord? { portfolios.first { $0.id == selectedPortfolioID } }
    var repository: PortfolioRepository { environment.repository }
    var provider: any MarketDataProvider { environment.market.provider }

    private var defaults: UserDefaults { environment.defaults }

    private enum Key {
        static let portfolio = "selection.portfolio"
        static let section = "selection.section"
    }

    init(environment: AppEnvironment, sync: SyncController) {
        self.environment = environment
        self.sync = sync
        section = environment.defaults.string(forKey: Key.section).flatMap(AppSection.init(rawValue:)) ?? .dashboard
        selectedPortfolioID = environment.defaults.string(forKey: Key.portfolio).flatMap(UUID.init(uuidString:))
        sync.onRecordsChanged = { [weak self] in Task { await self?.reloadAll() } }
    }

    // MARK: - Loading

    /// Loads portfolios, restores the last selection when it still exists, and refreshes stale market data.
    func start() async {
        await reloadAll()
        isLoaded = true
        await refreshMarketData()
    }

    func reloadAll() async {
        do {
            portfolios = try await repository.store.portfolios()
        } catch {
            errorMessage = error.localizedDescription
        }
        if selectedPortfolio == nil, portfolios.first?.id != selectedPortfolioID {
            await select(portfolios.first?.id)
        } else {
            await reloadPortfolio()
        }
    }

    /// Selects a portfolio and waits until its records are loaded.
    func select(_ id: UUID?) async {
        isSelecting = true
        selectedPortfolioID = id
        isSelecting = false
        await reloadPortfolio()
    }

    func reloadPortfolio() async {
        guard let portfolio = selectedPortfolio else {
            holdings = []; transactions = []; goals = []; market = .empty; valuation = nil
            dataVersion += 1
            return
        }
        do {
            holdings = try await repository.store.holdings(inPortfolio: portfolio.id)
            transactions = try await repository.store.transactions(inPortfolio: portfolio.id)
            goals = try await repository.store.goals(inPortfolio: portfolio.id)
            market = try await environment.market.snapshot(tickers: holdings.map(\.ticker), currencies: neededCurrencies,
                                                           base: portfolio.baseCurrency)
        } catch {
            errorMessage = error.localizedDescription
        }
        recompute()
    }

    private func recompute() {
        guard let portfolio = selectedPortfolio else { valuation = nil; return }
        valuation = PortfolioValuation(portfolio: portfolio, holdings: holdings, transactions: transactions, market: market)
        dataVersion += 1
        recordDailySnapshot()
    }

    /// Every currency a value of this portfolio may need converting from.
    private var neededCurrencies: Set<Currency> {
        Set(holdings.map(\.currency)).union(transactions.map(\.currency))
            .union(market.quotes.values.map(\.currency)).union(market.dividendEvents.values.map(\.currency))
    }

    private func recordDailySnapshot() {
        guard let valuation, let total = valuation.totalValue, let portfolio = selectedPortfolio else { return }
        let clock = clock()
        let snapshot = ValueSnapshot(portfolioID: portfolio.id, day: clock.today, totalValue: total,
                                     costBasis: valuation.costBasis, baseCurrency: portfolio.baseCurrency,
                                     recordedAt: clock.now)
        let cache = environment.cache
        Task { try? await cache.record(snapshot) }
    }

    // MARK: - Market data

    /// Refreshes stale data for the selected portfolio, or everything with `force` (the Refresh command).
    func refreshMarketData(force: Bool = false) async {
        guard let portfolio = selectedPortfolio, force || isActive, !marketStatus.isRefreshing else { return }
        // Automatic refreshes cover open positions; the Refresh command covers every holding.
        let tickers = force ? holdings.map(\.ticker) : valuation?.positions.map(\.ticker) ?? []
        guard !tickers.isEmpty else { return }
        marketStatus.isRefreshing = true
        let report = await environment.market.refresh(tickers: tickers, currencies: neededCurrencies,
                                                      base: portfolio.baseCurrency, force: force)
        // Quote currencies are only known after the first fetch; fetch their FX rates too.
        market = (try? await environment.market.snapshot(tickers: holdings.map(\.ticker), currencies: neededCurrencies,
                                                         base: portfolio.baseCurrency)) ?? market
        let fx = await environment.market.refreshFXRates(neededCurrencies.filter { $0 != portfolio.baseCurrency }
            .map { CurrencyPair($0, portfolio.baseCurrency) }, force: false)
        marketStatus.isRefreshing = false
        marketStatus.failedItems = report.failed.merging(fx.failed) { a, _ in a }
        marketStatus.isOffline = report.providerUnreachable
        if !report.updated.isEmpty || !fx.updated.isEmpty { marketStatus.lastRefresh = clock().now }
        await reloadPortfolio()
    }

    // MARK: - Portfolios

    @discardableResult
    func createPortfolio(_ draft: PortfolioDraft) async throws -> PortfolioRecord {
        let created = try await repository.createPortfolio(draft)
        await afterWrite()
        await select(created.id)
        return created
    }

    func updatePortfolio(_ id: UUID, _ draft: PortfolioDraft) async throws {
        try await repository.updatePortfolio(id, draft)
        await afterWrite()
        await refreshMarketData()
    }

    func deletePortfolio(_ id: UUID) async throws {
        try await repository.deletePortfolio(id)
        try? await environment.cache.deleteSnapshots(for: id)
        await afterWrite()
    }

    // MARK: - Holdings

    func lookUpSecurity(_ ticker: String) async -> Result<SecurityDetails, MarketDataError> {
        await environment.market.details(for: RecordIdentity.normalizeTicker(ticker))
    }

    func addHolding(_ draft: HoldingDraft) async throws -> PortfolioRepository.AddedHolding {
        guard let portfolio = selectedPortfolio else { throw PortfolioRepositoryError.notFound }
        let added = try await repository.addHolding(draft, to: portfolio.id)
        await afterWrite()
        if !added.alreadyExisted { await refreshMarketData() }
        return added
    }

    func updateHolding(_ id: UUID, _ draft: HoldingDraft) async throws {
        try await repository.updateHolding(id, draft)
        await afterWrite()
    }

    func deleteHolding(_ id: UUID) async throws {
        try await repository.deleteHolding(id)
        await afterWrite()
    }

    // MARK: - Transactions

    /// A trade can open a position that has no price yet, so stale market data is refreshed afterwards.
    func addTransaction(_ draft: TransactionDraft, holdingID: UUID) async throws {
        try await repository.addTransaction(draft, to: holdingID)
        await afterWrite()
        await refreshMarketData()
    }

    func updateTransaction(_ id: UUID, _ draft: TransactionDraft) async throws {
        try await repository.updateTransaction(id, draft)
        await afterWrite()
        await refreshMarketData()
    }

    func deleteTransaction(_ id: UUID) async throws {
        try await repository.deleteTransaction(id)
        await afterWrite()
    }

    /// Imports a CSV file into the selected portfolio and shows the result sheet.
    func importCSV(from url: URL) async {
        guard let portfolio = selectedPortfolio else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var outcome = CSVImportOutcome(fileName: url.lastPathComponent, imported: 0, holdingsCreated: 0, errors: [])
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let plan = try await repository.importFile(text, into: portfolio.id)
            outcome.imported = plan.added
            outcome.holdingsCreated = plan.holdings.count
            outcome.replaced = plan.replaced
            outcome.absorbed = plan.absorbed
            outcome.errors = plan.errors
            outcome.warnings = plan.warnings
        } catch let error as CSVImportError {
            outcome.fileError = error.message
        } catch {
            outcome.fileError = "The file could not be read as UTF-8 text."
        }
        await afterWrite()
        sheet = .importResult(outcome)
        if outcome.imported > 0 { await refreshMarketData() }
    }

    // MARK: - Goals

    func saveGoals(_ draft: GoalScopeDraft) async throws {
        guard let portfolio = selectedPortfolio else { throw PortfolioRepositoryError.notFound }
        try await repository.saveGoals(draft, for: portfolio.id)
        await afterWrite()
    }

    // MARK: - Helpers

    private func afterWrite() async {
        await reloadAll()
        await sync.refreshCounts()
    }
}

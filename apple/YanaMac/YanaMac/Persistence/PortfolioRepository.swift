import Foundation
import SwiftData
import YanaDomain
import YanaSync

enum PortfolioRepositoryError: Error, Equatable, LocalizedError {
    case notFound
    case holdingHasTransactions(count: Int)
    /// Another device saved this record with a newer app version; it stays read-only until this app updates.
    case readOnlyUntilAppUpdate

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "This item no longer exists."
        case .holdingHasTransactions(let count):
            return count == 1 ? "1 transaction must be deleted first." : "\(count) transactions must be deleted first."
        case .readOnlyUntilAppUpdate:
            return "This item was changed by a newer version of Yana. Update the app to edit it."
        }
    }
}

/// The app's write API for portfolios, holdings, transactions, and goals. It validates input, builds domain
/// records, and commits them through the `SyncCoordinator`, which stamps versions and queues uploads.
/// Callers only see domain structs, never `@Model` objects.
actor PortfolioRepository {
    nonisolated let store: PortfolioStore
    nonisolated let coordinator: SyncCoordinator
    nonisolated let deviceID: UUID
    private let now: @Sendable () -> Date

    init(store: PortfolioStore, deviceID: UUID, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.deviceID = deviceID
        self.coordinator = SyncCoordinator(deviceID: deviceID, store: store, now: now)
        self.now = now
    }

    /// A repository over `container` using the store's persisted device ID.
    static func make(container: ModelContainer,
                     now: @escaping @Sendable () -> Date = { Date() }) async throws -> PortfolioRepository {
        let store = PortfolioStore(modelContainer: container)
        return PortfolioRepository(store: store, deviceID: try await store.deviceID(), now: now)
    }

    // MARK: - Portfolios

    @discardableResult
    func createPortfolio(_ draft: PortfolioDraft) async throws -> PortfolioRecord {
        let valid = try draft.validated()
        let record = PortfolioRecord(id: UUID(), name: valid.name, baseCurrency: valid.baseCurrency,
                                     createdAt: now(), version: placeholderVersion)
        return try await commit(.portfolio(record), as: PortfolioRecord.self)
    }

    @discardableResult
    func updatePortfolio(_ id: UUID, _ draft: PortfolioDraft) async throws -> PortfolioRecord {
        let valid = try draft.validated()
        var record = try await live(try await store.portfolio(id))
        try await requireEditable(.portfolio(record))
        record.name = valid.name
        record.baseCurrency = valid.baseCurrency
        return try await commit(.portfolio(record), as: PortfolioRecord.self)
    }

    /// Tombstones the portfolio and all of its live holdings, transactions, and goals in one save.
    func deletePortfolio(_ id: UUID) async throws {
        let record = try await live(try await store.portfolio(id))
        try await requireEditable(.portfolio(record))
        let at = now()
        let doomed = [AnyRecord.portfolio(record)] + (try await store.liveChildren(ofPortfolio: id))
        try await coordinator.commitLocalEdits(doomed.map { var r = $0; r.deletedAt = at; return r })
    }

    // MARK: - Holdings

    struct AddedHolding: Equatable, Sendable {
        var holding: HoldingRecord
        /// True when the portfolio already had a live holding for the ticker, which is returned unchanged.
        var alreadyExisted: Bool
    }

    /// Adds a holding identified by its normalized ticker. Re-adding a deleted ticker revives it.
    func addHolding(_ draft: HoldingDraft, to portfolioID: UUID) async throws -> AddedHolding {
        let valid = try draft.validated()
        _ = try await live(try await store.portfolio(portfolioID))
        let id = RecordIdentity.holdingID(portfolioID: portfolioID, ticker: valid.ticker)
        if let existing = try await store.holding(id), !existing.isDeleted {
            return AddedHolding(holding: existing, alreadyExisted: true)
        }
        try await requireEditable(RecordKey(entity: .holding, id: id))
        let record = HoldingRecord(id: id, portfolioID: portfolioID, ticker: valid.ticker, name: valid.name,
                                   sector: valid.sector, assetClass: valid.assetClass ?? .default,
                                   currency: valid.currency, createdAt: now(), version: placeholderVersion)
        return AddedHolding(holding: try await commit(.holding(record), as: HoldingRecord.self), alreadyExisted: false)
    }

    /// Updates every attribute except the ticker, which is part of the holding's identity.
    @discardableResult
    func updateHolding(_ id: UUID, _ draft: HoldingDraft) async throws -> HoldingRecord {
        var record = try await live(try await store.holding(id))
        try await requireEditable(.holding(record))
        var valid = draft
        valid.ticker = record.ticker
        valid = try valid.validated()
        record.name = valid.name
        record.sector = valid.sector
        record.assetClass = valid.assetClass ?? .default
        record.currency = valid.currency
        return try await commit(.holding(record), as: HoldingRecord.self)
    }

    /// Deletes a holding only when it has no live transactions.
    func deleteHolding(_ id: UUID) async throws {
        var record = try await live(try await store.holding(id))
        try await requireEditable(.holding(record))
        let count = try await store.transactions(ofHolding: id).count
        guard count == 0 else { throw PortfolioRepositoryError.holdingHasTransactions(count: count) }
        record.deletedAt = now()
        try await coordinator.commitLocalEdits([.holding(record)])
    }

    // MARK: - Transactions

    @discardableResult
    func addTransaction(_ draft: TransactionDraft, to holdingID: UUID) async throws -> TransactionRecord {
        let valid = try draft.validated()
        let holding = try await live(try await store.holding(holdingID))
        let record = TransactionRecord(id: UUID(), portfolioID: holding.portfolioID, holdingID: holding.id,
                                       kind: valid.kind, date: valid.date!, quantity: valid.quantity,
                                       unitPrice: valid.unitPrice, amount: valid.amount, fee: valid.fee ?? 0,
                                       tax: valid.tax ?? 0, currency: valid.currency, notes: valid.notes,
                                       createdAt: now(), version: placeholderVersion)
        return try await commit(.transaction(record), as: TransactionRecord.self)
    }

    @discardableResult
    func updateTransaction(_ id: UUID, _ draft: TransactionDraft) async throws -> TransactionRecord {
        let valid = try draft.validated()
        var record = try await live(try await store.transaction(id))
        try await requireEditable(.transaction(record))
        record.kind = valid.kind
        record.date = valid.date!
        record.quantity = valid.quantity
        record.unitPrice = valid.unitPrice
        record.amount = valid.amount
        record.fee = valid.fee ?? 0
        record.tax = valid.tax ?? 0
        record.currency = valid.currency
        record.notes = valid.notes
        return try await commit(.transaction(record), as: TransactionRecord.self)
    }

    func deleteTransaction(_ id: UUID) async throws {
        var record = try await live(try await store.transaction(id))
        try await requireEditable(.transaction(record))
        record.deletedAt = now()
        try await coordinator.commitLocalEdits([.transaction(record)])
    }

    // MARK: - Goals

    /// Replaces all targets of one scope: changed or new keys are upserted under their derived IDs and keys no
    /// longer listed are tombstoned. The other scope is untouched.
    @discardableResult
    func saveGoals(_ draft: GoalScopeDraft, for portfolioID: UUID) async throws -> [GoalRecord] {
        let valid = try draft.validated()
        _ = try await live(try await store.portfolio(portfolioID))
        let existing = Dictionary(uniqueKeysWithValues: try await store.goals(inPortfolio: portfolioID, includingDeleted: true)
            .filter { $0.scope == valid.scope }.map { ($0.id, $0) })
        let at = now()
        var edits: [AnyRecord] = []
        var keep = Set<UUID>()
        for target in valid.targets {
            let id = RecordIdentity.goalID(portfolioID: portfolioID, scope: valid.scope, key: target.key)
            keep.insert(id)
            if let current = existing[id], !current.isDeleted, current.targetPercent == target.percent { continue }
            var goal = existing[id] ?? GoalRecord(id: id, portfolioID: portfolioID, scope: valid.scope, key: target.key,
                                                  targetPercent: target.percent, createdAt: at, version: placeholderVersion)
            goal.targetPercent = target.percent
            goal.deletedAt = nil
            edits.append(.goal(goal))
        }
        for goal in existing.values where !goal.isDeleted && !keep.contains(goal.id) {
            var tombstone = goal
            tombstone.deletedAt = at
            edits.append(.goal(tombstone))
        }
        for edit in edits { try await requireEditable(edit) }
        if !edits.isEmpty { try await coordinator.commitLocalEdits(edits) }
        return try await store.goals(inPortfolio: portfolioID).filter { $0.scope == valid.scope }
    }

    // MARK: - CSV import

    /// Validates every row, then creates the needed holdings and the valid transactions in one save.
    func importCSV(_ csv: String, into portfolioID: UUID) async throws -> CSVImportPlan {
        _ = try await live(try await store.portfolio(portfolioID))
        let plan = try CSVImportPlanner.plan(csv: csv, portfolioID: portfolioID,
                                             existingHoldings: try await store.holdings(inPortfolio: portfolioID,
                                                                                       includingDeleted: true),
                                             now: now(), deviceID: deviceID)
        let records = plan.holdingsToCreate.map(AnyRecord.holding) + plan.transactionsToInsert.map(AnyRecord.transaction)
        if !records.isEmpty { try await coordinator.commitLocalEdits(records) }
        return plan
    }

    // MARK: - Helpers

    /// Replaced by `SyncCoordinator.commitLocalEdits`, which stamps the real version.
    private var placeholderVersion: RecordVersion { .initial(at: now(), deviceID: deviceID) }

    private func live<R: SyncableRecord>(_ record: R?) async throws -> R {
        guard let record, !record.isDeleted else { throw PortfolioRepositoryError.notFound }
        return record
    }

    private func requireEditable(_ record: AnyRecord) async throws {
        try await requireEditable(record.key)
    }

    private func requireEditable(_ key: RecordKey) async throws {
        if try await store.state(for: key)?.pendingRemoteVersion != nil {
            throw PortfolioRepositoryError.readOnlyUntilAppUpdate
        }
    }

    private func commit<R>(_ record: AnyRecord, as: R.Type) async throws -> R {
        let stamped = try await coordinator.commitLocalEdits([record])
        switch stamped[0] {
        case .portfolio(let r as R), .holding(let r as R), .transaction(let r as R), .goal(let r as R): return r
        default: preconditionFailure("commitLocalEdits changed the record type")
        }
    }
}

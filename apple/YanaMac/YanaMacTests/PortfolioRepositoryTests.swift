import Foundation
import SwiftData
import Testing
import YanaDomain
import YanaSync
@testable import YanaMac

/// Strictly increasing timestamps, one second apart.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_729_300_000)
    func next() -> Date {
        lock.lock(); defer { lock.unlock() }
        t = t.addingTimeInterval(1)
        return t
    }
}

func makeRepository(clock: TestClock = TestClock()) async throws -> PortfolioRepository {
    try await PortfolioRepository.make(container: try PortfolioStore.makeContainer(inMemory: true),
                                       now: { clock.next() })
}

func date(_ s: String) -> LocalDate { LocalDate(string: s)! }

@Suite struct PortfolioRepositoryTests {
    @Test func optionHoldingAndOpeningRoundTrip() async throws {
        let repo = try await makeRepository()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "P"))
        let at = Date(timeIntervalSince1970: 1_729_000_000)
        let version = RecordVersion.initial(at: at, deviceID: repo.deviceID)
        var option = HoldingRecord(id: RecordIdentity.holdingID(portfolioID: p.id, ticker: "PBR271217C00027000"),
                                   portfolioID: p.id, ticker: "PBR271217C00027000", name: "PBR 17DEC27 27 C",
                                   assetClass: .option, currency: .usd, multiplier: 100, createdAt: at, version: version)
        var opening = TransactionRecord(
            id: UUID(), portfolioID: p.id, holdingID: option.id, kind: .buy, date: date("2026-08-03"),
            quantity: 20, unitPrice: 90, currency: .usd, notes: "Opening balance",
            importSource: .ibkr,
            openingBalance: OpeningBalance(asOf: date("2026-10-19"), targetQuantity: 30,
                                           targetCostBasis: Decimal(string: "2801.25")!,
                                           coveredFrom: date("2026-08-03")),
            createdAt: Date(timeIntervalSince1970: 0), version: version)
        try await repo.coordinator.commitLocalEdits([.holding(option), .transaction(opening)])

        let storedHolding = try #require(try await repo.store.holding(option.id))
        let storedTx = try #require(try await repo.store.transaction(opening.id))
        option.version = storedHolding.version
        opening.version = storedTx.version
        #expect(storedHolding == option)
        #expect(storedTx == opening)
    }

    @Test func portfolioRoundTripAndDefaults() async throws {
        let repo = try await makeRepository()
        let created = try await repo.createPortfolio(PortfolioDraft(name: "  Long term "))
        #expect(created.baseCurrency == .eur && created.name == "Long term")
        #expect(created.version.revision == 1)
        #expect(try await repo.store.portfolio(created.id) == created)

        let renamed = try await repo.updatePortfolio(created.id, PortfolioDraft(name: "Pension", baseCurrency: .usd))
        #expect(renamed.version.revision == 2 && renamed.id == created.id)
        #expect(try await repo.store.portfolios() == [renamed])

        await #expect(throws: ValidationError.self) { try await repo.createPortfolio(PortfolioDraft(name: "  ")) }
        #expect(try await repo.store.portfolios().count == 1)
    }

    @Test func holdingAndTransactionRoundTripExactly() async throws {
        let repo = try await makeRepository()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "P"))
        let h = try await repo.addHolding(HoldingDraft(ticker: "ko", name: "Coca-Cola", sector: "Consumer Defensive",
                                                       assetClass: nil, currency: .usd), to: p.id).holding
        #expect(h.ticker == "KO" && h.assetClass == .stock)
        #expect(try await repo.store.holding(h.id) == h)

        let buy = try await repo.addTransaction(TransactionDraft(kind: .buy, date: date("2024-01-02"), quantity: Decimal(string: "0.1"),
                                                                 unitPrice: Decimal(string: "58.123456789"), fee: Decimal(string: "0.99"),
                                                                 currency: .usd, notes: " first "), to: h.id)
        let dividend = try await repo.addTransaction(TransactionDraft(kind: .dividend, date: date("2024-04-01"), quantity: 50,
                                                                      amount: Decimal(string: "12.50"), tax: Decimal(string: "1.88"),
                                                                      currency: .usd), to: h.id)
        #expect(try await repo.store.transaction(buy.id) == buy)
        #expect(try await repo.store.transaction(dividend.id) == dividend)
        #expect(buy.unitPrice == Decimal(string: "58.123456789") && buy.notes == "first" && buy.amount == nil)
        #expect(dividend.amount == Decimal(string: "12.5") && dividend.tax == Decimal(string: "1.88") && dividend.quantity == 50)

        let edited = try await repo.updateTransaction(buy.id, TransactionDraft(kind: .buy, date: date("2024-01-03"),
                                                                               quantity: Decimal(string: "0.2"), unitPrice: 60,
                                                                               currency: .usd))
        #expect(edited.version.revision == 2 && edited.createdAt == buy.createdAt)
        let shares = PositionCalculator.positions(holdings: [h], transactions: try await repo.store.transactions(inPortfolio: p.id))
            .first?.shares
        #expect(shares == Decimal(string: "0.2"))
    }

    @Test func holdingUniquenessPerPortfolio() async throws {
        let repo = try await makeRepository()
        let p1 = try await repo.createPortfolio(PortfolioDraft(name: "One"))
        let p2 = try await repo.createPortfolio(PortfolioDraft(name: "Two"))
        let first = try await repo.addHolding(HoldingDraft(ticker: " aapl ", currency: .usd), to: p1.id)
        let again = try await repo.addHolding(HoldingDraft(ticker: "AAPL", name: "Ignored", currency: .usd), to: p1.id)
        #expect(!first.alreadyExisted && again.alreadyExisted)
        #expect(again.holding == first.holding)
        #expect(try await repo.store.holdings(inPortfolio: p1.id).count == 1)

        let other = try await repo.addHolding(HoldingDraft(ticker: "AAPL", currency: .usd), to: p2.id)
        #expect(!other.alreadyExisted && other.holding.id != first.holding.id)
    }

    @Test func tickerIsNotEditable() async throws {
        let repo = try await makeRepository()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "P"))
        let h = try await repo.addHolding(HoldingDraft(ticker: "VTI", currency: .usd), to: p.id).holding
        let updated = try await repo.updateHolding(h.id, HoldingDraft(ticker: "VOO", assetClass: .etf, currency: .usd))
        #expect(updated.ticker == "VTI" && updated.id == h.id && updated.assetClass == .etf)
    }

    @Test func holdingDeleteGuard() async throws {
        let repo = try await makeRepository()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "P"))
        let used = try await repo.addHolding(HoldingDraft(ticker: "MSFT", currency: .usd), to: p.id).holding
        let unused = try await repo.addHolding(HoldingDraft(ticker: "NVDA", currency: .usd), to: p.id).holding
        for day in ["2024-01-02", "2024-02-02", "2024-03-02"] {
            try await repo.addTransaction(TransactionDraft(kind: .buy, date: date(day), quantity: 1, unitPrice: 100, currency: .usd),
                                          to: used.id)
        }

        await #expect(throws: PortfolioRepositoryError.holdingHasTransactions(count: 3)) { try await repo.deleteHolding(used.id) }
        #expect(PortfolioRepositoryError.holdingHasTransactions(count: 3).localizedDescription
            == "3 transactions must be deleted first.")
        #expect(try await repo.store.holding(used.id)?.isDeleted == false)

        try await repo.deleteHolding(unused.id)
        #expect(try await repo.store.holdings(inPortfolio: p.id).map(\.ticker) == ["MSFT"])

        // Deleted transactions no longer block the deletion.
        for t in try await repo.store.transactions(ofHolding: used.id) { try await repo.deleteTransaction(t.id) }
        try await repo.deleteHolding(used.id)
        #expect(try await repo.store.holdings(inPortfolio: p.id).isEmpty)
    }

    @Test func reAddingDeletedTickerRevivesSameIdentity() async throws {
        let repo = try await makeRepository()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "P"))
        let h = try await repo.addHolding(HoldingDraft(ticker: "T", currency: .usd), to: p.id).holding
        try await repo.deleteHolding(h.id)
        let revived = try await repo.addHolding(HoldingDraft(ticker: "t", currency: .usd), to: p.id)
        #expect(!revived.alreadyExisted && revived.holding.id == h.id && revived.holding.version.revision == 3)
    }

    @Test func portfolioDeleteTombstonesEverythingInIt() async throws {
        let repo = try await makeRepository()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "Doomed"))
        let keep = try await repo.createPortfolio(PortfolioDraft(name: "Kept"))
        let h = try await repo.addHolding(HoldingDraft(ticker: "VTI", currency: .usd), to: p.id).holding
        let t = try await repo.addTransaction(TransactionDraft(kind: .buy, date: date("2024-05-01"), quantity: 1, unitPrice: 1,
                                                               currency: .usd), to: h.id)
        try await repo.saveGoals(GoalScopeDraft(scope: .holding, targets: [GoalTarget(key: "VTI", percent: 100)]), for: p.id)
        let other = try await repo.addHolding(HoldingDraft(ticker: "VTI", currency: .usd), to: keep.id).holding

        try await repo.deletePortfolio(p.id)

        #expect(try await repo.store.portfolios().map(\.id) == [keep.id])
        #expect(try await repo.store.liveChildren(ofPortfolio: p.id).isEmpty)
        #expect(try await repo.store.transaction(t.id)?.isDeleted == true)
        #expect(try await repo.store.holding(h.id)?.isDeleted == true)
        #expect(try await repo.store.goals(inPortfolio: p.id, includingDeleted: true).allSatisfy(\.isDeleted))
        #expect(try await repo.store.holding(other.id)?.isDeleted == false)
        let outbox = Set(try await repo.store.keysNeedingUpload())
        #expect(outbox.isSuperset(of: [RecordKey(entity: .portfolio, id: p.id), RecordKey(entity: .holding, id: h.id),
                                       RecordKey(entity: .transaction, id: t.id)]))
    }

    @Test func goalScopeReplacementUpsertsAndTombstones() async throws {
        let repo = try await makeRepository()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "P"))
        let first = try await repo.saveGoals(GoalScopeDraft(scope: .assetClass, targets: [
            GoalTarget(key: "stock", percent: 40), GoalTarget(key: "bond", percent: 60),
        ]), for: p.id)
        try await repo.saveGoals(GoalScopeDraft(scope: .holding, targets: [
            GoalTarget(key: "vti", percent: 70), GoalTarget(key: "BND", percent: 30),
        ]), for: p.id)

        let second = try await repo.saveGoals(GoalScopeDraft(scope: .assetClass, targets: [
            GoalTarget(key: "Stock", percent: 50), GoalTarget(key: "cash", percent: 50),
        ]), for: p.id)
        let stock = try #require(second.first { $0.key == "stock" })
        #expect(second.filter { $0.key == "stock" }.count == 1)
        #expect(stock.targetPercent == 50 && stock.id == first.first { $0.key == "stock" }?.id)
        #expect(stock.version.revision == 2)
        #expect(Set(second.map(\.key)) == ["stock", "cash"])
        let bond = try #require(try await repo.store.goals(inPortfolio: p.id, includingDeleted: true).first { $0.key == "bond" })
        #expect(bond.isDeleted)

        // Clearing the holding scope leaves asset-class goals alone.
        #expect(try await repo.saveGoals(GoalScopeDraft(scope: .holding, targets: []), for: p.id).isEmpty)
        let live = try await repo.store.goals(inPortfolio: p.id)
        #expect(live.allSatisfy { $0.scope == .assetClass } && live.count == 2)

        await #expect(throws: ValidationError.self) {
            try await repo.saveGoals(GoalScopeDraft(scope: .assetClass, targets: [
                GoalTarget(key: "stock", percent: 60), GoalTarget(key: "bond", percent: 30),
            ]), for: p.id)
        }
        #expect(try await repo.store.goals(inPortfolio: p.id).count == 2)
    }

    @Test func csvImportCreatesHoldingsAndTransactionsTogether() async throws {
        let repo = try await makeRepository()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "P"))
        let csv = """
        ticker,type,date,shares,price,currency
        AAPL,buy,2024-01-02,10,"185,5",USD
        VTI,transfer,2024-01-03,1,1,USD
        KO,dividend,2024-04-01,,12.5,USD
        """
        let plan = try await repo.importFile(csv, into: p.id)
        #expect(plan.added == 2 && plan.errors.count == 1 && plan.errors[0].line == 3)
        #expect(try await repo.store.holdings(inPortfolio: p.id).map(\.ticker) == ["AAPL", "KO"])
        #expect(try await repo.store.transactions(inPortfolio: p.id).count == 2)
    }

    func ibkrFixture() throws -> String {
        try String(contentsOf: fixtureURL("ibkr-aug-oct.csv"), encoding: .utf8)
    }

    func shares(_ repo: PortfolioRepository, _ portfolioID: UUID) async throws -> [String: Decimal] {
        let positions = PositionCalculator.positions(holdings: try await repo.store.holdings(inPortfolio: portfolioID),
                                                     transactions: try await repo.store.transactions(inPortfolio: portfolioID))
        return Dictionary(uniqueKeysWithValues: positions.map { ($0.ticker, $0.shares) })
    }

    @Test func ibkrImportTwiceIsStable() async throws {
        let repo = try await makeRepository()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "P"))
        let first = try await repo.importFile(try ibkrFixture(), into: p.id)
        let second = try await repo.importFile(try ibkrFixture(), into: p.id)
        #expect(first.added == 4 && second.added == 4 && second.replaced == 4)
        let live = try await repo.store.transactions(inPortfolio: p.id)
        #expect(live.filter { $0.openingBalance == nil }.count == 4)
        #expect(live.filter { $0.openingBalance != nil }.count == 4) // AIFS, EMIM, SXR8, VWCE
        #expect(try await shares(repo, p.id) == ["AIFS.DE": 12, "EMIM.AS": 7, "SXR8.DE": 2, "VWCE.DE": 30, "XEON.DE": 4,
                                                 "PBR271217C00027000": 4])
    }

    @Test func handEditedImportIsOverwritten() async throws {
        let repo = try await makeRepository()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "P"))
        try await repo.importFile(try ibkrFixture(), into: p.id)
        let vwce = try #require(try await repo.store.transactions(inPortfolio: p.id)
            .first { $0.date == date("2026-08-14") })
        let edited = try await repo.updateTransaction(vwce.id, TransactionDraft(
            kind: .buy, date: vwce.date, quantity: 10, unitPrice: 999, fee: vwce.fee, currency: .eur))
        #expect(edited.importSource == .ibkr)
        try await repo.importFile(try ibkrFixture(), into: p.id)
        let after = try await repo.store.transactions(inPortfolio: p.id).filter { $0.date == date("2026-08-14") }
        #expect(after.count == 1 && after.first?.unitPrice == 100)
    }

    @Test func outboxClearsOnlyForUploadedVersion() async throws {
        let repo = try await makeRepository()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "P"))
        let key = RecordKey(entity: .portfolio, id: p.id)
        #expect(try await repo.store.keysNeedingUpload() == [key])
        let newer = try await repo.updatePortfolio(p.id, PortfolioDraft(name: "Q"))
        try await repo.store.markUploaded(key, version: p.version)
        #expect(try await repo.store.keysNeedingUpload() == [key])
        try await repo.store.markUploaded(key, version: newer.version)
        #expect(try await repo.store.keysNeedingUpload().isEmpty)
    }

    @Test func newerSchemaPayloadLocksRecord() async throws {
        let repo = try await makeRepository()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "P"))
        var future = p
        future.version = p.version.bumped(at: p.version.modifiedAt.addingTimeInterval(60), deviceID: UUID())
        var json = try JSONSerialization.jsonObject(with: PayloadCodec.encode(future)) as! [String: Any]
        json["schemaVersion"] = 2
        let payload = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])

        #expect(try await repo.coordinator.receive(payload) == .deferUnknownSchema)
        #expect(try await repo.store.keysAwaitingAppUpdate() == [RecordKey(entity: .portfolio, id: p.id)])
        #expect(try await repo.store.keysNeedingUpload().isEmpty)
        await #expect(throws: PortfolioRepositoryError.readOnlyUntilAppUpdate) {
            try await repo.updatePortfolio(p.id, PortfolioDraft(name: "Edited"))
        }
    }

    @Test func deviceIDIsStable() async throws {
        let container = try PortfolioStore.makeContainer(inMemory: true)
        let a = try await PortfolioStore(modelContainer: container).deviceID()
        let b = try await PortfolioStore(modelContainer: container).deviceID()
        #expect(a == b)
    }

    @Test func engineStateRoundTrip() async throws {
        let store = PortfolioStore(modelContainer: try PortfolioStore.makeContainer(inMemory: true))
        #expect(try await store.syncEngineState() == nil)
        try await store.saveSyncEngineState(Data([1, 2]))
        try await store.saveSyncEngineState(Data([3]))
        #expect(try await store.syncEngineState() == Data([3]))
        try await store.saveSyncEngineState(nil)
        #expect(try await store.syncEngineState() == nil)
    }
}

/// Two SwiftData-backed devices exchanging records through the in-memory cloud.
@Suite struct PortfolioStoreSyncTests {
    @Test func concurrentEditsConvergeOnSwiftDataStores() async throws {
        let cloud = InMemoryCloud()
        let clock = TestClock()
        let a = try await makeRepository(clock: clock), b = try await makeRepository(clock: clock)
        let ta = InMemorySyncTransport(cloud: cloud), tb = InMemorySyncTransport(cloud: cloud)
        try await ta.connect(a.coordinator)
        try await tb.connect(b.coordinator)

        let p = try await a.createPortfolio(PortfolioDraft(name: "Shared"))
        try await ta.sync(); try await tb.sync()
        #expect(try await b.store.portfolio(p.id) == p)

        // Both Macs add the same ticker offline, and edit the portfolio concurrently.
        let ha = try await a.addHolding(HoldingDraft(ticker: "VTI", currency: .usd), to: p.id).holding
        let hb = try await b.addHolding(HoldingDraft(ticker: "vti", currency: .usd), to: p.id).holding
        #expect(ha.id == hb.id)
        try await a.addTransaction(TransactionDraft(kind: .buy, date: date("2024-01-02"), quantity: 1, unitPrice: 200,
                                                    currency: .usd), to: ha.id)
        try await b.addTransaction(TransactionDraft(kind: .buy, date: date("2024-01-03"), quantity: 2, unitPrice: 210,
                                                    currency: .usd), to: hb.id)
        try await a.updatePortfolio(p.id, PortfolioDraft(name: "From A"))
        try await b.updatePortfolio(p.id, PortfolioDraft(name: "From B"))

        for _ in 0..<3 { try await ta.sync(); try await tb.sync() }

        let recordsA = try await a.store.liveChildren(ofPortfolio: p.id).sorted { $0.key.description < $1.key.description }
        let recordsB = try await b.store.liveChildren(ofPortfolio: p.id).sorted { $0.key.description < $1.key.description }
        #expect(recordsA == recordsB)
        #expect(recordsA.filter { $0.entity == .holding }.count == 1)
        #expect(recordsA.filter { $0.entity == .transaction }.count == 2)
        let portfolioA = try await a.store.portfolio(p.id), portfolioB = try await b.store.portfolio(p.id)
        #expect(portfolioA == portfolioB)
        #expect(try await a.store.keysNeedingUpload().isEmpty)
        #expect(try await b.store.keysNeedingUpload().isEmpty)
    }
}

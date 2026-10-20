import Foundation
import Testing
import YanaDomain
@testable import YanaSync

/// One simulated Mac: a store, a coordinator, and a transport to the shared fake cloud.
private struct Device {
    let id: UUID
    let store = InMemoryRecordStore()
    let coordinator: SyncCoordinator
    let transport: InMemorySyncTransport

    init(_ id: UUID, cloud: InMemoryCloud, clock: Clock) async throws {
        self.id = id
        coordinator = SyncCoordinator(deviceID: id, store: store, now: { clock.next() })
        transport = InMemorySyncTransport(cloud: cloud)
        try await transport.connect(coordinator)
    }

    @discardableResult
    func edit<R: SyncableRecord>(_ record: R) async throws -> R {
        let saved = try await coordinator.commitLocalEdits([AnyRecord(record)])[0]
        switch saved {
        case .portfolio(let r): return r as! R
        case .holding(let r): return r as! R
        case .transaction(let r): return r as! R
        case .goal(let r): return r as! R
        }
    }

    func current<R: SyncableRecord>(_ record: R) async -> R {
        let key = AnyRecord(record).key
        switch await store.record(for: key)! {
        case .portfolio(let r): return r as! R
        case .holding(let r): return r as! R
        case .transaction(let r): return r as! R
        case .goal(let r): return r as! R
        }
    }

    func sync() async throws { try await transport.sync() }
}

/// Strictly increasing timestamps, one second apart.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = t0
    func next() -> Date {
        lock.lock(); defer { lock.unlock() }
        t = t.addingTimeInterval(1)
        return t
    }
}

private func world() async throws -> (InMemoryCloud, Device, Device) {
    let cloud = InMemoryCloud()
    let clock = Clock()
    return (cloud, try await Device(deviceA, cloud: cloud, clock: clock), try await Device(deviceB, cloud: cloud, clock: clock))
}

private func syncAll(_ devices: Device...) async throws {
    for _ in 0..<2 { for d in devices { try await d.sync() } }
}

private func expectConverged(_ a: Device, _ b: Device, _ cloud: InMemoryCloud,
                             sourceLocation: SourceLocation = #_sourceLocation) async throws {
    let ra = await a.store.records, rb = await b.store.records
    #expect(ra == rb, sourceLocation: sourceLocation)
    #expect(try await cloud.decodedRecords() == ra, sourceLocation: sourceLocation)
    #expect(await a.store.keysNeedingUpload().isEmpty, sourceLocation: sourceLocation)
    #expect(await b.store.keysNeedingUpload().isEmpty, sourceLocation: sourceLocation)
}

private func newPortfolio() -> PortfolioRecord {
    PortfolioRecord(id: pid, name: "Long term", createdAt: t0, version: .initial(at: t0, deviceID: deviceA))
}

private func newHolding(_ ticker: String) -> HoldingRecord {
    HoldingRecord(id: RecordIdentity.holdingID(portfolioID: pid, ticker: ticker), portfolioID: pid, ticker: ticker,
                  currency: .usd, createdAt: t0, version: .initial(at: t0, deviceID: deviceA))
}

private func newBuy(_ h: HoldingRecord, qty: Decimal, price: Decimal) -> TransactionRecord {
    TransactionRecord(id: UUID(), portfolioID: pid, holdingID: h.id, kind: .buy, date: LocalDate(string: "2024-05-01")!,
                      quantity: qty, unitPrice: price, currency: .usd, createdAt: t0,
                      version: .initial(at: t0, deviceID: deviceA))
}

@Suite struct TwoDeviceSimulationTests {
    @Test func concurrentOfflineEditsConverge() async throws {
        let (cloud, a, b) = try await world()
        try await a.edit(newPortfolio())
        let h = try await a.edit(newHolding("MSFT"))
        var t = try await a.edit(newBuy(h, qty: 10, price: 100))
        try await syncAll(a, b)

        // Both offline: A changes the price, B changes the fee.
        t.unitPrice = 101
        try await a.edit(t)
        var tb = await b.current(t)
        tb.fee = 2
        try await b.edit(tb)
        try await a.sync()
        try await b.sync()
        try await syncAll(a, b)

        try await expectConverged(a, b, cloud)
        let final = await a.current(t)
        // Same revision from the same base; B edited later, so B's version wins whole-record.
        #expect(final.fee == 2 && final.unitPrice == 100)
    }

    @Test func deleteBeatsStaleEdit() async throws {
        let (cloud, a, b) = try await world()
        try await a.edit(newPortfolio())
        let h = try await a.edit(newHolding("KO"))
        let t = try await a.edit(newBuy(h, qty: 1, price: 50))
        try await syncAll(a, b)

        // B edits offline first; A deletes later (both from the same base revision).
        var stale = await b.current(t)
        stale.notes = "edited on B"
        try await b.edit(stale)
        var deleted = await a.current(t)
        deleted.deletedAt = t0.addingTimeInterval(100)
        try await a.edit(deleted)
        try await a.sync()
        try await b.sync()
        try await syncAll(a, b)

        try await expectConverged(a, b, cloud)
        #expect(await a.current(t).isDeleted)
    }

    @Test func staleEditUploadedFirstStillLosesToLaterDelete() async throws {
        let (cloud, a, b) = try await world()
        try await a.edit(newPortfolio())
        let h = try await a.edit(newHolding("KO"))
        let t = try await a.edit(newBuy(h, qty: 1, price: 50))
        try await syncAll(a, b)

        var stale = await b.current(t)
        stale.notes = "edited on B"
        try await b.edit(stale)
        var deleted = await a.current(t)
        deleted.deletedAt = t0.addingTimeInterval(100)
        try await a.edit(deleted)
        try await b.sync() // B's edit reaches the server before A's delete.
        try await a.sync()
        try await syncAll(a, b)

        try await expectConverged(a, b, cloud)
        #expect(await b.current(t).isDeleted)
    }

    @Test func sameTickerOnBothDevicesMergesIntoOneHolding() async throws {
        let (cloud, a, b) = try await world()
        try await a.edit(newPortfolio())
        try await syncAll(a, b)

        let ha = try await a.edit(newHolding("MSFT"))
        try await a.edit(newBuy(ha, qty: 1, price: 300))
        let hb = try await b.edit(newHolding(" msft "))
        try await b.edit(newBuy(hb, qty: 2, price: 310))
        try await syncAll(a, b)

        try await expectConverged(a, b, cloud)
        let live = await a.store.liveRecords()
        let holdings = live.filter { $0.entity == .holding }
        let buys = live.filter { $0.entity == .transaction }
        #expect(holdings.count == 1)
        #expect(buys.count == 2 && buys.allSatisfy { if case .transaction(let t) = $0 { t.holdingID == ha.id } else { false } })
    }

    @Test func transactionBeforeHoldingIsKept() async throws {
        let cloud = InMemoryCloud()
        let clock = Clock()
        let b = try await Device(deviceB, cloud: cloud, clock: clock)
        let h = newHolding("VTI")
        let t = newBuy(h, qty: 3, price: 200)

        // Deliver the child first, then the parents.
        #expect(try await b.coordinator.receive(PayloadCodec.encode(t)) == .applyIncoming)
        #expect(await b.store.record(for: AnyRecord(t).key) != nil)
        try await b.coordinator.receive(PayloadCodec.encode(h))
        try await b.coordinator.receive(PayloadCodec.encode(newPortfolio()))

        let records = await b.store.records
        #expect(records.count == 3)
        let txns = records.values.compactMap { if case .transaction(let x) = $0 { x } else { nil } }
        let holdings = records.values.compactMap { if case .holding(let x) = $0 { x } else { nil } }
        #expect(PositionCalculator.positions(holdings: holdings, transactions: txns).first?.shares == 3)
        #expect(await b.store.keysNeedingUpload().isEmpty)
    }

    @Test func portfolioDeleteCascadesIncludingChildrenCreatedOffline() async throws {
        let (cloud, a, b) = try await world()
        let p = try await a.edit(newPortfolio())
        let h = try await a.edit(newHolding("KO"))
        try await a.edit(newBuy(h, qty: 1, price: 1))
        try await syncAll(a, b)

        // A deletes the portfolio (tombstoning the children it knows); B, offline, adds a new holding and buy.
        var gone = await a.current(p)
        gone.deletedAt = t0.addingTimeInterval(500)
        let children = await a.store.liveChildren(ofPortfolio: p.id)
        try await a.coordinator.commitLocalEdits(
            [AnyRecord(gone)] + children.map { var c = $0; c.deletedAt = t0.addingTimeInterval(500); return c })
        let pepsi = try await b.edit(newHolding("PEP"))
        try await b.edit(newBuy(pepsi, qty: 5, price: 1))
        try await a.sync()
        try await b.sync()
        try await syncAll(a, b)

        try await expectConverged(a, b, cloud)
        #expect(await a.store.liveRecords().isEmpty)
        #expect(await b.store.liveRecords().isEmpty)
    }

    @Test func outboxSurvivesRestart() async throws {
        let cloud = InMemoryCloud()
        let clock = Clock()
        let store = InMemoryRecordStore()
        // First launch: an edit is saved, then the app quits before any transport existed.
        let offline = SyncCoordinator(deviceID: deviceA, store: store, now: { clock.next() })
        try await offline.commitLocalEdits([AnyRecord(newPortfolio())])
        // Relaunch with a connection: attaching re-enqueues the outbox.
        let relaunched = SyncCoordinator(deviceID: deviceA, store: store, now: { clock.next() })
        let transport = InMemorySyncTransport(cloud: cloud)
        try await transport.connect(relaunched)
        #expect(await transport.pendingCount == 1)
        try await transport.sync()
        #expect(await cloud.records.count == 1)
        #expect(await store.keysNeedingUpload().isEmpty)
    }

    @Test func editDuringUploadStaysQueued() async throws {
        let store = InMemoryRecordStore()
        let coordinator = SyncCoordinator(deviceID: deviceA, store: store)
        let p = try await coordinator.commitLocalEdits([AnyRecord(newPortfolio())])[0]
        let sent = try await coordinator.outgoingRecord(for: p.key)!
        try await coordinator.commitLocalEdits([p]) // edited again before the send completes
        try await coordinator.didUpload(p.key, version: sent.version)
        #expect(await store.keysNeedingUpload() == [p.key])
    }

    @Test func newerSchemaRecordIsPreservedAndNotOverwritten() async throws {
        let (cloud, a, _) = try await world()
        let p = try await a.edit(newPortfolio())
        try await a.sync()
        var object = try JSONSerialization.jsonObject(with: PayloadCodec.encode(p)) as! [String: Any]
        object["schemaVersion"] = 2
        var version = object["version"] as! [String: Any]
        version["revision"] = 9
        object["version"] = version
        let future = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(try await a.coordinator.receive(future) == .deferUnknownSchema)
        #expect(await a.store.keysAwaitingAppUpdate() == [AnyRecord(p).key])
        #expect(await a.current(p) == p)
        #expect(try await a.coordinator.outgoingRecord(for: AnyRecord(p).key) == nil)
        _ = cloud
    }
}

import Foundation
import Testing
@testable import YanaDomain

@Suite struct OpeningBalanceTests {
    func augOct() throws -> ImportBatch { try IBKRStatementParser.batch(from: try fixture("ibkr-aug-oct.csv")) }

    /// A Jun–Sep statement consistent with the Aug–Oct fixture: the 20 VWCE held on Aug 3 were bought on Jun 10.
    func junSep() -> ImportBatch {
        batch("2026-06-01", "2026-09-30",
              rows: [row("VWCE.DE", .buy, "2026-06-10", qty: "20", price: "90"),
                     row("VWCE.DE", .buy, "2026-08-14", qty: "10", price: "100", fee: "1.25"),
                     row("PBR271217C00027000", .buy, "2026-09-25", qty: "1", price: "2", fee: "1", currency: .usd),
                     row("PBR271217C00027000", .buy, "2026-09-25", qty: "3", price: "2.5", fee: "1", currency: .usd)],
              positions: [ImportedPosition(ticker: "VWCE.DE", quantity: 30, costBasis: dec("2801.25")),
                          ImportedPosition(ticker: "PBR271217C00027000", quantity: 4, costBasis: 952),
                          ImportedPosition(ticker: "AIFS.DE", quantity: 12, costBasis: 120),
                          ImportedPosition(ticker: "EMIM.AS", quantity: 7, costBasis: 280),
                          ImportedPosition(ticker: "SXR8.DE", quantity: 2, costBasis: 1000)])
    }

    func liveOpening(_ ledger: Ledger, _ ticker: String) -> TransactionRecord? {
        let h = ledger.holdings.first { $0.ticker == ticker }!
        return ledger.live.first { $0.holdingID == h.id && $0.openingBalance != nil }
    }

    @Test func vwceOpeningFromSample() throws {
        var ledger = Ledger()
        ledger.importing(try augOct())
        let opening = try #require(liveOpening(ledger, "VWCE.DE"))
        #expect(opening.kind == .buy && opening.date == day("2026-08-03") && opening.quantity == 20)
        #expect(opening.unitPrice == (dec("2801.25") - dec("1001.25")) / 20)
        #expect(opening.unitPrice == 90)
        #expect(opening.importSource == .ibkr && opening.notes == "Opening balance")
        #expect(opening.openingBalance == OpeningBalance(asOf: day("2026-10-19"), targetQuantity: 30,
                                                         targetCostBasis: dec("2801.25"),
                                                         coveredFrom: day("2026-08-03")))
        let p = ledger.position("VWCE.DE")
        #expect(p.shares == 30 && p.costBasis.rounded(scale: 6) == dec("2801.25"))
    }

    @Test func heldOnlyPositionsGetFullOpening() throws {
        var ledger = Ledger()
        ledger.importing(try augOct())
        let sxr8 = try #require(liveOpening(ledger, "SXR8.DE"))
        #expect(sxr8.quantity == 2 && sxr8.unitPrice == 500)
        #expect(ledger.position("EMIM.AS").shares == 7 && ledger.position("AIFS.DE").shares == 12)
    }

    @Test func optionOpeningIsZero() throws {
        var ledger = Ledger()
        ledger.importing(try augOct())
        #expect(liveOpening(ledger, "PBR271217C00027000") == nil)
        #expect(liveOpening(ledger, "XEON.DE") == nil)
        let pbr = ledger.position("PBR271217C00027000")
        #expect(pbr.shares == 4 && pbr.costBasis == 952)
    }

    @Test func earlierStatementShrinksOpening() throws {
        var ledger = Ledger()
        ledger.importing(try augOct())
        ledger.importing(junSep(), at: epoch.addingTimeInterval(60))
        #expect(liveOpening(ledger, "VWCE.DE") == nil)
        let p = ledger.position("VWCE.DE")
        #expect(p.shares == 30 && p.costBasis.rounded(scale: 6) == dec("2801.25"))
        #expect(liveOpening(ledger, "SXR8.DE")?.date == day("2026-06-01"))
    }

    @Test func openingIsOrderIndependent() throws {
        var a = Ledger(), b = Ledger()
        a.importing(try augOct())
        a.importing(junSep(), at: epoch.addingTimeInterval(60))
        b.importing(junSep())
        b.importing(try augOct(), at: epoch.addingTimeInterval(60))
        #expect(Set(a.holdings.map(\.ticker)) == Set(b.holdings.map(\.ticker)))
        for ticker in a.holdings.map(\.ticker) {
            let pa = a.position(ticker), pb = b.position(ticker)
            #expect(pa.shares == pb.shares, "\(ticker)")
            #expect(pa.costBasis.rounded(scale: 6) == pb.costBasis.rounded(scale: 6), "\(ticker)")
        }
        #expect(a.position("XEON.DE").shares == 4 && b.position("VWCE.DE").shares == 30)
    }

    @Test func olderStatementKeepsNewerTarget() throws {
        var ledger = Ledger()
        ledger.importing(try augOct())
        ledger.importing(batch("2026-01-01", "2026-03-31", rows: [],
                               positions: [ImportedPosition(ticker: "VWCE.DE", quantity: 5, costBasis: 500)]),
                         at: epoch.addingTimeInterval(60))
        let opening = try #require(liveOpening(ledger, "VWCE.DE"))
        #expect(opening.openingBalance?.targetQuantity == 30 && opening.openingBalance?.asOf == day("2026-10-19"))
        #expect(opening.date == day("2026-01-01"))
        #expect(ledger.position("VWCE.DE").shares == 30)
    }

    @Test func soldOutHoldingTargetsZero() {
        var ledger = Ledger()
        ledger.importing(batch("2026-01-01", "2026-03-31", rows: [row("OLD.DE", .buy, "2026-02-01", qty: "5", price: "10")],
                               positions: [ImportedPosition(ticker: "OLD.DE", quantity: 5, costBasis: 50)]))
        let plan = ledger.importing(batch("2026-04-01", "2026-06-30",
                                          rows: [row("OLD.DE", .sell, "2026-05-01", qty: "5", price: "12")],
                                          positions: []), at: epoch.addingTimeInterval(60))
        #expect(plan.warnings.isEmpty)
        #expect(ledger.position("OLD.DE").shares == 0)
        #expect(liveOpening(ledger, "OLD.DE") == nil)
    }

    @Test func negativeOpeningWarns() {
        var ledger = Ledger()
        let plan = ledger.importing(batch("2026-01-01", "2026-03-31",
                                          rows: [row("X.DE", .buy, "2026-02-01", qty: "5", price: "10")],
                                          positions: [ImportedPosition(ticker: "X.DE", quantity: 3, costBasis: 30)]))
        #expect(plan.warnings.map(\.message) == ["X.DE: imported trades don't reconcile with the statement (-2 shares)"])
        #expect(liveOpening(ledger, "X.DE") == nil)
        #expect(ledger.position("X.DE").shares == 5)
    }

    @Test func openingSortsBeforeSameDayTrade() throws {
        var ledger = Ledger()
        ledger.importing(batch("2026-08-03", "2026-10-19", rows: [row("S.DE", .sell, "2026-08-03", qty: "5", price: "60")],
                               positions: [ImportedPosition(ticker: "S.DE", quantity: 15, costBasis: 750)]))
        let opening = try #require(liveOpening(ledger, "S.DE"))
        #expect(opening.quantity == 20 && opening.unitPrice == 50)
        let p = ledger.position("S.DE")
        #expect(p.shares == 15 && p.costBasis == 750)
    }

    @Test func gapFoldsIntoOpening() {
        var ledger = Ledger()
        ledger.importing(batch("2026-01-01", "2026-03-31", rows: [row("G.DE", .buy, "2026-01-10", qty: "10", price: "10")],
                               positions: [ImportedPosition(ticker: "G.DE", quantity: 10, costBasis: 100)]))
        ledger.importing(batch("2026-06-01", "2026-08-31", rows: [row("G.DE", .buy, "2026-07-01", qty: "2", price: "20")],
                               positions: [ImportedPosition(ticker: "G.DE", quantity: 15, costBasis: 170)]),
                         at: epoch.addingTimeInterval(60))
        let p = ledger.position("G.DE")
        #expect(p.shares == 15 && p.costBasis.rounded(scale: 6) == 170)
        #expect(liveOpening(ledger, "G.DE")?.date == day("2026-01-01"))
    }

    @Test func gapClosedHoldingIsOrderIndependent() {
        let a = batch("2026-01-01", "2026-03-31", rows: [],
                      positions: [ImportedPosition(ticker: "Y.DE", quantity: 10, costBasis: 100),
                                  ImportedPosition(ticker: "Z.DE", quantity: 1, costBasis: 10)])
        let b = batch("2026-07-01", "2026-09-30", rows: [],
                      positions: [ImportedPosition(ticker: "Z.DE", quantity: 1, costBasis: 10)])
        var ab = Ledger(), ba = Ledger()
        ab.importing(a); ab.importing(b, at: epoch.addingTimeInterval(60))
        ba.importing(b); ba.importing(a, at: epoch.addingTimeInterval(60))
        #expect(ab.position("Y.DE").shares == 0)
        #expect(ba.position("Y.DE").shares == 0)
    }

    @Test func openingIDIsDeterministic() throws {
        var mac1 = Ledger(), mac2 = Ledger()
        mac1.importing(try augOct())
        mac2.importing(try augOct(), at: epoch.addingTimeInterval(5))
        let ids1 = Set(mac1.transactions.filter { $0.openingBalance != nil }.map(\.id))
        let ids2 = Set(mac2.transactions.filter { $0.openingBalance != nil }.map(\.id))
        #expect(!ids1.isEmpty && ids1 == ids2)
    }

    @Test func duplicateOpeningsAreCollapsed() throws {
        var ledger = Ledger()
        ledger.importing(try augOct())
        var copy = try #require(liveOpening(ledger, "SXR8.DE"))
        copy.id = UUID()
        ledger.transactions.append(copy)
        #expect(ledger.position("SXR8.DE").shares == 4)
        ledger.importing(try augOct(), at: epoch.addingTimeInterval(60))
        #expect(ledger.position("SXR8.DE").shares == 2)
    }

    @Test func shortRoundTripWarns() {
        var ledger = Ledger()
        let plan = ledger.importing(batch("2026-01-01", "2026-03-31",
                                          rows: [row("PBR271217C00027000", .sell, "2026-01-10", qty: "1", price: "1.5"),
                                                 row("PBR271217C00027000", .buy, "2026-02-10", qty: "1", price: "1")],
                                          positions: []))
        #expect(plan.warnings.map(\.message).contains(
            "PBR271217C00027000: sells more than was held; short positions are not supported"))
    }

    @Test func reimportLeavesOpeningsUnchanged() throws {
        var ledger = Ledger()
        ledger.importing(try augOct())
        let second = ledger.importing(try augOct(), at: epoch.addingTimeInterval(60))
        #expect(second.transactions.filter { $0.openingBalance != nil }.isEmpty)
    }
}

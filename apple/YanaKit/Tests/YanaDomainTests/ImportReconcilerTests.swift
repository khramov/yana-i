import Foundation
import Testing
@testable import YanaDomain

/// The portfolio's records after saving `plan`: plan records replace inputs with the same ID.
struct Ledger {
    var holdings: [HoldingRecord] = []
    var transactions: [TransactionRecord] = []

    mutating func apply(_ plan: ImportPlan) {
        for h in plan.holdings {
            if let i = holdings.firstIndex(where: { $0.id == h.id }) { holdings[i] = h } else { holdings.append(h) }
        }
        for t in plan.transactions {
            if let i = transactions.firstIndex(where: { $0.id == t.id }) { transactions[i] = t } else { transactions.append(t) }
        }
    }

    @discardableResult
    mutating func importing(_ batch: ImportBatch, at now: Date = epoch) -> ImportPlan {
        let plan = ImportReconciler.plan(batch, portfolioID: portfolioID, holdings: holdings, transactions: transactions,
                                         now: now, deviceID: deviceA)
        apply(plan)
        return plan
    }

    var live: [TransactionRecord] { transactions.filter { !$0.isDeleted } }

    func position(_ ticker: String) -> Position {
        let h = holdings.first { $0.ticker == ticker }!
        return PositionCalculator.position(for: h, transactions: transactions)
    }
}

func row(_ ticker: String, _ kind: TransactionKind, _ date: String, qty: String? = nil, price: String? = nil,
         amount: String? = nil, fee: String = "0", currency: Currency = .eur, line: Int = 2) -> ImportedRow {
    ImportedRow(line: line, ticker: ticker, kind: kind, date: day(date), quantity: qty.map(dec), unitPrice: price.map(dec),
                amount: amount.map(dec), fee: dec(fee), tax: 0, currency: currency, notes: nil)
}

func batch(_ from: String, _ to: String, source: ImportSource = .ibkr, rows: [ImportedRow],
           positions: [ImportedPosition]? = nil) -> ImportBatch {
    var tickers: [String] = []
    for t in rows.map(\.ticker) + (positions ?? []).map(\.ticker) where !tickers.contains(t) { tickers.append(t) }
    return ImportBatch(source: source, range: day(from)...day(to),
                       holdings: tickers.map { ImportedHolding(ticker: $0, name: nil, assetClass: .etf, currency: .eur,
                                                               multiplier: nil) },
                       rows: rows, positions: positions, errors: [], warnings: [])
}

@Suite struct ImportReconcilerTests {
    @Test func insertsBatchRows() {
        var ledger = Ledger()
        let plan = ledger.importing(batch("2026-01-01", "2026-01-31", source: .csv,
                                          rows: [row("VWCE.DE", .buy, "2026-01-05", qty: "2", price: "100"),
                                                 row("VWCE.DE", .buy, "2026-01-06", qty: "1", price: "101")]))
        #expect(plan.added == 2 && plan.replaced == 0 && plan.absorbed == 0)
        #expect(ledger.holdings.map(\.ticker) == ["VWCE.DE"])
        #expect(ledger.live.allSatisfy { $0.importSource == .csv })
        #expect(ledger.position("VWCE.DE").shares == 3)
    }

    @Test func replacesEarlierImportInRange() {
        var ledger = Ledger()
        ledger.importing(batch("2026-01-01", "2026-03-31", source: .csv,
                               rows: [row("A", .buy, "2026-01-05", qty: "1", price: "10"),
                                      row("A", .buy, "2026-03-05", qty: "1", price: "10")]))
        let plan = ledger.importing(batch("2026-02-01", "2026-03-31", source: .csv,
                                          rows: [row("A", .buy, "2026-03-05", qty: "2", price: "11")]))
        #expect(plan.replaced == 1 && plan.added == 1)
        #expect(ledger.live.map(\.date).sorted() == [day("2026-01-05"), day("2026-03-05")])
        #expect(ledger.live.first { $0.date == day("2026-03-05") }?.quantity == 2)
    }

    @Test func otherSourceUntouched() {
        var ledger = Ledger()
        ledger.importing(batch("2026-01-01", "2026-01-31", source: .csv, rows: [row("A", .buy, "2026-01-05", qty: "1", price: "10")]))
        let plan = ledger.importing(batch("2026-01-01", "2026-01-31", source: .ibkr,
                                          rows: [row("A", .buy, "2026-01-06", qty: "3", price: "10")]))
        #expect(plan.replaced == 0)
        #expect(ledger.live.count == 2)
    }

    @Test func simpleCSVReplacesOnlyItsTickers() {
        var ledger = Ledger()
        ledger.importing(batch("2026-01-01", "2026-01-31", source: .csv,
                               rows: [row("A", .buy, "2026-01-05", qty: "1", price: "10"),
                                      row("B", .buy, "2026-01-05", qty: "1", price: "10")]))
        let plan = ledger.importing(batch("2026-01-01", "2026-01-31", source: .csv,
                                          rows: [row("A", .buy, "2026-01-05", qty: "1", price: "10")]))
        #expect(plan.replaced == 1)
        #expect(ledger.position("B").shares == 1)
    }

    func handBuy(_ ledger: inout Ledger, _ ticker: String, _ date: String, qty: String, price: String) {
        let h = ledger.holdings.first { $0.ticker == ticker } ?? holding(ticker, currency: .eur)
        if !ledger.holdings.contains(where: { $0.id == h.id }) { ledger.holdings.append(h) }
        ledger.transactions.append(tx(h, .buy, date, qty: qty, price: price))
    }

    @Test func absorbsLookAlikeHandEntry() {
        var ledger = Ledger()
        handBuy(&ledger, "VWCE.DE", "2026-08-14", qty: "10", price: "101")
        let plan = ledger.importing(batch("2026-08-03", "2026-10-19",
                                          rows: [row("VWCE.DE", .buy, "2026-08-14", qty: "10", price: "100")]))
        #expect(plan.absorbed == 1)
        #expect(ledger.live.count == 1 && ledger.live[0].importSource == .ibkr && ledger.live[0].unitPrice == 100)
    }

    @Test func keepsDifferentHandEntry() {
        var ledger = Ledger()
        handBuy(&ledger, "VWCE.DE", "2026-08-14", qty: "5", price: "170")
        let plan = ledger.importing(batch("2026-08-03", "2026-10-19",
                                          rows: [row("VWCE.DE", .buy, "2026-08-14", qty: "10", price: "100")]))
        #expect(plan.absorbed == 0)
        #expect(ledger.live.count == 2)
    }

    @Test func oneFileRowAbsorbsOneHandEntry() {
        var ledger = Ledger()
        handBuy(&ledger, "VWCE.DE", "2026-08-14", qty: "10", price: "101")
        handBuy(&ledger, "VWCE.DE", "2026-08-14", qty: "10", price: "101")
        let plan = ledger.importing(batch("2026-08-03", "2026-10-19",
                                          rows: [row("VWCE.DE", .buy, "2026-08-14", qty: "10", price: "100")]))
        #expect(plan.absorbed == 1)
        #expect(ledger.live.count == 2)
    }

    @Test func reimportingSameBatchIsIdempotent() {
        var ledger = Ledger()
        let b = batch("2026-08-03", "2026-10-19", rows: [row("VWCE.DE", .buy, "2026-08-14", qty: "10", price: "100"),
                                                       row("XEON.DE", .buy, "2026-10-07", qty: "4", price: "140")])
        ledger.importing(b)
        let before = ledger.live.count
        let second = ledger.importing(b, at: epoch.addingTimeInterval(60))
        #expect(second.added == second.replaced && second.added == 2 && second.absorbed == 0)
        #expect(ledger.live.count == before)
        #expect(ledger.position("VWCE.DE").shares == 10)
    }

    @Test func simpleCSVWithBOMImports() throws {
        let plan = try ImportReconciler.plan(text: "\u{FEFF}ticker,type,date,shares,price\r\nVTI,buy,2024-01-10,1,240\r\n",
                                             portfolioID: portfolioID, holdings: [], transactions: [], now: epoch,
                                             deviceID: deviceA)
        #expect(plan.added == 1 && plan.errors.isEmpty)
        #expect(plan.holdings.map(\.ticker) == ["VTI"])
    }

    @Test func detectsIBKR() throws {
        let plan = try ImportReconciler.plan(text: try fixture("ibkr-aug-oct.csv"), portfolioID: portfolioID,
                                             holdings: [], transactions: [], now: epoch, deviceID: deviceA)
        #expect(plan.added == 4)
        #expect(plan.transactions.filter { $0.openingBalance == nil }.allSatisfy { $0.importSource == .ibkr })
        #expect(plan.holdings.first { $0.ticker == "PBR271217C00027000" }?.multiplier == 100)
    }

    @Test func warnsAboutBareTickerTwin() {
        var ledger = Ledger()
        ledger.holdings.append(holding("VWCE", currency: .eur))
        let plan = ledger.importing(batch("2026-08-03", "2026-10-19",
                                          rows: [row("VWCE.DE", .buy, "2026-08-14", qty: "10", price: "100")]))
        #expect(plan.warnings.map(\.message).contains("VWCE.DE: you also have a holding VWCE; merge them by hand"))
    }

    @Test func fillsMissingNameAndMultiplierOnly() {
        var ledger = Ledger()
        var own = holding("PBR271217C00027000", assetClass: .option, name: "My PBR call")
        own.multiplier = nil
        ledger.holdings.append(own)
        var b = batch("2026-08-03", "2026-10-19", rows: [row("PBR271217C00027000", .buy, "2026-09-25", qty: "1",
                                                           price: "2")])
        b.holdings = [ImportedHolding(ticker: "PBR271217C00027000", name: "PBR 17DEC27 27 C", assetClass: .option,
                                      currency: .usd, multiplier: 100)]
        ledger.importing(b)
        let h = ledger.holdings.first { $0.id == own.id }!
        #expect(h.name == "My PBR call" && h.multiplier == 100)
    }
}

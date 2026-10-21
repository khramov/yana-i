import Foundation
import Testing
@testable import YanaDomain

@Suite struct CSVImportPlannerTests {
    func plan(_ csv: String, existing: [HoldingRecord] = []) throws -> ImportPlan {
        ImportReconciler.plan(try CSVImportPlanner.batch(csv: csv), portfolioID: portfolioID, holdings: existing,
                              transactions: [], now: epoch, deviceID: deviceA)
    }

    @Test func twentyRowsThreeTickers() throws {
        var csv = "ticker,type,date,shares,price,fee,tax,currency,notes\n"
        for i in 0..<20 {
            let ticker = ["AAPL", "msft", " vti "][i % 3]
            csv += "\(ticker),buy,2024-01-\(String(format: "%02d", i + 1)),1,100,0,0,USD,\n"
        }
        let p = try plan(csv)
        #expect(p.holdings.map(\.ticker) == ["AAPL", "MSFT", "VTI"])
        #expect(p.added == 20)
        #expect(p.errors.count == 0)
        #expect(Set(p.transactions.map(\.holdingID)) == Set(p.holdings.map(\.id)))
    }

    @Test func badTypeRowCreatesNoHolding() throws {
        let p = try plan("""
            ticker,type,date,shares,price
            AAPL,buy,2024-01-02,10,100
            XYZ,transfer,2024-01-03,1,1
            """)
        #expect(p.holdings.map(\.ticker) == ["AAPL"])
        #expect(p.added == 1)
        #expect(p.errors == [CSVLineError(line: 3, message: "type: must be buy/sell/dividend/fee (got \"transfer\")")])
    }

    @Test func invalidRowAfterTypeCheckAlsoCreatesNoHolding() throws {
        let p = try plan("ticker,type,date,shares,price\nNEW,buy,2024-01-02,10,\n")
        #expect(p.holdings.isEmpty)
        #expect(p.errors == [CSVLineError(line: 2, message: "price: Price is required for buy and sell")])
    }

    @Test func missingRequiredColumns() {
        #expect(throws: CSVImportError(message: "CSV must include at least 'ticker', 'type' and 'date' columns")) {
            try plan("ticker,type,shares\nAAPL,buy,1\n")
        }
        #expect(throws: CSVImportError(message: "CSV must have a header row and at least one data row")) {
            try plan("ticker,type,date\n")
        }
    }

    @Test func dividendAndFeePriceBecomesAmount() throws {
        let p = try plan("""
            Ticker,Type,Date,Shares,Price,Fee,Tax,Currency,Notes
            KO,dividend,2024-04-01,50,"12,50",,"1,88",usd,Q1
            KO,fee,2024-04-02,,3,,,,
            """)
        let div = p.transactions[0], fee = p.transactions[1]
        #expect(div.amount == dec("12.5") && div.unitPrice == nil && div.quantity == 50 && div.tax == dec("1.88"))
        #expect(div.currency == .usd && div.notes == "Q1")
        #expect(fee.amount == 3 && fee.currency == .eur)
    }

    @Test func unsupportedCurrencyFallsBackToEUR() throws {
        let p = try plan("ticker,type,date,shares,price,currency\nBP.L,buy,2024-01-02,1,5,GBP\n")
        #expect(p.transactions.first?.currency == .eur)
        #expect(p.holdings.first?.currency == .eur)
    }

    @Test func webCompatibleQuotingCRLFAndDecimalComma() throws {
        let csv = "ticker,type,date,shares,price,notes\r\n\"AAPL\",buy,2024-01-02,\"1,5\",\"100,25\",\"said \"\"hi\"\", ok\"\r\n\r\n"
        let p = try plan(csv)
        let t = try #require(p.transactions.first)
        #expect(t.quantity == dec("1.5") && t.unitPrice == dec("100.25") && t.notes == "said \"hi\", ok")
    }

    @Test func existingHoldingIsReusedAndTombstoneIsRecreatedAboveIt() throws {
        var live = holding("AAPL")
        var gone = holding("MSFT")
        gone.version = RecordVersion(revision: 7, modifiedAt: epoch, deviceID: deviceB)
        gone.deletedAt = epoch
        live.version.revision = 3
        let p = try plan("ticker,type,date,shares,price\naapl,buy,2024-01-02,1,1\nMSFT,buy,2024-01-02,1,1\n",
                         existing: [live, gone])
        #expect(p.holdings.map(\.ticker) == ["MSFT"])
        #expect(p.holdings[0].version.revision == 8)
        #expect(p.holdings[0].deletedAt == nil)
        #expect(p.transactions[0].holdingID == live.id)
    }

    @Test func badNumbersAndMissingTicker() throws {
        let p = try plan("ticker,type,date,shares,price\n,buy,2024-01-02,1,1\nA,buy,2024-01-02,abc,1\nA,buy,2024-1-2,1,1\n")
        #expect(p.errors.map(\.message) == ["Missing ticker", "shares: must be a number", "date: Date must be YYYY-MM-DD"])
        #expect(p.errors.map(\.line) == [2, 3, 4])
    }

    @Test func sameDayRowsKeepFileOrder() throws {
        let p = try plan("ticker,type,date,shares,price\nA,buy,2024-01-02,10,1\nA,sell,2024-01-02,4,1\n")
        let h = p.holdings[0]
        #expect(PositionCalculator.position(for: h, transactions: p.transactions.reversed()).shares == 6)
    }
}

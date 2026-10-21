import Foundation
import Testing
@testable import YanaDomain

func fixture(_ name: String) throws -> String {
    let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent(name)
    return try String(contentsOf: url, encoding: .utf8)
}

@Suite struct IBKRStatementParserTests {
    func augOct() throws -> ImportBatch { try IBKRStatementParser.batch(from: try fixture("ibkr-aug-oct.csv")) }
    func dividends() throws -> ImportBatch { try IBKRStatementParser.batch(from: try fixture("ibkr-dividends.csv")) }

    @Test func parsesWithBOMAndCRLF() throws {
        // Foundation drops a BOM when decoding a file, so pass one explicitly as other text sources may not.
        let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("ibkr-aug-oct.csv")
        #expect(try Data(contentsOf: url).prefix(3) == Data([0xEF, 0xBB, 0xBF]))
        let text = "\u{FEFF}" + (try fixture("ibkr-aug-oct.csv"))
        #expect(text.contains("\r\n"))
        #expect(IBKRStatementParser.isStatement(text))
        let batch = try IBKRStatementParser.batch(from: text)
        #expect(batch.source == .ibkr)
        #expect(batch.range == day("2026-08-03")...day("2026-10-19"))
        #expect(!IBKRStatementParser.isStatement("ticker,type,date\nVTI,buy,2024-01-10\n"))
    }

    @Test func stockTradesMapToYahooTickers() throws {
        let rows = try augOct().rows
        #expect(rows.contains(ImportedRow(line: rows.first { $0.ticker == "VWCE.DE" }!.line, ticker: "VWCE.DE",
                                          kind: .buy, date: day("2026-08-14"), quantity: 10, unitPrice: 100,
                                          amount: nil, fee: dec("1.25"), tax: 0, currency: .eur, notes: nil)))
        let xeon = try #require(rows.first { $0.ticker == "XEON.DE" })
        #expect(xeon.kind == .buy && xeon.date == day("2026-10-07") && xeon.quantity == 4)
        #expect(xeon.unitPrice == 140 && xeon.fee == 1)
    }

    @Test func optionTradesUseOCCSymbol() throws {
        let batch = try augOct()
        let pbr = batch.rows.filter { $0.ticker == "PBR271217C00027000" }
        #expect(pbr.count == 2)
        #expect(pbr.map(\.quantity) == [1, 3])
        #expect(pbr.map(\.unitPrice) == [2, dec("2.5")])
        #expect(pbr.map(\.fee) == [1, 1])
        #expect(pbr.allSatisfy { $0.currency == .usd && $0.kind == .buy })
        let h = try #require(batch.holdings.first { $0.ticker == "PBR271217C00027000" })
        #expect(h.assetClass == .option && h.multiplier == 100 && h.name == "PBR 17DEC27 27 C" && h.currency == .usd)
    }

    @Test func forexIgnoredSilently() throws {
        let batch = try augOct()
        #expect(batch.rows.count == 4)
        #expect(!batch.rows.contains { $0.ticker.contains("EUR.USD") })
        #expect(batch.errors.isEmpty && batch.warnings.isEmpty)
    }

    @Test func instrumentsGiveAssetClassAndExchange() throws {
        let holdings = try augOct().holdings
        for ticker in ["EMIM.AS", "SXR8.DE", "AIFS.DE", "VWCE.DE", "XEON.DE"] {
            let h = try #require(holdings.first { $0.ticker == ticker }, "\(ticker)")
            #expect(h.assetClass == .etf && h.currency == .eur && h.multiplier == nil)
        }
        #expect(holdings.first { $0.ticker == "EMIM.AS" }?.name == "ISHARES CORE EM IMI ACC")
    }

    @Test func openPositions() throws {
        let positions = try #require(try augOct().positions)
        #expect(positions.count == 6)
        #expect(positions.contains(ImportedPosition(ticker: "VWCE.DE", quantity: 30, costBasis: dec("2801.25"))))
        #expect(positions.contains(ImportedPosition(ticker: "PBR271217C00027000", quantity: 4, costBasis: 952)))
    }

    @Test func dividendWithWithholding() throws {
        let div = try dividends().rows.filter { $0.kind == .dividend }
        #expect(div.count == 1)
        #expect(div.first?.ticker == "VWCE.DE" && div.first?.date == day("2026-03-25"))
        #expect(div.first?.amount == 14 && div.first?.tax == dec("2.1") && div.first?.currency == .eur)
    }

    @Test func unsupportedCurrencyIsLineError() throws {
        let batch = try dividends()
        #expect(batch.errors.map(\.line) == [5])
        #expect(!batch.rows.contains { $0.ticker.hasPrefix("VOD") })
    }

    @Test func corporateActionWarns() throws {
        let warnings = try dividends().warnings
        #expect(warnings.contains(CSVLineError(line: 13, message: "Corporate actions are not supported")))
    }

    @Test func thousandsSeparatorsInQuantities() throws {
        let text = """
        Statement,Header,Field Name,Field Value
        Statement,Data,Period,"January 1, 2026 - March 31, 2026"
        Trades,Header,DataDiscriminator,Asset Category,Currency,Symbol,Date/Time,Quantity,T. Price,C. Price,Proceeds,Comm/Fee,Basis,Realized P/L,MTM P/L,Code
        Trades,Data,Order,Stocks,USD,VTI,"2026-02-02, 10:00:00","-1,200",250.5,250,"300,600",-2,0,0,0,C
        Financial Instrument Information,Header,Asset Category,Symbol,Description,Conid,Security ID,Underlying,Listing Exch,Multiplier,Type,Code
        Financial Instrument Information,Data,Stocks,VTI,VANGUARD TOTAL STOCK MKT ETF,1,US9229087690,VTI,ARCA,1,ETF,
        """
        let row = try #require(try IBKRStatementParser.batch(from: text).rows.first)
        #expect(row.ticker == "VTI" && row.kind == .sell && row.quantity == 1200 && row.unitPrice == dec("250.5"))
    }

    @Test func withholdingAndDividendCorrectionsAreNetted() throws {
        let text = """
        Statement,Header,Field Name,Field Value
        Statement,Data,Period,"January 1, 2026 - March 31, 2026"
        Dividends,Header,Currency,Date,Description,Amount
        Dividends,Data,USD,2026-03-10,KO(US1912161007) Cash Dividend USD 0.51 per Share (Ordinary Dividend),100
        Dividends,Data,USD,2026-03-10,KO(US1912161007) Cash Dividend USD 0.51 per Share (Ordinary Dividend),-100
        Dividends,Data,USD,2026-03-10,KO(US1912161007) Cash Dividend USD 0.51 per Share (Ordinary Dividend),102
        Withholding Tax,Header,Currency,Date,Description,Amount,Code
        Withholding Tax,Data,USD,2026-03-10,KO(US1912161007) Cash Dividend USD 0.51 per Share - US Tax,-30,
        Withholding Tax,Data,USD,2026-03-10,KO(US1912161007) Cash Dividend USD 0.51 per Share - US Tax,30,
        Withholding Tax,Data,USD,2026-03-10,KO(US1912161007) Cash Dividend USD 0.51 per Share - US Tax,-15,
        Financial Instrument Information,Header,Asset Category,Symbol,Description,Conid,Security ID,Underlying,Listing Exch,Multiplier,Type,Code
        Financial Instrument Information,Data,Stocks,KO,COCA-COLA CO,1,US1912161007,KO,NYSE,1,COMMON,
        """
        let div = try IBKRStatementParser.batch(from: text).rows.filter { $0.kind == .dividend }
        #expect(div.count == 1)
        #expect(div.first?.amount == 102 && div.first?.tax == 15)
    }

    @Test func shortPositionWarns() throws {
        let text = """
        Statement,Header,Field Name,Field Value
        Statement,Data,Period,"January 1, 2026 - March 31, 2026"
        Open Positions,Header,DataDiscriminator,Asset Category,Currency,Symbol,Quantity,Mult,Cost Price,Cost Basis,Close Price,Value,Unrealized P/L,Code
        Open Positions,Data,Summary,Equity and Index Options,USD,PBR 17DEC27 27 C,-1,100,1.5,-150,1.2,-120,30,
        Financial Instrument Information,Header,Asset Category,Symbol,Description,Conid,Underlying,Listing Exch,Multiplier,Expiry,Delivery Month,Type,Strike,Code
        Financial Instrument Information,Data,Equity and Index Options,PBR   271217C00027000,PBR 17DEC27 27 C,1,PBR,CBOE,100,2027-12-17,2027-12,C,27,
        """
        let batch = try IBKRStatementParser.batch(from: text)
        #expect(batch.warnings.map(\.message) == ["PBR271217C00027000: short positions are not supported (-1)"])
    }

    @Test func missingPeriodThrows() {
        #expect(throws: CSVImportError.self) {
            try IBKRStatementParser.batch(from: "Statement,Header,Field Name,Field Value\nStatement,Data,Title,Activity Statement\n")
        }
    }

    @Test func exchangeSuffixes() {
        #expect(IBKRStatementParser.yahooSuffix(exchange: "IBIS2") == ".DE")
        #expect(IBKRStatementParser.yahooSuffix(exchange: "AEB") == ".AS")
        #expect(IBKRStatementParser.yahooSuffix(exchange: "LSEETF") == ".L")
        #expect(IBKRStatementParser.yahooSuffix(exchange: "NASDAQ") == "")
        #expect(IBKRStatementParser.yahooSuffix(exchange: "XYZ") == nil)
    }
}

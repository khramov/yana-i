import Foundation
import Testing
@testable import YanaDomain

@Suite struct CSVParserTests {
    @Test func plainRows() {
        #expect(CSVParser.parse("a,b,c\n1,2,3\n") == [CSVRow(line: 1, fields: ["a", "b", "c"]),
                                                      CSVRow(line: 2, fields: ["1", "2", "3"])])
    }

    @Test func quotedFieldsWithCommasAndEscapedQuotes() {
        let rows = CSVParser.parse("ticker,notes\nAAPL,\"bought, \"\"finally\"\"\"\n")
        #expect(rows[1].fields == ["AAPL", "bought, \"finally\""])
    }

    @Test func crlfAndLoneCR() {
        #expect(CSVParser.parse("a,b\r\n1,2\r\n").map(\.fields) == [["a", "b"], ["1", "2"]])
        #expect(CSVParser.parse("a,b\r1,2").map(\.fields) == [["a", "b"], ["1", "2"]])
    }

    @Test func blankLinesAreSkippedButLinesCounted() {
        let rows = CSVParser.parse("a,b\n\n , \n1,2")
        #expect(rows == [CSVRow(line: 1, fields: ["a", "b"]), CSVRow(line: 4, fields: ["1", "2"])])
    }

    @Test func quotedNewlineStaysInField() {
        let rows = CSVParser.parse("a,b\n\"x\ny\",2\n3,4")
        #expect(rows.map(\.fields) == [["a", "b"], ["x\ny", "2"], ["3", "4"]])
        #expect(rows.map(\.line) == [1, 2, 4])
    }

    @Test func noTrailingNewlineAndEmptyTrailingField() {
        #expect(CSVParser.parse("a,b\n1,").map(\.fields) == [["a", "b"], ["1", ""]])
    }

    @Test func numbers() {
        #expect(CSVParser.number("12,5") == .value(dec("12.5")))
        #expect(CSVParser.number(" 100 ") == .value(100))
        #expect(CSVParser.number("0.1") == .value(dec("0.1")))
        #expect(CSVParser.number("-3") == .value(-3))
        #expect(CSVParser.number("1e3") == .value(1000))
        #expect(CSVParser.number("") == .absent)
        #expect(CSVParser.number(nil) == .absent)
        #expect(CSVParser.number("abc") == .invalid)
        #expect(CSVParser.number("12abc") == .invalid)
        #expect(CSVParser.number("1.234,5") == .invalid)
    }
}

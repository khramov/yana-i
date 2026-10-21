import Foundation
import Testing
@testable import YanaDomain

private func issues(_ body: () throws -> Any) -> ValidationError? {
    do { _ = try body(); return nil } catch let e as ValidationError { return e } catch { return nil }
}

@Suite struct PortfolioValidationTests {
    @Test func multiplierMustBePositive() throws {
        for bad in [Decimal(0), Decimal(-1)] {
            #expect(throws: ValidationError([ValidationIssue(.multiplier, "Multiplier must be greater than 0")])) {
                try HoldingDraft(ticker: "PBR271217C00027000", assetClass: .option, multiplier: bad).validated()
            }
        }
        #expect(try HoldingDraft(ticker: "PBR271217C00027000", assetClass: .option, multiplier: 100).validated().multiplier == 100)
        #expect(try HoldingDraft(ticker: "VTI").validated().multiplier == nil)
    }

    @Test func defaultsToEUR() throws {
        let d = try PortfolioDraft(name: "Long term").validated()
        #expect(d.baseCurrency == .eur)
        #expect(d.name == "Long term")
    }

    @Test func trimsName() throws {
        #expect(try PortfolioDraft(name: "  Kids  ", baseCurrency: .usd).validated().name == "Kids")
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func rejectsEmptyName(_ name: String) {
        #expect(issues { try PortfolioDraft(name: name).validated() }?.message(for: .name) == "Name is required")
    }

    @Test func rejectsUnsupportedCurrency() throws {
        #expect(try Currency.validated(code: "usd") == .usd)
        #expect(issues { try Currency.validated(code: "GBP") }?.message(for: .currency) == "Currency must be one of EUR, USD, RUB")
    }
}

@Suite struct HoldingValidationTests {
    @Test func normalizesTickerAndDefaultsAssetClass() throws {
        let h = try HoldingDraft(ticker: " aapl ", name: "  ", sector: " Technology ", currency: .usd).validated()
        #expect(h.ticker == "AAPL")
        #expect(h.name == nil)
        #expect(h.sector == "Technology")
        #expect(h.assetClass == .stock)
    }

    @Test func acceptsExchangeSuffixes() throws {
        #expect(try HoldingDraft(ticker: "sber.me").validated().ticker == "SBER.ME")
        #expect(try HoldingDraft(ticker: "brk-b").validated().ticker == "BRK-B")
    }

    @Test(arguments: ["", "  ", "AA PL", "AAPL!"])
    func rejectsBadTickers(_ ticker: String) {
        #expect(issues { try HoldingDraft(ticker: ticker).validated() }?.message(for: .ticker) != nil)
    }
}

@Suite struct TransactionValidationTests {
    let date = day("2025-01-15")

    @Test func buyWithoutPriceFailsOnPrice() {
        let e = issues { try TransactionDraft(kind: .buy, date: date, quantity: 10).validated() }
        #expect(e?.message(for: .unitPrice) == "Price is required for buy and sell")
        #expect(e?.message(for: .quantity) == nil)
    }

    @Test func sellWithoutSharesFailsOnShares() {
        let e = issues { try TransactionDraft(kind: .sell, date: date, unitPrice: 130).validated() }
        #expect(e?.message(for: .quantity) == "Shares are required for buy and sell")
    }

    @Test func sellAtZeroRecordsAnExpiry() throws {
        let valid = try TransactionDraft(kind: .sell, date: date, quantity: 1, unitPrice: 0).validated()
        #expect(valid.unitPrice == 0)
        let e = issues { try TransactionDraft(kind: .sell, date: date, quantity: 1, unitPrice: -1).validated() }
        #expect(e?.message(for: .unitPrice) == "Price cannot be negative")
    }

    @Test func nonPositiveSharesAndPrice() {
        let e = issues { try TransactionDraft(kind: .buy, date: date, quantity: 0, unitPrice: -1).validated() }
        #expect(e?.message(for: .quantity) == "Shares must be greater than 0")
        #expect(e?.message(for: .unitPrice) == "Price must be greater than 0")
    }

    @Test func negativeFeeAndTax() {
        let e = issues { try TransactionDraft(kind: .buy, date: date, quantity: 1, unitPrice: 1, fee: -1, tax: -2).validated() }
        #expect(e?.message(for: .fee) == "Fee cannot be negative")
        #expect(e?.message(for: .tax) == "Tax cannot be negative")
    }

    @Test func missingDate() {
        #expect(issues { try TransactionDraft(kind: .buy, date: nil, quantity: 1, unitPrice: 1).validated() }?
            .message(for: .date) == "Date must be YYYY-MM-DD")
    }

    @Test func dividendRecordsGrossSharesAndTax() throws {
        let t = try TransactionDraft(kind: .dividend, date: date, quantity: 50, unitPrice: 9, amount: dec("12.50"),
                                     tax: dec("1.88"), currency: .usd).validated()
        #expect(t.amount == dec("12.50"))
        #expect(t.quantity == 50)
        #expect(t.tax == dec("1.88"))
        #expect(t.fee == 0)
        #expect(t.unitPrice == nil)
        #expect(t.currency == .usd)
    }

    @Test func dividendAndFeeNeedPositiveAmount() {
        #expect(issues { try TransactionDraft(kind: .dividend, date: date).validated() }?
            .message(for: .amount) == "Amount is required for dividends")
        #expect(issues { try TransactionDraft(kind: .fee, date: date, amount: 0).validated() }?
            .message(for: .amount) == "Amount must be greater than 0")
        #expect(issues { try TransactionDraft(kind: .dividend, date: date, quantity: -5, amount: 1).validated() }?
            .message(for: .quantity) == "Shares must be greater than 0")
    }

    @Test func feeClearsTradeFieldsAndBuyClearsAmount() throws {
        let fee = try TransactionDraft(kind: .fee, date: date, quantity: 3, unitPrice: 4, amount: 2, notes: "  ").validated()
        #expect(fee.quantity == nil && fee.unitPrice == nil && fee.notes == nil)
        let buy = try TransactionDraft(kind: .buy, date: date, quantity: 1, unitPrice: 2, amount: 9).validated()
        #expect(buy.amount == nil)
    }
}

@Suite struct GoalValidationTests {
    @Test func reportsCurrentSum() {
        let e = issues {
            try GoalScopeDraft(scope: .assetClass, targets: [GoalTarget(key: "stock", percent: 60),
                                                             GoalTarget(key: "bond", percent: 30)]).validated()
        }
        #expect(e?.message(for: .targets) == "Targets must add up to 100% (currently 90.0%)")
    }

    @Test func acceptsWithinTolerance() throws {
        let ok = try GoalScopeDraft(scope: .holding, targets: [GoalTarget(key: "vti", percent: dec("60.25")),
                                                                GoalTarget(key: "BND", percent: dec("40.2"))]).validated()
        #expect(ok.targets.map(\.key) == ["VTI", "BND"])
        #expect(issues {
            try GoalScopeDraft(scope: .holding, targets: [GoalTarget(key: "VTI", percent: dec("60.6")),
                                                          GoalTarget(key: "BND", percent: 40)]).validated()
        }?.message(for: .targets) == "Targets must add up to 100% (currently 100.6%)")
    }

    @Test func emptySetIsValid() throws {
        #expect(try GoalScopeDraft(scope: .holding, targets: []).validated().targets.isEmpty)
    }

    @Test func rejectsZeroDuplicateAndUnknownKeys() {
        #expect(issues { try GoalScopeDraft(scope: .assetClass, targets: [GoalTarget(key: "stock", percent: 100),
                                                                         GoalTarget(key: "bond", percent: 0)]).validated() }?
            .message(for: .targets) == "Target for bond must be greater than 0")
        #expect(issues { try GoalScopeDraft(scope: .holding, targets: [GoalTarget(key: "vti", percent: 50),
                                                                      GoalTarget(key: "VTI", percent: 50)]).validated() }?
            .message(for: .targets) == "VTI appears more than once")
        #expect(issues { try GoalScopeDraft(scope: .assetClass, targets: [GoalTarget(key: "crypto", percent: 100)]).validated() }?
            .message(for: .targets) == "crypto is not an asset class")
    }
}

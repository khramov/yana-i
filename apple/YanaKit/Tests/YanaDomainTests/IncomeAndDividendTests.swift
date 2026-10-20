import Foundation
import Testing
@testable import YanaDomain

/// 2025-07-01 12:00 UTC.
let july2025 = CalculationClock(now: day("2025-07-01").startOfDay(in: utcCalendar).addingTimeInterval(12 * 3600),
                                calendar: utcCalendar)

func event(_ ticker: String, ex: String? = nil, pay: String? = nil, perShare: String? = nil, annual: String? = nil,
           currency: Currency = .usd) -> DividendEvent {
    DividendEvent(ticker: ticker, exDividendDate: ex.map(day), paymentDate: pay.map(day),
                  amountPerShare: perShare.map(dec), annualRate: annual.map(dec),
                  frequency: .detect(annualRate: annual.map(dec), lastAmount: perShare.map(dec)),
                  currency: currency, fetchedAt: epoch)
}

@Suite struct IncomeCalculatorTests {
    @Test func monthlyBarsAndTrailingTwelveMonths() {
        let ko = holding("KO", currency: .usd)
        let txns = [tx(ko, .buy, "2024-01-02", qty: "100", price: "60"),
                    tx(ko, .dividend, "2025-03-15", amount: "20"),
                    tx(ko, .dividend, "2025-06-15", amount: "30"),
                    tx(ko, .dividend, "2025-06-20", amount: "10"),
                    tx(ko, .dividend, "2024-06-30", amount: "40")] // before the trailing window
        let s = IncomeCalculator.summary(portfolio: portfolio(.eur), holdings: [ko], transactions: txns,
                                         market: MarketSnapshot(fxRates: [fx(.usd, .eur, "0.9")]), clock: july2025)
        #expect(s.monthly == [MonthlyIncome(year: 2024, month: 6, amount: 36),
                              MonthlyIncome(year: 2025, month: 3, amount: 18),
                              MonthlyIncome(year: 2025, month: 6, amount: 36)])
        #expect(s.trailingTwelveMonths == 54)
        #expect(s.byHolding.first?.trailingTwelveMonths == 54)
    }

    @Test func trailingWindowIncludesSameDayLastYear() {
        let ko = holding("KO", currency: .eur)
        let s = IncomeCalculator.summary(portfolio: portfolio(), holdings: [ko],
                                         transactions: [tx(ko, .dividend, "2024-07-01", amount: "5")],
                                         market: .empty, clock: july2025)
        #expect(s.trailingTwelveMonths == 5)
    }

    @Test func forwardAnnualFromRateTimesShares() {
        let ko = holding("KO", currency: .usd)
        let s = IncomeCalculator.summary(portfolio: portfolio(.eur), holdings: [ko],
                                         transactions: [tx(ko, .buy, "2024-01-02", qty: "100", price: "60")],
                                         market: MarketSnapshot(fxRates: [fx(.usd, .eur, "0.9")],
                                                                dividendEvents: [event("KO", perShare: "0.51", annual: "2.04")]),
                                         clock: july2025)
        #expect(s.forwardAnnual == dec("183.6"))
        #expect(s.byHolding == [HoldingIncome(ticker: "KO", name: nil, trailingTwelveMonths: 0, forwardAnnual: dec("183.6"))])
        #expect(s.lastRefreshed == epoch)
    }

    @Test func forwardUnavailableWithoutRates() {
        let ko = holding("KO", currency: .eur)
        let s = IncomeCalculator.summary(portfolio: portfolio(), holdings: [ko],
                                         transactions: [tx(ko, .buy, "2024-01-02", qty: "1", price: "60")],
                                         market: .empty, clock: july2025)
        #expect(s.forwardAnnual == nil)
        #expect(s.lastRefreshed == nil)
        #expect(s.byHolding.isEmpty)
    }

    @Test func dividendWithoutFXIsSkippedAndReported() {
        let s = holding("SBER", currency: .rub)
        let r = IncomeCalculator.summary(portfolio: portfolio(.eur), holdings: [s],
                                         transactions: [tx(s, .dividend, "2025-05-01", amount: "1000")],
                                         market: .empty, clock: july2025)
        #expect(r.monthly.isEmpty)
        #expect(r.missingRates == [CurrencyPair(.rub, .eur)])
    }
}

@Suite struct DividendAnalyticsTests {
    @Test func perShareAndYieldOnCost() throws {
        let h = holding("T", currency: .usd)
        let txns = [tx(h, .buy, "2024-01-02", qty: "20", price: "25"),
                    tx(h, .dividend, "2025-04-01", qty: "20", amount: "10", tax: "1.5")]
        let a = DividendAnalytics(portfolio: portfolio(.usd), holdings: [h], transactions: txns, market: .empty, clock: july2025)
        let row = try #require(a.rows.first)
        #expect(row.perShare == dec("0.5"))
        #expect(row.yieldOnCost == 2)
        #expect(row.tax == dec("1.5"))
        #expect(a.totalAllTime == 10)
        #expect(a.portfolioYieldOnCost == 2)
    }

    @Test func totalsYearsAndFilter() {
        let h = holding("T", currency: .eur)
        let txns = [tx(h, .dividend, "2023-03-01", amount: "5"), tx(h, .dividend, "2024-12-01", amount: "7"),
                    tx(h, .dividend, "2025-02-01", amount: "11")]
        let all = DividendAnalytics(portfolio: portfolio(), holdings: [h], transactions: txns, market: .empty, clock: july2025)
        #expect(all.years == [2025, 2024, 2023])
        #expect(all.rows.map(\.gross) == [11, 7, 5])
        #expect(all.totalAllTime == 23)
        #expect(all.trailingTwelveMonths == 18)
        #expect(all.portfolioYieldOnCost == nil)
        let only2024 = DividendAnalytics(portfolio: portfolio(), holdings: [h], transactions: txns, market: .empty,
                                         clock: july2025, year: 2024)
        #expect(only2024.rows.map(\.gross) == [7])
        #expect(only2024.totalAllTime == 23)
    }

    @Test func upcomingDividendEstimate() throws {
        let ko = holding("KO", currency: .usd), old = holding("OLD", currency: .usd)
        let txns = [tx(ko, .buy, "2024-01-02", qty: "100", price: "60"), tx(old, .buy, "2024-01-02", qty: "1", price: "1")]
        let market = MarketSnapshot(fxRates: [fx(.usd, .eur, "0.9")],
                                    dividendEvents: [event("KO", ex: "2025-08-14", pay: "2025-10-01", perShare: "0.51"),
                                                     event("OLD", ex: "2025-03-01", pay: "2025-04-01", perShare: "1")])
        let a = DividendAnalytics(portfolio: portfolio(.eur), holdings: [ko, old], transactions: txns, market: market, clock: july2025)
        let next = try #require(a.upcoming.first)
        #expect(a.upcoming.count == 1)
        #expect(next.ticker == "KO")
        #expect(next.estimatedIncome == 51)
        #expect(next.estimatedIncomeBase == dec("45.9"))
    }
}

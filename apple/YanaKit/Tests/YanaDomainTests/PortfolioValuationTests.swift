import Foundation
import Testing
@testable import YanaDomain

func portfolio(_ base: Currency = .eur) -> PortfolioRecord {
    PortfolioRecord(id: portfolioID, name: "Long term", baseCurrency: base, createdAt: epoch,
                    version: .initial(at: epoch, deviceID: deviceA))
}

func quote(_ ticker: String, _ price: String, _ currency: Currency = .usd, at: Date = epoch) -> Quote {
    Quote(ticker: ticker, price: dec(price), currency: currency, fetchedAt: at)
}

func fx(_ from: Currency, _ to: Currency, _ rate: String) -> FXRate {
    FXRate(pair: CurrencyPair(from, to), rate: dec(rate), fetchedAt: epoch)
}

@Suite struct PortfolioValuationTests {
    @Test func mixedCurrencyPosition() {
        let h = holding("MSFT", currency: .usd)
        let v = PortfolioValuation(portfolio: portfolio(.eur), holdings: [h],
                                   transactions: [tx(h, .buy, "2024-01-01", qty: "10", price: "150")],
                                   market: MarketSnapshot(quotes: [quote("MSFT", "200")], fxRates: [fx(.usd, .eur, "0.9")]))
        #expect(v.positions.first?.marketValue == 1800)
        #expect(v.totalValue == 1800)
        #expect(v.costBasis == 1350)
        #expect(v.unrealizedGain == 450)
        #expect(v.returnPercent!.rounded(scale: 4) == dec("33.3333"))
    }

    @Test func missingPriceKeepsCostBasis() {
        let a = holding("AAA", currency: .eur)
        let b = holding("BBB", currency: .eur)
        let v = PortfolioValuation(portfolio: portfolio(.eur), holdings: [a, b],
                                   transactions: [tx(a, .buy, "2024-01-01", qty: "10", price: "10"),
                                                  tx(b, .buy, "2024-01-01", qty: "5", price: "20")],
                                   market: MarketSnapshot(quotes: [quote("AAA", "12", .eur)]))
        #expect(v.totalValue == 120)
        #expect(v.costBasis == 200)
        #expect(v.positions.first { $0.ticker == "BBB" }?.marketValue == nil)
        #expect(v.positions.first { $0.ticker == "BBB" }?.unrealizedGain == nil)
        #expect(v.unavailableTickers == ["BBB"])
        #expect(v.holdingsCount == 2)
    }

    @Test func missingFXIsUnavailableNotRateOne() {
        let r = holding("SBER.ME", currency: .rub)
        let e = holding("SAP", currency: .eur)
        let v = PortfolioValuation(portfolio: portfolio(.eur), holdings: [r, e],
                                   transactions: [tx(r, .buy, "2024-01-01", qty: "10", price: "250"),
                                                  tx(e, .buy, "2024-01-01", qty: "1", price: "100")],
                                   market: MarketSnapshot(quotes: [quote("SBER.ME", "300", .rub), quote("SAP", "110", .eur)]))
        let rub = v.positions.first { $0.ticker == "SBER.ME" }!
        #expect(rub.marketValue == nil)
        #expect(rub.costBasis == nil)
        #expect(v.totalValue == 110)
        #expect(v.costBasis == 100)
        #expect(v.missingRates == [CurrencyPair(.rub, .eur)])
        #expect(v.unavailableTickers == ["SBER.ME"])
    }

    @Test func noPricesMeansNoTotal() {
        let h = holding("AAA", currency: .eur)
        let v = PortfolioValuation(portfolio: portfolio(), holdings: [h],
                                   transactions: [tx(h, .buy, "2024-01-01", qty: "1", price: "10")], market: .empty)
        #expect(v.totalValue == nil)
        #expect(v.unrealizedGain == nil)
        #expect(v.costBasis == 10)
    }

    @Test func topFiveByMarketValueWithWeights() {
        let hs = (1...8).map { holding("T\($0)", currency: .eur) }
        let txns = hs.map { tx($0, .buy, "2024-01-01", qty: "1", price: "1") }
        let quotes = hs.enumerated().map { quote($1.ticker, "\(($0 + 1) * 10)", .eur) }
        let v = PortfolioValuation(portfolio: portfolio(), holdings: hs, transactions: txns,
                                   market: MarketSnapshot(quotes: quotes))
        #expect(v.top5.map(\.ticker) == ["T8", "T7", "T6", "T5", "T4"])
        #expect(v.totalValue == 360)
        #expect(v.top5.first?.weightPercent?.rounded(scale: 2) == dec("22.22"))
        #expect(v.holdingsCount == 8)
    }

    @Test func closedPositionsAndDividends() {
        let h = holding("KO", currency: .usd)
        let txns = [tx(h, .buy, "2024-01-01", qty: "1", price: "10"), tx(h, .sell, "2024-02-01", qty: "1", price: "12"),
                    tx(h, .dividend, "2024-01-15", amount: "10")]
        let v = PortfolioValuation(portfolio: portfolio(.eur), holdings: [h], transactions: txns,
                                   market: MarketSnapshot(fxRates: [fx(.usd, .eur, "0.5")]))
        #expect(v.holdingsCount == 0)
        #expect(v.positions.isEmpty)
        #expect(v.dividendsReceived == 5)
        #expect(v.totalValue == nil)
    }

    @Test func pricesFetchedAtIsOldestQuote() {
        let a = holding("A", currency: .eur), b = holding("B", currency: .eur)
        let v = PortfolioValuation(portfolio: portfolio(), holdings: [a, b],
                                   transactions: [tx(a, .buy, "2024-01-01", qty: "1", price: "1"),
                                                  tx(b, .buy, "2024-01-01", qty: "1", price: "1")],
                                   market: MarketSnapshot(quotes: [quote("A", "1", .eur, at: epoch),
                                                                   quote("B", "1", .eur, at: epoch.addingTimeInterval(60))]))
        #expect(v.pricesFetchedAt == epoch)
    }
}

@Suite struct DividendFrequencyTests {
    @Test func portsDetectFrequencyThresholds() {
        #expect(DividendFrequency.detect(annualRate: 1, lastAmount: 1) == .annual)
        #expect(DividendFrequency.detect(annualRate: 2, lastAmount: 1) == .semiAnnual)
        #expect(DividendFrequency.detect(annualRate: 4, lastAmount: 1) == .quarterly)
        #expect(DividendFrequency.detect(annualRate: 12, lastAmount: 1) == .monthly)
        #expect(DividendFrequency.detect(annualRate: nil, lastAmount: 1) == .unknown)
        #expect(DividendFrequency.detect(annualRate: 1, lastAmount: 0) == .unknown)
    }
}

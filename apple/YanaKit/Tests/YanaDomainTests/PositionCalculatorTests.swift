import Foundation
import Testing
@testable import YanaDomain

@Suite struct PositionCalculatorTests {
    let h = holding("AAPL")

    @Test func averageCostIncludesFees() {
        let txns = [tx(h, .buy, "2024-01-10", qty: "10", price: "100", fee: "5"),
                    tx(h, .buy, "2024-02-10", qty: "10", price: "110")]
        let p = PositionCalculator.position(for: h, transactions: txns)
        #expect(p.shares == 20)
        #expect(p.averageCost == dec("105.25"))
        #expect(p.costBasis == 2105)
    }

    @Test func sellKeepsAverageCost() {
        let txns = [tx(h, .buy, "2024-01-10", qty: "10", price: "100", fee: "5"),
                    tx(h, .buy, "2024-02-10", qty: "10", price: "110"),
                    tx(h, .sell, "2024-03-10", qty: "5", price: "130")]
        let p = PositionCalculator.position(for: h, transactions: txns)
        #expect(p.shares == 15)
        #expect(p.averageCost == dec("105.25"))
        #expect(p.costBasis == dec("1578.75"))
    }

    @Test func oversellIsClamped() {
        let txns = [tx(h, .buy, "2024-01-10", qty: "5", price: "10"),
                    tx(h, .sell, "2024-01-11", qty: "8", price: "12")]
        let p = PositionCalculator.position(for: h, transactions: txns)
        #expect(p.shares == 0)
        #expect(!p.isOpen)
        #expect(p.averageCost == nil)
        #expect(p.costBasis == 0)
    }

    @Test func fractionalSharesAreExact() {
        let txns = [tx(h, .buy, "2024-01-10", qty: "0.1", price: "1"),
                    tx(h, .buy, "2024-01-11", qty: "0.2", price: "1")]
        #expect(PositionCalculator.position(for: h, transactions: txns).shares == dec("0.3"))
    }

    @Test func appliesInDateOrderNotInputOrder() {
        // The sell is dated before the buy, so it clamps at zero and the buy then opens 10 shares.
        let buy = tx(h, .buy, "2024-02-01", qty: "10", price: "10")
        let sell = tx(h, .sell, "2024-01-01", qty: "4", price: "10")
        #expect(PositionCalculator.position(for: h, transactions: [buy, sell]).shares == 10)
    }

    @Test func creationOrderBreaksSameDayTies() {
        let buy = tx(h, .buy, "2024-01-01", qty: "10", price: "10")
        let sell = tx(h, .sell, "2024-01-01", qty: "4", price: "10")
        #expect(PositionCalculator.position(for: h, transactions: [sell, buy]).shares == 6)
    }

    @Test func ignoresTombstonesDividendsAndOtherHoldings() {
        var deleted = tx(h, .buy, "2024-01-01", qty: "100", price: "1")
        deleted.deletedAt = epoch
        let other = holding("MSFT")
        let txns = [deleted, tx(h, .buy, "2024-01-02", qty: "1", price: "1"),
                    tx(h, .dividend, "2024-01-03", amount: "5"), tx(other, .buy, "2024-01-01", qty: "7", price: "1")]
        let positions = PositionCalculator.positions(holdings: [h, other], transactions: txns)
        #expect(positions.map(\.shares) == [1, 7])
    }

    @Test func costCurrencyFollowsLatestBuy() {
        let txns = [tx(h, .buy, "2024-01-01", qty: "1", price: "1", currency: .eur)]
        #expect(PositionCalculator.position(for: h, transactions: txns).costCurrency == .eur)
        #expect(PositionCalculator.position(for: h, transactions: []).costCurrency == .usd)
    }
}

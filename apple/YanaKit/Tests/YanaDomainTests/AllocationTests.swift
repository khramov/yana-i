import Foundation
import Testing
@testable import YanaDomain

func goal(_ scope: GoalScope, _ key: String, _ pct: String) -> GoalRecord {
    GoalRecord(id: RecordIdentity.goalID(portfolioID: portfolioID, scope: scope, key: key), portfolioID: portfolioID,
               scope: scope, key: key, targetPercent: dec(pct), createdAt: epoch,
               version: .initial(at: epoch, deviceID: deviceA))
}

/// 10,000 EUR portfolio: VTI 12 × 250 = 3,000 (30%), BND 70 × 100 = 7,000 (70%).
private func vtiPortfolio() -> PortfolioValuation {
    let vti = holding("VTI", currency: .eur, assetClass: .etf, sector: nil, name: "Vanguard Total")
    let bnd = holding("BND", currency: .eur, assetClass: .bond, sector: "Fixed income")
    return PortfolioValuation(portfolio: portfolio(), holdings: [vti, bnd],
                              transactions: [tx(vti, .buy, "2024-01-01", qty: "12", price: "200"),
                                             tx(bnd, .buy, "2024-01-01", qty: "70", price: "100")],
                              market: MarketSnapshot(quotes: [quote("VTI", "250", .eur), quote("BND", "100", .eur)]))
}

@Suite struct AllocationCalculatorTests {
    @Test func groupsByAssetClassAndSumsTo100() {
        let a = holding("A", currency: .eur, assetClass: .stock), b = holding("B", currency: .eur, assetClass: .etf)
        let c = holding("C", currency: .eur, assetClass: .stock), d = holding("D", currency: .eur, assetClass: .bond)
        let v = PortfolioValuation(portfolio: portfolio(), holdings: [a, b, c, d],
                                   transactions: [a, b, c, d].map { tx($0, .buy, "2024-01-01", qty: "1", price: "1") },
                                   market: MarketSnapshot(quotes: [quote("A", "1", .eur), quote("B", "1", .eur),
                                                                   quote("C", "1", .eur)]))
        let slices = AllocationCalculator.slices(v, by: .assetClass)
        #expect(slices.map(\.key) == ["stock", "etf"])
        #expect(slices.reduce(Decimal(0)) { $0 + $1.percent }.rounded(scale: 10) == 100)
        #expect(slices.first?.value == 2)
    }

    @Test func percentagesOfThirdsAddUpTo100() {
        let hs = ["X", "Y", "Z"].map { holding($0, currency: .eur) }
        let v = PortfolioValuation(portfolio: portfolio(), holdings: hs,
                                   transactions: hs.map { tx($0, .buy, "2024-01-01", qty: "1", price: "1") },
                                   market: MarketSnapshot(quotes: hs.map { quote($0.ticker, "1", .eur) }))
        let slices = AllocationCalculator.slices(v, by: .holding)
        #expect(slices.map(\.key) == ["X", "Y", "Z"])
        #expect(slices.reduce(Decimal(0)) { $0 + $1.percent }.rounded(scale: 10) == 100)
    }

    @Test func missingSectorIsUnknown() {
        let slices = AllocationCalculator.slices(vtiPortfolio(), by: .sector)
        #expect(slices.map(\.key) == ["Fixed income", "Unknown"])
        #expect(slices.map(\.percent) == [70, 30])
    }
}

@Suite struct RebalanceCalculatorTests {
    @Test func underweightHolding() throws {
        let rows = RebalanceCalculator.rows(vtiPortfolio(), goals: [goal(.holding, "VTI", "40"), goal(.holding, "BND", "60")],
                                            scope: .holding)
        let vti = try #require(rows.first { $0.key == "VTI" })
        #expect(vti.currentPercent == 30)
        #expect(vti.driftPercent == -10)
        #expect(vti.buyAmount == 1000)
        #expect(vti.buyShares == 4)
        #expect(vti.name == "Vanguard Total")
        #expect(rows.first?.key == "VTI")
    }

    @Test func overweightHoldingBuysNothing() throws {
        let rows = RebalanceCalculator.rows(vtiPortfolio(), goals: [goal(.holding, "VTI", "40"), goal(.holding, "BND", "60")],
                                            scope: .holding)
        let bnd = try #require(rows.first { $0.key == "BND" })
        #expect(bnd.driftPercent == 10)
        #expect(bnd.buyAmount == 0)
        #expect(bnd.buyShares == 0)
    }

    @Test func assetClassScopeAndUnheldGoalKeys() throws {
        let rows = RebalanceCalculator.rows(vtiPortfolio(), goals: [goal(.assetClass, "etf", "50"), goal(.assetClass, "cash", "10"),
                                                                    goal(.holding, "VTI", "100")], scope: .assetClass)
        #expect(Set(rows.map(\.key)) == ["etf", "cash", "bond"])
        let cash = try #require(rows.first { $0.key == "cash" })
        #expect(cash.currentValue == 0 && cash.buyAmount == 1000 && cash.buyShares == nil)
        let bond = try #require(rows.first { $0.key == "bond" })
        #expect(bond.targetPercent == nil && bond.driftPercent == nil && bond.buyAmount == 0)
        #expect(rows.first?.key == "etf")
    }

    @Test func ignoresTombstonedGoals() {
        var g = goal(.holding, "VTI", "40")
        g.deletedAt = epoch
        let rows = RebalanceCalculator.rows(vtiPortfolio(), goals: [g], scope: .holding)
        #expect(rows.allSatisfy { $0.targetPercent == nil })
    }
}

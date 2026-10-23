import Foundation
import Testing
@testable import YanaDomain

@Suite struct GoalPlanTests {
    @Test func parsesDotAndCommaInAnyLocale() {
        #expect(GoalPercent.parse("12.5") == dec("12.5"))
        #expect(GoalPercent.parse("12,5") == dec("12.5"))
        #expect(GoalPercent.parse(" 7,25 % ") == dec("7.25"))
        #expect(GoalPercent.parse(",5") == dec("0.5"))
        #expect(GoalPercent.parse("40") == 40)
        #expect(GoalPercent.parse("40.") == 40)
    }

    @Test func rejectsGroupingExtraDecimalsAndText() {
        for text in ["", "  ", ".", "abc", "-3", "1.234", "1,000.5", "1 000", "12%%", "+5"] {
            #expect(GoalPercent.parse(text) == nil, "\(text)")
        }
    }

    @Test func remainingAndValidity() {
        #expect(GoalPlan.remaining([dec("33.3"), dec("33.3"), nil]) == dec("33.4"))
        #expect(GoalPlan.remaining([60, 50]) == -10)
        #expect(GoalPlan.isTotalValid([dec("99.5")]))
        #expect(!GoalPlan.isTotalValid([dec("99.4")]))
    }

    @Test func putRemainderLandsOnExactly100() {
        #expect(GoalPlan.putRemainder(on: 2, in: [40, 20, nil]) == [40, 20, 40])
        #expect(GoalPlan.putRemainder(on: 1, in: [70, 40]) == [70, 30])
        #expect(GoalPlan.putRemainder(on: 0, in: [dec("33.33"), dec("33.33"), dec("33.33")])[0] == dec("33.34"))
        // Never below 0.1, even when the rest is already over.
        #expect(GoalPlan.putRemainder(on: 1, in: [120, 5])[1] == dec("0.1"))
    }

    @Test func splitsRemainderAcrossEmptyRows() {
        #expect(GoalPlan.splitRemainderAcrossEmpty([70, nil, 0]) == [70, 15, 15])
        let thirds = GoalPlan.splitRemainderAcrossEmpty([nil, nil, nil])
        #expect(thirds == [dec("33.4"), dec("33.3"), dec("33.3")])
        #expect(GoalPlan.total(thirds) == 100)
        // Nothing left, or nothing empty: unchanged.
        #expect(GoalPlan.splitRemainderAcrossEmpty([100, nil]) == [100, nil])
        #expect(GoalPlan.splitRemainderAcrossEmpty([50, 40]) == [50, 40])
    }

    @Test func scalesTo100() {
        #expect(GoalPlan.scaleTo100([40, 24, 16]) == [50, 30, 20])
        let scaled = GoalPlan.scaleTo100([10, 10, 10])
        #expect(GoalPlan.total(scaled) == 100)
        #expect(scaled.allSatisfy { $0 == $0?.rounded(scale: 1) })
        // 18.75 rounds up twice; the -0.1 residue lands on the largest row.
        #expect(GoalPlan.scaleTo100([20, 30, 15, 15]) == [25, dec("37.4"), dec("18.8"), dec("18.8")])
    }

    @Test func seedsFromCurrentWeights() {
        let seeded = GoalPlan.seed(fromCurrent: [GoalTarget(key: "A", percent: dec("33.333")),
                                                 GoalTarget(key: "B", percent: dec("33.333")),
                                                 GoalTarget(key: "C", percent: dec("33.334")),
                                                 GoalTarget(key: "D", percent: dec("0.02"))])
        #expect(seeded.map(\.key) == ["A", "B", "C"])
        #expect(GoalPlan.total(seeded.map(\.percent)) == 100)
        #expect(GoalPlan.seed(fromCurrent: []).isEmpty)
    }

    @Test func driftUsesOnePointTolerance() {
        #expect(GoalDrift.classify(current: dec("20.9"), target: 20).status == .onTarget)
        #expect(GoalDrift.classify(current: 19, target: 20).status == .onTarget)
        #expect(GoalDrift.classify(current: dec("18.9"), target: 20) == GoalDrift(status: .under, gap: dec("-1.1")))
        #expect(GoalDrift.classify(current: 22, target: 20) == GoalDrift(status: .over, gap: 2))
    }

    @Test func impliedMixSumsByAssetClassAndSkipsUnknownHoldings() {
        let mix = GoalPlan.impliedAssetClassMix(
            holdingTargets: [GoalTarget(key: "voo", percent: 50), GoalTarget(key: "VXUS", percent: 38),
                             GoalTarget(key: "BND", percent: 12), GoalTarget(key: "GONE", percent: 5)],
            assetClassOf: ["VOO": .etf, "VXUS": .etf, "BND": .bond])
        #expect(mix == [GoalTarget(key: "etf", percent: 88), GoalTarget(key: "bond", percent: 12)])
    }
}

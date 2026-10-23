import Foundation
import Testing
import YanaDomain
@testable import YanaMac

private func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

/// A USD portfolio worth 1,600: VTI 4 × 250 = 1,000 (ETF, 62.5%) and KO 10 × 60 = 600 (stock, 37.5%), plus AAPL and
/// MSFT holdings with no shares.
@MainActor
private func makeGoalsFixture(defaultsSuite: String = "yana.tests.\(UUID().uuidString)")
    async throws -> (AppModel, GoalsWorkspaceModel, [String: HoldingRecord]) {
    let model = try await makeAppModel(defaultsSuite: defaultsSuite)
    try await model.createPortfolio(PortfolioDraft(name: "P", baseCurrency: .usd))
    var holdings: [String: HoldingRecord] = [:]
    for ticker in ["VTI", "KO", "AAPL", "MSFT"] { holdings[ticker] = try await addHolding(model, ticker) }
    for (ticker, shares) in [("VTI", 4), ("KO", 10)] {
        try await model.addTransaction(TransactionDraft(kind: .buy, date: LocalDate(string: "2024-01-02"),
                                                        quantity: Decimal(shares), unitPrice: 10, currency: .usd),
                                       holdingID: holdings[ticker]!.id)
    }
    await model.refreshMarketData(force: true)
    model.goalScope = .holding
    return (model, GoalsWorkspaceModel(model: model, locale: Locale(identifier: "en_US")), holdings)
}

@MainActor
private func save(_ model: AppModel, _ scope: GoalScope, _ targets: [(String, Decimal)]) async throws {
    try await model.saveGoals(GoalScopeDraft(scope: scope, targets: targets.map { GoalTarget(key: $0.0, percent: $0.1) }),
                              for: model.selectedPortfolioID!)
}

@MainActor
private func row(_ w: GoalsWorkspaceModel, _ key: String) -> GoalRowState {
    w.rowStates.first { $0.key == key }!
}

@MainActor @Suite(.serialized) struct GoalsWorkspaceTests {
    @Test func sectionAndScopeAreRestored() async throws {
        let suite = "yana.tests.\(UUID().uuidString)"
        let model = try await makeAppModel(defaultsSuite: suite)
        model.section = .goals
        model.goalScope = .assetClass
        let relaunched = try await makeAppModel(defaultsSuite: suite)
        #expect(relaunched.section == .goals && relaunched.goalScope == .assetClass)
        UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
    }

    @Test func dirtyDraftsSurviveRelaunchAndCleanOnesStayInMemory() throws {
        let suite = "yana.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let portfolio = UUID()
        let store = GoalDraftStore(defaults: defaults)
        let dirty = GoalDraft(rows: [GoalDraftRow(key: "VTI", text: "55")], baseline: ["VTI": 100])
        store.set(dirty, portfolio, .holding)
        store.set(GoalDraft(rows: [GoalDraftRow(key: "etf", text: "100")], baseline: ["etf": 100]), portfolio, .assetClass)
        #expect(store.draft(portfolio, .assetClass) != nil)

        let relaunched = GoalDraftStore(defaults: defaults)
        #expect(relaunched.draft(portfolio, .holding)?.rows.map(\.text) == ["55"])
        #expect(relaunched.draft(portfolio, .holding)?.restored == true)
        #expect(relaunched.draft(portfolio, .assetClass) == nil)

        relaunched.removeDrafts(keeping: [])
        #expect(GoalDraftStore(defaults: defaults).draft(portfolio, .holding) == nil)
    }

    @Test func deletingAPortfolioDropsItsDrafts() async throws {
        let (model, w, _) = try await makeGoalsFixture()
        let doomed = model.selectedPortfolioID!
        w.add("VTI")
        #expect(model.goalDrafts.draft(doomed, .holding) != nil)
        try await model.createPortfolio(PortfolioDraft(name: "Other"))
        try await model.deletePortfolio(doomed)
        #expect(model.goalDrafts.draft(doomed, .holding) == nil)
    }

    @Test func pickerListsHeldFirstSearchesAndExcludesPlanRows() async throws {
        let (_, w, _) = try await makeGoalsFixture()
        let options = w.pickerOptions()
        #expect(options.map(\.key) == ["VTI", "KO", "AAPL", "MSFT"])
        #expect(options.map(\.isHeld) == [true, true, false, false])
        #expect(options.first?.currentPercent == dec("62.5"))
        #expect(w.pickerOptions(search: "apple").map(\.key) == ["AAPL"])
        #expect(w.pickerOptions(search: "ko").map(\.key) == ["KO"])

        w.add("AAPL")
        let added = try #require(w.rows.last)
        #expect(added.key == "AAPL" && added.text == "")
        #expect(w.focusRequest == added.id)
        #expect(!w.pickerOptions().contains { $0.key == "AAPL" })
        #expect(w.notInPlan.map(\.key) == ["VTI", "KO"])
    }

    @Test func savedRowsSortByGapAndShowProgress() async throws {
        let (model, w, _) = try await makeGoalsFixture()
        try await save(model, .holding, [("VTI", 60), ("KO", 30), ("AAPL", 10)])
        // Gaps: AAPL 10, KO 7.5, VTI 2.5.
        #expect(w.rows.map(\.key) == ["AAPL", "KO", "VTI"])
        let ko = row(w, "KO")
        #expect(ko.drift == GoalDrift(status: .over, gap: dec("7.5")))
        #expect(ko.gapValue == 120)
        #expect(row(w, "VTI").drift?.status == .over)
        #expect(w.summary == "0 of 3 targets on target · largest gap: AAPL under 10.0 pt")
        #expect(w.savedCountText(.holding) == "3 targets" && w.savedCountText(.assetClass) == "Not set")
        #expect(!w.isDirty && w.totalText == "Total 100.0%")

        w.setText("62,5", for: row(w, "VTI").id)
        #expect(row(w, "VTI").drift?.status == .onTarget)
        #expect(w.isDirty && w.isDirty(.holding) && !w.isDirty(.assetClass))
    }

    @Test func incompleteRowsAndDisabledSaveReasons() async throws {
        let (model, w, _) = try await makeGoalsFixture()
        try await save(model, .holding, [("VTI", 60), ("KO", 40)])
        w.add("MSFT")
        let msft = row(w, "MSFT").id
        #expect(row(w, "MSFT").problem == .incomplete && row(w, "MSFT").message == nil)
        #expect(w.saveBlockReason == "Fill in 1 empty target" && !w.canSave)

        w.setText("0", for: msft)
        #expect(row(w, "MSFT").message == "Enter a target above 0 or remove this row")
        w.setText("10", for: msft)
        #expect(w.saveBlockReason == "Remove 10.0% to save")
        #expect(w.totalText == "Total 110.0% · 10.0% over")

        w.remove(msft)
        w.setText("20,5", for: row(w, "KO").id)
        #expect(w.totalText == "Total 80.5% · 19.5% left")
        #expect(w.saveBlockReason == "Add 19.5% to save")
        w.setText("40.4", for: row(w, "KO").id)
        #expect(w.canSave && w.totalText == "Total 100.4% · Ready to save")
        #expect(await w.save())
        #expect(!w.isDirty && w.savedAt != nil)
        #expect(model.goals.first { $0.key == "KO" }?.targetPercent == dec("40.4"))
    }

    @Test func helpersLandOnExactly100() async throws {
        let (_, w, _) = try await makeGoalsFixture()
        #expect(w.rows.isEmpty && w.canStartFromCurrent && !w.replacingNeedsConfirmation)
        w.startFromCurrentAllocation()
        #expect(w.rows.map(\.key) == ["VTI", "KO"] && w.rows.map(\.text) == ["62.5", "37.5"])

        w.add("AAPL")
        w.add("MSFT")
        w.setText("30", for: row(w, "VTI").id)
        w.setText("40", for: row(w, "KO").id)
        #expect(w.canSplitRemainder)
        w.splitRemainder()
        #expect(row(w, "AAPL").text == "15" && row(w, "MSFT").text == "15" && w.total == 100)

        w.setText("10", for: row(w, "AAPL").id)
        w.setText("10", for: row(w, "MSFT").id)
        #expect(w.canScale)
        w.scaleTo100()
        // 30, 40, 10, 10 × 100/90 → 33.3, 44.4, 11.1, 11.1; the +0.1 residue lands on KO.
        #expect(w.rows.map(\.text) == ["33.3", "44.5", "11.1", "11.1"] && w.total == 100)

        w.setText("5", for: row(w, "MSFT").id)
        w.putRemainder(on: row(w, "MSFT").id)
        #expect(row(w, "MSFT").text == "11.1" && w.total == 100)
    }

    @Test func removeUndoAndClearWithConfirmation() async throws {
        let (model, w, _) = try await makeGoalsFixture()
        try await save(model, .holding, [("VTI", 100)])
        let vti = row(w, "VTI").id
        w.remove(vti)
        #expect(w.rows.isEmpty && w.lastRemoved?.row.key == "VTI")
        w.undoRemove()
        #expect(w.rows.map(\.text) == ["100"] && w.lastRemoved == nil && !w.isDirty)

        w.remove(vti)
        #expect(w.saveMode == .clear && w.canSave)
        #expect(w.clearConfirmationTitle == "Remove the holding target?")
        #expect(await w.save())
        #expect(model.goals.isEmpty && w.saveMode == .save && w.savedCountText(.holding) == "Not set")
    }

    @Test func draftsAreKeptPerPortfolioAndScope() async throws {
        let (model, w, _) = try await makeGoalsFixture()
        let first = model.selectedPortfolioID!
        w.add("VTI")
        w.scope = .assetClass
        #expect(w.rows.isEmpty)
        w.scope = .holding
        #expect(w.rows.map(\.key) == ["VTI"])

        try await model.createPortfolio(PortfolioDraft(name: "Other"))
        #expect(w.rows.isEmpty && !w.isDirty)
        await model.select(first)
        #expect(w.rows.map(\.key) == ["VTI"] && w.isDirty)
    }

    @Test func noticesWhenTheSavedPlanChangesUnderneath() async throws {
        let (model, w, _) = try await makeGoalsFixture()
        try await save(model, .holding, [("VTI", 60), ("KO", 40)])
        w.setText("55", for: row(w, "VTI").id)
        #expect(!w.savedPlanChanged && !w.isRestored)

        // Another Mac saves the same scope.
        try await save(model, .holding, [("VTI", 70), ("KO", 30)])
        #expect(w.savedPlanChanged)
        w.discard()
        #expect(!w.isDirty && Set(w.rows.map(\.text)) == ["70", "30"])
    }

    @Test func restoredDraftAfterRelaunch() async throws {
        let suite = "yana.tests.\(UUID().uuidString)"
        let (model, w, _) = try await makeGoalsFixture(defaultsSuite: suite)
        defer { UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite) }
        w.add("VTI")
        w.setText("100", for: row(w, "VTI").id)
        let portfolio = model.selectedPortfolioID!
        // A fresh store over the same defaults is what the next launch sees.
        let relaunched = GoalDraftStore(defaults: UserDefaults(suiteName: suite)!)
        #expect(relaunched.draft(portfolio, .holding)?.restored == true)
        #expect(relaunched.draft(portfolio, .holding)?.rows.map(\.text) == ["100"])
    }

    @Test func unavailableHoldingsBlockSavingUntilReplaced() async throws {
        let (model, w, holdings) = try await makeGoalsFixture()
        try await save(model, .holding, [("VTI", 60), ("AAPL", 40)])
        try await model.deleteHolding(holdings["AAPL"]!.id)
        #expect(model.goals.contains { $0.key == "AAPL" })
        let aapl = row(w, "AAPL")
        #expect(aapl.problem == .unavailable)
        w.setText("41", for: aapl.id)
        w.setText("59", for: row(w, "VTI").id)
        #expect(w.saveBlockReason == "Resolve 1 unavailable holding" && !w.canSave)

        w.replace(aapl.id, with: "MSFT")
        #expect(row(w, "MSFT").text == "41" && w.focusRequest == aapl.id)
        #expect(w.canSave)
        #expect(await w.save())
        #expect(Set(model.goals.map(\.key)) == ["VTI", "MSFT"])
    }

    @Test func saveErrorsAreShownOnTheirRows() async throws {
        let (model, w, _) = try await makeGoalsFixture()
        let portfolio = model.selectedPortfolioID!
        // A duplicate the picker would never offer, as a stale or synced draft could hold.
        model.goalDrafts.set(GoalDraft(rows: [GoalDraftRow(key: "vti", text: "50"), GoalDraftRow(key: "VTI", text: "50")],
                                       baseline: [:]), portfolio, .holding)
        #expect(w.canSave)
        #expect(await w.save() == false)
        #expect(w.rowStates.map(\.message) == ["VTI appears more than once", "VTI appears more than once"])
        #expect(model.goals.isEmpty)
    }

    @Test func impliedMixAndDisagreementWarnings() async throws {
        let (model, w, _) = try await makeGoalsFixture()
        try await save(model, .holding, [("VTI", 60), ("KO", 40)])
        w.scope = .assetClass
        #expect(w.impliedMixText == "Stock 40.0% · ETF 60.0%")
        #expect(w.planDisagreements.isEmpty)

        try await save(model, .assetClass, [("stock", 20), ("etf", 80)])
        #expect(w.planDisagreements == ["Your holding plan implies Stock 40.0%, but this plan targets 20.0%",
                                        "Your holding plan implies ETF 60.0%, but this plan targets 80.0%"])
        #expect(row(w, "stock").impliedPercent == 40)

        #expect(w.replacingNeedsConfirmation)
        w.useImpliedMix()
        #expect(w.rows.map(\.key) == ["stock", "etf"] && w.rows.map(\.text) == ["40", "60"])
        #expect(w.isDirty)
    }

    @Test func notInPlanStartsCollapsedOnlyWhenLong() async throws {
        let (model, w, _) = try await makeGoalsFixture()
        try await save(model, .holding, [("AAPL", 100)])
        #expect(w.notInPlan.map(\.key) == ["VTI", "KO"] && !w.notInPlanStartsCollapsed)
    }

    @Test func progressPlaceholderWithoutValuedPositions() async throws {
        let model = try await makeAppModel()
        try await model.createPortfolio(PortfolioDraft(name: "P", baseCurrency: .usd))
        _ = try await addHolding(model, "VTI")
        try await save(model, .holding, [("VTI", 100)])
        let w = GoalsWorkspaceModel(model: model, locale: Locale(identifier: "en_US"))
        #expect(!w.hasValuation)
        #expect(w.summary == "Progress appears once open positions have prices. You can still edit targets.")
        #expect(row(w, "VTI").drift == nil)
        #expect(w.pickerOptions().allSatisfy { $0.currentPercent == nil })
    }
}

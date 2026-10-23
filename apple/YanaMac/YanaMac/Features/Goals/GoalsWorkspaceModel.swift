import Foundation
import Observation
import YanaDomain

/// A holding or asset class that can be added to a plan.
struct GoalOption: Identifiable, Equatable {
    var key: String
    var label: String
    var name: String?
    /// Current weight in percent; `nil` without a valuation.
    var currentPercent: Decimal?
    /// Has an open position (asset classes: has a current value).
    var isHeld: Bool

    var id: String { key }
}

/// One plan row with everything the view shows for it.
struct GoalRowState: Identifiable, Equatable {
    enum Problem: Equatable {
        case unavailable, incomplete, invalid, tooLarge
    }

    var id: UUID
    var key: String
    var label: String
    var name: String?
    var isHeld: Bool
    var text: String
    var value: Decimal?
    var problem: Problem?
    /// The row's error, from local checks or the last save attempt.
    var message: String?
    /// `nil` without a valuation, or for an unavailable row.
    var currentPercent: Decimal?
    /// `nil` unless the row has a valid target and there is a valuation.
    var drift: GoalDrift?
    /// Gap in the base currency (always positive).
    var gapValue: Decimal?
    /// Share of this asset class implied by the holding plan (asset-class scope only).
    var impliedPercent: Decimal?
}

/// The Goals section's state for the selected portfolio and scope. Rows come from the scope's draft in
/// `AppModel.goalDrafts`, or from the saved goals when there is none; every edit writes the draft back.
@MainActor @Observable
final class GoalsWorkspaceModel {
    enum SaveMode: Equatable {
        case save
        /// An empty draft over a saved plan: a destructive save that needs confirmation.
        case clear
    }

    private let model: AppModel
    private let locale: Locale

    /// Errors from the last save attempt, by normalized key.
    private(set) var issues: [String: String] = [:]
    /// The last save attempt's error that belongs to no row (the total, a missing portfolio).
    private(set) var footerError: String?
    private(set) var savedAt: Date?
    private(set) var isSaving = false
    /// The last removed row, for "Removed VOO · Undo".
    private(set) var lastRemoved: (row: GoalDraftRow, index: Int)?
    /// Row whose target field should take keyboard focus; the view clears it once focused.
    var focusRequest: UUID?
    /// Set by a blocked save so empty rows show their message.
    private(set) var showsAllProblems = false

    init(model: AppModel, locale: Locale = .current) {
        self.model = model
        self.locale = locale
    }

    var scope: GoalScope {
        get { model.goalScope }
        set {
            guard newValue != model.goalScope else { return }
            model.goalScope = newValue
            resetTransientState()
        }
    }

    var portfolioID: UUID? { model.selectedPortfolio?.id }
    var hasPortfolio: Bool { portfolioID != nil }
    var baseCurrency: Currency { model.selectedPortfolio?.baseCurrency ?? .default }

    // MARK: - Draft

    private func savedGoals(_ scope: GoalScope) -> [GoalRecord] {
        model.goals.filter { $0.scope == scope && !$0.isDeleted }
    }

    private func savedBaseline(_ scope: GoalScope) -> [String: Decimal] {
        GoalDraft.baseline(model.goals, scope: scope)
    }

    /// The scope's draft: the stored one while it has edits or still matches the saved plan, otherwise rows built
    /// from the saved goals, largest gap first.
    func draft(for scope: GoalScope) -> GoalDraft {
        let baseline = savedBaseline(scope)
        if let portfolioID, let stored = model.goalDrafts.draft(portfolioID, scope),
           stored.isDirty(scope: scope) || stored.baseline == baseline {
            return stored
        }
        let current = currentWeights(scope)
        let rows = savedGoals(scope)
            .sorted { $0.key < $1.key }
            .map { GoalDraftRow(id: $0.id, key: $0.key, text: DecimalInput.text($0.targetPercent, locale: Self.posix)) }
            .sorted { a, b in gapSize(a, current, scope) > gapSize(b, current, scope) }
        return GoalDraft(rows: rows, baseline: baseline)
    }

    var draft: GoalDraft { draft(for: scope) }
    var rows: [GoalDraftRow] { draft.rows }

    func isDirty(_ scope: GoalScope) -> Bool { draft(for: scope).isDirty(scope: scope) }
    var isDirty: Bool { isDirty(scope) }

    /// The draft came back from a previous launch.
    var isRestored: Bool { draft.restored && isDirty }
    /// The saved plan changed (for example through sync) since the draft started.
    var savedPlanChanged: Bool { isDirty && draft.baseline != savedBaseline(scope) }

    private static let posix = Locale(identifier: "en_US_POSIX")

    private func gapSize(_ row: GoalDraftRow, _ current: [String: AllocationSlice]?, _ scope: GoalScope) -> Decimal {
        guard let current, let value = GoalPercent.parse(row.text) else { return -1 }
        return abs(GoalDrift.classify(current: current[normalize(row.key, scope)]?.percent ?? 0, target: value).gap)
    }

    private func normalize(_ key: String, _ scope: GoalScope? = nil) -> String {
        RecordIdentity.normalizeGoalKey(key, scope: scope ?? self.scope)
    }

    private func mutate(keepingUndo: Bool = false, _ change: (inout [GoalDraftRow]) -> Void) {
        guard let portfolioID else { return }
        var next = draft
        change(&next.rows)
        model.goalDrafts.set(next, portfolioID, scope)
        issues = [:]
        footerError = nil
        savedAt = nil
        if !keepingUndo { lastRemoved = nil }
    }

    private func resetTransientState() {
        issues = [:]
        footerError = nil
        savedAt = nil
        lastRemoved = nil
        showsAllProblems = false
        focusRequest = nil
    }

    // MARK: - Current weights

    /// Current weight and value by normalized key; `nil` when nothing open could be valued.
    private func currentWeights(_ scope: GoalScope) -> [String: AllocationSlice]? {
        guard let valuation = model.valuation else { return nil }
        let slices = AllocationCalculator.slices(valuation, by: scope == .holding ? .holding : .assetClass)
        guard !slices.isEmpty else { return nil }
        return Dictionary(slices.map { (normalize($0.key, scope), $0) }, uniquingKeysWith: { a, _ in a })
    }

    var hasValuation: Bool { currentWeights(scope) != nil }
    private var totalValue: Decimal { model.valuation?.totalValue ?? 0 }

    private var heldTickers: Set<String> {
        Set((model.valuation?.positions ?? []).map { normalize($0.ticker, .holding) })
    }

    // MARK: - Options

    private var liveHoldings: [HoldingRecord] { model.holdings.filter { !$0.isDeleted } }
    var hasHoldings: Bool { !liveHoldings.isEmpty }

    private var holdingKeys: Set<String> { Set(liveHoldings.map { normalize($0.ticker, .holding) }) }

    /// Every holding or asset class of the scope, held first and by current weight.
    private var allOptions: [GoalOption] {
        let current = currentWeights(scope)
        switch scope {
        case .holding:
            let held = heldTickers
            return liveHoldings.map { h in
                let key = normalize(h.ticker, .holding)
                return GoalOption(key: h.ticker, label: h.ticker, name: h.name,
                                  currentPercent: current.map { $0[key]?.percent ?? 0 }, isHeld: held.contains(key))
            }
            .sorted { ($0.isHeld ? 1 : 0, $0.currentPercent ?? 0, $1.label) > ($1.isHeld ? 1 : 0, $1.currentPercent ?? 0, $0.label) }
        case .assetClass:
            return AssetClass.allCases.map { cls in
                let pct = current?[cls.rawValue]?.percent
                return GoalOption(key: cls.rawValue, label: Fmt.assetClass(cls), name: nil,
                                  currentPercent: current.map { _ in pct ?? 0 }, isHeld: (pct ?? 0) > 0)
            }
        }
    }

    private var keysInPlan: Set<String> { Set(rows.map { normalize($0.key) }) }

    /// Options not yet in the plan matching `search` (ticker, name, or label; case-insensitive).
    func pickerOptions(search: String = "") -> [GoalOption] {
        let inPlan = keysInPlan
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return allOptions.filter { option in
            !inPlan.contains(normalize(option.key)) && (query.isEmpty
                || option.key.lowercased().contains(query) || option.label.lowercased().contains(query)
                || (option.name?.lowercased().contains(query) ?? false))
        }
    }

    /// Held positions (or classes with a value) that have no target: they count as 0%.
    var notInPlan: [GoalOption] {
        let inPlan = keysInPlan
        return allOptions.filter { $0.isHeld && !inPlan.contains(normalize($0.key)) }
    }

    var notInPlanStartsCollapsed: Bool { notInPlan.count > 5 }

    // MARK: - Rows

    private var values: [Decimal?] { rows.map { GoalPercent.parse($0.text) } }

    var rowStates: [GoalRowState] {
        let current = currentWeights(scope)
        let options = Dictionary(allOptions.map { (normalize($0.key), $0) }, uniquingKeysWith: { a, _ in a })
        let members = holdingKeys
        let implied = impliedMix.map { Dictionary($0.map { ($0.key, $0.percent) }, uniquingKeysWith: { a, _ in a }) }
        return rows.map { row in
            let key = normalize(row.key)
            let option = options[key]
            let value = GoalPercent.parse(row.text)
            let problem: GoalRowState.Problem?
            if scope == .holding, !members.contains(key) { problem = .unavailable }
            else if row.text.trimmingCharacters(in: .whitespaces).isEmpty || value == 0 { problem = .incomplete }
            else if value == nil { problem = .invalid }
            else if value! > 100 { problem = .tooLarge }
            else { problem = nil }

            var local: String?
            switch problem {
            case .incomplete where showsAllProblems || !row.text.trimmingCharacters(in: .whitespaces).isEmpty:
                local = "Enter a target above 0 or remove this row"
            case .invalid: local = "Enter a number like 12.5"
            case .tooLarge: local = "A target can be at most 100%"
            default: local = nil
            }

            var state = GoalRowState(id: row.id, key: row.key, label: option?.label ?? row.key, name: option?.name,
                                     isHeld: option?.isHeld ?? false, text: row.text, value: value, problem: problem,
                                     message: issues[key] ?? local, impliedPercent: implied?[key])
            if let current, problem != .unavailable {
                let pct = current[key]?.percent ?? 0
                state.currentPercent = pct
                if let value, problem == nil {
                    let drift = GoalDrift.classify(current: pct, target: value)
                    state.drift = drift
                    state.gapValue = abs(drift.gap) / 100 * totalValue
                }
            }
            return state
        }
    }

    // MARK: - Totals and saving

    var total: Decimal { GoalPlan.total(values) }
    var remaining: Decimal { GoalPlan.remaining(values) }

    var saveMode: SaveMode { rows.isEmpty && !savedBaseline(scope).isEmpty ? .clear : .save }

    /// Why the draft cannot be saved, shown next to Save; `nil` when it can (or when nothing changed).
    var saveBlockReason: String? {
        guard !rows.isEmpty else { return nil }
        let problems = rowStates.compactMap(\.problem)
        let unavailable = problems.filter { $0 == .unavailable }.count
        let incomplete = problems.filter { $0 == .incomplete }.count
        let invalid = problems.filter { $0 == .invalid || $0 == .tooLarge }.count
        if unavailable > 0 { return "Resolve \(count(unavailable, "unavailable holding", "unavailable holdings"))" }
        if incomplete > 0 { return "Fill in \(count(incomplete, "empty target", "empty targets"))" }
        if invalid > 0 { return "Fix \(count(invalid, "target", "targets"))" }
        if !GoalPlan.isTotalValid(values) {
            let rest = remaining
            return rest > 0 ? "Add \(pct(rest)) to save" : "Remove \(pct(-rest)) to save"
        }
        return nil
    }

    var canSave: Bool { isDirty && saveBlockReason == nil && !isSaving }

    /// "Total 82.5% · 17.5% left", "Total 102.5% · 2.5% over", "Total 100.0% · Ready to save".
    var totalText: String {
        guard !rows.isEmpty else { return "No targets in this plan" }
        let rest = remaining
        if GoalPlan.isTotalValid(values) { return "Total \(pct(total))" + (canSave ? " · Ready to save" : "") }
        return rest > 0 ? "Total \(pct(total)) · \(pct(rest)) left" : "Total \(pct(total)) · \(pct(-rest)) over"
    }

    /// "Remove all 5 holding targets?"
    var clearConfirmationTitle: String {
        let n = savedBaseline(scope).count
        let noun = scope == .holding ? "holding" : "asset-class"
        return n == 1 ? "Remove the \(noun) target?" : "Remove all \(n) \(noun) targets?"
    }

    /// Saves the draft to the portfolio it belongs to. Returns whether it was saved.
    @discardableResult
    func save() async -> Bool {
        guard canSave, let portfolioID else {
            showsAllProblems = true
            return false
        }
        let scope = scope
        let targets = rows.map { GoalTarget(key: $0.key, percent: GoalPercent.parse($0.text) ?? 0) }
        isSaving = true
        defer { isSaving = false }
        issues = [:]
        footerError = nil
        do {
            try await model.saveGoals(GoalScopeDraft(scope: scope, targets: targets), for: portfolioID)
            model.goalDrafts.set(nil, portfolioID, scope)
            lastRemoved = nil
            showsAllProblems = false
            savedAt = model.clock().now
            return true
        } catch let error as ValidationError {
            for issue in error.issues {
                if let key = issue.key { issues[normalize(key, scope)] = issue.message } else { footerError = issue.message }
            }
        } catch PortfolioRepositoryError.notFound {
            model.goalDrafts.set(nil, portfolioID, scope)
            footerError = "This portfolio no longer exists. The draft was discarded."
        } catch {
            footerError = error.localizedDescription
        }
        return false
    }

    func discard() {
        guard let portfolioID else { return }
        model.goalDrafts.set(nil, portfolioID, scope)
        resetTransientState()
    }

    // MARK: - Editing

    func add(_ key: String) {
        let row = GoalDraftRow(key: key, text: "")
        mutate { $0.append(row) }
        focusRequest = row.id
    }

    func setText(_ text: String, for id: UUID) {
        guard rows.first(where: { $0.id == id })?.text != text else { return }
        mutate { rows in
            if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].text = text }
        }
    }

    /// Removes a row; `undoRemove()` brings it back until the next edit or save.
    func remove(_ id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let row = rows[index]
        mutate { $0.remove(at: index) }
        lastRemoved = (row, index)
    }

    func undoRemove() {
        guard let removed = lastRemoved else { return }
        mutate(keepingUndo: true) { $0.insert(removed.row, at: min(removed.index, $0.count)) }
        lastRemoved = nil
        focusRequest = removed.row.id
    }

    /// Swaps a row's key (for an unavailable holding), keeping its target.
    func replace(_ id: UUID, with key: String) {
        mutate { rows in
            if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].key = key }
        }
        focusRequest = id
    }

    // MARK: - Helpers

    private func apply(_ next: [Decimal?]) {
        mutate { rows in
            for i in rows.indices where next.indices.contains(i) {
                guard let v = next[i], v != GoalPercent.parse(rows[i].text) else { continue }
                rows[i].text = DecimalInput.text(v, locale: Self.posix)
            }
        }
    }

    private func replaceRows(with targets: [GoalTarget]) {
        mutate { rows in
            rows = targets.map { GoalDraftRow(key: $0.key, text: DecimalInput.text($0.percent, locale: Self.posix)) }
        }
    }

    /// Today's weights of open positions (or asset classes with a value).
    private var currentTargets: [GoalTarget] {
        guard let valuation = model.valuation else { return [] }
        return AllocationCalculator.slices(valuation, by: scope == .holding ? .holding : .assetClass)
            .map { GoalTarget(key: $0.key, percent: $0.percent) }
    }

    var canStartFromCurrent: Bool { !currentTargets.isEmpty }
    /// Replacing a non-empty draft asks for confirmation first.
    var replacingNeedsConfirmation: Bool { !rows.isEmpty }

    func startFromCurrentAllocation() { replaceRows(with: GoalPlan.seed(fromCurrent: currentTargets)) }

    var canPutRemainder: Bool { !rows.isEmpty && remaining != 0 }
    func putRemainder(on id: UUID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        apply(GoalPlan.putRemainder(on: i, in: values))
    }

    var canSplitRemainder: Bool { values.contains { ($0 ?? 0) == 0 } && remaining > 0 }
    func splitRemainder() { apply(GoalPlan.splitRemainderAcrossEmpty(values)) }

    var canScale: Bool { !rows.isEmpty && values.allSatisfy { ($0 ?? 0) > 0 } && !GoalPlan.isTotalValid(values) }
    func scaleTo100() { apply(GoalPlan.scaleTo100(values)) }

    // MARK: - Summary

    /// "6 of 8 targets on target · largest gap: VXUS under 4.2 pt".
    var summary: String? {
        guard !rows.isEmpty else { return nil }
        guard hasValuation else { return "Progress appears once open positions have prices. You can still edit targets." }
        let measured = rowStates.filter { $0.drift != nil }
        guard !measured.isEmpty else { return "Enter targets to see how far off you are." }
        let onTarget = measured.filter { $0.drift?.status == .onTarget }.count
        if onTarget == measured.count { return measured.count == 1 ? "On target" : "All \(measured.count) targets on target" }
        var text = "\(onTarget) of \(measured.count) targets on target"
        if let largest = measured.max(by: { abs($0.drift!.gap) < abs($1.drift!.gap) }), let drift = largest.drift {
            text += " · largest gap: \(largest.label) \(drift.status == .over ? "over" : "under") \(points(abs(drift.gap)))"
        }
        return text
    }

    // MARK: - Scope labels and recommendations

    /// "5 targets" or "Not set".
    func savedCountText(_ scope: GoalScope) -> String {
        let n = savedGoals(scope).count
        return n == 0 ? "Not set" : n == 1 ? "1 target" : "\(n) targets"
    }

    var recommendations: [RebalanceRow] {
        model.valuation.map { RebalanceCalculator.rows($0, goals: model.goals, scope: scope) } ?? []
    }

    // MARK: - Holding plan vs asset-class plan

    /// The asset-class mix the saved holding plan implies; `nil` without a holding plan.
    var impliedMix: [GoalTarget]? {
        let holdingTargets = savedGoals(.holding).map { GoalTarget(key: $0.key, percent: $0.targetPercent) }
        guard scope == .assetClass, !holdingTargets.isEmpty else { return nil }
        let classOf = Dictionary(liveHoldings.map { (normalize($0.ticker, .holding), $0.assetClass) },
                                 uniquingKeysWith: { a, _ in a })
        return GoalPlan.impliedAssetClassMix(holdingTargets: holdingTargets, assetClassOf: classOf)
    }

    /// "ETF 88% · Bond 12%".
    var impliedMixText: String? {
        impliedMix.map { mix in mix.map { "\(classLabel($0.key)) \(pct($0.percent))" }.joined(separator: " · ") }
    }

    func useImpliedMix() {
        guard let mix = impliedMix else { return }
        replaceRows(with: mix)
    }

    /// One warning per asset class where the two saved plans differ by more than the drift tolerance.
    var planDisagreements: [String] {
        guard let mix = impliedMix else { return [] }
        let saved = savedBaseline(.assetClass)
        guard !saved.isEmpty else { return [] }
        let implied = Dictionary(mix.map { ($0.key, $0.percent) }, uniquingKeysWith: { a, _ in a })
        return AssetClass.allCases.compactMap { cls in
            let i = implied[cls.rawValue] ?? 0
            let t = saved[cls.rawValue] ?? 0
            guard abs(i - t) > GoalDrift.tolerance else { return nil }
            return "Your holding plan implies \(Fmt.assetClass(cls)) \(pct(i)), but this plan targets \(pct(t))"
        }
    }

    // MARK: - Formatting

    private func classLabel(_ key: String) -> String { AssetClass(rawValue: key).map(Fmt.assetClass) ?? key }

    func pct(_ value: Decimal) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(1...2))) + "%"
    }

    func points(_ value: Decimal) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(1))) + " pt"
    }

    func money(_ value: Decimal) -> String { Fmt.money(value, baseCurrency, locale: locale) }

    private func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
}

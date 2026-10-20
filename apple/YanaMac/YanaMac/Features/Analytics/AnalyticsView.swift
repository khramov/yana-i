import Charts
import SwiftUI
import YanaDomain

struct AnalyticsView: View {
    let model: AppModel
    @Environment(\.locale) private var locale
    @State private var grouping = AllocationGrouping.assetClass
    @State private var range = HistoryRange.threeMonths
    @State private var snapshots: [ValueSnapshot] = []
    @State private var goals: GoalsEditorModel?

    private var base: Currency { model.selectedPortfolio?.baseCurrency ?? .default }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                allocation
                if let goals { GoalsSection(model: model, editor: goals) }
                history
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: model.dataVersion) {
            if goals == nil { goals = GoalsEditorModel(model: model, locale: locale) } else { goals?.load() }
            await loadSnapshots()
        }
    }

    // MARK: - Allocation

    private var allocation: some View {
        let points = AllocationModel.points(model.valuation, grouping: grouping, locale: locale)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Allocation").font(.headline)
                Spacer()
                Picker("Group by", selection: $grouping) {
                    ForEach(AllocationGrouping.allCases, id: \.self) { Text(AllocationModel.groupingTitle($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .accessibilityIdentifier("allocationGrouping")
            }
            if points.isEmpty {
                Text("Allocation appears once positions have prices.").foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 24) {
                    Chart(points) { point in
                        SectorMark(angle: .value("Value", NSDecimalNumber(decimal: point.value).doubleValue),
                                   innerRadius: .ratio(0.55), angularInset: 1)
                            .foregroundStyle(by: .value("Group", point.label))
                            .accessibilityLabel(point.accessibilityLabel)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 220, height: 220)
                    .accessibilityIdentifier("allocationChart")
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                        ForEach(points) { p in
                            GridRow {
                                Text(p.label).fontWeight(.medium)
                                Text(Fmt.money(p.value, base, locale: locale)).monospacedDigit()
                                Text(Fmt.percent(p.percent, locale: locale, digits: 1)).monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Value history

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Value history").font(.headline)
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                .accessibilityIdentifier("historyRange")
            }
            let clock = model.clock()
            let shown = range.filter(snapshots, today: clock.today, calendar: clock.calendar)
            if shown.isEmpty {
                Text("Yana records the portfolio's value once a day while prices are available. History builds up as you use the app.")
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(shown, id: \.day) { s in
                        LineMark(x: .value("Day", s.day.startOfDay(in: clock.calendar)),
                                 y: .value("Amount", NSDecimalNumber(decimal: s.totalValue).doubleValue))
                            .foregroundStyle(by: .value("Series", "Value"))
                            .accessibilityLabel("\(Fmt.date(s.day, locale: locale)): value "
                                                + Fmt.money(s.totalValue, s.baseCurrency, locale: locale))
                        LineMark(x: .value("Day", s.day.startOfDay(in: clock.calendar)),
                                 y: .value("Amount", NSDecimalNumber(decimal: s.costBasis).doubleValue))
                            .foregroundStyle(by: .value("Series", "Cost basis"))
                            .accessibilityLabel("\(Fmt.date(s.day, locale: locale)): cost basis "
                                                + Fmt.money(s.costBasis, s.baseCurrency, locale: locale))
                    }
                }
                .chartYAxisLabel(base.code)
                .frame(height: 220)
                .accessibilityIdentifier("historyChart")
            }
        }
    }

    private func loadSnapshots() async {
        guard let id = model.selectedPortfolio?.id else { snapshots = []; return }
        snapshots = (try? await model.environment.cache.snapshots(for: id)) ?? []
    }
}

/// The goals editor and the recommendations that follow from the saved goals.
private struct GoalsSection: View {
    let model: AppModel
    @Bindable var editor: GoalsEditorModel
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Goals").font(.headline)
                Spacer()
                Picker("Scope", selection: $editor.scope) {
                    Text("Asset class").tag(GoalScope.assetClass)
                    Text("Holding").tag(GoalScope.holding)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
            ForEach($editor.rows) { $row in
                HStack {
                    if editor.scope == .assetClass {
                        Picker("Asset class", selection: $row.key) {
                            ForEach(AssetClass.allCases, id: \.self) { Text(Fmt.assetClass($0)).tag($0.rawValue) }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    } else {
                        TextField("Ticker", text: $row.key).frame(width: 140)
                    }
                    TextField("Target", text: $row.percent).frame(width: 80)
                        .accessibilityLabel("Target percent for \(row.key)")
                    Text("%")
                    Button { editor.remove(row.id) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(row.key)")
                }
            }
            HStack {
                Button("Add Target") { editor.addRow() }
                Text("Total \(Fmt.percent(editor.total, locale: locale, digits: 1))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save Goals") { Task { await editor.save() } }
                    .accessibilityIdentifier("saveGoals")
            }
            if let error = editor.error {
                Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier("goalsError")
            }
            recommendations
        }
    }

    private var recommendations: some View {
        let rows = model.valuation.map { RebalanceCalculator.rows($0, goals: model.goals, scope: editor.scope) } ?? []
        let base = model.selectedPortfolio?.baseCurrency ?? .default
        return VStack(alignment: .leading, spacing: 6) {
            Text("Recommendations").font(.subheadline.weight(.semibold)).padding(.top, 8)
            if rows.allSatisfy({ $0.targetPercent == nil }) {
                Text("Save goals to see how far each position is from its target.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
                    GridRow {
                        Text("Key"); Text("Current"); Text("Target"); Text("Drift"); Text("Buy"); Text("Shares")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(rows, id: \.key) { r in
                        GridRow {
                            Text(editor.scope == .assetClass ? AssetClass(rawValue: r.key).map(Fmt.assetClass) ?? r.key : r.key)
                                .fontWeight(.medium)
                            Text(Fmt.percent(r.currentPercent, locale: locale, digits: 1)).monospacedDigit()
                            Text(Fmt.percent(r.targetPercent, locale: locale, digits: 1)).monospacedDigit()
                            Text(Fmt.percent(r.driftPercent, locale: locale, signed: true, digits: 1)).monospacedDigit()
                            Text(Fmt.money(r.buyAmount, base, locale: locale)).monospacedDigit()
                            Text(r.buyShares.map { Fmt.number($0.rounded(scale: 4), locale: locale) } ?? "").monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .accessibilityIdentifier("recommendations")
            }
        }
    }
}

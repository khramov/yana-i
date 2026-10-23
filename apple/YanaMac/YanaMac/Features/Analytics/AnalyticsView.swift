import Charts
import SwiftUI
import YanaDomain

struct AnalyticsView: View {
    let model: AppModel
    @Environment(\.locale) private var locale
    @State private var grouping = AllocationGrouping.assetClass
    @State private var range = HistoryRange.threeMonths
    @State private var snapshots: [ValueSnapshot] = []

    private var base: Currency { model.selectedPortfolio?.baseCurrency ?? .default }

    /// The goal scope matching the grouping; sectors have no goals.
    private var goalScope: GoalScope? {
        switch grouping {
        case .holding: return .holding
        case .assetClass: return .assetClass
        case .sector: return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                allocation
                history
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: model.dataVersion) {
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
                if let scope = goalScope {
                    Button("Edit Goals") {
                        model.goalScope = scope
                        model.section = .goals
                    }
                    .accessibilityIdentifier("editGoals")
                }
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

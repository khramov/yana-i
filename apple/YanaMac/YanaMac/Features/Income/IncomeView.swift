import Charts
import SwiftUI
import YanaDomain

/// A bar in the monthly income chart, with what VoiceOver reads for it.
struct IncomeBar: Identifiable, Equatable {
    var year: Int
    var month: Int
    var amount: Decimal
    var label: String
    var valueText: String

    /// What VoiceOver announces for the bar, e.g. "Mar 2024: $10.00".
    var accessibilityLabel: String { "\(label): \(valueText)" }

    var id: String { "\(year)-\(month)" }
    var monthStart: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return LocalDate(year: year, month: month, day: 1)!.startOfDay(in: calendar)
    }
}

@MainActor
enum IncomeModel {
    static func summary(_ model: AppModel) -> IncomeSummary? {
        guard let portfolio = model.selectedPortfolio else { return nil }
        return IncomeCalculator.summary(portfolio: portfolio, holdings: model.holdings, transactions: model.transactions,
                                        market: model.market, clock: model.clock())
    }

    static func bars(_ summary: IncomeSummary, locale: Locale) -> [IncomeBar] {
        summary.monthly.map {
            IncomeBar(year: $0.year, month: $0.month, amount: $0.amount,
                      label: Fmt.month(year: $0.year, month: $0.month, locale: locale),
                      valueText: Fmt.money($0.amount, summary.baseCurrency, locale: locale))
        }
    }
}

struct IncomeView: View {
    let model: AppModel
    @Environment(\.locale) private var locale

    var body: some View {
        if let summary = IncomeModel.summary(model) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], alignment: .leading, spacing: 12) {
                        MetricTile(title: "Trailing 12 months",
                                   value: Fmt.money(summary.trailingTwelveMonths, summary.baseCurrency, locale: locale),
                                   identifier: "incomeTrailing")
                        MetricTile(title: "Forward annual (estimated)",
                                   value: Fmt.money(summary.forwardAnnual, summary.baseCurrency, locale: locale),
                                   identifier: "incomeForward")
                    }
                    if summary.forwardAnnual == nil {
                        HStack {
                            Text("Forward income needs dividend rates from market data.")
                                .foregroundStyle(.secondary)
                            Button("Refresh Market Data") { Task { await model.refreshMarketData(force: true) } }
                        }
                        .font(.callout)
                    }
                    chart(summary)
                    breakdown(summary)
                    if let refreshed = summary.lastRefreshed {
                        Text("Dividend data refreshed \(Fmt.timestamp(refreshed, locale: locale))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView("No portfolio selected", systemImage: "chart.bar")
        }
    }

    private func chart(_ summary: IncomeSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dividend income per month").font(.headline)
            let bars = IncomeModel.bars(summary, locale: locale)
            if bars.isEmpty {
                Text("No dividends recorded yet.").foregroundStyle(.secondary)
            } else {
                Chart(bars) { bar in
                    BarMark(x: .value("Month", bar.monthStart, unit: .month),
                            y: .value("Income", NSDecimalNumber(decimal: bar.amount).doubleValue))
                        .accessibilityLabel(bar.accessibilityLabel)
                }
                .chartYAxisLabel(summary.baseCurrency.code)
                .frame(height: 220)
                .accessibilityIdentifier("incomeChart")
            }
        }
    }

    private func breakdown(_ summary: IncomeSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By holding").font(.headline)
            if summary.byHolding.isEmpty {
                Text("No income yet.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    GridRow {
                        Text("Ticker"); Text("Trailing 12 months"); Text("Forward annual")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(summary.byHolding, id: \.ticker) { h in
                        GridRow {
                            Text(h.ticker).fontWeight(.medium)
                            Text(Fmt.money(h.trailingTwelveMonths, summary.baseCurrency, locale: locale)).monospacedDigit()
                            Text(Fmt.money(h.forwardAnnual, summary.baseCurrency, locale: locale)).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

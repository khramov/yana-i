import SwiftUI
import YanaDomain

struct DashboardView: View {
    let model: AppModel
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let valuation = model.valuation, valuation.holdingsCount > 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        summary(valuation)
                        topPositions(valuation)
                        notices(valuation)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .safeAreaInset(edge: .bottom) { MarketStatusBar(model: model) }
            } else {
                emptyState
            }
        }
    }

    private func summary(_ v: PortfolioValuation) -> some View {
        let base = v.baseCurrency
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], alignment: .leading, spacing: 12) {
            MetricTile(title: "Total value", value: Fmt.money(v.totalValue, base, locale: locale), identifier: "totalValue")
            MetricTile(title: "Cost basis", value: Fmt.money(v.costBasis, base, locale: locale), identifier: "costBasis")
            MetricTile(title: "Unrealized gain", value: Fmt.signedMoney(v.unrealizedGain, base, locale: locale),
                       detail: Fmt.percent(v.returnPercent, locale: locale, signed: true), tone: v.unrealizedGain,
                       identifier: "unrealizedGain")
            MetricTile(title: "Dividends received", value: Fmt.money(v.dividendsReceived, base, locale: locale),
                       identifier: "dividendsReceived")
            MetricTile(title: "Open holdings", value: "\(v.holdingsCount)", identifier: "holdingsCount")
        }
    }

    private func topPositions(_ v: PortfolioValuation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Largest positions").font(.headline)
            if v.top5.isEmpty {
                Text("Values appear once prices have been fetched.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    GridRow {
                        Text("Ticker"); Text("Market value"); Text("Weight"); Text("Return")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(v.top5, id: \.ticker) { p in
                        GridRow {
                            VStack(alignment: .leading) {
                                Text(p.ticker).fontWeight(.medium)
                                if let name = p.name { Text(name).font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(Fmt.money(p.marketValue, v.baseCurrency, locale: locale)).monospacedDigit()
                            Text(Fmt.percent(p.weightPercent, locale: locale, digits: 1)).monospacedDigit()
                            AmountCell(text: Fmt.percent(p.returnPercent, locale: locale, signed: true), tone: p.returnPercent)
                                .frame(width: 90)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .accessibilityIdentifier("topPositions")
            }
        }
    }

    @ViewBuilder
    private func notices(_ v: PortfolioValuation) -> some View {
        if !v.missingRates.isEmpty {
            Label("No exchange rate yet for \(v.missingRates.map { "\($0.from.code)→\($0.to.code)" }.joined(separator: ", ")). "
                  + "Affected values are shown as unavailable.", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if !v.unavailableTickers.isEmpty {
            Label("Not included in total value: \(v.unavailableTickers.joined(separator: ", ")).", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No open positions", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Add a holding and its transactions, or import your transaction history from a CSV file.")
        } actions: {
            HStack {
                Button("Add Holding…") { model.sheet = .addHolding }
                Button("Add Transaction…") { model.sheet = .newTransaction }
                Button("Import CSV…") { model.isImportingCSV = true }
            }
        }
        .accessibilityIdentifier("dashboardEmpty")
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var detail: String?
    var tone: Decimal?
    var identifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tone.map { $0 > 0 ? Color.green : $0 < 0 ? .red : .primary } ?? .primary)
            if let detail { Text(detail).font(.callout).monospacedDigit().foregroundStyle(.secondary) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value == Fmt.unavailable ? Fmt.unavailableLabel : value)\(detail.map { ", \($0)" } ?? "")")
        .accessibilityIdentifier(identifier ?? title)
    }
}

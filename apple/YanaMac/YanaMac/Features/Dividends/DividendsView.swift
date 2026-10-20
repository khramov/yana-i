import SwiftUI
import YanaDomain

@MainActor
enum DividendsModel {
    static func analytics(_ model: AppModel, year: Int?) -> DividendAnalytics? {
        guard let portfolio = model.selectedPortfolio else { return nil }
        return DividendAnalytics(portfolio: portfolio, holdings: model.holdings, transactions: model.transactions,
                                 market: model.market, clock: model.clock(), year: year)
    }
}

extension DividendRow: Identifiable {
    public var id: UUID { transactionID }
}

extension UpcomingDividend: Identifiable {
    public var id: String { ticker }
}

struct DividendsView: View {
    let model: AppModel
    @Environment(\.locale) private var locale
    @State private var year: Int?

    var body: some View {
        if let analytics = DividendsModel.analytics(model, year: year) {
            let base = analytics.baseCurrency
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], alignment: .leading, spacing: 12) {
                    MetricTile(title: "All time", value: Fmt.money(analytics.totalAllTime, base, locale: locale),
                               identifier: "dividendsAllTime")
                    MetricTile(title: "Trailing 12 months", value: Fmt.money(analytics.trailingTwelveMonths, base, locale: locale),
                               identifier: "dividendsTrailing")
                    MetricTile(title: "Yield on cost", value: Fmt.percent(analytics.portfolioYieldOnCost, locale: locale),
                               identifier: "dividendsYieldOnCost")
                }
                upcoming(analytics)
                Table(analytics.rows) {
                    TableColumn("Date") { (r: DividendRow) in Text(Fmt.date(r.date, locale: locale)).monospacedDigit() }
                    TableColumn("Ticker") { (r: DividendRow) in Text(r.ticker).fontWeight(.medium) }
                    TableColumn("Gross") { (r: DividendRow) in AmountCell(text: Fmt.money(r.gross, r.currency, locale: locale)) }
                    TableColumn("Per share") { (r: DividendRow) in
                        AmountCell(text: Fmt.money(r.perShare, r.currency, locale: locale))
                    }
                    TableColumn("Tax") { (r: DividendRow) in AmountCell(text: Fmt.money(r.tax, r.currency, locale: locale)) }
                    TableColumn("Yield on cost") { (r: DividendRow) in
                        AmountCell(text: Fmt.percent(r.yieldOnCost, locale: locale))
                    }
                }
                .overlay {
                    if analytics.rows.isEmpty {
                        ContentUnavailableView("No dividends", systemImage: "banknote",
                                               description: Text("Dividend transactions you record appear here."))
                    }
                }
            }
            .padding(20)
            .toolbar {
                Picker("Year", selection: $year) {
                    Text("All years").tag(Int?.none)
                    ForEach(analytics.years, id: \.self) { Text(String($0)).tag(Optional($0)) }
                }
                .accessibilityIdentifier("dividendYear")
            }
        } else {
            ContentUnavailableView("No portfolio selected", systemImage: "banknote")
        }
    }

    private func upcoming(_ analytics: DividendAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Upcoming").font(.headline)
            if analytics.upcoming.isEmpty {
                Text("No upcoming dividends in cached market data.").foregroundStyle(.secondary).font(.callout)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                    GridRow {
                        Text("Ticker"); Text("Ex-dividend"); Text("Payment"); Text("Per share"); Text("Estimated income")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(analytics.upcoming) { u in
                        GridRow {
                            Text(u.ticker).fontWeight(.medium)
                            Text(u.exDividendDate.map { Fmt.date($0, locale: locale) } ?? Fmt.unavailable)
                            Text(u.paymentDate.map { Fmt.date($0, locale: locale) } ?? Fmt.unavailable)
                            Text(Fmt.money(u.amountPerShare, u.currency, locale: locale)).monospacedDigit()
                            Text(Fmt.money(u.estimatedIncomeBase, analytics.baseCurrency, locale: locale)).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .accessibilityIdentifier("upcomingDividends")
            }
        }
    }
}

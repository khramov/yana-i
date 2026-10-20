import SwiftUI
import YanaDomain

struct HoldingsView: View {
    let model: AppModel
    @Environment(\.locale) private var locale
    @State private var showClosed = false
    @State private var sortOrder = [KeyPathComparator(\HoldingRow.ticker)]
    @State private var selection: HoldingRow.ID?
    @State private var pendingDelete: HoldingRow?
    @State private var deleteError: String?

    private var base: Currency { model.selectedPortfolio?.baseCurrency ?? .default }

    private var rows: [HoldingRow] {
        HoldingsTable.rows(holdings: model.holdings, transactions: model.transactions, valuation: model.valuation,
                           showClosed: showClosed)
            .sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Ticker", value: \.ticker) { row in
                Text(row.ticker).fontWeight(.medium).foregroundStyle(row.isClosed ? .secondary : .primary)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Name", value: \.name)
                .width(min: 120, ideal: 200)
            TableColumn("Class", value: \.assetClass)
                .width(min: 50, ideal: 60)
            TableColumn("Shares", value: \.sharesKey) { row in
                Text(Fmt.number(row.shares, locale: locale)).monospacedDigit()
            }
            TableColumn("Avg Cost", value: \.averageCostKey) { row in
                AmountCell(text: Fmt.money(row.averageCost, row.costCurrency, locale: locale))
            }
            TableColumn("Price", value: \.priceKey) { row in
                AmountCell(text: Fmt.money(row.price, row.priceCurrency, locale: locale))
            }
            TableColumn("Market Value", value: \.marketValueKey) { row in
                AmountCell(text: Fmt.money(row.marketValue, base, locale: locale))
            }
            TableColumn("Gain", value: \.gainKey) { row in
                AmountCell(text: Fmt.signedMoney(row.gain, base, locale: locale), tone: row.gain)
            }
            TableColumn("Return", value: \.returnKey) { row in
                AmountCell(text: Fmt.percent(row.returnPercent, locale: locale, signed: true), tone: row.returnPercent)
            }
        }
        .accessibilityIdentifier("holdingsTable")
        .contextMenu(forSelectionType: HoldingRow.ID.self) { ids in
            if let row = rows.first(where: { ids.contains($0.id) }) {
                Button("Edit…") { model.sheet = .editHolding(row.holding) }
                Button("Delete…", role: .destructive) { pendingDelete = row }
            }
        } primaryAction: { ids in
            if let row = rows.first(where: { ids.contains($0.id) }) { model.sheet = .editHolding(row.holding) }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label("No holdings", systemImage: "tablecells")
                } description: {
                    Text("Add a holding by its ticker, or import transactions from a CSV file.")
                } actions: {
                    Button("Add Holding…") { model.sheet = .addHolding }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            MarketStatusBar(model: model)
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle("Show Closed", isOn: $showClosed)
                    .accessibilityIdentifier("showClosed")
                Button {
                    model.sheet = .addHolding
                } label: {
                    Label("Add Holding", systemImage: "plus")
                }
                .accessibilityIdentifier("addHolding")
                Button {
                    pendingDelete = rows.first { $0.id == selection }
                } label: {
                    Label("Delete Holding", systemImage: "trash")
                }
                .disabled(selection == nil)
                .accessibilityIdentifier("deleteHolding")
            }
        }
        .confirmationDialog("Delete \(pendingDelete?.ticker ?? "")?", isPresented: .constant(pendingDelete != nil),
                            presenting: pendingDelete) { row in
            Button("Delete", role: .destructive) {
                pendingDelete = nil
                Task {
                    do {
                        try await model.deleteHolding(row.id)
                        selection = nil
                    } catch {
                        deleteError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("The holding is removed from this portfolio on all your Macs.")
        }
        .alert("The holding can't be deleted", isPresented: .constant(deleteError != nil)) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }
}

/// A right-aligned figure; `tone` colors gains green and losses red.
struct AmountCell: View {
    let text: String
    var tone: Decimal?

    var body: some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel(text == Fmt.unavailable ? Fmt.unavailableLabel : text)
    }

    private var color: Color {
        guard let tone else { return text == Fmt.unavailable ? .secondary : .primary }
        return tone > 0 ? .green : tone < 0 ? .red : .primary
    }
}

/// When prices were fetched, and whether market data is offline or some items failed.
struct MarketStatusBar: View {
    let model: AppModel
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 8) {
            if model.marketStatus.isRefreshing {
                ProgressView().controlSize(.small)
                Text("Refreshing market data…")
            } else if model.marketStatus.isOffline {
                Label("Market data is offline. Showing cached values.", systemImage: "wifi.slash")
            } else if !model.marketStatus.failedItems.isEmpty {
                Label("Couldn't refresh \(model.marketStatus.failedItems.keys.sorted().joined(separator: ", ")).",
                      systemImage: "exclamationmark.triangle")
            }
            Spacer()
            if let fetched = model.valuation?.pricesFetchedAt {
                Text("Prices as of \(Fmt.timestamp(fetched, locale: locale))")
                    .accessibilityIdentifier("pricesFetchedAt")
            } else if !(model.valuation?.positions.isEmpty ?? true) {
                Text("No prices fetched yet")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

import SwiftUI
import YanaDomain

struct TransactionsView: View {
    let model: AppModel
    @Environment(\.locale) private var locale
    @State private var filter = TransactionFilter()
    @State private var selection: TransactionRow.ID?
    @State private var pendingDelete: TransactionRow?

    private var rows: [TransactionRow] { filter.rows(model.transactions, holdings: model.holdings) }

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("Date") { row in Text(Fmt.date(row.record.date, locale: locale)).monospacedDigit() }
                .width(min: 80, ideal: 100)
            TableColumn("Ticker") { row in Text(row.ticker).fontWeight(.medium) }
                .width(min: 60, ideal: 70)
            TableColumn("Type") { row in Text(Fmt.kind(row.record.kind)) }
                .width(min: 60, ideal: 70)
            TableColumn("Shares") { row in AmountCell(text: row.record.quantity.map { Fmt.number($0, locale: locale) } ?? "") }
            TableColumn("Price / Amount") { row in
                AmountCell(text: Fmt.money(row.priceOrAmount, row.record.currency, locale: locale))
            }
            TableColumn("Fee") { row in AmountCell(text: Fmt.money(row.record.fee, row.record.currency, locale: locale)) }
            TableColumn("Tax") { row in AmountCell(text: Fmt.money(row.record.tax, row.record.currency, locale: locale)) }
            TableColumn("Currency") { row in Text(row.record.currency.code) }
                .width(min: 50, ideal: 60)
            TableColumn("Notes") { row in Text(row.record.notes ?? "").foregroundStyle(.secondary) }
        }
        .accessibilityIdentifier("transactionsTable")
        .contextMenu(forSelectionType: TransactionRow.ID.self) { ids in
            if let row = rows.first(where: { ids.contains($0.id) }) {
                Button("Edit…") { model.sheet = .editTransaction(row.record) }
                Button("Delete…", role: .destructive) { pendingDelete = row }
            }
        } primaryAction: { ids in
            if let row = rows.first(where: { ids.contains($0.id) }) { model.sheet = .editTransaction(row.record) }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label(model.transactions.isEmpty ? "No transactions" : "No matching transactions",
                          systemImage: "list.bullet.rectangle")
                } description: {
                    Text(model.transactions.isEmpty
                         ? "Add a transaction, or drop a CSV file here to import your history."
                         : "Change the filters to see more transactions.")
                } actions: {
                    if model.transactions.isEmpty {
                        Button("Add Transaction…") { model.sheet = .newTransaction }
                        Button("Import CSV…") { model.isImportingCSV = true }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("Ticker", selection: $filter.ticker) {
                    Text("All tickers").tag(String?.none)
                    ForEach(model.holdings.map(\.ticker), id: \.self) { Text($0).tag(Optional($0)) }
                }
                .accessibilityIdentifier("filterTicker")
                Picker("Type", selection: $filter.kind) {
                    Text("All types").tag(TransactionKind?.none)
                    ForEach(TransactionKind.allCases, id: \.self) { Text(Fmt.kind($0)).tag(Optional($0)) }
                }
                .accessibilityIdentifier("filterType")
                Picker("Year", selection: $filter.year) {
                    Text("All years").tag(Int?.none)
                    ForEach(TransactionFilter.years(model.transactions), id: \.self) { Text(String($0)).tag(Optional($0)) }
                }
                .accessibilityIdentifier("filterYear")
                Button {
                    model.isImportingCSV = true
                } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
                .help("Import CSV (⌘I)")
                Button {
                    model.sheet = .newTransaction
                } label: {
                    Label("New Transaction", systemImage: "plus")
                }
                .help("New Transaction (⌘N)")
                .accessibilityIdentifier("newTransaction")
                Button {
                    pendingDelete = rows.first { $0.id == selection }
                } label: {
                    Label("Delete Transaction", systemImage: "trash")
                }
                .disabled(selection == nil)
            }
        }
        .confirmationDialog("Delete this transaction?", isPresented: .constant(pendingDelete != nil),
                            presenting: pendingDelete) { row in
            Button("Delete", role: .destructive) {
                pendingDelete = nil
                Task {
                    do {
                        try await model.deleteTransaction(row.id)
                        selection = nil
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                }
            }
            .accessibilityIdentifier("confirmDeleteTransaction")
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { row in
            Text("\(Fmt.kind(row.record.kind)) of \(row.ticker) on \(Fmt.date(row.record.date, locale: locale)) "
                 + "will be deleted on all your Macs.")
        }
    }
}

struct TransactionFormSheet: View {
    @State private var form: TransactionFormModel
    @Environment(\.dismiss) private var dismiss
    private let holdings: [HoldingRecord]
    private let openAddHolding: () -> Void

    init(model: AppModel, editing: TransactionRecord?) {
        _form = State(initialValue: TransactionFormModel(model: model, editing: editing))
        holdings = model.holdings
        openAddHolding = { model.sheet = .addHolding }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(form.editing == nil ? "New Transaction" : "Edit Transaction")
                .font(.headline)
                .padding([.top, .horizontal])
            if holdings.isEmpty {
                ContentUnavailableView {
                    Label("Add a holding first", systemImage: "tablecells")
                } description: {
                    Text("Transactions belong to a holding. Add the ticker you traded, then record the transaction.")
                } actions: {
                    Button("Add Holding…", action: openAddHolding)
                }
                .frame(height: 220)
            } else {
                fields
            }
            HStack {
                if let failure = form.failure { Text(failure).font(.caption).foregroundStyle(.red) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task { if await form.save() { dismiss() } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(form.isSaving || holdings.isEmpty)
                .accessibilityIdentifier("saveTransaction")
            }
            .padding()
        }
        .frame(width: 440)
    }

    private var fields: some View {
        Form {
            Picker("Holding", selection: $form.holdingID) {
                Text("Choose…").tag(UUID?.none)
                ForEach(holdings) { Text($0.ticker).tag(Optional($0.id)) }
            }
            .disabled(form.editing != nil)
            .accessibilityIdentifier("transactionHolding")
            FieldError(message: form.holdingError)
            Picker("Type", selection: $form.kind) {
                ForEach(TransactionKind.allCases, id: \.self) { Text(Fmt.kind($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("transactionKind")
            DatePicker("Date", selection: $form.date, displayedComponents: .date)
            FieldError(message: form.errors[.date])
            if form.kind != .fee {
                TextField(form.kind == .dividend ? "Shares (optional)" : "Shares", text: $form.quantity)
                    .accessibilityIdentifier("transactionShares")
                FieldError(message: form.errors[.quantity])
            }
            if form.kind.isTrade {
                TextField("Price per share", text: $form.unitPrice)
                    .accessibilityIdentifier("transactionPrice")
                FieldError(message: form.errors[.unitPrice])
            } else {
                TextField(form.kind == .dividend ? "Gross amount" : "Amount", text: $form.amount)
                    .accessibilityIdentifier("transactionAmount")
                FieldError(message: form.errors[.amount])
            }
            TextField("Fee", text: $form.fee, prompt: Text("0"))
                .accessibilityIdentifier("transactionFee")
            FieldError(message: form.errors[.fee])
            if form.kind == .dividend || form.kind == .sell {
                TextField(form.kind == .dividend ? "Tax withheld" : "Tax", text: $form.tax, prompt: Text("0"))
                FieldError(message: form.errors[.tax])
            }
            Picker("Currency", selection: $form.currency) {
                ForEach(Currency.allCases, id: \.self) { Text($0.code).tag($0) }
            }
            TextField("Notes", text: $form.notes)
        }
        .formStyle(.grouped)
    }
}

struct CSVImportResultSheet: View {
    let outcome: CSVImportOutcome
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Imported \(outcome.fileName)").font(.headline)
            if let fileError = outcome.fileError {
                Label(fileError, systemImage: "xmark.octagon").foregroundStyle(.red)
                Text("Required columns: \(CSVImportPlanner.requiredColumns.joined(separator: ", ")). Optional: shares, "
                     + "price, fee, tax, currency, notes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 24) {
                    Label("\(outcome.imported) imported", systemImage: "checkmark.circle")
                        .accessibilityIdentifier("importedCount")
                    Label("\(outcome.errors.count) failed", systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("failedCount")
                    if outcome.holdingsCreated > 0 {
                        Label("\(outcome.holdingsCreated) new holdings", systemImage: "plus.circle")
                    }
                }
                if !outcome.errors.isEmpty {
                    Table(outcome.errors, columns: {
                        TableColumn("Line") { (e: CSVLineError) in Text(String(e.line)).monospacedDigit() }
                            .width(50)
                        TableColumn("Problem") { (e: CSVLineError) in Text(e.message) }
                    })
                    .frame(minHeight: 140)
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

extension CSVLineError: Identifiable {
    public var id: Int { line }
}

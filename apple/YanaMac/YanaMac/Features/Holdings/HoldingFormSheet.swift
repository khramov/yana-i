import SwiftUI
import YanaDomain

struct HoldingFormSheet: View {
    @State private var form: HoldingFormModel
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, editing: HoldingRecord?) {
        _form = State(initialValue: HoldingFormModel(model: model, editing: editing))
    }

    private var isEditing: Bool {
        if case .edit = form.mode { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? "Edit \(form.ticker)" : "Add Holding")
                .font(.headline)
                .padding([.top, .horizontal])
            Form {
                TextField("Ticker", text: $form.ticker, prompt: Text("AAPL"))
                    .disabled(isEditing)
                    .accessibilityIdentifier("holdingTicker")
                FieldError(message: form.tickerError)
                if isEditing {
                    Text("A holding's ticker can't be changed.").font(.caption).foregroundStyle(.secondary)
                }
                if let notice = form.notice {
                    Label(notice, systemImage: "wifi.slash")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("holdingNotice")
                }
                if form.mode != .lookup {
                    TextField("Name", text: $form.name)
                        .accessibilityIdentifier("holdingName")
                    TextField("Sector", text: $form.sector)
                    Picker("Asset class", selection: $form.assetClass) {
                        ForEach(AssetClass.allCases, id: \.self) { Text(Fmt.assetClass($0)).tag($0) }
                    }
                    Picker("Currency", selection: $form.currency) {
                        ForEach(Currency.allCases, id: \.self) { Text($0.code).tag($0) }
                    }
                } else {
                    Text("Name, asset class, sector, and currency are looked up automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                if form.isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") {
                    Task { if await form.submit() != nil { dismiss() } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(form.isWorking)
                .accessibilityIdentifier("saveHolding")
            }
            .padding()
        }
        .frame(width: 420)
    }
}

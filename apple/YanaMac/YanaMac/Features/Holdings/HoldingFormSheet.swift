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

    private var isOption: Binding<Bool> {
        Binding(get: { form.assetClass == .option }, set: { form.assetClass = $0 ? .option : .default })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? "Edit \(form.ticker)" : "Add Holding")
                .font(.headline)
                .padding([.top, .horizontal])
            Form {
                if !isEditing {
                    Picker("Type", selection: isOption) {
                        Text("Security").tag(false)
                        Text("Option").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("holdingType")
                }
                if !isEditing && form.assetClass == .option {
                    optionFields
                } else {
                    securityFields
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

    @ViewBuilder private var optionFields: some View {
        TextField("Underlying", text: $form.optionUnderlying, prompt: Text("PBR"))
            .accessibilityIdentifier("optionUnderlying")
        DatePicker("Expiry", selection: $form.optionExpiry, displayedComponents: .date)
        Picker("Right", selection: $form.optionRight) {
            Text("Call").tag(OptionRight.call)
            Text("Put").tag(OptionRight.put)
        }
        .pickerStyle(.segmented)
        TextField("Strike", text: $form.optionStrike, prompt: Text("27"))
            .accessibilityIdentifier("optionStrike")
        TextField("Multiplier", text: $form.optionMultiplier, prompt: Text("100"))
        Picker("Currency", selection: $form.currency) {
            ForEach(Currency.allCases, id: \.self) { Text($0.code).tag($0) }
        }
        FieldError(message: form.optionError)
        if let contract = form.optionPreview {
            LabeledContent(contract.displayName, value: contract.occSymbol)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("optionPreview")
        }
    }

    @ViewBuilder private var securityFields: some View {
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
                    if form.assetClass == .option {
                        TextField("Multiplier", text: $form.optionMultiplier, prompt: Text("100"))
                        FieldError(message: form.optionError)
                    }
                } else {
                    Text("Name, asset class, sector, and currency are looked up automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
    }
}

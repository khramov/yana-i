import SwiftUI
import YanaDomain

/// First launch with no portfolios: create one, then the empty dashboard offers the next steps.
struct OnboardingView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Welcome to Yana")
                .font(.largeTitle.weight(.semibold))
            Text("Create a portfolio to start tracking holdings, transactions, and dividends.")
                .foregroundStyle(.secondary)
            PortfolioForm(submitTitle: "Create Portfolio") { draft in
                try await model.createPortfolio(draft)
            }
            .frame(width: 360)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Name and base currency, validated on submit.
struct PortfolioForm: View {
    let submitTitle: String
    var cancel: (() -> Void)?
    let submit: (PortfolioDraft) async throws -> Void

    @State private var name = ""
    @State private var currency = Currency.default
    @State private var nameError: String?
    @State private var isSaving = false

    init(submitTitle: String, cancel: (() -> Void)? = nil, submit: @escaping (PortfolioDraft) async throws -> Void) {
        self.submitTitle = submitTitle
        self.cancel = cancel
        self.submit = submit
    }

    var body: some View {
        Form {
            TextField("Name", text: $name, prompt: Text("Long term"))
                .accessibilityIdentifier("portfolioName")
            FieldError(message: nameError)
            Picker("Base currency", selection: $currency) {
                ForEach(Currency.allCases, id: \.self) { Text($0.code).tag($0) }
            }
            .accessibilityIdentifier("portfolioCurrency")
            HStack {
                Spacer()
                if let cancel {
                    Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                }
                Button(submitTitle) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
                    .accessibilityIdentifier("savePortfolio")
            }
        }
        .formStyle(.grouped)
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await submit(PortfolioDraft(name: name, baseCurrency: currency))
                nameError = nil
            } catch let error as ValidationError {
                nameError = error.message(for: .name)
            } catch {
                nameError = error.localizedDescription
            }
        }
    }
}

struct PortfolioFormSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading) {
            Text("New Portfolio").font(.headline).padding([.top, .horizontal])
            PortfolioForm(submitTitle: "Create", cancel: { dismiss() }) { draft in
                try await model.createPortfolio(draft)
                dismiss()
            }
        }
        .frame(width: 380)
    }
}

/// A validation message under a form field.
struct FieldError: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("fieldError")
        }
    }
}

struct AppCommands: Commands {
    let model: AppModel?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Transaction…") { model?.sheet = .newTransaction }
                .keyboardShortcut("n")
                .disabled(model?.selectedPortfolio == nil)
            Button("New Portfolio…") { model?.sheet = .newPortfolio }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model?.isLoaded != true)
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Import CSV…") { model?.isImportingCSV = true }
                .keyboardShortcut("i")
                .disabled(model?.selectedPortfolio == nil)
        }
        CommandGroup(before: .toolbar) {
            Button("Refresh Market Data") { Task { await model?.refreshMarketData(force: true) } }
                .keyboardShortcut("r")
                .disabled(model?.selectedPortfolio == nil)
            Divider()
        }
    }
}

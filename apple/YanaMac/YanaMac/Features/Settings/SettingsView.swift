import Observation
import SwiftUI
import YanaDomain
import YanaMarketData
import YanaSync

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            PortfolioSettings(model: model)
                .tabItem { Label("Portfolios", systemImage: "folder") }
            SyncSettings(sync: model.sync)
                .tabItem { Label("iCloud", systemImage: "icloud") }
            MarketDataSettings(model: model)
                .tabItem { Label("Market Data", systemImage: "chart.line.uptrend.xyaxis") }
        }
        .frame(width: 520, height: 360)
    }
}

private struct PortfolioSettings: View {
    let model: AppModel
    @State private var selection: UUID?
    @State private var name = ""
    @State private var currency = Currency.default
    @State private var error: String?
    @State private var confirmDelete = false

    private var selected: PortfolioRecord? { model.portfolios.first { $0.id == selection } }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            List(model.portfolios, selection: $selection) { p in
                Text(p.name).tag(p.id)
            }
            .frame(width: 170)
            .accessibilityIdentifier("settingsPortfolios")
            Form {
                if let selected {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("settingsPortfolioName")
                    FieldError(message: error)
                    Picker("Base currency", selection: $currency) {
                        ForEach(Currency.allCases, id: \.self) { Text($0.code).tag($0) }
                    }
                    .accessibilityIdentifier("settingsBaseCurrency")
                    Text("Changing the base currency recalculates every value of this portfolio.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Delete Portfolio…", role: .destructive) { confirmDelete = true }
                        Spacer()
                        Button("Save") { save(selected.id) }
                            .keyboardShortcut(.defaultAction)
                            .disabled(name == selected.name && currency == selected.baseCurrency)
                            .accessibilityIdentifier("settingsSavePortfolio")
                    }
                } else {
                    Text("Select a portfolio.").foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { selection = selection ?? model.selectedPortfolioID }
        .onChange(of: selection, initial: true) { _, _ in
            name = selected?.name ?? ""
            currency = selected?.baseCurrency ?? .default
            error = nil
        }
        .confirmationDialog("Delete “\(selected?.name ?? "")”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                guard let id = selection else { return }
                Task {
                    do { try await model.deletePortfolio(id); selection = model.portfolios.first?.id } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("All of its holdings, transactions, and goals are deleted on all your Macs.")
        }
    }

    private func save(_ id: UUID) {
        Task {
            do {
                try await model.updatePortfolio(id, PortfolioDraft(name: name, baseCurrency: currency))
                error = nil
            } catch let e as ValidationError {
                error = e.message(for: .name) ?? e.description
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct SyncSettings: View {
    let sync: SyncController
    @Environment(\.locale) private var locale

    var body: some View {
        let status = sync.status
        Form {
            LabeledContent("Status") {
                Text(status.summary).accessibilityIdentifier("settingsSyncSummary")
            }
            if let reason = status.reason {
                Text(reason).font(.callout).foregroundStyle(.secondary)
            }
            LabeledContent("Last successful sync") {
                Text(status.lastSuccessfulSync.map { Fmt.timestamp($0, locale: locale) } ?? "Never")
            }
            if let notice = status.readOnlyNotice {
                Label(notice, systemImage: "arrow.down.app").font(.callout)
            }
            HStack {
                Spacer()
                Button("Sync Now") { Task { await sync.syncNow() } }
                    .disabled(!status.canSyncNow || status.state == .syncing)
            }
            Text("Portfolios, holdings, transactions, and goals sync through your private iCloud database. Prices, "
                 + "value history, preferences, and credentials stay on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct MarketDataSettings: View {
    let model: AppModel
    @Environment(\.locale) private var locale

    var body: some View {
        let provider = model.provider
        Form {
            LabeledContent("Provider", value: provider.displayName)
            if provider.isUnofficial {
                Label("This source is unofficial and might stop working without notice. Yana then keeps showing the "
                      + "last cached values.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("unofficialNotice")
            }
            LabeledContent("Status") {
                Text(model.marketStatus.isOffline ? "Offline" :
                        model.marketStatus.failedItems.isEmpty ? "OK" : "Some items failed")
            }
            LabeledContent("Last refresh") {
                Text(model.marketStatus.lastRefresh.map { Fmt.timestamp($0, locale: locale) } ?? "Not this session")
            }
            Text("Requests contain only the tickers and currency pairs being looked up.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if provider.requiresCredential {
                CredentialSection(credentials: CredentialSettingsModel(store: model.environment.credentials,
                                                                       providerID: provider.id))
            }
        }
        .formStyle(.grouped)
    }
}

/// Save, replace, or remove a provider's credential. Only shown for providers that need one.
@MainActor @Observable
final class CredentialSettingsModel {
    var input = ""
    private(set) var hasCredential: Bool
    private(set) var error: String?

    private let store: any CredentialStore
    private let providerID: String

    init(store: any CredentialStore, providerID: String) {
        self.store = store
        self.providerID = providerID
        hasCredential = ((try? store.credential(for: providerID)) ?? nil) != nil
    }

    func save() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { error = "Enter the credential"; return }
        do {
            try store.save(value, for: providerID)
            input = ""
            hasCredential = true
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func remove() {
        do {
            try store.remove(for: providerID)
            hasCredential = false
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct CredentialSection: View {
    @State var credentials: CredentialSettingsModel

    var body: some View {
        Section("Credential") {
            Text(credentials.hasCredential ? "A credential is saved in this Mac's Keychain."
                 : "This provider requires a credential.")
                .font(.callout)
            SecureField(credentials.hasCredential ? "Replace credential" : "Credential", text: $credentials.input)
            FieldError(message: credentials.error)
            HStack {
                if credentials.hasCredential {
                    Button("Remove", role: .destructive) { credentials.remove() }
                }
                Spacer()
                Button("Save") { credentials.save() }
            }
            Text("Stored only in this Mac's Keychain; it never syncs to iCloud.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

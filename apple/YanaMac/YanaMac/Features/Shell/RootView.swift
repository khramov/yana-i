import SwiftUI
import UniformTypeIdentifiers
import YanaDomain
import YanaSync

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !model.isLoaded {
                ProgressView()
            } else if model.portfolios.isEmpty {
                OnboardingView(model: model)
            } else {
                NavigationSplitView {
                    SidebarView(model: model)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
                } detail: {
                    SectionView(model: model)
                        .onDrop(of: [.fileURL], isTargeted: nil) { providers in importDropped(providers) }
                }
            }
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .newPortfolio: PortfolioFormSheet(model: model)
            case .addHolding: HoldingFormSheet(model: model, editing: nil)
            case .editHolding(let holding): HoldingFormSheet(model: model, editing: holding)
            case .newTransaction: TransactionFormSheet(model: model, editing: nil)
            case .editTransaction(let transaction): TransactionFormSheet(model: model, editing: transaction)
            case .importResult(let outcome): CSVImportResultSheet(outcome: outcome)
            }
        }
        .sheet(isPresented: .constant(model.sync.unsentChangesWarning != nil)) {
            AccountChangeSheet(count: model.sync.unsentChangesWarning ?? 0) {
                Task { await model.sync.acknowledgeAccountChange() }
            }
            .interactiveDismissDisabled()
        }
        .fileImporter(isPresented: $model.isImportingCSV, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            if case .success(let url) = result { Task { await model.importCSV(from: url) } }
        }
        .alert("Something went wrong", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            model.isActive = phase == .active
            if phase == .active { Task { await model.refreshMarketData() } }
        }
    }

    private func importDropped(_ providers: [NSItemProvider]) -> Bool {
        guard model.selectedPortfolio != nil,
              let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
        else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in await model.importCSV(from: url) }
        }
        return true
    }
}

struct SectionView: View {
    let model: AppModel

    var body: some View {
        Group {
            switch model.section {
            case .dashboard: DashboardView(model: model)
            case .holdings: HoldingsView(model: model)
            case .transactions: TransactionsView(model: model)
            case .income: IncomeView(model: model)
            case .dividends: DividendsView(model: model)
            case .analytics: AnalyticsView(model: model)
            case .goals: GoalsView(model: model)
            }
        }
        .navigationTitle(model.section.title)
        .navigationSubtitle(model.selectedPortfolio?.name ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refreshMarketData(force: true) }
                } label: {
                    Label("Refresh Market Data", systemImage: "arrow.clockwise")
                }
                .disabled(model.marketStatus.isRefreshing)
                .help("Refresh Market Data (⌘R)")
            }
        }
    }
}

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: Binding(get: { model.section }, set: { if let s = $0 { model.section = s } })) {
            Section {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                        .accessibilityIdentifier("section-\(section.rawValue)")
                }
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Picker("Portfolio", selection: $model.selectedPortfolioID) {
                    ForEach(model.portfolios) { portfolio in
                        Text(portfolio.name).tag(Optional(portfolio.id))
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("portfolioPicker")
                Button {
                    model.sheet = .newPortfolio
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New Portfolio (⇧⌘N)")
                .accessibilityLabel("New Portfolio")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom) {
            SyncStatusFooter(status: model.sync.status)
                .padding(12)
        }
    }
}

struct SyncStatusFooter: View {
    let status: SyncStatus
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(status.summary, systemImage: icon)
                .font(.callout)
            if let last = status.lastSuccessfulSync {
                Text("Last synced \(Fmt.timestamp(last, locale: locale))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("syncStatus")
        .help(status.reason ?? status.summary)
    }

    private var icon: String {
        switch status.state {
        case .upToDate: return "checkmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .pendingChanges: return "icloud.and.arrow.up"
        case .offline: return "icloud.slash"
        case .off: return "xmark.icloud"
        case .error: return "exclamationmark.icloud"
        }
    }
}

struct AccountChangeSheet: View {
    let count: Int
    let acknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your iCloud account changed", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.headline)
            Text(count == 1
                 ? "1 change made on this Mac was never uploaded to the previous iCloud account."
                 : "\(count) changes made on this Mac were never uploaded to the previous iCloud account.")
            Text("To keep accounts separate, Yana removes the previous account's portfolios from this Mac. "
                 + "Those unsent changes will be lost. Data already in the previous account's iCloud stays there.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Remove and Continue", role: .destructive, action: acknowledge)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

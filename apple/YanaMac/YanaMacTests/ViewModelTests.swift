import Foundation
import Testing
import YanaDomain
import YanaMarketData
@testable import YanaMac

let utcCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// 2024-07-15 12:00 UTC.
let fixedClock = CalculationClock(now: Date(timeIntervalSince1970: 1_721_044_800), calendar: utcCalendar)

private final class BundleToken {}

func fixtureURL(_ name: String) -> URL {
    Bundle(for: BundleToken.self).url(forResource: name, withExtension: nil)!
}

/// An app model over in-memory stores and the stub provider, with a fixed clock.
@MainActor
func makeAppModel(offline: Bool = false, defaultsSuite: String = "yana.tests.\(UUID().uuidString)") async throws -> AppModel {
    let options = LaunchOptions(inMemory: true, defaultsSuite: defaultsSuite, stubMarketData: true, stubOffline: offline)
    let (environment, sync) = try await AppEnvironment.make(options)
    let model = AppModel(environment: environment, sync: sync)
    model.clock = { fixedClock }
    await model.start()
    return model
}

@MainActor
@discardableResult
func addHolding(_ model: AppModel, _ ticker: String) async throws -> HoldingRecord {
    let form = HoldingFormModel(model: model, editing: nil)
    form.ticker = ticker
    guard case .created(let holding) = await form.submit() else { throw PortfolioRepositoryError.notFound }
    return holding
}

@MainActor @Suite(.serialized) struct AppShellModelTests {
    @Test func firstPortfolioIsSelectedAndSelectionIsRestored() async throws {
        let suite = "yana.tests.\(UUID().uuidString)"
        let model = try await makeAppModel(defaultsSuite: suite)
        #expect(model.portfolios.isEmpty && model.selectedPortfolio == nil)

        let created = try await model.createPortfolio(PortfolioDraft(name: "Long term"))
        #expect(model.selectedPortfolioID == created.id)
        #expect(model.selectedPortfolio?.baseCurrency == .eur)
        model.section = .dividends

        let defaults = UserDefaults(suiteName: suite)!
        #expect(defaults.string(forKey: "selection.portfolio") == created.id.uuidString)
        #expect(defaults.string(forKey: "selection.section") == "dividends")
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func switchingPortfolioShowsItsDataInItsCurrency() async throws {
        let model = try await makeAppModel()
        let eur = try await model.createPortfolio(PortfolioDraft(name: "EUR"))
        try await addHolding(model, "AAPL")
        let usd = try await model.createPortfolio(PortfolioDraft(name: "USD", baseCurrency: .usd))
        #expect(model.holdings.isEmpty && model.valuation?.baseCurrency == .usd)
        await model.select(eur.id)
        #expect(model.holdings.map(\.ticker) == ["AAPL"] && model.valuation?.baseCurrency == .eur)
        _ = usd
    }
}

@MainActor @Suite(.serialized) struct HoldingsModelTests {
    @Test func addByTickerLooksUpDetails() async throws {
        let model = try await makeAppModel()
        try await model.createPortfolio(PortfolioDraft(name: "P"))
        let vti = try await addHolding(model, " vti ")
        #expect(vti.ticker == "VTI" && vti.assetClass == .etf && vti.currency == .usd)
        #expect(vti.name == "Vanguard Total Stock Market ETF")

        let again = HoldingFormModel(model: model, editing: nil)
        again.ticker = "vti"
        #expect(await again.submit() == .existing(vti))
        #expect(model.holdings.count == 1)
    }

    func optionForm(_ model: AppModel, strike: String) -> HoldingFormModel {
        let form = HoldingFormModel(model: model, editing: nil)
        form.assetClass = .option
        form.optionUnderlying = "pbr"
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .current
        form.optionExpiry = utc.date(from: DateComponents(year: 2027, month: 12, day: 17))!
        form.optionRight = .call
        form.optionStrike = strike
        form.optionMultiplier = "100"
        form.currency = .usd
        return form
    }

    @Test func optionFormBuildsOCCTicker() async throws {
        let model = try await makeAppModel()
        try await model.createPortfolio(PortfolioDraft(name: "P"))
        let form = optionForm(model, strike: "27")
        #expect(form.optionPreview?.occSymbol == "PBR271217C00027000")
        guard case .created(let h) = await form.submit() else { Issue.record("not created"); return }
        #expect(h.ticker == "PBR271217C00027000" && h.name == "PBR 17DEC27 27 C")
        #expect(h.assetClass == .option && h.multiplier == 100 && h.currency == .usd)
    }

    @Test func optionFormRequiresStrike() async throws {
        let model = try await makeAppModel()
        try await model.createPortfolio(PortfolioDraft(name: "P"))
        let form = optionForm(model, strike: "")
        #expect(await form.submit() == nil)
        #expect(form.optionError != nil)
        #expect(model.holdings.isEmpty)
    }

    @Test func editingOptionKeepsMultiplier() async throws {
        let model = try await makeAppModel()
        try await model.createPortfolio(PortfolioDraft(name: "P"))
        guard case .created(let h) = await optionForm(model, strike: "27").submit() else { Issue.record("not created"); return }
        let edit = HoldingFormModel(model: model, editing: h)
        edit.name = "Petrobras call"
        #expect(await edit.submit() == .updated)
        let saved = try #require(model.holdings.first { $0.id == h.id })
        #expect(saved.name == "Petrobras call" && saved.multiplier == 100)
    }

    @Test func unknownTickerCreatesNothing() async throws {
        let model = try await makeAppModel()
        try await model.createPortfolio(PortfolioDraft(name: "P"))
        let form = HoldingFormModel(model: model, editing: nil)
        form.ticker = "ZZZZQ"
        #expect(await form.submit() == nil)
        #expect(form.tickerError?.contains("ZZZZQ was not found") == true)
        #expect(model.holdings.isEmpty)
    }

    @Test func offlineFallsBackToManualEntry() async throws {
        let model = try await makeAppModel(offline: true)
        try await model.createPortfolio(PortfolioDraft(name: "P"))
        let form = HoldingFormModel(model: model, editing: nil)
        form.ticker = "MSFT"
        #expect(await form.submit() == nil)
        #expect(form.mode == .manual && form.notice != nil)
        form.name = "Microsoft"
        form.assetClass = .stock
        form.currency = .usd
        guard case .created(let msft) = await form.submit() else { Issue.record("not created"); return }
        #expect(msft.name == "Microsoft" && msft.currency == .usd)
    }

    @Test func rowsShowUnavailableValuesAndClosedHoldings() async throws {
        let model = try await makeAppModel(offline: true)
        try await model.createPortfolio(PortfolioDraft(name: "P"))
        let form = HoldingFormModel(model: model, editing: nil)
        form.ticker = "KO"
        _ = await form.submit()
        form.currency = .usd
        guard case .created(let ko) = await form.submit() else { Issue.record("not created"); return }
        let closedForm = HoldingFormModel(model: model, editing: nil)
        closedForm.ticker = "T"
        _ = await closedForm.submit()
        guard case .created(let t) = await closedForm.submit() else { Issue.record("not created"); return }
        let newForm = HoldingFormModel(model: model, editing: nil)
        newForm.ticker = "NEW"
        _ = await newForm.submit()
        _ = await newForm.submit()

        try await model.addTransaction(TransactionDraft(kind: .buy, date: LocalDate(string: "2024-01-02"), quantity: 10,
                                                        unitPrice: 50, currency: .usd), holdingID: ko.id)
        for kind in [TransactionKind.buy, .sell] {
            try await model.addTransaction(TransactionDraft(kind: kind, date: LocalDate(string: "2024-01-03"), quantity: 1,
                                                            unitPrice: 5, currency: .usd), holdingID: t.id)
        }
        let rows = HoldingsTable.rows(holdings: model.holdings, transactions: model.transactions,
                                      valuation: model.valuation, showClosed: false)
        // NEW has no trades yet, so it is listed; T was sold down to zero, so it is closed.
        #expect(rows.map(\.ticker) == ["KO", "NEW"])
        #expect(rows.allSatisfy { !$0.isClosed })
        let row = try #require(rows.first)
        #expect(row.price == nil && row.marketValue == nil && row.gain == nil)
        #expect(row.averageCost == 50 && row.shares == 10)
        #expect(Fmt.money(row.marketValue, .eur, locale: Locale(identifier: "en_US")) == Fmt.unavailable)

        let withClosed = HoldingsTable.rows(holdings: model.holdings, transactions: model.transactions,
                                            valuation: model.valuation, showClosed: true)
        #expect(withClosed.map(\.ticker) == ["KO", "NEW", "T"] && withClosed[2].isClosed)
    }

    @Test func pricedRowsSortByMarketValue() async throws {
        let model = try await makeAppModel()
        try await model.createPortfolio(PortfolioDraft(name: "P", baseCurrency: .usd))
        for (ticker, shares) in [("AAPL", 1), ("MSFT", 1), ("KO", 1)] {
            let h = try await addHolding(model, ticker)
            try await model.addTransaction(TransactionDraft(kind: .buy, date: LocalDate(string: "2024-01-02"),
                                                            quantity: Decimal(shares), unitPrice: 10, currency: .usd),
                                           holdingID: h.id)
        }
        await model.refreshMarketData(force: true)
        let rows = HoldingsTable.rows(holdings: model.holdings, transactions: model.transactions,
                                      valuation: model.valuation, showClosed: false)
        #expect(rows.sorted(using: KeyPathComparator(\HoldingRow.marketValueKey, order: .reverse)).map(\.ticker)
            == ["MSFT", "AAPL", "KO"])
        #expect(model.valuation?.top5.first?.ticker == "MSFT")
        #expect(model.valuation?.pricesFetchedAt != nil)
    }

    @Test func deleteGuardMessage() async throws {
        let model = try await makeAppModel()
        try await model.createPortfolio(PortfolioDraft(name: "P"))
        let h = try await addHolding(model, "KO")
        try await model.addTransaction(TransactionDraft(kind: .buy, date: LocalDate(string: "2024-01-02"), quantity: 1,
                                                        unitPrice: 1, currency: .usd), holdingID: h.id)
        await #expect(throws: PortfolioRepositoryError.holdingHasTransactions(count: 1)) {
            try await model.deleteHolding(h.id)
        }
    }
}

@MainActor @Suite(.serialized) struct TransactionsModelTests {
    @Test func sellWithoutSharesShowsFieldError() async throws {
        let model = try await makeAppModel()
        try await model.createPortfolio(PortfolioDraft(name: "P"))
        try await addHolding(model, "KO")
        let form = TransactionFormModel(model: model, editing: nil, locale: Locale(identifier: "en_US"), calendar: utcCalendar)
        form.kind = .sell
        form.unitPrice = "60"
        #expect(await form.save() == false)
        #expect(form.errors[.quantity] == "Shares are required for buy and sell")
        #expect(model.transactions.isEmpty)

        form.quantity = "abc"
        #expect(await form.save() == false)
        #expect(form.errors[.quantity] == "Enter a number")
    }

    @Test func editingABuyUpdatesHoldings() async throws {
        let model = try await makeAppModel()
        try await model.createPortfolio(PortfolioDraft(name: "P"))
        let h = try await addHolding(model, "KO")
        let de = Locale(identifier: "de_DE")
        let form = TransactionFormModel(model: model, editing: nil, locale: de, calendar: utcCalendar)
        #expect(form.holdingID == h.id && form.currency == .usd)
        form.quantity = "10"
        form.unitPrice = "50,5"
        #expect(await form.save())
        let buy = try #require(model.transactions.first)
        #expect(buy.unitPrice == Decimal(string: "50.5"))
        #expect(model.valuation?.positions.first?.position.shares == 10)

        let edit = TransactionFormModel(model: model, editing: buy, locale: de, calendar: utcCalendar)
        #expect(edit.unitPrice == "50,5")
        edit.quantity = "12"
        #expect(await edit.save())
        #expect(model.valuation?.positions.first?.position.shares == 12)
        #expect(model.transactions.count == 1)
    }

    @Test func filtersAndNewestFirst() async throws {
        let model = try await makeAppModel()
        try await model.createPortfolio(PortfolioDraft(name: "P"))
        let ko = try await addHolding(model, "KO")
        let vti = try await addHolding(model, "VTI")
        for (h, kind, day) in [(ko, TransactionKind.buy, "2023-05-01"), (ko, .dividend, "2024-04-01"),
                               (vti, .buy, "2024-02-01")] {
            try await model.addTransaction(TransactionDraft(kind: kind, date: LocalDate(string: day), quantity: 1,
                                                            unitPrice: kind == .buy ? 1 : nil, amount: kind == .buy ? nil : 1,
                                                            currency: .usd), holdingID: h.id)
        }
        let all = TransactionFilter().rows(model.transactions, holdings: model.holdings)
        #expect(all.map(\.record.date.description) == ["2024-04-01", "2024-02-01", "2023-05-01"])
        #expect(TransactionFilter(ticker: "KO").rows(model.transactions, holdings: model.holdings).count == 2)
        #expect(TransactionFilter(kind: .buy, year: 2024).rows(model.transactions, holdings: model.holdings)
            .map(\.ticker) == ["VTI"])
        #expect(TransactionFilter.years(model.transactions) == [2024, 2023])
    }

    @Test func csvFixtureWithOneBadRow() async throws {
        let model = try await makeAppModel()
        try await model.createPortfolio(PortfolioDraft(name: "P"))
        await model.importCSV(from: fixtureURL("import-one-bad-row.csv"))
        guard case .importResult(let outcome) = model.sheet else { Issue.record("no result sheet"); return }
        #expect(outcome.imported == 4 && outcome.holdingsCreated == 2)
        #expect(outcome.errors.map(\.line) == [5])
        #expect(outcome.errors.first?.message.contains("transfer") == true)
        #expect(outcome.fileError == nil)
        #expect(Set(model.holdings.map(\.ticker)) == ["VTI", "KO"])
        let vti = try #require(model.valuation?.positions.first { $0.ticker == "VTI" })
        #expect(vti.position.shares == Decimal(string: "12.5"))
    }

    @Test func ibkrStatementOutcomeCounts() async throws {
        let model = try await makeAppModel()
        try await model.createPortfolio(PortfolioDraft(name: "P"))
        await model.importCSV(from: fixtureURL("ibkr-aug-oct.csv"))
        guard case .importResult(let first) = model.sheet else { Issue.record("no result sheet"); return }
        #expect(first.imported == 4 && first.replaced == 0 && first.absorbed == 0 && first.fileError == nil)
        #expect(first.warnings.isEmpty && first.errors.isEmpty)
        await model.importCSV(from: fixtureURL("ibkr-aug-oct.csv"))
        guard case .importResult(let second) = model.sheet else { Issue.record("no result sheet"); return }
        #expect(second.imported == 4 && second.replaced == 4)
    }

    @Test func csvWithoutRequiredColumnsImportsNothing() async throws {
        let model = try await makeAppModel()
        try await model.createPortfolio(PortfolioDraft(name: "P"))
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).csv")
        try "ticker,type\nKO,buy\n".write(to: url, atomically: true, encoding: .utf8)
        await model.importCSV(from: url)
        guard case .importResult(let outcome) = model.sheet else { Issue.record("no result sheet"); return }
        #expect(outcome.fileError?.contains("'date'") == true)
        #expect(model.transactions.isEmpty && model.holdings.isEmpty)
    }
}

@MainActor @Suite(.serialized) struct IncomeAndDividendsModelTests {
    private func portfolioWithDividends(offline: Bool = false) async throws -> AppModel {
        let model = try await makeAppModel(offline: offline)
        try await model.createPortfolio(PortfolioDraft(name: "P", baseCurrency: .usd))
        let form = HoldingFormModel(model: model, editing: nil)
        form.ticker = "KO"
        form.currency = .usd
        if await form.submit() == nil { _ = await form.submit() } // offline: second submit saves manual entry
        let ko = try #require(model.holdings.first)
        try await model.addTransaction(TransactionDraft(kind: .buy, date: LocalDate(string: "2024-01-02"), quantity: 20,
                                                        unitPrice: 25, currency: .usd), holdingID: ko.id)
        for (day, amount) in [("2024-03-15", "10"), ("2024-06-14", "12.5")] {
            try await model.addTransaction(TransactionDraft(kind: .dividend, date: LocalDate(string: day), quantity: 20,
                                                            amount: Decimal(string: amount), currency: .usd), holdingID: ko.id)
        }
        return model
    }

    @Test func monthlyBarsCarryAccessibleLabels() async throws {
        let model = try await portfolioWithDividends()
        let summary = try #require(IncomeModel.summary(model))
        let bars = IncomeModel.bars(summary, locale: Locale(identifier: "en_US"))
        #expect(bars.map(\.month) == [3, 6])
        #expect(bars.map(\.amount) == [10, Decimal(string: "12.5")!])
        #expect(bars.map(\.label) == ["Mar 2024", "Jun 2024"])
        #expect(bars.map(\.accessibilityLabel) == ["Mar 2024: $10.00", "Jun 2024: $12.50"])
        #expect(summary.trailingTwelveMonths == Decimal(string: "22.5"))
    }

    @Test func forwardIncomeUnavailableWithoutFetchedRates() async throws {
        let model = try await portfolioWithDividends(offline: true)
        let summary = try #require(IncomeModel.summary(model))
        #expect(summary.forwardAnnual == nil)
        #expect(summary.trailingTwelveMonths == Decimal(string: "22.5"))
    }

    @Test func forwardIncomeFromFetchedRates() async throws {
        // Recording the buy refreshes market data, which caches KO's annual rate of 1.94.
        let model = try await portfolioWithDividends()
        #expect(IncomeModel.summary(model)?.forwardAnnual == Decimal(string: "38.8"))
    }

    @Test func yieldOnCostPerDividend() async throws {
        let model = try await portfolioWithDividends()
        let analytics = try #require(DividendsModel.analytics(model, year: nil))
        let march = try #require(analytics.rows.first { $0.date.month == 3 })
        #expect(march.perShare == Decimal(string: "0.5") && march.yieldOnCost == 2)
        #expect(DividendsModel.analytics(model, year: 2023)?.rows.isEmpty == true)
    }
}

@MainActor @Suite(.serialized) struct AnalyticsModelTests {
    private let snapshots: [ValueSnapshot] = ["2024-01-10", "2024-04-15", "2024-05-01", "2024-07-15"].map {
        ValueSnapshot(portfolioID: UUID(), day: LocalDate(string: $0)!, totalValue: 1, costBasis: 1, baseCurrency: .eur,
                      recordedAt: Date())
    }

    @Test func rangeFiltering() {
        func days(_ range: HistoryRange) -> [String] {
            range.filter(snapshots, today: fixedClock.today, calendar: utcCalendar).map(\.day.description)
        }
        #expect(days(.oneMonth) == ["2024-07-15"])
        #expect(days(.threeMonths) == ["2024-04-15", "2024-05-01", "2024-07-15"])
        #expect(days(.all).count == 4)
        #expect(days(.oneYear).count == 4)
    }

    @Test func goalSaveErrorsAndSuccess() async throws {
        let model = try await makeAppModel()
        try await model.createPortfolio(PortfolioDraft(name: "P"))
        let editor = GoalsEditorModel(model: model, scope: .assetClass, locale: Locale(identifier: "en_US"))
        editor.rows = [.init(key: "stock", percent: "60"), .init(key: "bond", percent: "30")]
        #expect(await editor.save() == false)
        #expect(editor.error == "Targets must add up to 100% (currently 90.0%)")
        #expect(model.goals.isEmpty)

        editor.rows[1].percent = ""
        #expect(await editor.save() == false)
        #expect(editor.error?.contains("bond") == true)

        editor.rows[1].percent = "40"
        #expect(await editor.save())
        #expect(model.goals.map(\.key).sorted() == ["bond", "stock"])
        #expect(editor.rows.count == 2 && editor.error == nil)
    }

    @Test func allocationSlicesAnnounceLabelValueAndPercent() async throws {
        let model = try await makeAppModel()
        try await model.createPortfolio(PortfolioDraft(name: "P", baseCurrency: .usd))
        for (ticker, shares) in [("VTI", 4), ("KO", 10)] {
            let h = try await addHolding(model, ticker)
            try await model.addTransaction(TransactionDraft(kind: .buy, date: LocalDate(string: "2024-01-02"),
                                                            quantity: Decimal(shares), unitPrice: 10, currency: .usd),
                                           holdingID: h.id)
        }
        await model.refreshMarketData(force: true)
        let points = AllocationModel.points(model.valuation, grouping: .assetClass, locale: Locale(identifier: "en_US"))
        // VTI 4 × 250 = 1,000 (ETF); KO 10 × 60 = 600 (stock).
        #expect(points.map(\.label) == ["ETF", "Stock"])
        #expect(points.map(\.accessibilityLabel) == ["ETF: $1,000.00, 62.5%", "Stock: $600.00, 37.5%"])
        #expect(points.reduce(Decimal(0)) { $0 + $1.percent } == 100)
    }

    @Test func dailySnapshotIsWrittenOncePerDay() async throws {
        let model = try await makeAppModel()
        let p = try await model.createPortfolio(PortfolioDraft(name: "P", baseCurrency: .usd))
        let h = try await addHolding(model, "KO")
        try await model.addTransaction(TransactionDraft(kind: .buy, date: LocalDate(string: "2024-01-02"), quantity: 1,
                                                        unitPrice: 1, currency: .usd), holdingID: h.id)
        await model.refreshMarketData(force: true)
        await model.reloadPortfolio()
        try await Task.sleep(nanoseconds: 100_000_000)
        let stored = try await model.environment.cache.snapshots(for: p.id)
        #expect(stored.count == 1 && stored.first?.day == fixedClock.today && stored.first?.totalValue == 60)
    }
}

@MainActor @Suite(.serialized) struct SettingsModelTests {
    @Test func changingBaseCurrencyRecalculates() async throws {
        let model = try await makeAppModel()
        let p = try await model.createPortfolio(PortfolioDraft(name: "P"))
        let h = try await addHolding(model, "AAPL")
        try await model.addTransaction(TransactionDraft(kind: .buy, date: LocalDate(string: "2024-01-02"), quantity: 1,
                                                        unitPrice: 100, currency: .usd), holdingID: h.id)
        await model.refreshMarketData(force: true)
        #expect(model.valuation?.totalValue == 180) // 200 USD × 0.9

        try await model.updatePortfolio(p.id, PortfolioDraft(name: "P", baseCurrency: .usd))
        #expect(model.valuation?.baseCurrency == .usd)
        #expect(model.valuation?.totalValue == 200)
    }

    @Test func credentialSaveReplaceRemove() {
        let store = InMemoryCredentialStore()
        let settings = CredentialSettingsModel(store: store, providerID: "test-keyed")
        #expect(!settings.hasCredential)
        settings.save()
        #expect(settings.error == "Enter the credential")
        settings.input = " secret "
        settings.save()
        #expect(settings.hasCredential && store.credential(for: "test-keyed") == "secret" && settings.input.isEmpty)
        settings.remove()
        #expect(!settings.hasCredential && store.credential(for: "test-keyed") == nil)
    }

    @Test(.enabled(if: keychainAvailableForSettings, "Requires a test host signed with a development team"))
    func credentialSettingsWriteToTheKeychain() throws {
        let store = KeychainCredentialStore(service: "yana.tests.\(UUID().uuidString)")
        let settings = CredentialSettingsModel(store: store, providerID: "test-keyed")
        defer { try? store.remove(for: "test-keyed") }
        settings.input = "secret"
        settings.save()
        #expect(try store.credential(for: "test-keyed") == "secret")
        settings.remove()
        #expect(try store.credential(for: "test-keyed") == nil)
    }
}

/// Same probe as the Keychain store tests.
let keychainAvailableForSettings: Bool = {
    let store = KeychainCredentialStore(service: "yana.tests.probe.\(UUID().uuidString)")
    defer { try? store.remove(for: "probe") }
    return (try? store.save("probe", for: "probe")) != nil
}()

@Suite struct FormattingTests {
    private let us = Locale(identifier: "en_US")
    private let de = Locale(identifier: "de_DE")

    @Test func moneyFollowsLocale() {
        #expect(Fmt.money(Decimal(string: "1234.5")!, .eur, locale: us) == "€1,234.50")
        #expect(Fmt.money(Decimal(string: "1234.5")!, .eur, locale: de) == "1.234,50\u{00A0}€")
        #expect(Fmt.money(nil, .eur, locale: de) == Fmt.unavailable)
        #expect(Fmt.signedMoney(Decimal(string: "12.3")!, .usd, locale: us) == "+$12.30")
    }

    @Test func percentAndNumbers() {
        #expect(Fmt.percent(Decimal(string: "12.5")!, locale: us) == "12.50%")
        #expect(Fmt.percent(Decimal(string: "12.5")!, locale: de) == "12,50\u{00A0}%")
        #expect(Fmt.percent(-10, locale: us, signed: true, digits: 1) == "-10.0%")
        #expect(Fmt.number(Decimal(string: "0.3")!, locale: de) == "0,3")
        #expect(Fmt.number(Decimal(string: "1234.125")!, locale: us) == "1,234.125")
    }

    @Test func datesAreCalendarDaysInAnyTimeZone() {
        let day = LocalDate(string: "2024-03-01")!
        #expect(Fmt.date(day, locale: us) == "Mar 1, 2024")
        #expect(Fmt.date(day, locale: de) == "1. März 2024")
    }

    @Test func decimalInputAcceptsLocaleAndPlainNotation() {
        #expect(DecimalInput.parse("1.234,5", locale: de) == Decimal(string: "1234.5"))
        #expect(DecimalInput.parse("2,5", locale: de) == Decimal(string: "2.5"))
        #expect(DecimalInput.parse("2.5", locale: us) == Decimal(string: "2.5"))
        #expect(DecimalInput.parse("abc", locale: us) == nil)
        #expect(DecimalInput.parse("", locale: us) == nil)
        #expect(DecimalInput.text(Decimal(string: "1234.5"), locale: de) == "1234,5")
    }
}

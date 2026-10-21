import Foundation
import Observation
import YanaDomain
import YanaMarketData

/// One row of the holdings table. Values the app cannot compute are `nil` and shown as unavailable.
struct HoldingRow: Identifiable, Equatable {
    var holding: HoldingRecord
    var shares: Decimal
    var averageCost: Decimal?
    var costCurrency: Currency
    var price: Decimal?
    var priceCurrency: Currency
    /// In the portfolio's base currency.
    var marketValue: Decimal?
    var gain: Decimal?
    var returnPercent: Decimal?
    /// Traded down to zero shares. A holding with no trades yet is new, not closed.
    var isClosed = false

    var id: UUID { holding.id }
    var ticker: String { holding.ticker }
    var name: String { holding.name ?? "" }
    var assetClass: String { Fmt.assetClass(holding.assetClass) }

    // Non-optional sort keys: unavailable values sort below every real value.
    var sharesKey: Decimal { shares }
    var averageCostKey: Decimal { averageCost ?? .leastFiniteMagnitude }
    var priceKey: Decimal { price ?? .leastFiniteMagnitude }
    var marketValueKey: Decimal { marketValue ?? .leastFiniteMagnitude }
    var gainKey: Decimal { gain ?? .leastFiniteMagnitude }
    var returnKey: Decimal { returnPercent ?? .leastFiniteMagnitude }
}

enum HoldingsTable {
    /// Open positions from the valuation and holdings not traded yet, plus closed holdings when `showClosed` is on.
    /// Sorted by ticker.
    static func rows(holdings: [HoldingRecord], transactions: [TransactionRecord], valuation: PortfolioValuation?,
                     showClosed: Bool) -> [HoldingRow] {
        let valued = Dictionary(uniqueKeysWithValues: (valuation?.positions ?? []).map { ($0.holding.id, $0) })
        let traded = Set(transactions.filter { !$0.isDeleted && $0.kind.isTrade }.map(\.holdingID))
        let positions = PositionCalculator.positions(holdings: holdings, transactions: transactions)
        return positions.compactMap { p -> HoldingRow? in
            guard let holding = holdings.first(where: { $0.id == p.holdingID }) else { return nil }
            if let v = valued[p.holdingID] {
                return HoldingRow(holding: holding, shares: p.shares, averageCost: p.averageCost, costCurrency: p.costCurrency,
                                  price: v.price, priceCurrency: v.priceCurrency, marketValue: v.marketValue,
                                  gain: v.unrealizedGain, returnPercent: v.returnPercent)
            }
            let closed = traded.contains(p.holdingID)
            guard showClosed || !closed else { return nil }
            return HoldingRow(holding: holding, shares: p.shares, averageCost: p.averageCost, costCurrency: p.costCurrency,
                              price: nil, priceCurrency: holding.currency, marketValue: nil, gain: nil, returnPercent: nil,
                              isClosed: closed)
        }
        .sorted { $0.ticker < $1.ticker }
    }
}

/// Adding a holding by ticker (with a provider lookup, falling back to manual entry when offline) or editing one.
@MainActor @Observable
final class HoldingFormModel {
    enum Mode: Equatable {
        /// Ticker only; details come from the market-data provider.
        case lookup
        /// The provider is unreachable: the person enters name, asset class, and currency.
        case manual
        case edit(HoldingRecord)
    }

    enum Outcome: Equatable {
        case created(HoldingRecord)
        case existing(HoldingRecord)
        case updated
    }

    var mode: Mode
    var ticker = ""
    var name = ""
    var sector = ""
    var assetClass = AssetClass.default
    var currency = Currency.default
    /// Option fields: the ticker and name are built from these when `assetClass` is `.option`.
    var optionUnderlying = ""
    var optionExpiry = Date()
    var optionRight = OptionRight.call
    var optionStrike = ""
    var optionMultiplier = "100"
    private(set) var optionError: String?
    private(set) var tickerError: String?
    /// Explains why manual entry is shown, or another non-field problem.
    private(set) var notice: String?
    private(set) var isWorking = false

    private let model: AppModel
    private let locale: Locale
    private let calendar: Calendar

    init(model: AppModel, editing: HoldingRecord?, locale: Locale = .current, calendar: Calendar = .current) {
        self.model = model
        self.locale = locale
        self.calendar = calendar
        if let holding = editing {
            optionMultiplier = DecimalInput.text(holding.multiplier ?? 100, locale: locale)
            mode = .edit(holding)
            ticker = holding.ticker
            name = holding.name ?? ""
            sector = holding.sector ?? ""
            assetClass = holding.assetClass
            currency = holding.currency
        } else {
            mode = .lookup
            currency = model.selectedPortfolio?.baseCurrency ?? .default
        }
    }

    /// The contract the option fields describe, or nil until underlying and a positive strike are entered.
    var optionPreview: OptionContract? {
        let underlying = optionUnderlying.trimmingCharacters(in: .whitespaces)
        guard !underlying.isEmpty, let strike = DecimalInput.parse(optionStrike, locale: locale), strike > 0 else { return nil }
        return OptionContract(underlying: underlying, expiry: LocalDate(optionExpiry, calendar: calendar),
                              right: optionRight, strike: strike)
    }

    private var isAddingOption: Bool {
        if case .edit = mode { return false }
        return assetClass == .option
    }

    /// Returns the outcome, or `nil` when the form must stay open.
    func submit() async -> Outcome? {
        isWorking = true
        defer { isWorking = false }
        tickerError = nil
        optionError = nil
        do {
            if isAddingOption {
                guard let contract = optionPreview else {
                    optionError = "Enter the underlying and a strike greater than 0."
                    return nil
                }
                guard let multiplier = DecimalInput.parse(optionMultiplier, locale: locale) else {
                    optionError = "Enter the contract multiplier, usually 100."
                    return nil
                }
                return try await add(HoldingDraft(ticker: contract.occSymbol, name: contract.displayName,
                                                  assetClass: .option, currency: currency, multiplier: multiplier))
            }
            switch mode {
            case .edit(let holding):
                try await model.updateHolding(holding.id, draft)
                return .updated
            case .manual:
                return try await add(draft)
            case .lookup:
                let valid = try draft.validated()
                switch await model.lookUpSecurity(valid.ticker) {
                case .success(let details):
                    return try await add(HoldingDraft(ticker: valid.ticker, name: details.name, sector: details.sector,
                                                      assetClass: details.assetClass, currency: details.currency))
                case .failure(.notFound):
                    tickerError = "\(valid.ticker) was not found. Check the symbol, including any exchange suffix."
                case .failure(.unsupportedCurrency(let code)):
                    tickerError = "\(valid.ticker) trades in \(code), which Yana doesn't support."
                case .failure:
                    mode = .manual
                    notice = "Market data can't be reached right now. Enter the details yourself; prices "
                        + "will load once the connection returns."
                }
                return nil
            }
        } catch let error as ValidationError {
            tickerError = error.message(for: .ticker)
            optionError = error.message(for: .multiplier)
            notice = tickerError == nil && optionError == nil ? error.description : nil
        } catch {
            notice = error.localizedDescription
        }
        return nil
    }

    private var draft: HoldingDraft {
        var multiplier: Decimal?
        if assetClass == .option {
            multiplier = DecimalInput.parse(optionMultiplier, locale: locale)
            if multiplier == nil, case .edit(let holding) = mode { multiplier = holding.multiplier }
        }
        return HoldingDraft(ticker: ticker, name: name, sector: sector, assetClass: assetClass, currency: currency,
                            multiplier: multiplier)
    }

    private func add(_ draft: HoldingDraft) async throws -> Outcome {
        let added = try await model.addHolding(draft)
        return added.alreadyExisted ? .existing(added.holding) : .created(added.holding)
    }
}

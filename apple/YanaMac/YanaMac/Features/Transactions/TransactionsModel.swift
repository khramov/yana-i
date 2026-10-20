import Foundation
import Observation
import YanaDomain

struct TransactionRow: Identifiable, Equatable {
    var record: TransactionRecord
    var ticker: String

    var id: UUID { record.id }
    /// Price per share for trades, total amount for dividends and fees.
    var priceOrAmount: Decimal? { record.kind.isTrade ? record.unitPrice : record.amount }
}

/// Ticker, type, and year filters over a portfolio's transactions, newest first.
struct TransactionFilter: Equatable {
    var ticker: String?
    var kind: TransactionKind?
    var year: Int?

    func rows(_ transactions: [TransactionRecord], holdings: [HoldingRecord]) -> [TransactionRow] {
        let tickers = Dictionary(uniqueKeysWithValues: holdings.map { ($0.id, $0.ticker) })
        return transactions
            .filter { !$0.isDeleted }
            .compactMap { t in tickers[t.holdingID].map { TransactionRow(record: t, ticker: $0) } }
            .filter { row in
                (ticker == nil || row.ticker == ticker)
                    && (kind == nil || row.record.kind == kind)
                    && (year == nil || row.record.date.year == year)
            }
            .sorted { !PositionCalculator.chronological($0.record, $1.record) }
    }

    static func years(_ transactions: [TransactionRecord]) -> [Int] {
        Set(transactions.filter { !$0.isDeleted }.map(\.date.year)).sorted(by: >)
    }
}

/// The create/edit transaction form. Numbers are typed as text in the person's locale; errors map to fields.
@MainActor @Observable
final class TransactionFormModel {
    var holdingID: UUID? {
        didSet {
            if editing == nil, let h = model.holdings.first(where: { $0.id == holdingID }) { currency = h.currency }
        }
    }
    var kind = TransactionKind.buy
    var date = Date()
    var quantity = ""
    var unitPrice = ""
    var amount = ""
    var fee = ""
    var tax = ""
    var currency = Currency.default
    var notes = ""
    private(set) var errors: [ValidationField: String] = [:]
    private(set) var holdingError: String?
    private(set) var failure: String?
    private(set) var isSaving = false

    let editing: TransactionRecord?
    private let model: AppModel
    private let locale: Locale
    private let calendar: Calendar

    init(model: AppModel, editing: TransactionRecord?, locale: Locale = .current, calendar: Calendar = .current) {
        self.model = model
        self.editing = editing
        self.locale = locale
        self.calendar = calendar
        if let t = editing {
            holdingID = t.holdingID
            kind = t.kind
            date = t.date.startOfDay(in: calendar)
            quantity = DecimalInput.text(t.quantity, locale: locale)
            unitPrice = DecimalInput.text(t.unitPrice, locale: locale)
            amount = DecimalInput.text(t.amount, locale: locale)
            fee = t.fee == 0 ? "" : DecimalInput.text(t.fee, locale: locale)
            tax = t.tax == 0 ? "" : DecimalInput.text(t.tax, locale: locale)
            currency = t.currency
            notes = t.notes ?? ""
        } else {
            holdingID = model.holdings.count == 1 ? model.holdings[0].id : nil
            currency = model.holdings.first { $0.id == holdingID }?.currency ?? model.selectedPortfolio?.baseCurrency ?? .default
        }
    }

    /// Saves, returning `true` when the form can close.
    func save() async -> Bool {
        errors = [:]
        holdingError = nil
        failure = nil
        guard let holdingID else {
            holdingError = "Choose a holding"
            return false
        }
        var parsed: [ValidationField: Decimal?] = [:]
        for (field, text) in [(ValidationField.quantity, quantity), (.unitPrice, unitPrice), (.amount, amount),
                              (.fee, fee), (.tax, tax)] {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                parsed[field] = .some(nil)
            } else if let value = DecimalInput.parse(trimmed, locale: locale) {
                parsed[field] = value
            } else {
                errors[field] = "Enter a number"
            }
        }
        guard errors.isEmpty else { return false }

        let draft = TransactionDraft(kind: kind, date: LocalDate(date, calendar: calendar),
                                     quantity: kind == .fee ? nil : parsed[.quantity] ?? nil,
                                     unitPrice: kind.isTrade ? parsed[.unitPrice] ?? nil : nil,
                                     amount: kind.isTrade ? nil : parsed[.amount] ?? nil,
                                     fee: parsed[.fee] ?? nil, tax: parsed[.tax] ?? nil, currency: currency, notes: notes)
        isSaving = true
        defer { isSaving = false }
        do {
            if let editing {
                try await model.updateTransaction(editing.id, draft)
            } else {
                try await model.addTransaction(draft, holdingID: holdingID)
            }
            return true
        } catch let error as ValidationError {
            for issue in error.issues where errors[issue.field] == nil { errors[issue.field] = issue.message }
        } catch {
            failure = error.localizedDescription
        }
        return false
    }
}

import Foundation

public struct CSVImportError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String
    public var description: String { message }
}

public struct CSVLineError: Equatable, Sendable {
    public var line: Int
    public var message: String
}

/// Reads the web app's column format: `ticker,type,date[,shares,price,fee,tax,currency,notes]`. A dividend or
/// fee row's `price` is its total amount, and an unsupported or missing currency becomes EUR. The batch's range
/// runs from the earliest to the latest valid row date.
public enum CSVImportPlanner {
    public static let requiredColumns = ["ticker", "type", "date"]

    public static func batch(csv: String) throws -> ImportBatch {
        let rows = CSVParser.parse(IBKRStatementParser.stripBOM(csv))
        guard rows.count >= 2 else {
            throw CSVImportError(message: "CSV must have a header row and at least one data row")
        }
        let header = rows[0].fields.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func column(_ name: String) -> Int? { header.firstIndex(of: name) }
        guard let tickerCol = column("ticker"), let typeCol = column("type"), let dateCol = column("date") else {
            throw CSVImportError(message: "CSV must include at least 'ticker', 'type' and 'date' columns")
        }
        let sharesCol = column("shares"), priceCol = column("price"), feeCol = column("fee"),
            taxCol = column("tax"), currencyCol = column("currency"), notesCol = column("notes")

        var holdings: [ImportedHolding] = []
        var imported: [ImportedRow] = []
        var errors: [CSVLineError] = []

        for row in rows.dropFirst() {
            func cell(_ col: Int?) -> String? {
                guard let col, col < row.fields.count else { return nil }
                return row.fields[col]
            }
            func fail(_ message: String) { errors.append(CSVLineError(line: row.line, message: message)) }

            let ticker = RecordIdentity.normalizeTicker(cell(tickerCol) ?? "")
            if ticker.isEmpty { fail("Missing ticker"); continue }
            let rawType = (cell(typeCol) ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            guard let kind = TransactionKind(rawValue: rawType) else {
                fail("type: must be buy/sell/dividend/fee (got \"\(rawType)\")"); continue
            }
            guard let date = LocalDate(string: (cell(dateCol) ?? "").trimmingCharacters(in: .whitespaces)) else {
                fail("date: Date must be YYYY-MM-DD"); continue
            }

            var invalidNumber: String?
            func number(_ col: Int?, _ name: String) -> Decimal? {
                switch CSVParser.number(cell(col)) {
                case .absent: return nil
                case .value(let v): return v
                case .invalid:
                    if invalidNumber == nil { invalidNumber = "\(name): must be a number" }
                    return nil
                }
            }
            let shares = number(sharesCol, "shares")
            let price = number(priceCol, "price")
            let fee = number(feeCol, "fee")
            let tax = number(taxCol, "tax")
            if let invalidNumber { fail(invalidNumber); continue }

            let currency = Currency(code: cell(currencyCol) ?? "") ?? .default
            let draft = TransactionDraft(kind: kind, date: date, quantity: shares,
                                         unitPrice: kind.isTrade ? price : nil,
                                         amount: kind.isTrade ? nil : price,
                                         fee: fee, tax: tax, currency: currency, notes: cell(notesCol))
            let valid: TransactionDraft
            let holdingDraft: HoldingDraft
            do {
                valid = try draft.validated()
                holdingDraft = try HoldingDraft(ticker: ticker, currency: currency).validated()
            } catch let error as ValidationError {
                let issue = error.issues[0]
                fail("\(csvColumn(for: issue.field)): \(issue.message)"); continue
            } catch {
                fail(error.localizedDescription); continue
            }

            if !holdings.contains(where: { $0.ticker == holdingDraft.ticker }) {
                holdings.append(ImportedHolding(ticker: holdingDraft.ticker, name: nil,
                                                assetClass: holdingDraft.assetClass ?? .default,
                                                currency: holdingDraft.currency, multiplier: nil))
            }
            imported.append(ImportedRow(line: row.line, ticker: holdingDraft.ticker, kind: kind, date: date,
                                        quantity: valid.quantity, unitPrice: valid.unitPrice, amount: valid.amount,
                                        fee: valid.fee ?? 0, tax: valid.tax ?? 0, currency: valid.currency,
                                        notes: valid.notes))
        }

        // With no valid rows nothing is replaced, since replacement is limited to the batch's tickers.
        let none = LocalDate(year: 1, month: 1, day: 1)!
        let dates = imported.map(\.date)
        let range = dates.min().flatMap { lo in dates.max().map { lo...$0 } } ?? (none...none)
        return ImportBatch(source: .csv, range: range, holdings: holdings, rows: imported, positions: nil,
                           errors: errors, warnings: [])
    }

    /// The web format's column name for a validation field.
    static func csvColumn(for field: ValidationField) -> String {
        switch field {
        case .quantity: return "shares"
        case .unitPrice, .amount: return "price"
        default: return field.rawValue
        }
    }
}

import Foundation

public struct CSVImportError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String
    public var description: String { message }
}

public struct CSVLineError: Equatable, Sendable {
    public var line: Int
    public var message: String
}

/// What an import will write. Nothing is persisted until the caller saves it.
public struct CSVImportPlan: Equatable, Sendable {
    /// New holdings (or re-creations over a tombstone) referenced by valid rows only.
    public var holdingsToCreate: [HoldingRecord]
    public var transactionsToInsert: [TransactionRecord]
    public var errors: [CSVLineError]

    public var importedCount: Int { transactionsToInsert.count }
    public var failedCount: Int { errors.count }
}

/// Plans an import in the web app's column format:
/// `ticker,type,date[,shares,price,fee,tax,currency,notes]`. A dividend or fee row's `price`
/// is its total amount, and an unsupported or missing currency becomes EUR.
public enum CSVImportPlanner {
    public static let requiredColumns = ["ticker", "type", "date"]

    /// - Parameter existingHoldings: the portfolio's holdings, tombstones included.
    public static func plan(csv: String, portfolioID: UUID, existingHoldings: [HoldingRecord],
                            now: Date, deviceID: UUID) throws -> CSVImportPlan {
        let rows = CSVParser.parse(csv)
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

        let existing = Dictionary(existingHoldings.filter { $0.portfolioID == portfolioID }.map { ($0.id, $0) },
                                  uniquingKeysWith: { $1 })
        var created: [UUID: HoldingRecord] = [:]
        var createdOrder: [UUID] = []
        var transactions: [TransactionRecord] = []
        var errors: [CSVLineError] = []

        for (index, row) in rows.dropFirst().enumerated() {
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
            }

            let holdingID = RecordIdentity.holdingID(portfolioID: portfolioID, ticker: ticker)
            if created[holdingID] == nil, existing[holdingID].map({ $0.isDeleted }) ?? true {
                let version = existing[holdingID].map { $0.version.bumped(at: now, deviceID: deviceID) }
                    ?? .initial(at: now, deviceID: deviceID)
                created[holdingID] = HoldingRecord(id: holdingID, portfolioID: portfolioID, ticker: holdingDraft.ticker,
                                                   assetClass: holdingDraft.assetClass ?? .default,
                                                   currency: holdingDraft.currency, createdAt: now, version: version)
                createdOrder.append(holdingID)
            }

            // Spread creation times by a millisecond per row so same-day rows keep file order.
            let createdAt = now.addingTimeInterval(Double(index) / 1000)
            transactions.append(TransactionRecord(
                id: UUID(), portfolioID: portfolioID, holdingID: holdingID, kind: kind, date: date,
                quantity: valid.quantity, unitPrice: valid.unitPrice, amount: valid.amount,
                fee: valid.fee ?? 0, tax: valid.tax ?? 0, currency: valid.currency, notes: valid.notes,
                createdAt: createdAt, version: .initial(at: now, deviceID: deviceID)))
        }

        return CSVImportPlan(holdingsToCreate: createdOrder.compactMap { created[$0] },
                             transactionsToInsert: transactions, errors: errors)
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

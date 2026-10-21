import Foundation

/// What an import will write. Nothing is persisted until the caller saves it.
public struct ImportPlan: Equatable, Sendable {
    /// Created, revived, or filled-in holdings.
    public var holdings: [HoldingRecord]
    /// Inserted rows, tombstones of the rows they replace, and opening-balance rows.
    public var transactions: [TransactionRecord]
    /// Rows inserted from the file.
    public var added: Int
    /// Earlier imported rows in the file's range that the file replaced.
    public var replaced: Int
    /// Hand-entered rows replaced by a file row that looks the same.
    public var absorbed: Int
    public var errors: [CSVLineError]
    public var warnings: [CSVLineError]
}

/// Applies an import batch to a portfolio. The file is the authority for its date range: earlier rows from the same
/// source in that range are replaced, a hand-entered row that looks like a file row is replaced by it, and other
/// hand entries stay.
public enum ImportReconciler {
    /// Detects the format (an IBKR Activity Statement or the app's own CSV) and plans the import.
    public static func plan(text: String, portfolioID: UUID, holdings: [HoldingRecord],
                            transactions: [TransactionRecord], now: Date, deviceID: UUID) throws -> ImportPlan {
        let batch = IBKRStatementParser.isStatement(text)
            ? try IBKRStatementParser.batch(from: text)
            : try CSVImportPlanner.batch(csv: text)
        return plan(batch, portfolioID: portfolioID, holdings: holdings, transactions: transactions, now: now,
                    deviceID: deviceID)
    }

    /// - Parameters:
    ///   - holdings: the portfolio's holdings, tombstones included.
    ///   - transactions: the portfolio's transactions, tombstones included.
    public static func plan(_ batch: ImportBatch, portfolioID: UUID, holdings: [HoldingRecord],
                            transactions: [TransactionRecord], now: Date, deviceID: UUID) -> ImportPlan {
        var work = Work(portfolioID: portfolioID, now: now, deviceID: deviceID,
                        holdings: holdings.filter { $0.portfolioID == portfolioID },
                        transactions: transactions.filter { $0.portfolioID == portfolioID })
        var warnings = batch.warnings

        // Holdings every row and position needs, in file order.
        var tickers: [String] = []
        for t in batch.rows.map(\.ticker) + (batch.positions ?? []).map(\.ticker) where !tickers.contains(t) {
            tickers.append(t)
        }
        var holdingIDs: [String: UUID] = [:]
        for ticker in tickers {
            let info = batch.holdings.first { $0.ticker == ticker }
                ?? ImportedHolding(ticker: ticker, name: nil, assetClass: .default,
                                   currency: batch.rows.first { $0.ticker == ticker }?.currency ?? .default,
                                   multiplier: nil)
            holdingIDs[ticker] = work.upsertHolding(info)
            if let twin = bareTicker(ticker), work.liveHolding(ticker: twin) != nil {
                warnings.append(CSVLineError(line: batch.rows.first { $0.ticker == ticker }?.line ?? 0,
                                             message: "\(ticker): you also have a holding \(twin); merge them by hand"))
            }
        }

        // 1. Replace earlier rows from the same source in the range (the app's own CSV: only for its tickers).
        let batchHoldingIDs = Set(holdingIDs.values)
        var replaced = 0
        for t in work.liveTransactions where t.importSource == batch.source && t.openingBalance == nil
            && batch.range.contains(t.date) && (batch.source != .csv || batchHoldingIDs.contains(t.holdingID)) {
            work.tombstone(t)
            replaced += 1
        }

        // 2. A hand entry that looks like a file row is replaced by it; each file row absorbs at most one.
        var absorbed = 0
        for row in batch.rows {
            guard let holdingID = holdingIDs[row.ticker],
                  let twin = work.liveTransactions.first(where: { $0.importSource == nil
                      && batch.range.contains($0.date) && looksTheSame($0, row, holdingID: holdingID) })
            else { continue }
            work.tombstone(twin)
            absorbed += 1
        }

        // 3. Insert the file's rows, spreading creation times by a millisecond so same-day rows keep file order.
        for (index, row) in batch.rows.enumerated() {
            guard let holdingID = holdingIDs[row.ticker] else { continue }
            work.save(TransactionRecord(
                id: UUID(), portfolioID: portfolioID, holdingID: holdingID, kind: row.kind, date: row.date,
                quantity: row.quantity, unitPrice: row.unitPrice, amount: row.amount, fee: row.fee, tax: row.tax,
                currency: row.currency, notes: row.notes, importSource: batch.source,
                createdAt: now.addingTimeInterval(Double(index) / 1000), version: .initial(at: now, deviceID: deviceID)))
        }

        // 4. Opening balances keep each holding equal to the latest statement's positions.
        if let positions = batch.positions {
            warnings += reconcileOpenings(&work, batch: batch, positions: positions)
        }

        return ImportPlan(holdings: work.changedHoldings, transactions: work.changedTransactions,
                          added: batch.rows.filter { holdingIDs[$0.ticker] != nil }.count, replaced: replaced,
                          absorbed: absorbed, errors: batch.errors, warnings: warnings)
    }

    /// Sorts opening rows before any same-day trade under `PositionCalculator.chronological`.
    static let openingCreatedAt = Date(timeIntervalSince1970: 0)

    /// One opening-balance buy per holding, recomputed so the holding matches the most recent statement imported
    /// (the latest period end), whatever the import order. A zero or negative opening is kept as a tombstone so its
    /// target survives for later imports.
    static func reconcileOpenings(_ work: inout Work, batch: ImportBatch,
                                  positions: [ImportedPosition]) -> [CSVLineError] {
        var warnings: [CSVLineError] = []
        let positionByID = Dictionary(positions.map {
            (RecordIdentity.holdingID(portfolioID: work.portfolioID, ticker: $0.ticker), $0)
        }, uniquingKeysWith: { a, _ in a })
        let ibkrHoldingIDs = Set(work.transactions.filter { $0.importSource == .ibkr }.map(\.holdingID))
        let scope = work.holdings.filter { !$0.isDeleted && (positionByID[$0.id] != nil || ibkrHoldingIDs.contains($0.id)) }
            .sorted { $0.ticker < $1.ticker }
        // Every IBKR import writes an opening row (live or tombstone) for each holding it covers, so the latest
        // statement already imported is the latest `asOf` among them. A holding that statement did not list was
        // closed by then, even if this older batch shows it.
        let latestAsOf = work.transactions.compactMap { $0.openingBalance?.asOf }.max()

        for h in scope {
            let openingID = RecordIdentity.openingID(holdingID: h.id)
            let openings = work.transactions.filter { $0.holdingID == h.id && $0.openingBalance != nil }
            let existing = openings.first { $0.id == openingID } ?? openings.first
            // Openings made on another device before IDs were derived, or duplicated otherwise, are folded into one.
            for extra in openings where extra.id != openingID && !extra.isDeleted { work.tombstone(extra) }
            var target: OpeningBalance
            if let current = existing?.openingBalance, batch.range.upperBound < current.asOf {
                target = current
            } else if existing == nil, let latestAsOf, batch.range.upperBound < latestAsOf {
                target = OpeningBalance(asOf: latestAsOf, targetQuantity: 0, targetCostBasis: 0,
                                        coveredFrom: batch.range.lowerBound)
            } else {
                let p = positionByID[h.id]
                target = OpeningBalance(asOf: batch.range.upperBound, targetQuantity: p?.quantity ?? 0,
                                        targetCostBasis: p?.costBasis ?? 0, coveredFrom: batch.range.lowerBound)
            }
            let real = work.liveTransactions.filter { $0.holdingID == h.id && $0.openingBalance == nil }
            target.coveredFrom = ([existing?.openingBalance?.coveredFrom, batch.range.lowerBound]
                + real.filter { $0.importSource == .ibkr }.map(\.date)).compactMap { $0 }.min()!

            let upTo = real.filter { $0.date <= target.asOf }.sorted(by: PositionCalculator.chronological)
            let net = upTo.reduce(Decimal(0)) { sum, t in
                switch t.kind {
                case .buy: return sum + (t.quantity ?? 0)
                case .sell: return sum - (t.quantity ?? 0)
                case .dividend, .fee: return sum
                }
            }
            let q0 = target.targetQuantity - net
            if q0 < 0 {
                warnings.append(CSVLineError(line: 0, message: "\(h.ticker): imported trades don't reconcile with the statement (\(q0) shares)"))
            }
            var held = max(q0, 0)
            for t in upTo where t.kind == .buy || t.kind == .sell {
                let q = t.quantity ?? 0
                if t.kind == .sell && q > held {
                    warnings.append(CSVLineError(line: 0, message: "\(h.ticker): sells more than was held; short positions are not supported"))
                    break
                }
                held += t.kind == .buy ? q : -q
            }
            let price = q0 > 0 ? openingPrice(quantity: q0, multiplier: h.effectiveMultiplier, target: target.targetCostBasis,
                                              trades: upTo) : 0
            let previous = existing?.id == openingID ? existing : nil
            var opening = TransactionRecord(
                id: openingID, portfolioID: work.portfolioID, holdingID: h.id, kind: .buy,
                date: target.coveredFrom, quantity: max(q0, 0), unitPrice: price, currency: h.currency,
                notes: "Opening balance", importSource: .ibkr, openingBalance: target,
                createdAt: openingCreatedAt, version: previous?.version ?? .initial(at: work.now, deviceID: work.deviceID),
                deletedAt: q0 > 0 ? nil : (previous?.deletedAt ?? work.now))
            if let previous, sameOpening(previous, opening) { continue }
            if let previous { opening.version = previous.version.bumped(at: work.now, deviceID: work.deviceID) }
            work.save(opening)
        }
        return warnings
    }

    /// Solves the opening lot's price so the average-cost replay of `trades` ends at `target`. Cost after each step
    /// is linear in the opening lot cost `c0`: `a * c0 + b`.
    static func openingPrice(quantity q0: Decimal, multiplier m: Decimal, target: Decimal,
                             trades: [TransactionRecord]) -> Decimal {
        var a: Decimal = 1, b: Decimal = 0, shares = q0
        for t in trades {
            guard let q = t.quantity else { continue }
            switch t.kind {
            case .buy:
                b += q * (t.unitPrice ?? 0) * m + t.fee
                shares += q
            case .sell:
                if q >= shares {
                    a = 0; b = 0; shares = 0
                } else {
                    let k = (shares - q) / shares
                    a *= k; b *= k; shares -= q
                }
            case .dividend, .fee:
                continue
            }
        }
        let c0 = a != 0 ? (target - b) / a : target
        return c0 / (q0 * m)
    }

    static func sameOpening(_ a: TransactionRecord, _ b: TransactionRecord) -> Bool {
        a.date == b.date && a.quantity == b.quantity && a.unitPrice == b.unitPrice && a.currency == b.currency
            && a.openingBalance == b.openingBalance && a.isDeleted == b.isDeleted
    }

    /// Same holding, type, and date, and the same quantity (buy/sell) or amount (dividend/fee).
    static func looksTheSame(_ t: TransactionRecord, _ row: ImportedRow, holdingID: UUID) -> Bool {
        guard t.holdingID == holdingID, t.kind == row.kind, t.date == row.date else { return false }
        return row.kind.isTrade ? t.quantity == row.quantity : t.amount == row.amount
    }

    static let yahooSuffixes: Set<String> = [".DE", ".AS", ".L", ".PA", ".MI", ".SW"]

    /// `VWCE` for `VWCE.DE`; nil when the ticker has no exchange suffix.
    static func bareTicker(_ ticker: String) -> String? {
        guard let dot = ticker.lastIndex(of: "."), yahooSuffixes.contains(String(ticker[dot...])) else { return nil }
        return String(ticker[..<dot])
    }

    /// The portfolio's records as the plan changes them, plus what changed.
    struct Work {
        let portfolioID: UUID
        let now: Date
        let deviceID: UUID
        var holdings: [HoldingRecord]
        var transactions: [TransactionRecord]
        private(set) var changedHoldingIDs: [UUID] = []
        private(set) var changedTransactionIDs: [UUID] = []

        init(portfolioID: UUID, now: Date, deviceID: UUID, holdings: [HoldingRecord], transactions: [TransactionRecord]) {
            self.portfolioID = portfolioID
            self.now = now
            self.deviceID = deviceID
            self.holdings = holdings
            self.transactions = transactions
        }

        var liveTransactions: [TransactionRecord] { transactions.filter { !$0.isDeleted } }
        var changedHoldings: [HoldingRecord] { changedHoldingIDs.compactMap { id in holdings.first { $0.id == id } } }
        var changedTransactions: [TransactionRecord] {
            changedTransactionIDs.compactMap { id in transactions.first { $0.id == id } }
        }

        func liveHolding(ticker: String) -> HoldingRecord? {
            holdings.first { $0.ticker == ticker && !$0.isDeleted }
        }

        /// Creates, revives, or fills in the holding for `info` and returns its ID. An existing live holding only
        /// gains a name or multiplier it lacks; the owner's values are never overwritten.
        mutating func upsertHolding(_ info: ImportedHolding) -> UUID {
            let id = RecordIdentity.holdingID(portfolioID: portfolioID, ticker: info.ticker)
            if let i = holdings.firstIndex(where: { $0.id == id }) {
                var h = holdings[i]
                if !h.isDeleted {
                    guard (h.name == nil && info.name != nil) || (h.multiplier == nil && info.multiplier != nil)
                    else { return id }
                    h.name = h.name ?? info.name
                    h.multiplier = h.multiplier ?? info.multiplier
                } else {
                    h = HoldingRecord(id: id, portfolioID: portfolioID, ticker: info.ticker, name: info.name,
                                      assetClass: info.assetClass, currency: info.currency,
                                      multiplier: info.multiplier, createdAt: now, version: h.version)
                }
                h.version = h.version.bumped(at: now, deviceID: deviceID)
                holdings[i] = h
                markChanged(holding: id)
            } else {
                holdings.append(HoldingRecord(id: id, portfolioID: portfolioID, ticker: info.ticker, name: info.name,
                                              assetClass: info.assetClass, currency: info.currency,
                                              multiplier: info.multiplier, createdAt: now,
                                              version: .initial(at: now, deviceID: deviceID)))
                markChanged(holding: id)
            }
            return id
        }

        mutating func tombstone(_ t: TransactionRecord) {
            var dead = t
            dead.deletedAt = now
            dead.version = t.version.bumped(at: now, deviceID: deviceID)
            save(dead)
        }

        mutating func save(_ t: TransactionRecord) {
            if let i = transactions.firstIndex(where: { $0.id == t.id }) { transactions[i] = t } else { transactions.append(t) }
            if !changedTransactionIDs.contains(t.id) { changedTransactionIDs.append(t.id) }
        }

        private mutating func markChanged(holding id: UUID) {
            if !changedHoldingIDs.contains(id) { changedHoldingIDs.append(id) }
        }
    }
}

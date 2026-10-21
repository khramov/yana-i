import Foundation

/// Reads an Interactive Brokers Activity Statement (CSV export). The file is a set of sections: every row starts
/// with the section name and `Header`, `Data`, `SubTotal`, or `Total`, and a section may repeat its header with
/// different columns (one per asset category), so each data row is read against the latest header of its section.
public enum IBKRStatementParser {
    public static func isStatement(_ text: String) -> Bool {
        stripBOM(text).hasPrefix("Statement,Header")
    }

    public static func batch(from text: String) throws -> ImportBatch {
        var sections: [String: [Record]] = [:]
        var headers: [String: [String]] = [:]
        for row in CSVParser.parse(stripBOM(text)) {
            guard row.fields.count >= 2 else { continue }
            let section = row.fields[0], kind = row.fields[1], values = Array(row.fields.dropFirst(2))
            if kind == "Header" {
                headers[section] = values
            } else if kind == "Data", let header = headers[section] {
                var cells: [String: String] = [:]
                for (name, value) in zip(header, values) where !name.isEmpty { cells[name] = value }
                sections[section, default: []].append(Record(line: row.line, cells: cells))
            }
        }

        guard let periodText = sections["Statement"]?.first(where: { $0["Field Name"] == "Period" })?["Field Value"],
              let range = period(periodText)
        else { throw CSVImportError(message: "Statement period not found") }

        var reader = Reader(instruments: (sections["Financial Instrument Information"] ?? []).map(Instrument.init))
        for r in sections["Trades"] ?? [] { reader.trade(r) }
        for r in sections["Open Positions"] ?? [] { reader.position(r) }
        reader.dividends(sections["Dividends"] ?? [], withholding: sections["Withholding Tax"] ?? [])
        for r in sections["Corporate Actions"] ?? [] {
            reader.warnings.append(CSVLineError(line: r.line, message: "Corporate actions are not supported"))
        }
        return ImportBatch(source: .ibkr, range: range, holdings: reader.holdings, rows: reader.rows,
                           positions: reader.positions, errors: reader.errors.sorted { $0.line < $1.line },
                           warnings: reader.warnings.sorted { $0.line < $1.line })
    }

    /// Yahoo's suffix for an IBKR listing exchange: `""` for US exchanges, `nil` when unknown.
    public static func yahooSuffix(exchange: String) -> String? {
        switch exchange.uppercased() {
        case "IBIS", "IBIS2": return ".DE"
        case "AEB": return ".AS"
        case "LSE", "LSEETF": return ".L"
        case "SBF": return ".PA"
        case "BVME", "BVME.ETF": return ".MI"
        case "EBS": return ".SW"
        case "NASDAQ", "NYSE", "ARCA", "BATS", "AMEX": return ""
        default: return nil
        }
    }

    // MARK: - Rows

    struct Record {
        var line: Int
        var cells: [String: String]
        subscript(_ column: String) -> String? { cells[column]?.trimmingCharacters(in: .whitespaces) }
    }

    struct Instrument {
        var category: String
        /// The symbol trades and positions use: the ticker for stocks, the description for options.
        var key: String
        var ticker: String?
        var name: String?
        var assetClass: AssetClass
        var multiplier: Decimal?
        var isin: String?
        var unknownExchange: String?

        init(_ r: Record) {
            category = r["Asset Category"] ?? ""
            isin = r["Security ID"].flatMap { $0.isEmpty ? nil : $0 }
            let symbol = r["Symbol"] ?? ""
            if category == "Equity and Index Options" {
                key = r["Description"] ?? symbol
                ticker = OptionContract(occSymbol: symbol)?.occSymbol
                name = key
                assetClass = .option
                multiplier = number(r["Multiplier"]).flatMap { $0 == 1 ? nil : $0 }
            } else {
                key = symbol
                let exchange = r["Listing Exch"] ?? ""
                if let suffix = yahooSuffix(exchange: exchange) {
                    ticker = symbol + suffix
                } else {
                    ticker = symbol
                    unknownExchange = exchange
                }
                name = r["Description"]
                assetClass = r["Type"] == "ETF" ? .etf : .stock
                multiplier = number(r["Multiplier"]).flatMap { $0 == 1 ? nil : $0 }
            }
        }
    }

    struct Reader {
        var instruments: [Instrument]
        var holdings: [ImportedHolding] = []
        var rows: [ImportedRow] = []
        var positions: [ImportedPosition] = []
        var errors: [CSVLineError] = []
        var warnings: [CSVLineError] = []
        private var warnedExchanges = Set<String>()

        init(instruments: [Instrument]) { self.instruments = instruments }

        static let categories = ["Stocks", "Equity and Index Options"]

        mutating func trade(_ r: Record) {
            guard r["DataDiscriminator"] == "Order", let category = r["Asset Category"],
                  Self.categories.contains(category) else { return }
            guard let (ticker, currency) = resolve(r, category: category) else { return }
            guard let date = r["Date/Time"].flatMap({ LocalDate(string: String($0.prefix(10))) }),
                  let quantity = number(r["Quantity"]), quantity != 0, let price = number(r["T. Price"])
            else { return fail(r, "Trade row could not be read") }
            rows.append(ImportedRow(line: r.line, ticker: ticker, kind: quantity > 0 ? .buy : .sell, date: date,
                                    quantity: abs(quantity), unitPrice: price, amount: nil,
                                    fee: abs(number(r["Comm/Fee"]) ?? 0), tax: 0, currency: currency, notes: nil))
        }

        mutating func position(_ r: Record) {
            guard r["DataDiscriminator"] == "Summary", let category = r["Asset Category"],
                  Self.categories.contains(category) else { return }
            guard let (ticker, _) = resolve(r, category: category) else { return }
            guard let quantity = number(r["Quantity"]), let cost = number(r["Cost Basis"])
            else { return fail(r, "Position row could not be read") }
            guard quantity >= 0 else {
                // Treated as no position, so the holding shows 0 rather than a long position.
                warnings.append(CSVLineError(line: r.line, message: "\(ticker): short positions are not supported (\(quantity))"))
                return
            }
            positions.append(ImportedPosition(ticker: ticker, quantity: quantity, costBasis: cost))
        }

        /// Dividends and withholding are netted per date and security, since IBKR posts corrections as a reversal
        /// plus a new amount. A dividend that nets to zero or less is dropped.
        mutating func dividends(_ dividendRows: [Record], withholding: [Record]) {
            var withheld: [String: Decimal] = [:]
            for w in withholding {
                guard let key = Self.dividendKey(w), let amount = number(w["Amount"]) else { continue }
                withheld[key, default: 0] += amount
            }
            var order: [String] = []
            var gross: [String: (record: Record, amount: Decimal)] = [:]
            for d in dividendRows {
                guard let currencyText = d["Currency"], !currencyText.hasPrefix("Total") else { continue }
                guard let key = Self.dividendKey(d), let amount = number(d["Amount"]) else {
                    fail(d, "Dividend row could not be read"); continue
                }
                if let current = gross[key] {
                    gross[key] = (current.record, current.amount + amount)
                } else {
                    gross[key] = (d, amount)
                    order.append(key)
                }
            }
            for key in order {
                guard let (d, amount) = gross[key], amount > 0 else { continue }
                guard let date = d["Date"].flatMap(LocalDate.init(string:)), let currencyText = d["Currency"]
                else { fail(d, "Dividend row could not be read"); continue }
                let isin = String(key.split(separator: "|")[1])
                guard let instrument = instruments.first(where: { $0.isin == isin }) else {
                    fail(d, "No instrument information for \(isin)"); continue
                }
                guard let currency = Currency(code: currencyText) else {
                    fail(d, "Unsupported currency \(currencyText)"); continue
                }
                guard let ticker = holding(for: instrument, currency: currency, line: d.line) else { continue }
                rows.append(ImportedRow(line: d.line, ticker: ticker, kind: .dividend, date: date, quantity: nil,
                                        unitPrice: nil, amount: amount, fee: 0, tax: max(0, -(withheld[key] ?? 0)),
                                        currency: currency, notes: nil))
            }
        }

        /// `date|ISIN` from a dividend or withholding row (`VWCE(IE00BK5BQT80) Cash Dividend …`).
        static func dividendKey(_ r: Record) -> String? {
            guard let date = r["Date"], !date.isEmpty, let description = r["Description"],
                  let open = description.firstIndex(of: "("), let close = description[open...].firstIndex(of: ")")
            else { return nil }
            return "\(date)|\(description[description.index(after: open)..<close])"
        }

        /// The Yahoo ticker and currency for a trade or position row, registering its holding; records a line
        /// error and returns nil when the row cannot be imported.
        private mutating func resolve(_ r: Record, category: String) -> (String, Currency)? {
            let symbol = r["Symbol"] ?? ""
            guard let instrument = instruments.first(where: { $0.category == category && $0.key == symbol }) else {
                fail(r, "No instrument information for \(symbol)"); return nil
            }
            guard let currencyText = r["Currency"], let currency = Currency(code: currencyText) else {
                fail(r, "Unsupported currency \(r["Currency"] ?? "")"); return nil
            }
            guard let ticker = holding(for: instrument, currency: currency, line: r.line) else { return nil }
            return (ticker, currency)
        }

        private mutating func holding(for instrument: Instrument, currency: Currency, line: Int) -> String? {
            guard let ticker = instrument.ticker else {
                fail(line, "Option symbol for \(instrument.key) could not be read"); return nil
            }
            if let exchange = instrument.unknownExchange, warnedExchanges.insert(ticker).inserted {
                warnings.append(CSVLineError(line: line,
                                             message: "\(ticker): unknown exchange \(exchange), using the bare symbol"))
            }
            if !holdings.contains(where: { $0.ticker == ticker }) {
                holdings.append(ImportedHolding(ticker: ticker, name: instrument.name, assetClass: instrument.assetClass,
                                                currency: currency, multiplier: instrument.multiplier))
            }
            return ticker
        }

        private mutating func fail(_ r: Record, _ message: String) { fail(r.line, message) }
        private mutating func fail(_ line: Int, _ message: String) {
            errors.append(CSVLineError(line: line, message: message))
        }
    }

    // MARK: - Scalars

    static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    /// IBKR numbers use `.` for decimals and may group thousands with `,` (`"1,200"`).
    static func number(_ raw: String?) -> Decimal? {
        guard let raw else { return nil }
        let text = raw.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, case .value(let value) = CSVParser.number(text) else { return nil }
        return value
    }

    private static let periodFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    /// `"August 3, 2026 - October 19, 2026"`.
    static func period(_ text: String) -> ClosedRange<LocalDate>? {
        let parts = text.components(separatedBy: " - ")
        guard parts.count == 2 else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let start = periodFormatter.date(from: parts[0].trimmingCharacters(in: .whitespaces)),
              let end = periodFormatter.date(from: parts[1].trimmingCharacters(in: .whitespaces))
        else { return nil }
        let from = LocalDate(start, calendar: utc), to = LocalDate(end, calendar: utc)
        return from <= to ? from...to : nil
    }
}

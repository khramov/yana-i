import Foundation
import YanaDomain

/// Keyless provider on Yahoo Finance's public (unofficial) endpoints.
///
/// - Price, currency, name, and instrument type come from `v8/finance/chart`, which needs no crumb; FX uses the
///   same endpoint with `FROMTO=X` symbols.
/// - Sector and the dividend calendar come from `v10/finance/quoteSummary` after the cookie + `getcrumb` handshake.
///   If the handshake fails, dividend rate and frequency are estimated from the chart endpoint's `events=div` history.
///
/// Requests carry only the symbol being looked up. The session is ephemeral, so its cookies are isolated from
/// every other session and discarded with it.
public actor YahooFinanceProvider: MarketDataProvider {
    public nonisolated let id = "yahoo"
    public nonisolated let displayName = "Yahoo Finance"
    public nonisolated let isUnofficial = true
    public nonisolated let requiresCredential = false

    static let chartBase = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/")!
    static let summaryBase = URL(string: "https://query2.finance.yahoo.com/v10/finance/quoteSummary/")!
    static let cookieURL = URL(string: "https://fc.yahoo.com/")!
    static let crumbURL = URL(string: "https://query2.finance.yahoo.com/v1/test/getcrumb")!

    private let session: URLSession
    private let now: @Sendable () -> Date
    private var crumb: String?

    public init(session: URLSession = YahooFinanceProvider.makeSession(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.now = now
    }

    /// An ephemeral, cookie-isolated session. `protocolClasses` lets tests stub the network.
    public static func makeSession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                                        "Accept": "application/json"]
        if let protocolClasses { config.protocolClasses = protocolClasses }
        return URLSession(configuration: config)
    }

    // MARK: - MarketDataProvider

    public func quotes(for tickers: [String]) async -> [String: Result<Quote, MarketDataError>] {
        await each(tickers) { t in
            let meta = try await self.chartMeta(t)
            guard let price = meta.decimal("regularMarketPrice") else { throw MarketDataError.invalidResponse("no price") }
            return Quote(ticker: t, price: price, currency: try Self.currency(meta), fetchedAt: self.now())
        }
    }

    public func securityDetails(for tickers: [String]) async -> [String: Result<SecurityDetails, MarketDataError>] {
        await each(tickers) { t in
            let meta = try await self.chartMeta(t)
            let assetClass = Self.assetClass(forInstrumentType: meta.string("instrumentType"))
            var sector: String?
            if assetClass == .stock, let summary = try? await self.quoteSummary(t, modules: ["assetProfile"]) {
                sector = JSON(summary["assetProfile"]).string("sector")
            }
            return SecurityDetails(ticker: t, name: meta.string("longName") ?? meta.string("shortName"),
                                   currency: try Self.currency(meta), assetClass: assetClass, sector: sector)
        }
    }

    public func fxRates(for pairs: [CurrencyPair]) async -> [CurrencyPair: Result<FXRate, MarketDataError>] {
        var out: [CurrencyPair: Result<FXRate, MarketDataError>] = [:]
        for pair in pairs {
            if pair.from == pair.to {
                out[pair] = .success(FXRate(pair: pair, rate: 1, fetchedAt: now()))
                continue
            }
            out[pair] = await capture {
                let meta = try await self.chartMeta("\(pair.from.code)\(pair.to.code)=X")
                guard let rate = meta.decimal("regularMarketPrice"), rate > 0 else {
                    throw MarketDataError.invalidResponse("no rate")
                }
                return FXRate(pair: pair, rate: rate, fetchedAt: self.now())
            }
        }
        return out
    }

    public func dividendEvents(for tickers: [String]) async -> [String: Result<DividendEvent, MarketDataError>] {
        await each(tickers) { t in
            if let summary = try? await self.quoteSummary(t, modules: ["calendarEvents", "summaryDetail", "defaultKeyStatistics"]) {
                return try self.dividendEvent(t, summary: summary)
            }
            return try await self.dividendEventFromHistory(t)
        }
    }

    // MARK: - Chart endpoint

    private func chartMeta(_ symbol: String) async throws -> JSON {
        try await chartResult(symbol, query: [URLQueryItem(name: "range", value: "1d"), URLQueryItem(name: "interval", value: "1d")])
            .object("meta")
    }

    private func chartResult(_ symbol: String, query: [URLQueryItem]) async throws -> JSON {
        var components = URLComponents(url: Self.chartBase.appendingPathComponent(symbol), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        let body = try await get(components.url!)
        let chart = JSON(body).object("chart")
        if chart.string("error.code") == "Not Found" { throw MarketDataError.notFound }
        guard let first = chart.array("result").first else { throw MarketDataError.notFound }
        return JSON(first)
    }

    private func dividendEventFromHistory(_ t: String) async throws -> DividendEvent {
        let result = try await chartResult(t, query: [URLQueryItem(name: "range", value: "2y"),
                                                      URLQueryItem(name: "interval", value: "1mo"),
                                                      URLQueryItem(name: "events", value: "div")])
        let meta = result.object("meta")
        let payments = result.object("events").object("dividends").raw.values
            .compactMap { v -> (Date, Decimal)? in
                let e = JSON(v)
                guard let seconds = e.double("date"), let amount = e.decimal("amount") else { return nil }
                return (Date(timeIntervalSince1970: seconds), amount)
            }
            .sorted { $0.0 < $1.0 }
        let yearAgo = now().addingTimeInterval(-365 * 24 * 3600)
        let lastYear = payments.filter { $0.0 >= yearAgo }
        let annual: Decimal? = lastYear.isEmpty ? nil : lastYear.reduce(Decimal(0)) { $0 + $1.1 }
        let last = payments.last?.1
        return DividendEvent(ticker: t, amountPerShare: last, annualRate: annual,
                             frequency: .detect(annualRate: annual, lastAmount: last),
                             currency: try Self.currency(meta), fetchedAt: now())
    }

    // MARK: - quoteSummary endpoint

    private func quoteSummary(_ symbol: String, modules: [String]) async throws -> [String: Any] {
        for attempt in 0..<2 {
            let crumb = try await currentCrumb(forceRefresh: attempt > 0)
            var components = URLComponents(url: Self.summaryBase.appendingPathComponent(symbol), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "modules", value: modules.joined(separator: ",")),
                                     URLQueryItem(name: "crumb", value: crumb)]
            do {
                let body = try await get(components.url!)
                guard let result = JSON(body).object("quoteSummary").array("result").first as? [String: Any] else {
                    throw MarketDataError.notFound
                }
                return result
            } catch MarketDataError.http(401) {
                continue // stale crumb; fetch a new one once
            }
        }
        throw MarketDataError.http(401)
    }

    private func currentCrumb(forceRefresh: Bool) async throws -> String {
        if let crumb, !forceRefresh { return crumb }
        // The cookie request commonly answers 404 but still sets the session cookie.
        _ = try? await session.data(from: Self.cookieURL)
        let (data, response) = try await load(Self.crumbURL)
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard response.statusCode == 200, !text.isEmpty, !text.contains("<"), !text.contains(" ") else {
            throw MarketDataError.invalidResponse("crumb handshake failed")
        }
        crumb = text
        return text
    }

    private nonisolated func dividendEvent(_ t: String, summary: [String: Any]) throws -> DividendEvent {
        let calendar = JSON(summary["calendarEvents"])
        let detail = JSON(summary["summaryDetail"])
        let stats = JSON(summary["defaultKeyStatistics"])
        let annual = detail.decimal("dividendRate")
        let last = detail.decimal("lastDividendValue") ?? stats.decimal("lastDividendValue")
        guard let currency = Currency(code: detail.string("currency") ?? "") else {
            throw MarketDataError.unsupportedCurrency(detail.string("currency") ?? "unknown")
        }
        return DividendEvent(ticker: t, exDividendDate: calendar.localDate("exDividendDate"),
                             paymentDate: calendar.localDate("dividendDate"), amountPerShare: last, annualRate: annual,
                             frequency: .detect(annualRate: annual, lastAmount: last), currency: currency, fetchedAt: now())
    }

    // MARK: - HTTP

    private func get(_ url: URL) async throws -> Any {
        let (data, response) = try await load(url)
        // Chart's not-found answers 404 with a JSON error body.
        if response.statusCode == 404 { throw MarketDataError.notFound }
        guard (200...299).contains(response.statusCode) else { throw MarketDataError.http(response.statusCode) }
        guard let body = try? JSONSerialization.jsonObject(with: data) else {
            throw MarketDataError.invalidResponse("not JSON")
        }
        return body
    }

    private func load(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { throw MarketDataError.invalidResponse("not HTTP") }
            if http.statusCode == 429 { throw MarketDataError.rateLimited }
            return (data, http)
        } catch let error as MarketDataError {
            throw error
        } catch {
            throw MarketDataError.offline
        }
    }

    private func capture<T>(_ body: () async throws -> T) async -> Result<T, MarketDataError> {
        do { return .success(try await body()) } catch let e as MarketDataError { return .failure(e) } catch {
            return .failure(.invalidResponse("\(error)"))
        }
    }

    private func each<T>(_ tickers: [String], _ body: (String) async throws -> T) async -> [String: Result<T, MarketDataError>] {
        var out: [String: Result<T, MarketDataError>] = [:]
        for t in tickers { out[t] = await capture { try await body(t) } }
        return out
    }

    // MARK: - Mapping

    static func currency(_ meta: JSON) throws -> Currency {
        let code = meta.string("currency") ?? ""
        guard let c = Currency(code: code) else { throw MarketDataError.unsupportedCurrency(code) }
        return c
    }

    /// Ported from the web app's `mapQuoteType`.
    static func assetClass(forInstrumentType type: String?) -> AssetClass {
        switch type?.uppercased() {
        case "ETF", "MUTUALFUND": return .etf
        case "BOND": return .bond
        case "CURRENCY": return .cash
        default: return .stock
        }
    }
}

/// Lenient reader over `JSONSerialization` output. Yahoo returns numbers either plain or as `{"raw": …, "fmt": …}`.
struct JSON {
    let raw: [String: Any]

    init(_ value: Any?) { raw = value as? [String: Any] ?? [:] }

    /// Follows a dotted path.
    private func value(_ path: String) -> Any? {
        var current: Any? = raw
        for part in path.split(separator: ".") { current = (current as? [String: Any])?[String(part)] }
        if let wrapped = current as? [String: Any], let inner = wrapped["raw"] { return inner }
        return current
    }

    func object(_ path: String) -> JSON { JSON(value(path)) }
    func array(_ path: String) -> [Any] { value(path) as? [Any] ?? [] }
    func string(_ path: String) -> String? { value(path) as? String }

    func double(_ path: String) -> Double? {
        guard let n = value(path) as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    /// Via the number's shortest decimal string, so 0.9213 stays exactly 0.9213.
    func decimal(_ path: String) -> Decimal? {
        guard let n = value(path) as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return Decimal(string: n.stringValue, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// A date given as `{"fmt": "YYYY-MM-DD"}` or as epoch seconds (read in UTC).
    func localDate(_ path: String) -> LocalDate? {
        var node: Any? = raw
        for part in path.split(separator: ".") { node = (node as? [String: Any])?[String(part)] }
        if let fmt = (node as? [String: Any])?["fmt"] as? String, let d = LocalDate(string: fmt) { return d }
        guard let seconds = double(path) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return LocalDate(Date(timeIntervalSince1970: seconds), calendar: utc)
    }
}

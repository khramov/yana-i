import Foundation
import Testing
import YanaDomain
@testable import YanaMarketData

/// Routes every request of a stubbed session through a handler and records the requests.
final class StubURLProtocol: URLProtocol {
    struct Reply {
        var status: Int
        var body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((URLRequest) -> Reply)?
    nonisolated(unsafe) private static var log: [URLRequest] = []

    static func install(_ handler: @escaping (URLRequest) -> Reply) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
        log = []
    }

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return log
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.log.append(request)
        let handler = Self.handler
        Self.lock.unlock()
        let reply = handler?(request) ?? Reply(status: 500, body: Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

let fixturesDirectory = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!

func fixture(_ name: String) -> Data? {
    try? Data(contentsOf: fixturesDirectory.appendingPathComponent(name))
}

/// Serves the checked-in fixtures the way the live endpoints would.
func yahooRouter(crumbStatus: Int = 200, summaryStatus: Int? = nil) -> (URLRequest) -> StubURLProtocol.Reply {
    { request in
        let url = request.url!
        let path = url.path.removingPercentEncoding ?? url.path
        let symbol = (path as NSString).lastPathComponent
        if url.host == "fc.yahoo.com" { return .init(status: 404, body: Data()) }
        if path.hasSuffix("/getcrumb") {
            return .init(status: crumbStatus, body: Data((crumbStatus == 200 ? "AbCdEf12345" : "Too Many Requests").utf8))
        }
        if path.contains("/quoteSummary/") {
            if let summaryStatus { return .init(status: summaryStatus, body: Data()) }
            let name = symbol == "AAPL" ? "quoteSummary-AAPL-assetProfile.json" : "quoteSummary-\(symbol).json"
            if let body = fixture(name) { return .init(status: 200, body: body) }
            return .init(status: 404, body: Data(#"{"quoteSummary":{"result":null,"error":{"code":"Not Found"}}}"#.utf8))
        }
        if path.contains("/chart/") {
            let suffix = (url.query ?? "").contains("events=div") ? "-div" : ""
            if let body = fixture("chart-\(symbol)\(suffix).json") { return .init(status: 200, body: body) }
            return .init(status: 404, body: fixture("chart-notfound.json")!)
        }
        return .init(status: 500, body: Data())
    }
}

let fixedNow = Date(timeIntervalSince1970: 1_729_300_000) // 2024-10-19

func makeProvider() -> YahooFinanceProvider {
    YahooFinanceProvider(session: YahooFinanceProvider.makeSession(protocolClasses: [StubURLProtocol.self]),
                         now: { fixedNow })
}

@Suite(.serialized) struct YahooFinanceProviderTests {
    @Test func quoteFromChart() async throws {
        StubURLProtocol.install(yahooRouter())
        let q = try await makeProvider().quotes(for: ["AAPL"])["AAPL"]!.get()
        #expect(q == Quote(ticker: "AAPL", price: 235, currency: .usd, fetchedAt: fixedNow))
    }

    @Test func detailsMapInstrumentTypeAndSector() async throws {
        StubURLProtocol.install(yahooRouter())
        let r = await makeProvider().securityDetails(for: ["AAPL", "VTI", "ZZZZQ"])
        #expect(try r["AAPL"]!.get() == SecurityDetails(ticker: "AAPL", name: "Apple Inc.", currency: .usd,
                                                        assetClass: .stock, sector: "Technology"))
        let vti = try r["VTI"]!.get()
        #expect(vti.assetClass == .etf && vti.sector == nil)
        #expect(vti.name == "Vanguard Total Stock Market Index Fund ETF Shares")
        #expect(r["ZZZZQ"] == .failure(.notFound))
    }

    @Test func detailsSurviveCrumbFailureWithoutSector() async throws {
        StubURLProtocol.install(yahooRouter(crumbStatus: 429))
        let aapl = try await makeProvider().securityDetails(for: ["AAPL"])["AAPL"]!.get()
        #expect(aapl.sector == nil && aapl.currency == .usd)
    }

    @Test func unsupportedCurrencyIsReported() async throws {
        StubURLProtocol.install(yahooRouter())
        #expect(await makeProvider().quotes(for: ["VOD.L"])["VOD.L"] == .failure(.unsupportedCurrency("GBp")))
        #expect(try await makeProvider().quotes(for: ["SBER.ME"])["SBER.ME"]!.get().currency == .rub)
    }

    @Test func fxRateFromCurrencySymbol() async throws {
        StubURLProtocol.install(yahooRouter())
        let r = await makeProvider().fxRates(for: [CurrencyPair(.usd, .eur), CurrencyPair(.eur, .eur), CurrencyPair(.rub, .eur)])
        #expect(try r[CurrencyPair(.usd, .eur)]!.get().rate == Decimal(string: "0.9213"))
        #expect(try r[CurrencyPair(.eur, .eur)]!.get().rate == 1)
        #expect(r[CurrencyPair(.rub, .eur)] == .failure(.notFound))
        #expect(StubURLProtocol.requests.contains { $0.url!.path.removingPercentEncoding!.hasSuffix("/chart/USDEUR=X") })
    }

    @Test func dividendEventFromQuoteSummary() async throws {
        StubURLProtocol.install(yahooRouter())
        let e = try await makeProvider().dividendEvents(for: ["KO"])["KO"]!.get()
        #expect(e.exDividendDate == LocalDate(string: "2024-11-29"))
        #expect(e.paymentDate == LocalDate(string: "2024-12-13"))
        #expect(e.annualRate == Decimal(string: "1.94"))
        #expect(e.amountPerShare == Decimal(string: "0.485"))
        #expect(e.frequency == .quarterly)
        #expect(e.currency == .usd)
        let summary = try #require(StubURLProtocol.requests.first { $0.url!.path.contains("quoteSummary") })
        #expect(URLComponents(url: summary.url!, resolvingAgainstBaseURL: false)!.queryItems!
            .first { $0.name == "crumb" }?.value == "AbCdEf12345")
    }

    @Test func dividendFallbackWhenCrumbFails() async throws {
        StubURLProtocol.install(yahooRouter(crumbStatus: 429))
        let e = try await makeProvider().dividendEvents(for: ["KO"])["KO"]!.get()
        // Payments in the year before 2024-10-19: 0.46 (Dec 2023) + 3 × 0.485.
        #expect(e.annualRate == Decimal(string: "1.915"))
        #expect(e.amountPerShare == Decimal(string: "0.485"))
        #expect(e.frequency == .quarterly)
        #expect(e.exDividendDate == nil)
        #expect(!StubURLProtocol.requests.contains { $0.url!.path.contains("quoteSummary") })
    }

    @Test func staleCrumbIsRefreshedOnceThenFallsBack() async throws {
        StubURLProtocol.install(yahooRouter(summaryStatus: 401))
        let e = try await makeProvider().dividendEvents(for: ["KO"])["KO"]!.get()
        #expect(e.annualRate == Decimal(string: "1.915"))
        #expect(StubURLProtocol.requests.filter { $0.url!.path.hasSuffix("/getcrumb") }.count == 2)
    }

    @Test func rateLimitAndServerErrorsMapToTransientErrors() async {
        StubURLProtocol.install { _ in .init(status: 429, body: Data("Too Many Requests".utf8)) }
        #expect(await makeProvider().quotes(for: ["AAPL"])["AAPL"] == .failure(.rateLimited))
        StubURLProtocol.install { _ in .init(status: 502, body: Data()) }
        #expect(await makeProvider().quotes(for: ["AAPL"])["AAPL"] == .failure(.http(502)))
        #expect(MarketDataError.http(502).isTransient && MarketDataError.rateLimited.isTransient)
        #expect(!MarketDataError.notFound.isTransient)
    }

    @Test func requestsContainOnlySymbols() async {
        StubURLProtocol.install(yahooRouter())
        let p = makeProvider()
        _ = await p.quotes(for: ["MSFT", "AAPL"])
        _ = await p.securityDetails(for: ["AAPL"])
        _ = await p.fxRates(for: [CurrencyPair(.usd, .eur)])
        _ = await p.dividendEvents(for: ["KO"])
        let allowedQueryKeys: Set<String> = ["range", "interval", "events", "modules", "crumb"]
        for r in StubURLProtocol.requests {
            let c = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)!
            #expect(Set((c.queryItems ?? []).map(\.name)).isSubset(of: allowedQueryKeys), "\(r.url!)")
            #expect(r.httpBody == nil && r.httpMethod == "GET")
            #expect(r.value(forHTTPHeaderField: "Authorization") == nil)
        }
        let symbols = Set(StubURLProtocol.requests.compactMap { r -> String? in
            let path = r.url!.path.removingPercentEncoding!
            return path.contains("/chart/") || path.contains("/quoteSummary/") ? (path as NSString).lastPathComponent : nil
        })
        #expect(symbols == ["MSFT", "AAPL", "USDEUR=X", "KO"])
    }

    @Test func sessionIsEphemeralWithIsolatedCookies() {
        let session = YahooFinanceProvider.makeSession()
        #expect(session.configuration.httpCookieStorage !== HTTPCookieStorage.shared)
        #expect(session.configuration.urlCache !== URLCache.shared)
    }

    @Test func instrumentTypeMappingMatchesWeb() {
        #expect(YahooFinanceProvider.assetClass(forInstrumentType: "MUTUALFUND") == .etf)
        #expect(YahooFinanceProvider.assetClass(forInstrumentType: "BOND") == .bond)
        #expect(YahooFinanceProvider.assetClass(forInstrumentType: "CURRENCY") == .cash)
        #expect(YahooFinanceProvider.assetClass(forInstrumentType: "EQUITY") == .stock)
        #expect(YahooFinanceProvider.assetClass(forInstrumentType: nil) == .stock)
    }
}

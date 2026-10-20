import AppKit
import XCTest

/// Drives the app against a throwaway store directory, its own preferences suite, and the stub market-data
/// provider (AAPL 200 USD, MSFT 400 USD, KO 60 USD, USD→EUR 0.9; ZZZZQ is unknown).
class YanaUITestCase: XCTestCase {
    var storeDirectory: URL!
    var defaultsSuite: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        storeDirectory = FileManager.default.temporaryDirectory.appending(path: "yana-uitests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defaultsSuite = "yana.uitests.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
    }

    @discardableResult
    func launch(_ extra: [String] = ["-AppleLocale", "en_US", "-AppleLanguages", "(en)"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-YanaStoreDirectory", storeDirectory.path, "-YanaDefaultsSuite", defaultsSuite,
                               "-YanaStubMarketData", "YES", "-ApplePersistenceIgnoreState", "YES"] + extra
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func createFirstPortfolio(_ app: XCUIApplication, name: String) {
        let field = app.textFields["portfolioName"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click()
        field.typeText(name)
        app.buttons["savePortfolio"].click()
        XCTAssertTrue(element(app, "portfolioPicker").waitForExistence(timeout: 10))
    }

    func showSection(_ app: XCUIApplication, _ title: String) {
        let row = app.outlines.firstMatch.staticTexts[title]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
    }

    func addHolding(_ app: XCUIApplication, _ ticker: String) {
        app.buttons["addHolding"].firstMatch.click()
        let field = app.textFields["holdingTicker"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText(ticker)
        app.buttons["saveHolding"].click()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10), "add sheet stayed open for \(ticker)")
    }

    /// Records a buy through the ⌘N form.
    func addBuy(_ app: XCUIApplication, ticker: String, shares: String, price: String) {
        app.typeKey("n", modifierFlags: .command)
        let holding = app.popUpButtons["transactionHolding"]
        XCTAssertTrue(holding.waitForExistence(timeout: 5))
        holding.click()
        app.menuItems[ticker].click()
        let sharesField = app.textFields["transactionShares"]
        sharesField.click()
        sharesField.typeText(shares)
        let priceField = app.textFields["transactionPrice"]
        priceField.click()
        priceField.typeText(price)
        app.buttons["saveTransaction"].click()
        XCTAssertTrue(sharesField.waitForNonExistence(timeout: 10))
    }

    /// Clicks a button in the window's confirmation sheet (not its Touch Bar twin).
    func confirm(_ app: XCUIApplication, _ title: String) {
        let button = app.windows.firstMatch.sheets.buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "no “\(title)” button in a sheet")
        button.click()
    }

    /// SwiftUI exposes a text's content as the element's value, and a control's as its label.
    func waitForText(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 10) {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let shown = element.exists ? "\(element.label) / \(element.value ?? "")" : "missing"
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed,
                       "\(element) shows “\(shown)”, expected “\(text)”")
    }

    func waitForTitle(_ app: XCUIApplication, containing text: String) {
        let predicate = NSPredicate(format: "title CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.windows.firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, app.windows.firstMatch.title)
    }

    func text(_ value: String, in element: XCUIElement) -> XCUIElement {
        element.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", value, value)).firstMatch
    }
}

final class AppShellUITests: YanaUITestCase {
    func testFirstPortfolioFromEmptyStateAndRelaunchRestoresSelection() throws {
        var app = launch()
        XCTAssertTrue(app.staticTexts["Welcome to Yana"].waitForExistence(timeout: 10))
        createFirstPortfolio(app, name: "Long term")
        XCTAssertTrue(element(app, "dashboardEmpty").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Add Transaction…"].exists)
        XCTAssertTrue(app.buttons["Import CSV…"].exists)

        // A second portfolio becomes selected; switch back and open Dividends.
        app.typeKey("n", modifierFlags: [.command, .shift])
        let name = app.textFields["portfolioName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("Pension")
        app.buttons["savePortfolio"].click()
        let picker = app.popUpButtons["portfolioPicker"]
        waitForText(picker, containing: "Pension")
        XCTAssertEqual(picker.value as? String, "Pension")
        picker.click()
        app.menuItems["Long term"].click()
        XCTAssertEqual(picker.value as? String, "Long term")
        showSection(app, "Dividends")
        waitForTitle(app, containing: "Dividends")

        app.terminate()
        app = launch()
        let restored = app.popUpButtons["portfolioPicker"]
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertEqual(restored.value as? String, "Long term")
        waitForTitle(app, containing: "Dividends")
    }
}

final class HoldingsUITests: YanaUITestCase {
    func testAddSortAndDeleteHoldings() throws {
        let app = launch()
        createFirstPortfolio(app, name: "P")
        showSection(app, "Holdings")
        addHolding(app, "AAPL")
        addHolding(app, "MSFT")

        // An unknown ticker is rejected and creates nothing.
        app.buttons["addHolding"].firstMatch.click()
        let ticker = app.textFields["holdingTicker"]
        XCTAssertTrue(ticker.waitForExistence(timeout: 5))
        ticker.click()
        ticker.typeText("ZZZZQ")
        app.buttons["saveHolding"].click()
        let error = element(app, "fieldError")
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        waitForText(error, containing: "ZZZZQ was not found")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(ticker.waitForNonExistence(timeout: 5))

        addBuy(app, ticker: "AAPL", shares: "3", price: "150")  // 3 × 200 = 600 USD
        addBuy(app, ticker: "MSFT", shares: "1", price: "300")  // 1 × 400 = 400 USD

        let table = app.outlines["holdingsTable"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        XCTAssertEqual(table.outlineRows.count, 2)
        waitForText(text("€540.00", in: table), containing: "€540.00")  // prices loaded: 3 × 200 × 0.9
        func firstTicker() -> String { table.outlineRows.element(boundBy: 0).staticTexts.element(boundBy: 0).value as? String ?? "" }
        XCTAssertEqual(firstTicker(), "AAPL")

        // Header buttons of an NSTableView report themselves as not hittable; click their center directly.
        let marketValue = table.buttons["Market Value"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        marketValue.click()
        let ascending = firstTicker()
        marketValue.click()
        let descending = firstTicker()
        XCTAssertEqual(Set([ascending, descending]), ["AAPL", "MSFT"], "clicking again reverses the order")
        XCTAssertEqual(descending == "AAPL" ? ascending : descending, "MSFT")

        // A holding with transactions can't be deleted.
        // Rows are wider than the visible table, so click a cell's text rather than the row.
        table.outlineRows.element(boundBy: 0).staticTexts.element(boundBy: 0).click()
        app.buttons["deleteHolding"].firstMatch.click()
        confirm(app, "Delete")
        XCTAssertTrue(text("1 transaction must be deleted first.", in: app).waitForExistence(timeout: 5))
        confirm(app, "OK")
        XCTAssertEqual(table.outlineRows.count, 2)

        // A holding without transactions can.
        addHolding(app, "KO")
        XCTAssertEqual(table.outlineRows.count, 3)
        let ko = text("KO", in: table)
        ko.click()
        app.buttons["deleteHolding"].firstMatch.click()
        confirm(app, "Delete")
        XCTAssertTrue(ko.waitForNonExistence(timeout: 5))
        XCTAssertEqual(table.outlineRows.count, 2)
    }
}

final class TransactionsUITests: YanaUITestCase {
    func testEditingABuyUpdatesHoldings() throws {
        let app = launch()
        createFirstPortfolio(app, name: "P")
        showSection(app, "Holdings")
        addHolding(app, "KO")
        addBuy(app, ticker: "KO", shares: "10", price: "50")

        showSection(app, "Transactions")
        let transactions = app.outlines["transactionsTable"]
        XCTAssertTrue(transactions.waitForExistence(timeout: 5))
        XCTAssertEqual(transactions.outlineRows.count, 1)
        text("KO", in: transactions).doubleClick()
        let shares = app.textFields["transactionShares"]
        XCTAssertTrue(shares.waitForExistence(timeout: 5))
        shares.doubleClick()
        shares.typeKey("a", modifierFlags: .command)
        shares.typeText("12")
        app.buttons["saveTransaction"].click()
        XCTAssertTrue(shares.waitForNonExistence(timeout: 5))

        showSection(app, "Holdings")
        let row = app.outlines["holdingsTable"].outlineRows.element(boundBy: 0)
        XCTAssertTrue(text("12", in: row).waitForExistence(timeout: 5))
    }

    func testSellWithoutSharesShowsInlineError() throws {
        let app = launch()
        createFirstPortfolio(app, name: "P")
        showSection(app, "Holdings")
        addHolding(app, "KO")
        app.typeKey("n", modifierFlags: .command)
        let kind = app.radioGroups["transactionKind"]
        XCTAssertTrue(kind.waitForExistence(timeout: 5))
        kind.radioButtons["Sell"].click()
        let price = app.textFields["transactionPrice"]
        price.click()
        price.typeText("60")
        app.buttons["saveTransaction"].click()
        XCTAssertTrue(app.staticTexts["Shares are required for buy and sell"].waitForExistence(timeout: 5))
        XCTAssertTrue(price.exists, "the form stays open")
    }
}

final class SettingsUITests: YanaUITestCase {
    func testChangingBaseCurrencyRecalculatesValues() throws {
        let app = launch()
        createFirstPortfolio(app, name: "P")
        showSection(app, "Holdings")
        addHolding(app, "AAPL")
        addBuy(app, ticker: "AAPL", shares: "1", price: "100")
        showSection(app, "Dashboard")
        let total = element(app, "totalValue")
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        waitForText(total, containing: "€180.00")

        app.typeKey(",", modifierFlags: .command)
        let currency = app.popUpButtons["settingsBaseCurrency"]
        XCTAssertTrue(currency.waitForExistence(timeout: 5))
        currency.click()
        app.menuItems["USD"].click()
        app.buttons["settingsSavePortfolio"].click()
        app.typeKey("w", modifierFlags: .command)

        waitForText(total, containing: "$200.00")
    }
}

final class AppearanceUITests: YanaUITestCase {
    /// Average luminance (0…1) of the main window.
    private func luminance(_ app: XCUIApplication) throws -> Double {
        let image = app.windows.firstMatch.screenshot().image
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let width = 64, height = 64
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var sum = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            sum += (0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])) / 255
        }
        return sum / Double(width * height)
    }

    private func preparePortfolio(_ app: XCUIApplication) {
        createFirstPortfolio(app, name: "P")
        showSection(app, "Holdings")
        addHolding(app, "AAPL")
        addBuy(app, ticker: "AAPL", shares: "10", price: "100")
        showSection(app, "Dashboard")
    }

    func testFollowsLightAndDarkAppearance() throws {
        var app = launch(["-AppleLocale", "en_US", "-AppleLanguages", "(en)", "-YanaAppearance", "light"])
        preparePortfolio(app)
        XCTAssertTrue(element(app, "totalValue").waitForExistence(timeout: 10))
        let light = try luminance(app)
        add(XCTAttachment(screenshot: app.windows.firstMatch.screenshot()))
        app.terminate()

        app = launch(["-AppleLocale", "en_US", "-AppleLanguages", "(en)", "-YanaAppearance", "dark"])
        XCTAssertTrue(element(app, "totalValue").waitForExistence(timeout: 10))
        let dark = try luminance(app)
        add(XCTAttachment(screenshot: app.windows.firstMatch.screenshot()))
        XCTAssertGreaterThan(light, 0.6, "light appearance")
        XCTAssertLessThan(dark, 0.35, "dark appearance")
    }

    func testGermanLocaleUsesDecimalComma() throws {
        let app = launch(["-AppleLocale", "de_DE", "-AppleLanguages", "(en)"])
        preparePortfolio(app)
        // 10 × 200 USD × 0.9 = 1.800,00 €
        waitForText(element(app, "totalValue"), containing: "1.800,00\u{00A0}€")
        showSection(app, "Holdings")
        let row = app.outlines["holdingsTable"].outlineRows.element(boundBy: 0)
        let price = row.staticTexts.matching(NSPredicate(format: "value BEGINSWITH '200,00'")).firstMatch
        XCTAssertTrue(price.waitForExistence(timeout: 5), "price cell uses a decimal comma")
        add(XCTAttachment(screenshot: app.windows.firstMatch.screenshot()))
    }
}

final class ChartAccessibilityUITests: YanaUITestCase {
    func testChartMarksAreAnnounced() throws {
        let app = launch()
        createFirstPortfolio(app, name: "P")
        showSection(app, "Holdings")
        addHolding(app, "VTI")
        addHolding(app, "KO")
        addBuy(app, ticker: "VTI", shares: "4", price: "200")   // 4 × 250 × 0.9 = 900 €
        addBuy(app, ticker: "KO", shares: "10", price: "50")    // 10 × 60 × 0.9 = 540 €

        showSection(app, "Analytics")
        let chart = element(app, "allocationChart")
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        let etf = chart.descendants(matching: .any).matching(NSPredicate(format: "label == 'ETF: €900.00, 62.5%'")).firstMatch
        XCTAssertTrue(etf.waitForExistence(timeout: 5), "allocation slice is announced with label, value, and percentage")
        XCTAssertTrue(chart.descendants(matching: .any)["Stock: €540.00, 37.5%"].exists)

        // Record a dividend so the income chart has a bar.
        app.typeKey("n", modifierFlags: .command)
        let holding = app.popUpButtons["transactionHolding"]
        XCTAssertTrue(holding.waitForExistence(timeout: 5))
        holding.click()
        app.menuItems["KO"].click()
        app.radioGroups["transactionKind"].radioButtons["Dividend"].click()
        let amount = app.textFields["transactionAmount"]
        amount.click()
        amount.typeText("10")
        app.buttons["saveTransaction"].click()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 10))

        showSection(app, "Income")
        let income = element(app, "incomeChart")
        XCTAssertTrue(income.waitForExistence(timeout: 10))
        let bar = income.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH ': €9.00'")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "income bar is announced with its month and amount")
    }
}

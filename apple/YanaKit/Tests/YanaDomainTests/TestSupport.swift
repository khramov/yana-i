import Foundation
@testable import YanaDomain

/// Exact decimal from a literal string (avoids `Double` rounding in `Decimal(0.1)`).
func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

func day(_ s: String) -> LocalDate { LocalDate(string: s)! }

let deviceA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
let deviceB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
let epoch = Date(timeIntervalSince1970: 1_700_000_000)

var utcCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

let portfolioID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

func holding(_ ticker: String, currency: Currency = .usd, assetClass: AssetClass = .stock,
             sector: String? = nil, name: String? = nil) -> HoldingRecord {
    HoldingRecord(id: RecordIdentity.holdingID(portfolioID: portfolioID, ticker: ticker), portfolioID: portfolioID,
                  ticker: ticker, name: name, sector: sector, assetClass: assetClass, currency: currency,
                  createdAt: epoch, version: .initial(at: epoch, deviceID: deviceA))
}

private let txCounterLock = NSLock()
private nonisolated(unsafe) var txCounter = 0

private func nextTxTick() -> Int {
    txCounterLock.lock()
    defer { txCounterLock.unlock() }
    txCounter += 1
    return txCounter
}

/// A transaction with an increasing creation time, so ties on date keep insertion order.
func tx(_ h: HoldingRecord, _ kind: TransactionKind, _ date: String, qty: String? = nil, price: String? = nil,
        amount: String? = nil, fee: String = "0", tax: String = "0", currency: Currency? = nil) -> TransactionRecord {
    let created = epoch.addingTimeInterval(TimeInterval(nextTxTick()))
    return TransactionRecord(id: UUID(), portfolioID: h.portfolioID, holdingID: h.id, kind: kind, date: day(date),
                             quantity: qty.map(dec), unitPrice: price.map(dec), amount: amount.map(dec),
                             fee: dec(fee), tax: dec(tax), currency: currency ?? h.currency, createdAt: created,
                             version: .initial(at: created, deviceID: deviceA))
}

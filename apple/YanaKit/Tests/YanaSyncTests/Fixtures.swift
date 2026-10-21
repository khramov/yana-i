import Foundation
import YanaDomain
@testable import YanaSync

func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

let deviceA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
let deviceB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
/// 2023-11-14T22:13:20.123Z
let t0 = Date(timeIntervalSince1970: 1_700_000_000.123)
let pid = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

enum Sample {
    static let portfolio = PortfolioRecord(id: pid, name: "Long term / \"core\"", baseCurrency: .eur, createdAt: t0,
                                           version: RecordVersion(revision: 3, modifiedAt: t0, deviceID: deviceA))

    static let holding = HoldingRecord(id: RecordIdentity.holdingID(portfolioID: pid, ticker: "VTI"), portfolioID: pid,
                                       ticker: "VTI", name: "Vanguard Total Stock Market", sector: nil, assetClass: .etf,
                                       currency: .usd, createdAt: t0,
                                       version: RecordVersion(revision: 1, modifiedAt: t0, deviceID: deviceB))

    static let transaction = TransactionRecord(
        id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!, portfolioID: pid, holdingID: holding.id,
        kind: .buy, date: LocalDate(string: "2024-02-29")!, quantity: dec("0.3"), unitPrice: dec("105.25"),
        fee: dec("1.5"), tax: 0, currency: .usd, notes: "Ünïcode ✓", createdAt: t0,
        version: RecordVersion(revision: 2, modifiedAt: t0.addingTimeInterval(60), deviceID: deviceA))

    static let goalTombstone = GoalRecord(
        id: RecordIdentity.goalID(portfolioID: pid, scope: .assetClass, key: "stock"), portfolioID: pid,
        scope: .assetClass, key: "stock", targetPercent: dec("62.5"), createdAt: t0,
        version: RecordVersion(revision: 4, modifiedAt: t0, deviceID: deviceA), deletedAt: t0.addingTimeInterval(1))

    static let optionHolding = HoldingRecord(
        id: RecordIdentity.holdingID(portfolioID: pid, ticker: "PBR271217C00027000"), portfolioID: pid,
        ticker: "PBR271217C00027000", name: "PBR 17DEC27 27 C", assetClass: .option, currency: .usd,
        multiplier: dec("100"), createdAt: t0, version: RecordVersion(revision: 1, modifiedAt: t0, deviceID: deviceA))

    static let openingTransaction = TransactionRecord(
        id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!, portfolioID: pid,
        holdingID: RecordIdentity.holdingID(portfolioID: pid, ticker: "VWCE.DE"), kind: .buy,
        date: LocalDate(string: "2026-08-03")!, quantity: dec("20"), unitPrice: dec("90"), currency: .eur,
        notes: "Opening balance", importSource: .ibkr,
        openingBalance: OpeningBalance(asOf: LocalDate(string: "2026-10-19")!, targetQuantity: dec("30"),
                                       targetCostBasis: dec("2801.25"),
                                       coveredFrom: LocalDate(string: "2026-08-03")!),
        createdAt: Date(timeIntervalSince1970: 0),
        version: RecordVersion(revision: 1, modifiedAt: t0, deviceID: deviceA))

    static let all: [(String, AnyRecord)] = [("portfolio", AnyRecord(portfolio)), ("holding", AnyRecord(holding)),
                                             ("transaction", AnyRecord(transaction)), ("goal-tombstone", AnyRecord(goalTombstone)),
                                             ("option-holding", AnyRecord(optionHolding)),
                                             ("opening-transaction", AnyRecord(openingTransaction))]
}

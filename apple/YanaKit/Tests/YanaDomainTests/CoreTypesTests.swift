import Foundation
import Testing
@testable import YanaDomain

@Suite struct RecordVersionTests {
    @Test func revisionDominates() {
        let older = RecordVersion(revision: 2, modifiedAt: epoch.addingTimeInterval(1000), deviceID: deviceB)
        let newer = RecordVersion(revision: 3, modifiedAt: epoch, deviceID: deviceA)
        #expect(older < newer)
    }

    @Test func timestampBreaksEqualRevisions() {
        let a = RecordVersion(revision: 3, modifiedAt: epoch, deviceID: deviceB)
        let b = RecordVersion(revision: 3, modifiedAt: epoch.addingTimeInterval(1), deviceID: deviceA)
        #expect(a < b)
    }

    @Test func deviceBreaksEqualRevisionAndTime() {
        let a = RecordVersion(revision: 3, modifiedAt: epoch, deviceID: deviceA)
        let b = RecordVersion(revision: 3, modifiedAt: epoch, deviceID: deviceB)
        #expect(a < b)
        #expect(!(b < a))
        #expect(a == a)
    }

    @Test func bumpIncrementsRevisionAndStampsDevice() {
        let v = RecordVersion.initial(at: epoch, deviceID: deviceA).bumped(at: epoch.addingTimeInterval(5), deviceID: deviceB)
        #expect(v == RecordVersion(revision: 2, modifiedAt: epoch.addingTimeInterval(5), deviceID: deviceB))
    }
}

@Suite struct LocalDateTests {
    @Test func parsesValidDates() {
        let d = LocalDate(string: "2024-02-29")
        #expect(d?.year == 2024 && d?.month == 2 && d?.day == 29)
        #expect(d?.description == "2024-02-29")
    }

    @Test(arguments: ["2023-02-29", "2024-13-01", "2024-00-10", "2024-04-31", "24-01-01",
                      "2024-1-01", "2024/01/01", "2024-01-01T00:00", " 2024-01-01", "", "abcd-ef-gh"])
    func rejectsInvalidStrings(_ raw: String) {
        #expect(LocalDate(string: raw) == nil)
    }

    @Test func ordersChronologically() {
        #expect(day("2024-01-31") < day("2024-02-01"))
        #expect(day("2023-12-31") < day("2024-01-01"))
    }

    @Test func codesAsString() throws {
        let data = try JSONEncoder().encode([day("2025-03-07")])
        #expect(String(decoding: data, as: UTF8.self) == #"["2025-03-07"]"#)
        #expect(try JSONDecoder().decode([LocalDate].self, from: data) == [day("2025-03-07")])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([LocalDate].self, from: Data(#"["2025-3-7"]"#.utf8)) }
    }

    @Test func doesNotShiftWithTimeZone() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = day("2025-06-15")
        #expect(LocalDate(date.startOfDay(in: tokyo), calendar: tokyo) == date)
        #expect(LocalDate(date.startOfDay(in: utcCalendar), calendar: utcCalendar) == date)
    }
}

@Suite struct EnumTests {
    @Test func currencyLookup() {
        #expect(Currency(code: " usd ") == .usd)
        #expect(Currency(code: "GBP") == nil)
        #expect(Currency.default == .eur)
        #expect(GoalScope.assetClass.rawValue == "asset_class")
    }
}

@Suite struct MillisecondPrecisionTests {
    @Test func versionTruncatesToMilliseconds() {
        let v = RecordVersion(revision: 1, modifiedAt: Date(timeIntervalSince1970: 1.2345678), deviceID: deviceA)
        #expect(v.modifiedAt == Date(timeIntervalSince1970: 1.234))
    }
}

import Foundation

/// A calendar date (`YYYY-MM-DD`) with no time or time zone, so it never shifts between devices.
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Returns `nil` unless the components form a real Gregorian date in years 1...9999.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month), day >= 1,
              day <= LocalDate.daysInMonth(year: year, month: month)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses exactly `YYYY-MM-DD` (four, two, and two ASCII digits).
    public init?(string: String) {
        let bytes = Array(string.utf8)
        guard bytes.count == 10, bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-") else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for b in bytes[range] {
                guard b >= UInt8(ascii: "0"), b <= UInt8(ascii: "9") else { return nil }
                value = value * 10 + Int(b - UInt8(ascii: "0"))
            }
            return value
        }
        guard let y = number(0..<4), let m = number(5..<7), let d = number(8..<10) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// The date `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year!
        self.month = c.month!
        self.day = c.day!
    }

    /// Midnight at the start of this date in `calendar`'s time zone.
    public func startOfDay(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public func adding(months: Int, calendar: Calendar) -> LocalDate {
        LocalDate(calendar.date(byAdding: .month, value: months, to: startOfDay(in: calendar))!, calendar: calendar)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }
}

extension LocalDate: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let date = LocalDate(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected YYYY-MM-DD, got \(raw)")
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

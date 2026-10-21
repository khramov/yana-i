import Foundation

public enum OptionRight: String, Sendable, CaseIterable {
    case call = "C"
    case put = "P"
}

/// An exchange-listed option, identified by its OCC symbol (`PBR271217C00027000`): underlying, expiry as `yyMMdd`,
/// `C` or `P`, and the strike × 1000 as eight digits. Yahoo quotes options under the same symbol.
public struct OptionContract: Equatable, Sendable {
    public var underlying: String
    public var expiry: LocalDate
    public var right: OptionRight
    public var strike: Decimal

    public init(underlying: String, expiry: LocalDate, right: OptionRight, strike: Decimal) {
        self.underlying = underlying.trimmingCharacters(in: .whitespaces).uppercased()
        self.expiry = expiry
        self.right = right
        self.strike = strike
    }

    /// Parses an OCC symbol, including IBKR's form with the underlying padded by spaces (`PBR   271217C00027000`).
    public init?(occSymbol: String) {
        let compact = occSymbol.replacingOccurrences(of: " ", with: "").uppercased()
        guard compact.count > 15 else { return nil }
        let tail = Array(compact.suffix(15))
        let underlying = String(compact.dropLast(15))
        guard !underlying.isEmpty, underlying.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." }),
              tail.allSatisfy({ $0.isASCII }),
              let yy = Int(String(tail[0..<2])), let mm = Int(String(tail[2..<4])), let dd = Int(String(tail[4..<6])),
              let expiry = LocalDate(year: 2000 + yy, month: mm, day: dd),
              let right = OptionRight(rawValue: String(tail[6])),
              let thousandths = Int(String(tail[7..<15]))
        else { return nil }
        self.init(underlying: underlying, expiry: expiry, right: right, strike: Decimal(thousandths) / 1000)
    }

    public var occSymbol: String {
        var thousandths = strike * 1000
        var whole = Decimal()
        NSDecimalRound(&whole, &thousandths, 0, .plain)
        let digits = String(describing: whole)
        return underlying + Self.twoDigits(expiry.year % 100) + Self.twoDigits(expiry.month) + Self.twoDigits(expiry.day)
            + right.rawValue + String(repeating: "0", count: max(0, 8 - digits.count)) + digits
    }

    /// The broker-style name, `PBR 17DEC27 27 C`.
    public var displayName: String {
        "\(underlying) \(Self.twoDigits(expiry.day))\(Self.months[expiry.month - 1])\(Self.twoDigits(expiry.year % 100))"
            + " \(strike) \(right.rawValue)"
    }

    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    private static func twoDigits(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}

import Foundation
import SwiftUI
import YanaDomain

/// Locale-aware display formatting. Values stay `Decimal` until this point; rounding happens only here.
/// Views pass `@Environment(\.locale)`, so the person's region settings apply everywhere.
enum Fmt {
    /// Shown for a value that cannot be computed (no price or FX rate), never as zero.
    static let unavailable = "—"
    static let unavailableLabel = "Unavailable"

    static func money(_ value: Decimal, _ currency: Currency, locale: Locale) -> String {
        value.formatted(.currency(code: currency.code).locale(locale))
    }

    static func money(_ value: Decimal?, _ currency: Currency, locale: Locale) -> String {
        value.map { money($0, currency, locale: locale) } ?? unavailable
    }

    /// A signed amount, e.g. "+120.00 €".
    static func signedMoney(_ value: Decimal?, _ currency: Currency, locale: Locale) -> String {
        guard let value else { return unavailable }
        return value.formatted(.currency(code: currency.code).sign(strategy: .always(showZero: false)).locale(locale))
    }

    /// `value` is in percentage points (12.5 means 12.5%).
    static func percent(_ value: Decimal?, locale: Locale, signed: Bool = false, digits: Int = 2) -> String {
        guard let value else { return unavailable }
        let style = Decimal.FormatStyle.Percent.percent.locale(locale).precision(.fractionLength(digits))
        return (value / 100).formatted(signed ? style.sign(strategy: .always(includingZero: false)) : style)
    }

    /// Share counts and other plain quantities, without trailing zeros (up to 8 fractional digits).
    static func number(_ value: Decimal?, locale: Locale) -> String {
        guard let value else { return unavailable }
        return value.formatted(.number.locale(locale).precision(.fractionLength(0...8)))
    }

    static func date(_ date: LocalDate, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return date.startOfDay(in: calendar)
            .formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: .gmt))
    }

    static func timestamp(_ date: Date, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
    }

    /// "Prices as of 14:05" style age text, relative to `now`.
    static func age(_ date: Date, now: Date = Date(), locale: Locale) -> String {
        date.formatted(Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide).locale(locale))
    }

    static func month(year: Int, month: Int, locale: Locale) -> String {
        let date = LocalDate(year: year, month: month, day: 1)!.startOfDay(in: utcCalendar)
        return date.formatted(Date.FormatStyle(locale: locale, calendar: utcCalendar, timeZone: .gmt).month(.abbreviated).year())
    }

    static func assetClass(_ value: AssetClass) -> String {
        switch value {
        case .stock: return "Stock"
        case .etf: return "ETF"
        case .bond: return "Bond"
        case .cash: return "Cash"
        }
    }

    static func kind(_ value: TransactionKind) -> String {
        switch value {
        case .buy: return "Buy"
        case .sell: return "Sell"
        case .dividend: return "Dividend"
        case .fee: return "Fee"
        }
    }

    static func frequency(_ value: DividendFrequency) -> String {
        switch value {
        case .annual: return "Annual"
        case .semiAnnual: return "Semi-annual"
        case .quarterly: return "Quarterly"
        case .monthly: return "Monthly"
        case .unknown: return "Unknown"
        }
    }

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .gmt
        return c
    }()
}

/// Parses numbers typed in forms. Accepts the person's locale (e.g. "1.234,5" in Germany) and plain
/// "1234.5", so pasted values work too.
enum DecimalInput {
    static func parse(_ text: String, locale: Locale) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let value = try? Decimal(trimmed, format: .number.locale(locale)) { return value }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
            .flatMap { trimmed.allSatisfy { "0123456789.-+".contains($0) } ? $0 : nil }
    }

    /// The text a form field starts with for an existing value.
    static func text(_ value: Decimal?, locale: Locale) -> String {
        guard let value else { return "" }
        return value.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...10)))
    }
}

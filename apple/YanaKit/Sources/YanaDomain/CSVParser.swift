import Foundation

/// One non-blank CSV record and the 1-based physical line it starts on.
public struct CSVRow: Equatable, Sendable {
    public var line: Int
    public var fields: [String]
}

/// Minimal RFC 4180-style parser ported from the web importer: quoted fields, `""` escapes,
/// and `\n` / `\r\n` / `\r` line endings. Rows whose fields are all blank are dropped.
public enum CSVParser {
    public static func parse(_ text: String) -> [CSVRow] {
        var rows: [CSVRow] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var line = 1
        var rowStart = 1
        let chars = Array(text)
        var i = 0

        func endRow() {
            row.append(field)
            if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                rows.append(CSVRow(line: rowStart, fields: row))
            }
            row = []
            field = ""
        }

        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    if ch.isNewline { line += 1 }
                    field.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == "," {
                row.append(field)
                field = ""
            } else if ch.isNewline {
                // Swift treats "\r\n" as a single Character, so each line ending is seen once.
                endRow()
                line += 1
                rowStart = line
            } else {
                field.append(ch)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            endRow()
        }
        return rows
    }

    public enum Number: Equatable, Sendable {
        case absent
        case value(Decimal)
        case invalid
    }

    /// Ported `parseNum`: blank is absent, the first comma is a decimal separator ("12,5" → 12.5),
    /// and anything that is not a plain decimal number is invalid.
    public static func number(_ raw: String?) -> Number {
        guard let raw else { return .absent }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .absent }
        var text = trimmed
        if let comma = text.firstIndex(of: ",") { text.replaceSubrange(comma...comma, with: ".") }
        guard text.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        else { return .invalid }
        return .value(value)
    }
}

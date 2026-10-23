import Foundation

public enum ValidationField: String, Sendable, Hashable {
    case name, ticker, date, quantity, unitPrice, amount, fee, tax, currency, targets, multiplier
}

public struct ValidationIssue: Equatable, Sendable {
    public var field: ValidationField
    public var message: String
    /// The normalized goal key an issue about one target refers to, so editors can show it on that row.
    public var key: String?

    public init(_ field: ValidationField, _ message: String, key: String? = nil) {
        self.field = field
        self.message = message
        self.key = key
    }
}

/// One or more field errors; forms show each next to its field.
public struct ValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    public var issues: [ValidationIssue]

    public init(_ issues: [ValidationIssue]) { self.issues = issues }

    public func message(for field: ValidationField) -> String? {
        issues.first { $0.field == field }?.message
    }

    public var description: String {
        issues.map { "\($0.field.rawValue): \($0.message)" }.joined(separator: "; ")
    }
}

private func trimmedOrNil(_ s: String?) -> String? {
    guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
    return t
}

// MARK: - Portfolio

public struct PortfolioDraft: Equatable, Sendable {
    public var name: String
    public var baseCurrency: Currency

    public init(name: String, baseCurrency: Currency = .default) {
        self.name = name
        self.baseCurrency = baseCurrency
    }

    /// Returns the draft with a trimmed name, or throws if the name is empty.
    public func validated() throws -> PortfolioDraft {
        guard let name = trimmedOrNil(name) else {
            throw ValidationError([ValidationIssue(.name, "Name is required")])
        }
        return PortfolioDraft(name: name, baseCurrency: baseCurrency)
    }
}

extension Currency {
    /// Parses a user- or file-supplied code, throwing a `.currency` issue when unsupported.
    public static func validated(code: String) throws -> Currency {
        guard let c = Currency(code: code) else {
            let supported = Currency.allCases.map(\.code).joined(separator: ", ")
            throw ValidationError([ValidationIssue(.currency, "Currency must be one of \(supported)")])
        }
        return c
    }
}

// MARK: - Holding

public struct HoldingDraft: Equatable, Sendable {
    public var ticker: String
    public var name: String?
    public var sector: String?
    public var assetClass: AssetClass?
    public var currency: Currency
    /// Contract size for options; `nil` means 1.
    public var multiplier: Decimal?

    public init(ticker: String, name: String? = nil, sector: String? = nil, assetClass: AssetClass? = nil,
                currency: Currency = .default, multiplier: Decimal? = nil) {
        self.ticker = ticker
        self.name = name
        self.sector = sector
        self.assetClass = assetClass
        self.currency = currency
        self.multiplier = multiplier
    }

    static let allowedTickerCharacters = CharacterSet.uppercaseLetters
        .union(.decimalDigits).union(CharacterSet(charactersIn: ".-=^"))

    /// Returns the draft with a normalized ticker, trimmed optional text, and asset class defaulted to stock.
    public func validated() throws -> HoldingDraft {
        let symbol = RecordIdentity.normalizeTicker(ticker)
        if symbol.isEmpty {
            throw ValidationError([ValidationIssue(.ticker, "Ticker is required")])
        }
        if symbol.count > 32 || !symbol.unicodeScalars.allSatisfy(Self.allowedTickerCharacters.contains) {
            throw ValidationError([ValidationIssue(.ticker, "Ticker may only contain letters, digits, '.', '-', '=' and '^'")])
        }
        if let multiplier, multiplier <= 0 {
            throw ValidationError([ValidationIssue(.multiplier, "Multiplier must be greater than 0")])
        }
        return HoldingDraft(ticker: symbol, name: trimmedOrNil(name), sector: trimmedOrNil(sector),
                            assetClass: assetClass ?? .default, currency: currency, multiplier: multiplier)
    }
}

// MARK: - Transaction

public struct TransactionDraft: Equatable, Sendable {
    public var kind: TransactionKind
    public var date: LocalDate?
    public var quantity: Decimal?
    public var unitPrice: Decimal?
    public var amount: Decimal?
    public var fee: Decimal?
    public var tax: Decimal?
    public var currency: Currency
    public var notes: String?

    public init(kind: TransactionKind, date: LocalDate?, quantity: Decimal? = nil, unitPrice: Decimal? = nil,
                amount: Decimal? = nil, fee: Decimal? = nil, tax: Decimal? = nil,
                currency: Currency = .default, notes: String? = nil) {
        self.kind = kind
        self.date = date
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.amount = amount
        self.fee = fee
        self.tax = tax
        self.currency = currency
        self.notes = notes
    }

    /// Checks every rule at once and returns the normalized draft: fee and tax default to 0,
    /// fields that do not apply to the kind are cleared, and notes are trimmed.
    public func validated() throws -> TransactionDraft {
        var issues: [ValidationIssue] = []

        if date == nil { issues.append(ValidationIssue(.date, "Date must be YYYY-MM-DD")) }

        func requirePositive(_ value: Decimal?, _ field: ValidationField, _ label: String, required: String?) {
            if let value {
                if value <= 0 { issues.append(ValidationIssue(field, "\(label) must be greater than 0")) }
            } else if let required {
                issues.append(ValidationIssue(field, required))
            }
        }

        switch kind {
        case .buy, .sell:
            requirePositive(quantity, .quantity, "Shares", required: "Shares are required for buy and sell")
            if kind == .sell, let unitPrice {
                // A sell at 0 records an option that expired worthless.
                if unitPrice < 0 { issues.append(ValidationIssue(.unitPrice, "Price cannot be negative")) }
            } else {
                requirePositive(unitPrice, .unitPrice, "Price", required: "Price is required for buy and sell")
            }
        case .dividend:
            requirePositive(amount, .amount, "Amount", required: "Amount is required for dividends")
            requirePositive(quantity, .quantity, "Shares", required: nil)
        case .fee:
            requirePositive(amount, .amount, "Amount", required: "Amount is required for fees")
        }

        if let fee, fee < 0 { issues.append(ValidationIssue(.fee, "Fee cannot be negative")) }
        if let tax, tax < 0 { issues.append(ValidationIssue(.tax, "Tax cannot be negative")) }

        guard issues.isEmpty else { throw ValidationError(issues) }

        var out = self
        out.fee = fee ?? 0
        out.tax = tax ?? 0
        out.notes = trimmedOrNil(notes)
        switch kind {
        case .buy, .sell: out.amount = nil
        case .dividend: out.unitPrice = nil
        case .fee: out.quantity = nil; out.unitPrice = nil
        }
        return out
    }
}

// MARK: - Goals

public struct GoalTarget: Equatable, Sendable {
    public var key: String
    public var percent: Decimal

    public init(key: String, percent: Decimal) {
        self.key = key
        self.percent = percent
    }
}

/// The complete target list for one goal scope; saving it replaces the scope.
public struct GoalScopeDraft: Equatable, Sendable {
    public static let sumTolerance: Decimal = Decimal(string: "0.5")!

    public var scope: GoalScope
    public var targets: [GoalTarget]

    public init(scope: GoalScope, targets: [GoalTarget]) {
        self.scope = scope
        self.targets = targets
    }

    /// Returns targets with normalized keys. Each must be > 0 and ≤ 100, keys unique, and a non-empty set must
    /// add up to 100 ± 0.5. With `holdingTickers`, holding keys must also be among them (normalized).
    /// Issues about one target carry its normalized key.
    public func validated(holdingTickers: Set<String>? = nil) throws -> GoalScopeDraft {
        let members = holdingTickers.map { Set($0.map { RecordIdentity.normalizeGoalKey($0, scope: .holding) }) }
        var issues: [ValidationIssue] = []
        var seen = Set<String>()
        var normalized: [GoalTarget] = []

        for target in targets {
            let key = RecordIdentity.normalizeGoalKey(target.key, scope: scope)
            if key.isEmpty {
                issues.append(ValidationIssue(.targets, "Every target needs a key"))
                continue
            }
            if scope == .assetClass, AssetClass(rawValue: key) == nil {
                issues.append(ValidationIssue(.targets, "\(key) is not an asset class", key: key))
                continue
            }
            if !seen.insert(key).inserted {
                issues.append(ValidationIssue(.targets, "\(key) appears more than once", key: key))
                continue
            }
            if scope == .holding, let members, !members.contains(key) {
                issues.append(ValidationIssue(.targets, "\(key) is not a holding in this portfolio", key: key))
            }
            if target.percent <= 0 {
                issues.append(ValidationIssue(.targets, "Target for \(key) must be greater than 0", key: key))
            } else if target.percent > 100 {
                issues.append(ValidationIssue(.targets, "Target for \(key) must be at most 100%", key: key))
            }
            normalized.append(GoalTarget(key: key, percent: target.percent))
        }

        if issues.isEmpty, !normalized.isEmpty {
            let sum = normalized.reduce(Decimal(0)) { $0 + $1.percent }
            var diff = sum - 100
            if diff < 0 { diff = -diff }
            if diff > Self.sumTolerance {
                issues.append(ValidationIssue(.targets, "Targets must add up to 100% (currently \(Self.formatPercent(sum))%)"))
            }
        }

        guard issues.isEmpty else { throw ValidationError(issues) }
        return GoalScopeDraft(scope: scope, targets: normalized)
    }

    /// One decimal place, locale-independent, e.g. "90.0".
    static func formatPercent(_ value: Decimal) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 1, .plain)
        let text = NSDecimalNumber(decimal: rounded).description(withLocale: Locale(identifier: "en_US_POSIX"))
        return text.contains(".") ? text : text + ".0"
    }
}

import Foundation

/// Currencies a portfolio, holding, or transaction may use.
public enum Currency: String, Codable, Sendable, CaseIterable, Hashable {
    case eur = "EUR"
    case usd = "USD"
    case rub = "RUB"

    public static let `default`: Currency = .eur

    /// Case-insensitive lookup of an ISO code; `nil` for unsupported codes.
    public init?(code: String) {
        self.init(rawValue: code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }

    public var code: String { rawValue }
}

public enum AssetClass: String, Codable, Sendable, CaseIterable, Hashable {
    case stock
    case etf
    case bond
    case cash

    public static let `default`: AssetClass = .stock
}

public enum TransactionKind: String, Codable, Sendable, CaseIterable, Hashable {
    case buy
    case sell
    case dividend
    case fee

    /// Buy and sell carry `quantity` × `unitPrice`; dividend and fee carry `amount`.
    public var isTrade: Bool { self == .buy || self == .sell }
}

public enum GoalScope: String, Codable, Sendable, CaseIterable, Hashable {
    case holding
    case assetClass = "asset_class"
}

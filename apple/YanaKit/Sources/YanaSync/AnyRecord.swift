import Foundation
import YanaDomain

/// Any one of the four synchronized record types.
public enum AnyRecord: Equatable, Sendable {
    case portfolio(PortfolioRecord)
    case holding(HoldingRecord)
    case transaction(TransactionRecord)
    case goal(GoalRecord)

    public init<R: SyncableRecord>(_ record: R) {
        switch record {
        case let r as PortfolioRecord: self = .portfolio(r)
        case let r as HoldingRecord: self = .holding(r)
        case let r as TransactionRecord: self = .transaction(r)
        case let r as GoalRecord: self = .goal(r)
        default: preconditionFailure("Unknown record type \(R.self)")
        }
    }

    public var key: RecordKey { RecordKey(entity: entity, id: id) }

    public var entity: RecordEntity {
        switch self {
        case .portfolio: return .portfolio
        case .holding: return .holding
        case .transaction: return .transaction
        case .goal: return .goal
        }
    }

    public var id: UUID {
        switch self {
        case .portfolio(let r): return r.id
        case .holding(let r): return r.id
        case .transaction(let r): return r.id
        case .goal(let r): return r.id
        }
    }

    public var version: RecordVersion {
        get {
            switch self {
            case .portfolio(let r): return r.version
            case .holding(let r): return r.version
            case .transaction(let r): return r.version
            case .goal(let r): return r.version
            }
        }
        set {
            switch self {
            case .portfolio(var r): r.version = newValue; self = .portfolio(r)
            case .holding(var r): r.version = newValue; self = .holding(r)
            case .transaction(var r): r.version = newValue; self = .transaction(r)
            case .goal(var r): r.version = newValue; self = .goal(r)
            }
        }
    }

    public var deletedAt: Date? {
        get {
            switch self {
            case .portfolio(let r): return r.deletedAt
            case .holding(let r): return r.deletedAt
            case .transaction(let r): return r.deletedAt
            case .goal(let r): return r.deletedAt
            }
        }
        set {
            switch self {
            case .portfolio(var r): r.deletedAt = newValue; self = .portfolio(r)
            case .holding(var r): r.deletedAt = newValue; self = .holding(r)
            case .transaction(var r): r.deletedAt = newValue; self = .transaction(r)
            case .goal(var r): r.deletedAt = newValue; self = .goal(r)
            }
        }
    }

    public var isDeleted: Bool { deletedAt != nil }

    /// The portfolio this record belongs to (itself for a portfolio).
    public var portfolioID: UUID {
        switch self {
        case .portfolio(let r): return r.id
        case .holding(let r): return r.portfolioID
        case .transaction(let r): return r.portfolioID
        case .goal(let r): return r.portfolioID
        }
    }
}

/// Synchronized entity names; the raw value is the CloudKit record type and the payload `entity`.
public enum RecordEntity: String, Codable, Sendable, CaseIterable, Hashable {
    case portfolio = "Portfolio"
    case holding = "Holding"
    case transaction = "Transaction"
    case goal = "Goal"
}

public struct RecordKey: Hashable, Sendable, CustomStringConvertible {
    public var entity: RecordEntity
    public var id: UUID

    public init(entity: RecordEntity, id: UUID) {
        self.entity = entity
        self.id = id
    }

    public var description: String { "\(entity.rawValue)/\(id.uuidString.lowercased())" }
}

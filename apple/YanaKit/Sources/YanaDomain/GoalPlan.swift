import Foundation

/// Parsing for typed goal targets.
public enum GoalPercent {
    /// A target as typed: `.` or `,` as the decimal separator in any locale, at most two decimals, an optional
    /// trailing `%`, and no grouping. `nil` for empty or anything else, so `12,5` is 12.5 even under `en_US`.
    public static func parse(_ text: String) -> Decimal? {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("%") { trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces) }
        let parts = trimmed.split(omittingEmptySubsequences: false) { $0 == "." || $0 == "," }
        guard parts.count <= 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              parts.contains(where: { !$0.isEmpty }),
              parts.count == 1 || parts[1].count <= 2
        else { return nil }
        let whole = parts[0].isEmpty ? "0" : String(parts[0])
        let fraction = parts.count == 2 && !parts[1].isEmpty ? "." + parts[1] : ""
        return Decimal(string: whole + fraction, locale: Locale(identifier: "en_US_POSIX"))
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

/// Pure helpers for building a goal plan. Values are row targets in percent; `nil` is an empty row.
/// Every helper rounds to 0.1 and settles the rounding residue on the largest affected row so the plan
/// totals exactly 100.
public enum GoalPlan {
    public static func total(_ values: [Decimal?]) -> Decimal {
        values.reduce(Decimal(0)) { $0 + ($1 ?? 0) }
    }

    /// Percentage points still to assign; negative when the plan is over 100%.
    public static func remaining(_ values: [Decimal?]) -> Decimal {
        100 - total(values)
    }

    /// Whether a non-empty plan's total is close enough to 100 to save.
    public static func isTotalValid(_ values: [Decimal?]) -> Bool {
        abs(remaining(values)) <= GoalScopeDraft.sumTolerance
    }

    /// Adds what is left to 100% to one row, or removes the excess, never going below 0.1. Uses the exact
    /// remainder so the plan lands on 100.
    public static func putRemainder(on index: Int, in values: [Decimal?]) -> [Decimal?] {
        guard values.indices.contains(index) else { return values }
        let others = total(values.enumerated().filter { $0.offset != index }.map(\.element))
        var next = values
        next[index] = max(minimumTarget, 100 - others)
        return next
    }

    /// Splits what is left to 100% evenly across empty (or 0) rows.
    public static func splitRemainderAcrossEmpty(_ values: [Decimal?]) -> [Decimal?] {
        let empty = values.indices.filter { (values[$0] ?? 0) == 0 }
        let rest = remaining(values)
        guard !empty.isEmpty, rest > 0 else { return values }
        let each = (rest / Decimal(empty.count)).rounded(scale: 1, mode: .down)
        guard each >= minimumTarget else { return values }
        var next = values
        for i in empty { next[i] = each }
        return settle(next, on: empty)
    }

    /// Scales every filled row proportionally so the plan totals exactly 100.
    public static func scaleTo100(_ values: [Decimal?]) -> [Decimal?] {
        let sum = total(values)
        guard sum > 0 else { return values }
        let filled = values.indices.filter { (values[$0] ?? 0) > 0 }
        var next = values
        for i in filled { next[i] = max(minimumTarget, (values[i]! * 100 / sum).rounded(scale: 1)) }
        return settle(next, on: filled)
    }

    /// One target per entry with a current weight, rounded to 0.1 and totalling exactly 100. Entries too small
    /// to round to 0.1 are left out. Order is kept.
    public static func seed(fromCurrent current: [GoalTarget]) -> [GoalTarget] {
        let kept = current.map { GoalTarget(key: $0.key, percent: $0.percent.rounded(scale: 1)) }.filter { $0.percent > 0 }
        guard !kept.isEmpty else { return [] }
        let settled = settle(kept.map { Optional($0.percent) }, on: Array(kept.indices))
        return kept.enumerated().map { GoalTarget(key: $0.element.key, percent: settled[$0.offset] ?? $0.element.percent) }
    }

    /// The asset-class mix a holding plan implies: holding targets summed by each holding's asset class, in
    /// `AssetClass` order. Targets whose holding is unknown are skipped, so the mix can total less than 100.
    public static func impliedAssetClassMix(holdingTargets: [GoalTarget],
                                            assetClassOf: [String: AssetClass]) -> [GoalTarget] {
        var mix: [AssetClass: Decimal] = [:]
        for target in holdingTargets {
            guard let cls = assetClassOf[RecordIdentity.normalizeGoalKey(target.key, scope: .holding)] else { continue }
            mix[cls, default: 0] += target.percent
        }
        return AssetClass.allCases.compactMap { cls in mix[cls].map { GoalTarget(key: cls.rawValue, percent: $0) } }
    }

    static let minimumTarget = Decimal(string: "0.1", locale: Locale(identifier: "en_US_POSIX"))!

    /// Puts `100 − total` on the largest of `indexes`.
    private static func settle(_ values: [Decimal?], on indexes: [Int]) -> [Decimal?] {
        let residue = remaining(values)
        guard residue != 0, let largest = indexes.max(by: { (values[$0] ?? 0) < (values[$1] ?? 0) }) else { return values }
        var next = values
        next[largest] = (next[largest] ?? 0) + residue
        return next
    }
}

/// How far a current weight is from its target.
public struct GoalDrift: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case onTarget, over, under
    }

    /// A current weight within this many percentage points of the target counts as on target.
    public static let tolerance: Decimal = 1

    public var status: Status
    /// `current − target` in percentage points; positive when overweight.
    public var gap: Decimal

    public init(status: Status, gap: Decimal) {
        self.status = status
        self.gap = gap
    }

    public static func classify(current: Decimal, target: Decimal) -> GoalDrift {
        let gap = current - target
        if abs(gap) <= tolerance { return GoalDrift(status: .onTarget, gap: gap) }
        return GoalDrift(status: gap > 0 ? .over : .under, gap: gap)
    }
}

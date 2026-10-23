import Foundation
import Observation
import YanaDomain

/// One row of a goal draft, as typed.
struct GoalDraftRow: Identifiable, Equatable, Codable {
    var id = UUID()
    /// Ticker or asset-class raw value.
    var key: String
    /// The target as typed; parsed with `GoalPercent.parse`.
    var text: String
}

/// Unsaved edits to one portfolio's goals in one scope.
struct GoalDraft: Equatable, Codable {
    var rows: [GoalDraftRow]
    /// Saved targets (by normalized key) when the draft started, to tell whether the saved plan changed underneath it.
    var baseline: [String: Decimal]
    /// True when the draft came back from a previous launch rather than this session's edits.
    var restored = false

    private enum CodingKeys: String, CodingKey { case rows, baseline }

    /// Whether the rows differ from `targets` (normalized key → percent). A row whose text does not parse
    /// always counts as a difference.
    func differs(from targets: [String: Decimal], scope: GoalScope) -> Bool {
        guard rows.count == targets.count else { return true }
        return rows.contains { row in
            let key = RecordIdentity.normalizeGoalKey(row.key, scope: scope)
            guard let saved = targets[key], let value = GoalPercent.parse(row.text) else { return true }
            return saved != value
        }
    }

    func isDirty(scope: GoalScope) -> Bool { differs(from: baseline, scope: scope) }

    static func baseline(_ goals: [GoalRecord], scope: GoalScope) -> [String: Decimal] {
        Dictionary(goals.filter { $0.scope == scope && !$0.isDeleted }
            .map { (RecordIdentity.normalizeGoalKey($0.key, scope: scope), $0.targetPercent) }, uniquingKeysWith: { $1 })
    }
}

/// Goal drafts per portfolio and scope. Kept in memory and mirrored to `UserDefaults` so they survive relaunch;
/// they are local preferences and never synced.
@MainActor @Observable
final class GoalDraftStore {
    struct Key: Hashable {
        var portfolioID: UUID
        var scope: GoalScope
    }

    private(set) var drafts: [Key: GoalDraft] = [:]
    @ObservationIgnored private let defaults: UserDefaults

    private static let prefix = "goals.draft."

    init(defaults: UserDefaults) {
        self.defaults = defaults
        for (name, value) in defaults.dictionaryRepresentation() where name.hasPrefix(Self.prefix) {
            guard let key = Self.key(fromDefaultsName: name), let data = value as? Data,
                  var draft = try? JSONDecoder().decode(GoalDraft.self, from: data), draft.isDirty(scope: key.scope)
            else { continue }
            draft.restored = true
            drafts[key] = draft
        }
    }

    func draft(_ portfolioID: UUID, _ scope: GoalScope) -> GoalDraft? {
        drafts[Key(portfolioID: portfolioID, scope: scope)]
    }

    /// Stores a draft, or removes it with `nil`. Only dirty drafts are written to `UserDefaults`; a clean one stays in
    /// memory so rows keep their order and identity while the person types.
    func set(_ draft: GoalDraft?, _ portfolioID: UUID, _ scope: GoalScope) {
        let key = Key(portfolioID: portfolioID, scope: scope)
        let name = Self.defaultsName(key)
        drafts[key] = draft
        if let draft, draft.isDirty(scope: scope), let data = try? JSONEncoder().encode(draft) {
            defaults.set(data, forKey: name)
        } else {
            defaults.removeObject(forKey: name)
        }
    }

    /// Drops drafts whose portfolio no longer exists.
    func removeDrafts(keeping portfolioIDs: Set<UUID>) {
        for key in drafts.keys where !portfolioIDs.contains(key.portfolioID) {
            set(nil, key.portfolioID, key.scope)
        }
    }

    private static func defaultsName(_ key: Key) -> String {
        "\(prefix)\(key.portfolioID.uuidString).\(key.scope.rawValue)"
    }

    private static func key(fromDefaultsName name: String) -> Key? {
        let parts = name.dropFirst(prefix.count).split(separator: ".", maxSplits: 1)
        guard parts.count == 2, let id = UUID(uuidString: String(parts[0])),
              let scope = GoalScope(rawValue: String(parts[1])) else { return nil }
        return Key(portfolioID: id, scope: scope)
    }
}

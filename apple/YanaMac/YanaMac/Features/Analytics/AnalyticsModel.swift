import Foundation
import Observation
import YanaDomain

/// One allocation slice with what VoiceOver announces for it.
struct AllocationPoint: Identifiable, Equatable {
    var key: String
    var label: String
    var value: Decimal
    var percent: Decimal
    /// Label, value, and percentage in one phrase, e.g. "ETF: €900.00, 62.5%".
    var accessibilityLabel: String

    var id: String { key }
}

enum AllocationModel {
    static func points(_ valuation: PortfolioValuation?, grouping: AllocationGrouping, locale: Locale) -> [AllocationPoint] {
        guard let valuation else { return [] }
        return AllocationCalculator.slices(valuation, by: grouping).map { slice in
            let label = grouping == .assetClass ? AssetClass(rawValue: slice.key).map(Fmt.assetClass) ?? slice.key : slice.key
            return AllocationPoint(key: slice.key, label: label, value: slice.value, percent: slice.percent,
                                   accessibilityLabel: "\(label): \(Fmt.money(slice.value, valuation.baseCurrency, locale: locale)), "
                                       + Fmt.percent(slice.percent, locale: locale, digits: 1))
        }
    }

    static func groupingTitle(_ grouping: AllocationGrouping) -> String {
        switch grouping {
        case .holding: return "Holding"
        case .sector: return "Sector"
        case .assetClass: return "Asset class"
        }
    }
}

/// Date ranges for the value-history chart.
enum HistoryRange: String, CaseIterable, Identifiable {
    case oneMonth = "1M", threeMonths = "3M", sixMonths = "6M", oneYear = "1Y", all = "All"

    var id: String { rawValue }

    private var months: Int? {
        switch self {
        case .oneMonth: return 1
        case .threeMonths: return 3
        case .sixMonths: return 6
        case .oneYear: return 12
        case .all: return nil
        }
    }

    /// The first day included, or `nil` for all history.
    func start(today: LocalDate, calendar: Calendar) -> LocalDate? {
        months.map { today.adding(months: -$0, calendar: calendar) }
    }

    func filter(_ snapshots: [ValueSnapshot], today: LocalDate, calendar: Calendar) -> [ValueSnapshot] {
        guard let start = start(today: today, calendar: calendar) else { return snapshots }
        return snapshots.filter { $0.day >= start && $0.day <= today }
    }
}

/// Editing one goal scope. Saving replaces the scope's targets; errors are shown as a single message.
@MainActor @Observable
final class GoalsEditorModel {
    struct Row: Identifiable, Equatable {
        var id = UUID()
        var key: String
        var percent: String
    }

    var scope: GoalScope {
        didSet { if oldValue != scope { load() } }
    }
    var rows: [Row] = []
    private(set) var error: String?

    private let model: AppModel
    private let locale: Locale

    init(model: AppModel, scope: GoalScope = .assetClass, locale: Locale = .current) {
        self.model = model
        self.scope = scope
        self.locale = locale
        load()
    }

    /// Rows from the stored goals of the current scope.
    func load() {
        rows = model.goals.filter { $0.scope == scope && !$0.isDeleted }.sorted { $0.key < $1.key }
            .map { Row(key: $0.key, percent: DecimalInput.text($0.targetPercent, locale: locale)) }
        error = nil
    }

    func addRow() {
        let used = Set(rows.map(\.key))
        let suggestion: String
        switch scope {
        case .assetClass: suggestion = AssetClass.allCases.map(\.rawValue).first { !used.contains($0) } ?? ""
        case .holding: suggestion = model.holdings.map(\.ticker).first { !used.contains($0) } ?? ""
        }
        rows.append(Row(key: suggestion, percent: ""))
    }

    func remove(_ id: Row.ID) {
        rows.removeAll { $0.id == id }
    }

    /// Sum of the targets that parse, for the running total under the editor.
    var total: Decimal {
        rows.compactMap { DecimalInput.parse($0.percent, locale: locale) }.reduce(0, +)
    }

    func save() async -> Bool {
        error = nil
        var targets: [GoalTarget] = []
        for row in rows {
            guard let percent = DecimalInput.parse(row.percent, locale: locale) else {
                error = "Enter a target percentage for \(row.key.isEmpty ? "every row" : row.key)."
                return false
            }
            targets.append(GoalTarget(key: row.key, percent: percent))
        }
        do {
            try await model.saveGoals(GoalScopeDraft(scope: scope, targets: targets))
            load()
            return true
        } catch let e as ValidationError {
            error = e.issues.map(\.message).joined(separator: "\n")
        } catch {
            self.error = error.localizedDescription
        }
        return false
    }
}

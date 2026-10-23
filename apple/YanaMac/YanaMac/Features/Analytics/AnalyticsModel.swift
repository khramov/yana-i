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

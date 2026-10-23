import SwiftUI
import YanaDomain

/// Searchable list of holdings (or asset classes) to add to a plan. Held positions come first; holdings with no
/// shares follow under "Not held". Arrow keys move the highlight and Return picks it.
struct GoalPickerPopover: View {
    let scope: GoalScope
    let options: (String) -> [GoalOption]
    let onPick: (String) -> Void
    /// Opens the add-holding sheet; holding scope only.
    var onAddHolding: (() -> Void)?

    @Environment(\.locale) private var locale
    @State private var search = ""
    @State private var highlighted: String?
    @FocusState private var searchFocused: Bool

    private var matches: [GoalOption] { options(search) }
    private var held: [GoalOption] { matches.filter { scope == .assetClass || $0.isHeld } }
    private var notHeld: [GoalOption] { scope == .assetClass ? [] : matches.filter { !$0.isHeld } }
    /// In display order, for keyboard navigation.
    private var ordered: [GoalOption] { held + notHeld }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(scope == .holding ? "Search ticker or name" : "Search asset classes", text: $search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityIdentifier("goalPickerSearch")
                .onSubmit { pick(highlighted ?? ordered.first?.key) }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if ordered.isEmpty {
                        Text(scope == .holding ? "No holdings match" : "No asset classes match")
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }
                    section(scope == .holding && !notHeld.isEmpty ? "Held" : nil, held)
                    section(notHeld.isEmpty ? nil : "Not held", notHeld)
                }
            }
            .frame(height: 240)
            if let onAddHolding {
                Divider()
                Button("Add a New Holding…", action: onAddHolding)
                    .buttonStyle(.link)
            }
        }
        .padding(12)
        .frame(width: 360)
        .onAppear { searchFocused = true }
        .onChange(of: search) { highlighted = nil }
    }

    @ViewBuilder
    private func section(_ title: String?, _ items: [GoalOption]) -> some View {
        if !items.isEmpty {
            if let title {
                Text(title).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.top, 4)
            }
            ForEach(items) { option in
                Button { pick(option.key) } label: { row(option) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("goalOption-\(option.key)")
            }
        }
    }

    private func row(_ option: GoalOption) -> some View {
        HStack(spacing: 8) {
            Text(option.label).fontWeight(.medium)
            if let name = option.name {
                Text(name).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Text(option.currentPercent.map { Fmt.percent($0, locale: locale, digits: 1) } ?? Fmt.unavailable)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(highlighted == option.key ? Color.accentColor.opacity(0.2) : .clear,
                    in: RoundedRectangle(cornerRadius: 5))
        .accessibilityElement(children: .combine)
    }

    private func move(_ step: Int) {
        let keys = ordered.map(\.key)
        guard !keys.isEmpty else { return }
        let index = highlighted.flatMap { keys.firstIndex(of: $0) }.map { $0 + step } ?? (step > 0 ? 0 : keys.count - 1)
        highlighted = keys[min(max(index, 0), keys.count - 1)]
    }

    private func pick(_ key: String?) {
        guard let key else { return }
        search = ""
        onPick(key)
    }
}

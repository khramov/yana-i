import SwiftUI
import YanaDomain

struct GoalsView: View {
    let model: AppModel
    @Environment(\.locale) private var locale
    @State private var workspace: GoalsWorkspaceModel?

    var body: some View {
        Group {
            if let workspace { GoalsWorkspaceView(model: model, workspace: workspace) } else { ProgressView() }
        }
        .task { if workspace == nil { workspace = GoalsWorkspaceModel(model: model, locale: locale) } }
    }
}

private struct GoalsWorkspaceView: View {
    let model: AppModel
    @Bindable var workspace: GoalsWorkspaceModel
    @Environment(\.locale) private var locale
    @Environment(\.undoManager) private var undoManager
    @FocusState private var focusedRow: UUID?
    @State private var isPickerShown = false
    @State private var replacingRow: UUID?
    @State private var confirmingClear = false
    @State private var pendingReplacement: Replacement?
    @State private var notInPlanExpanded: Bool?

    /// A helper that replaces a non-empty draft, waiting for confirmation.
    private enum Replacement: String, Identifiable {
        case current, implied
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                scopePicker
                notices
                if workspace.scope == .holding && !workspace.hasHoldings {
                    noHoldings
                } else {
                    impliedMix
                    if let summary = workspace.summary {
                        Text(summary).foregroundStyle(.secondary).accessibilityIdentifier("goalsSummary")
                    }
                    toolbar
                    if workspace.rows.isEmpty { emptyPlan } else { planRows }
                    notInPlan
                }
                recommendations
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .onChange(of: workspace.focusRequest) { _, id in
            guard let id else { return }
            focusedRow = id
            workspace.focusRequest = nil
        }
        .onChange(of: model.selectedPortfolioID) { replacingRow = nil }
        .confirmationDialog(workspace.clearConfirmationTitle, isPresented: $confirmingClear) {
            Button("Clear Targets", role: .destructive) { Task { await workspace.save() } }
        } message: {
            Text("The saved plan for this scope is removed. Anything not in a plan counts as 0%.")
        }
        .confirmationDialog("Replace your draft?", isPresented: Binding(
            get: { pendingReplacement != nil }, set: { if !$0 { pendingReplacement = nil } }), presenting: pendingReplacement
        ) { replacement in
            Button("Replace Draft") { apply(replacement) }
        } message: { replacement in
            Text(replacement == .current
                 ? "Your draft will be replaced with one target per open position at today's weight."
                 : "Your draft will be replaced with the asset-class mix implied by your holding plan.")
        }
    }

    // MARK: - Scope and notices

    private var scopePicker: some View {
        Picker("Scope", selection: $workspace.scope) {
            ForEach([GoalScope.holding, .assetClass], id: \.self) { scope in
                let title = scope == .holding ? "Holdings" : "Asset classes"
                let dirty = workspace.isDirty(scope)
                Text("\(title) · \(workspace.savedCountText(scope))\(dirty ? " •" : "")")
                    .accessibilityLabel("\(title), \(workspace.savedCountText(scope))\(dirty ? ", unsaved changes" : "")")
                    .tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("goalsScope")
    }

    @ViewBuilder
    private var notices: some View {
        if workspace.isRestored || workspace.savedPlanChanged {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                Text((workspace.isRestored ? "Restored unsaved changes." : "You have unsaved changes.")
                     + (workspace.savedPlanChanged ? " The saved plan changed since this draft started." : ""))
                Spacer()
                Button("Discard") { workspace.discard() }
            }
            .padding(10)
            .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("goalsNotice")
        }
    }

    private var noHoldings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add holdings to this portfolio to set holding targets.").foregroundStyle(.secondary)
            Button("Add Holding…") { model.sheet = .addHolding }
        }
    }

    @ViewBuilder
    private var impliedMix: some View {
        if let text = workspace.impliedMixText {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Your holding plan implies \(text)")
                    Spacer()
                    Button("Use Implied Mix") { request(.implied) }
                }
                ForEach(workspace.planDisagreements, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            if workspace.pickerOptions().isEmpty {
                Text(workspace.scope == .holding ? "Every holding is in your plan." : "Every asset class is in your plan.")
                    .foregroundStyle(.secondary)
            } else {
                Button(workspace.scope == .holding ? "Add Holding…" : "Add Asset Class…") { isPickerShown = true }
                    .accessibilityIdentifier("addGoalTarget")
                    .popover(isPresented: $isPickerShown, arrowEdge: .bottom) {
                        picker { key in
                            isPickerShown = false
                            workspace.add(key)
                        }
                    }
            }
            Spacer()
            if workspace.canSplitRemainder {
                Button("Split Remainder Across Empty Rows") { workspace.splitRemainder() }
            }
            if workspace.canScale {
                Button("Scale to 100%") { workspace.scaleTo100() }
            }
            if !workspace.rows.isEmpty && (workspace.canStartFromCurrent || workspace.impliedMix != nil) {
                Menu("More") {
                    if workspace.canStartFromCurrent {
                        Button("Start from Current Allocation…") { request(.current) }
                    }
                    if workspace.impliedMix != nil {
                        Button("Use Implied Mix…") { request(.implied) }
                    }
                }
                .fixedSize()
            }
        }
    }

    private func picker(onPick: @escaping (String) -> Void) -> some View {
        GoalPickerPopover(scope: workspace.scope, options: { workspace.pickerOptions(search: $0) }, onPick: onPick,
                          onAddHolding: workspace.scope == .holding ? {
                              isPickerShown = false
                              replacingRow = nil
                              model.sheet = .addHolding
                          } : nil)
    }

    private func request(_ replacement: Replacement) {
        if workspace.replacingNeedsConfirmation { pendingReplacement = replacement } else { apply(replacement) }
    }

    private func apply(_ replacement: Replacement) {
        switch replacement {
        case .current: workspace.startFromCurrentAllocation()
        case .implied: workspace.useImpliedMix()
        }
    }

    // MARK: - Rows

    private var emptyPlan: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(workspace.saveMode == .clear
                 ? "Every target is removed from this draft. Save to clear the plan, or discard to keep it."
                 : "No \(workspace.scope == .holding ? "holding" : "asset-class") targets yet.")
                .foregroundStyle(.secondary)
            if workspace.canStartFromCurrent {
                Button("Start from Current Allocation") { workspace.startFromCurrentAllocation() }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4])))
    }

    private var planRows: some View {
        let states = workspace.rowStates
        let scaleMax = states.reduce(Decimal(1)) { max($0, $1.currentPercent ?? 0, $1.value ?? 0) }
        return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            ForEach(states) { row in
                GridRow {
                    identity(row)
                    progress(row, scaleMax: scaleMax)
                    targetField(row)
                    gap(row).gridColumnAlignment(.leading)
                    actions(row)
                }
                if let message = row.message {
                    GridRow {
                        Text(message).font(.callout).foregroundStyle(.red).gridCellColumns(5)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("goalRows")
    }

    private func identity(_ row: GoalRowState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(row.label).fontWeight(.medium)
                if let name = row.name { Text(name).foregroundStyle(.secondary).lineLimit(1) }
            }
            if row.problem == .unavailable {
                Text("No longer in this portfolio").font(.caption).foregroundStyle(.orange)
            } else if workspace.scope == .holding && !row.isHeld {
                Text("Not held").font(.caption).foregroundStyle(.secondary)
            }
            if let implied = row.impliedPercent {
                Text("Holding plan implies \(workspace.pct(implied))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 160, alignment: .leading)
    }

    private func progress(_ row: GoalRowState, scaleMax: Decimal) -> some View {
        HStack(spacing: 6) {
            Text(row.currentPercent.map { Fmt.percent($0, locale: locale, digits: 1) } ?? Fmt.unavailable)
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
            GoalProgressBar(current: row.currentPercent, target: row.drift == nil ? nil : row.value, scaleMax: scaleMax)
                .frame(width: 140, height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.currentPercent.map { current in
            "\(row.label): current \(Fmt.percent(current, locale: locale, digits: 1))"
                + (row.drift == nil ? "" : ", target \(workspace.pct(row.value ?? 0))")
        } ?? "\(row.label): progress unavailable")
    }

    private func targetField(_ row: GoalRowState) -> some View {
        HStack(spacing: 4) {
            TextField("Target", text: Binding(get: { row.text }, set: { workspace.setText($0, for: row.id) }))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 70)
                .focused($focusedRow, equals: row.id)
                .accessibilityLabel("Target for \(row.label)")
                .accessibilityHint(row.message ?? "")
                .accessibilityIdentifier("goalTarget-\(row.key)")
            Text("%").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func gap(_ row: GoalRowState) -> some View {
        if let drift = row.drift {
            let points = workspace.points(abs(drift.gap))
            let value = row.gapValue.map { " · " + workspace.money($0) } ?? ""
            switch drift.status {
            case .onTarget: Text("On target").foregroundStyle(.green)
            case .under: Text("Under \(points)\(value)").foregroundStyle(.blue).monospacedDigit()
            case .over: Text("Over \(points)\(value)").foregroundStyle(.orange).monospacedDigit()
            }
        } else {
            Text(Fmt.unavailable).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func actions(_ row: GoalRowState) -> some View {
        HStack(spacing: 6) {
            if row.problem == .unavailable {
                Button("Replace With…") { replacingRow = row.id }
                    .disabled(workspace.pickerOptions().isEmpty)
                    .popover(isPresented: Binding(get: { replacingRow == row.id },
                                                  set: { if !$0 { replacingRow = nil } }), arrowEdge: .bottom) {
                        GoalPickerPopover(scope: .holding, options: { workspace.pickerOptions(search: $0) }) { key in
                            replacingRow = nil
                            workspace.replace(row.id, with: key)
                        }
                    }
                Button("Remove") { remove(row) }
                    .accessibilityLabel("Remove \(row.label) from plan")
            } else {
                if workspace.canPutRemainder {
                    Button("Put Remainder Here") { workspace.putRemainder(on: row.id) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .accessibilityLabel("Put remainder on \(row.label)")
                }
                Button { remove(row) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(row.label) from plan")
                    .help("Remove \(row.label) from plan")
            }
        }
    }

    private func remove(_ row: GoalRowState) {
        workspace.remove(row.id)
        let workspace = workspace
        undoManager?.registerUndo(withTarget: workspace) { target in
            MainActor.assumeIsolated { target.undoRemove() }
        }
        undoManager?.setActionName("Remove \(row.label)")
    }

    // MARK: - Not in plan

    @ViewBuilder
    private var notInPlan: some View {
        let entries = workspace.notInPlan
        if !entries.isEmpty {
            DisclosureGroup(isExpanded: Binding(get: { notInPlanExpanded ?? !workspace.notInPlanStartsCollapsed },
                                                set: { notInPlanExpanded = $0 })) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    ForEach(entries) { option in
                        GridRow {
                            Text(option.label).fontWeight(.medium)
                            Text(option.name ?? "").foregroundStyle(.secondary).lineLimit(1)
                            Text(option.currentPercent.map { Fmt.percent($0, locale: locale, digits: 1) } ?? Fmt.unavailable)
                                .monospacedDigit().foregroundStyle(.secondary)
                            Button("Add") { workspace.add(option.key) }
                                .accessibilityLabel("Add \(option.label) to plan")
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("Not in plan — counted as 0% (\(entries.count))").fontWeight(.medium)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("notInPlan")
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text(workspace.totalText).monospacedDigit().fontWeight(.medium).accessibilityIdentifier("goalsTotal")
            if workspace.isDirty {
                Text("Unsaved changes").foregroundStyle(.secondary)
            } else if let savedAt = workspace.savedAt {
                Text("Saved \(savedAt.formatted(date: .omitted, time: .shortened))").foregroundStyle(.green)
            }
            if let error = workspace.footerError {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("goalsError")
            }
            Spacer()
            if let removed = workspace.lastRemoved {
                Text("Removed \(removed.row.key)")
                Button("Undo") { workspace.undoRemove() }
            }
            if let reason = workspace.saveBlockReason, workspace.isDirty {
                Text(reason).foregroundStyle(.secondary).accessibilityIdentifier("goalsSaveReason")
            }
            if workspace.isDirty {
                Button("Discard") { workspace.discard() }
            }
            if workspace.saveMode == .clear {
                Button("Clear Targets", role: .destructive) { confirmingClear = true }
                    .disabled(!workspace.canSave)
                    .keyboardShortcut("s")
                    .accessibilityIdentifier("saveGoals")
            } else {
                Button("Save Targets") { Task { await workspace.save() } }
                    .disabled(!workspace.canSave)
                    .keyboardShortcut("s")
                    .accessibilityIdentifier("saveGoals")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Recommendations

    private var recommendations: some View {
        let rows = workspace.recommendations
        let base = workspace.baseCurrency
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("What to buy now").font(.headline)
                if workspace.isDirty {
                    Text("Based on your saved plan").font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.top, 8)
            if rows.allSatisfy({ $0.targetPercent == nil }) {
                Text("Save targets to see how far each position is from its target.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
                    GridRow {
                        Text("Key"); Text("Current"); Text("Target"); Text("Drift"); Text("Buy"); Text("Shares")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(rows, id: \.key) { r in
                        GridRow {
                            Text(workspace.scope == .assetClass ? AssetClass(rawValue: r.key).map(Fmt.assetClass) ?? r.key : r.key)
                                .fontWeight(.medium)
                            Text(Fmt.percent(r.currentPercent, locale: locale, digits: 1)).monospacedDigit()
                            Text(Fmt.percent(r.targetPercent, locale: locale, digits: 1)).monospacedDigit()
                            Text(Fmt.percent(r.driftPercent, locale: locale, signed: true, digits: 1)).monospacedDigit()
                            Text(Fmt.money(r.buyAmount, base, locale: locale)).monospacedDigit()
                            Text(r.buyShares.map { Fmt.number($0.rounded(scale: 4), locale: locale) } ?? "").monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .accessibilityIdentifier("recommendations")
            }
        }
    }
}

/// Current weight as a filled bar with a marker at the target, both on a shared scale.
struct GoalProgressBar: View {
    let current: Decimal?
    let target: Decimal?
    let scaleMax: Decimal

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let scale = max(scaleMax, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 6)
                if let current {
                    Capsule().fill(Color.accentColor.opacity(0.6))
                        .frame(width: width * fraction(min(current, scale), of: scale), height: 6)
                }
                if let target {
                    Rectangle().fill(.primary)
                        .frame(width: 2, height: geo.size.height)
                        .offset(x: width * fraction(target, of: scale) - 1)
                }
            }
            .frame(height: geo.size.height)
        }
    }

    private func fraction(_ value: Decimal, of scale: Decimal) -> CGFloat {
        CGFloat(NSDecimalNumber(decimal: value / scale).doubleValue)
    }
}

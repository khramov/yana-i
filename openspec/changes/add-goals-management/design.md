# Design

## Context

Today the goals editor lives inside `AnalyticsView` as a private `GoalsSection` backed by `GoalsEditorModel` (`Features/Analytics/AnalyticsModel.swift`):

- rows hold a free-text ticker or an asset-class picker, plus a percent string parsed with the locale-aware `DecimalInput`;
- "Save Goals" calls `AppModel.saveGoals(_:)`, which goes through `PortfolioRepository.saveGoals(_:for:)` and then `GoalScopeDraft.validated()`;
- validation enforces positive targets, unique normalized keys, and 100 ± 0.5, and reports problems as `ValidationIssue(field: .targets, message:)` with no row identity;
- the repository upserts goal records under derived IDs (`RecordIdentity.goalID`) and tombstones dropped keys, and sync carries them to other Macs;
- `RebalanceCalculator.rows` produces the recommendations shown under the editor;
- deleting a holding does not touch its goals, and nothing checks that a holding goal refers to an existing holding.

See `proposal.md` for motivation and `specs/` for the behavior contract.

## Goals / Non-Goals

**Goals:**

- A dedicated Goals section that follows the app's existing pattern: one folder per sidebar section, a testable `@Observable` model, and views that read from `AppModel`.
- Pure, unit-tested plan logic in `YanaDomain`, so the rules live in one place and the view model stays thin.
- Drafts that survive anything short of an explicit Discard, stored locally only.
- No change to the record shapes, sync payloads, or CloudKit schema.

**Non-Goals:**

- Changing the web app on `main`. The web version is parked on `web-goals-management`.
- Changing how recommendations are calculated, or the drift format in the recommendations table.
- Deleting or migrating goals for missing holdings automatically.
- Menu-bar commands for the Goals helpers beyond ⌘S and ⌘Z.

## Decisions

### A `goals` sidebar section; Analytics hands off

Add `AppSection.goals` after `.analytics`. Its title is "Goals" and its symbol is `target`. `SectionView` routes it to `GoalsView`. `AppModel.section` already persists its raw value, so relaunch restores Goals with no extra work.

The selected scope is stored in `AppModel` as `goalScope: GoalScope`, persisted in `UserDefaults` under `selection.goalScope`. Analytics then hands off with `model.goalScope = …; model.section = .goals`.

`AnalyticsView` drops `GoalsSection` and `GoalsEditorModel`. Its allocation header gains an "Edit Goals" button for the holding and asset-class groupings.

Keeping goals inside Analytics behind a disclosure was rejected: it keeps planning hidden and tied to the chart's grouping.

### Plan logic in `YanaDomain` (`GoalPlan.swift`)

Pure `Decimal` functions, so rounding is exact and testable without the app:

- **`GoalPercent.parse(_:)`**:
  - trims the text and an optional trailing `%`;
  - accepts exactly one `.` or `,` as the decimal separator in any locale, with at most two decimals and no grouping;
  - returns `nil` for anything else.

  This replaces `DecimalInput` for target fields. `DecimalInput` reads `12,5` as 125 under `en_US`.
- **`GoalPlan.remaining(_:)`**: what is left to 100.
- **The four helpers**: `putRemainder(on:)`, `splitRemainderAcrossEmpty`, `scaleTo100`, and `seed(fromCurrent:)`.
  - Each rounds to 0.1 and settles the leftover on the largest affected row, so the result is exactly 100.
  - "Put remainder" uses the exact remainder and never goes below 0.1.
- **`GoalDrift.classify(current:target:)`**: returns `.onTarget`, `.over`, or `.under` with the gap in points. `GoalDrift.tolerance` is 1.
- **`GoalPlan.impliedAssetClassMix(holdingTargets:assetClassOf:)`**: sums holding targets by asset class and skips keys with no known holding.

### Row-level validation and membership

`ValidationIssue` gains an optional `key: String?`. The existing initializer is kept, so other drafts are unaffected.

`GoalScopeDraft.validated(holdingTickers: Set<String>? = nil)`:

- attaches the normalized key to every per-target issue;
- adds an upper bound (`percent > 100` is an issue);
- in the holding scope, rejects keys missing from `holdingTickers` when the set is given;
- checks the total only when every row is valid, as today.

`PortfolioRepository.saveGoals(_:for:)` passes the portfolio's live holding tickers. Validation still runs before any edit is built, so a rejected save commits nothing.

`GoalsWorkspaceModel` maps keyed issues to rows and other issues to the footer.

Keeping membership out of the domain and checking it only in the view model was rejected: the repository is the write boundary, and future callers would skip the check.

### Drafts: in memory, mirrored to `UserDefaults`

A `GoalDraftStore` owned by `AppModel` keeps drafts keyed by `(portfolioID, scope)`. Each draft holds its rows (`id`, `key`, `text`), the saved targets it started from (the baseline), and a `restored` flag. Every edit writes the draft as JSON to `UserDefaults` under `goals.draft.<portfolioID>.<scope>`. A draft that matches its baseline again is removed.

On first access after launch, a stored draft that differs from its baseline comes back with `restored = true`.

Like the window's other selection state, drafts are local preferences and are never synced. `AppModel.reloadAll()` drops drafts whose portfolio no longer exists.

The workspace derives the rest:

- a draft with no edits follows the saved goals, so changes arriving through sync show up;
- a draft is dirty when its parsed rows differ from its baseline;
- a dirty draft whose baseline differs from the current saved goals gets the "saved plan changed" notice.

Saving calls `AppModel.saveGoals(_:for:)` with the draft's own portfolio ID, not the selected one, so a draft can never land in another portfolio. If the portfolio is gone, the repository's `notFound` error removes the draft.

Intercepting quit with a Save/Discard prompt was rejected. Persisting drafts gives the same protection without blocking quit, and it matches how the app restores the rest of the person's place.

### `GoalsWorkspaceModel` and views (`Features/Goals`)

`GoalsWorkspaceModel` (`@MainActor @Observable`) is created by `GoalsView` and reads from `AppModel`. It exposes:

- rows with their identity, current weight, progress, and incomplete or unavailable state;
- picker options;
- the "Not in plan" entries;
- total, remaining, the save state (enabled, reason, or clear), and the summary;
- the implied mix and disagreement warnings;
- actions: add, remove, undo, replace, the helpers, discard, and save.

Current weights come from `AllocationCalculator.slices(model.valuation, by:)`. Holdings with a positive quantity count as held, so a held position without a price still counts as held. Rows keep their order while editing and are sorted by largest absolute gap when the draft is created from saved goals.

Views:

- **Scope picker**: a segmented `Picker` whose labels carry the count or "Not set" and an unsaved dot with an accessibility label.
- **Rows**: a `Grid` showing identity (ticker, name, "Not held" or "No longer in this portfolio"), a current-vs-target bar drawn with a small `Canvas`, a trailing `%` target `TextField` labelled "Target for VOO", the gap text, and row actions ("Put Remainder Here", remove).
  - `@FocusState` keyed by row ID moves focus to a new row.
  - Row errors sit under the row and are attached with `.accessibilityHint`.
- **Picker**: an "Add Holding" button opens a popover with a search field and a `List` in Held and Not held sections. Return picks the highlighted entry. "Add a New Holding…" sets `model.sheet = .addHolding`. "Replace With…" opens the same popover in replace mode.
- **Not in plan**: a `DisclosureGroup`, collapsed when it has more than five entries.
- **Footer**: the total and remaining amount, unsaved state, the save reason, and Discard and Save (⌘S via `.keyboardShortcut("s")`). Clearing goes through `.confirmationDialog`.
- **Undo**: removing a row registers an action with the window's `UndoManager` (⌘Z), and the footer shows "Removed VOO · Undo" until the next edit or save.
- **Recommendations**: the existing recommendations grid moves here unchanged. It gets the "Based on your saved plan" note while the draft is dirty.

### Testing

- **YanaKit**: tests for `GoalPercent`, the helpers (exact 100.0), drift classification, the implied mix, and validation (keys on issues, the upper bound, membership).
- **YanaMac** `PortfolioRepositoryTests`:
  - membership rejection leaves the stored goals unchanged;
  - a goal for a deleted holding survives.
- **YanaMac** `ViewModelTests`, replacing `goalSaveErrorsAndSuccess`:
  - adding a row and excluding it from the picker;
  - incomplete rows and save reasons;
  - the helpers, undo, and clear;
  - drafts across portfolio switches;
  - restore through a fresh `AppModel` with the same defaults;
  - the sync-changed notice;
  - replacing an unavailable row;
  - mapping row issues.
- **YanaMac** `WorkspaceUITests`: open Goals, add a holding from the picker, type a target, and save.

## Risks / Trade-offs

- [Reading "not in plan = 0%" as advice to sell] → The heading states the meaning, and recommendations never suggest sells.
- [Stricter validation rejects plans a sync peer still accepts] → Goals for missing holdings are never deleted; they show as unavailable and only block the next save of that scope.
- [Stale drafts in `UserDefaults`] → Drafts are removed when they match their baseline, on save or discard, and when their portfolio disappears.
- [`UndoManager` and model state drift apart] → Undo only reinserts the removed row; any other edit or save clears the undo stack for that scope.
- [The popover picker on large portfolios] → Search filters as you type, and the list is lazy.

## Migration Plan

1. Ship the domain helpers and validation changes with their tests; the existing editor keeps working.
2. Add the repository membership check, the Goals section, the draft store, and the workspace.
3. Remove the Analytics editor and add "Edit Goals".
4. Verify with package tests, app tests in Debug and Release, the UI test, and a keyboard and VoiceOver pass.

Roll back by restoring the Analytics editor. Stored goals and sync payloads are unchanged, and stored drafts are ignored by older builds.

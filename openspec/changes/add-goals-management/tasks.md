# Tasks

Package tests run with `cd apple/YanaKit && ./test.sh`. App tests run with `cd apple/YanaMac && xcodebuild test -scheme YanaMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.

## 1. Domain rules (YanaKit)

- [x] 1.1 Add `GoalPlan.swift` to `YanaDomain` with:
  - `GoalPercent.parse`: `.` or `,` as the decimal separator, up to two decimals, optional `%`, no grouping;
  - `GoalPlan.remaining`, `putRemainder(on:)`, `splitRemainderAcrossEmpty`, `scaleTo100`, and `seed(fromCurrent:)`;
  - `GoalDrift.classify` with `tolerance = 1`;
  - `GoalPlan.impliedAssetClassMix`.

  Verify with `./test.sh --filter GoalPlanTests`: comma and dot parsing, rejection of grouping and of 3 decimals, every helper landing on exactly 100.0, the 0.1 floor, the drift labels at ±1 pt, and the implied mix skipping unknown holdings.
- [x] 1.2 Give `ValidationIssue` an optional `key`, and let `GoalScopeDraft.validated(holdingTickers:)` attach normalized keys to per-target issues, reject percentages above 100, and reject holding keys missing from `holdingTickers` when it is given. Verify that `./test.sh --filter GoalValidationTests` covers keys on issues, the upper bound, membership, and normalized duplicates, and that the existing goal tests still pass.

## 2. Persistence and app model (YanaMac)

- [x] 2.1 Make `PortfolioRepository.saveGoals(_:for:)` validate against the portfolio's live holding tickers. Verify in `PortfolioRepositoryTests` that a target for another portfolio's holding is rejected and leaves the stored goals unchanged, that `vti`/`VTI` is rejected, and that a goal whose holding was deleted stays stored.
- [x] 2.2 Add `AppSection.goals` (title "Goals", symbol `target`) after Analytics, a persisted `AppModel.goalScope`, and `AppModel.saveGoals(_:for:)` bound to an explicit portfolio ID. Verify with a view-model test that the section and scope are restored by a fresh `AppModel` using the same defaults.
- [x] 2.3 Add `GoalDraftStore`, owned by `AppModel`:
  - drafts per `(portfolioID, scope)` holding rows, baseline, and the restored flag;
  - mirrored to `UserDefaults` under `goals.draft.<portfolioID>.<scope>`;
  - removed when clean, saved, or discarded, or when their portfolio no longer exists after `reloadAll()`.

  Verify with view-model tests for persistence across a fresh `AppModel` and for cleanup after deleting a portfolio.

## 3. Goals workspace (YanaMac `Features/Goals`)

- [x] 3.1 Build `GoalsWorkspaceModel`:
  - row state: identity, current weight, progress, and incomplete or unavailable state;
  - picker options (Held then Not held, excluding rows already in the plan) and the "Not in plan" entries;
  - total, remaining, the save state with its reason or clear mode, and the summary;
  - gap-sorted rows for a draft created from saved goals;
  - the restored and "saved plan changed" notices;
  - row-issue mapping from `ValidationError`.

  Verify with view-model tests covering each of these.
- [x] 3.2 Build `GoalsView` and route `.goals` to it in `SectionView`, with:
  - the scope picker, whose labels show the count or "Not set" and an unsaved marker with an accessibility label;
  - rows in a `Grid` with a current-vs-target bar, a `%` target field labelled "Target for <key>", gap text ("Under 4.2 pt · €420"), and a labelled remove button;
  - the plan summary and the neutral placeholder when there is no valuation;
  - the restored and changed notices with Discard.

  Verify by running the app.
- [x] 3.3 Build the picker popover: search by ticker or name, Held and Not held sections showing current weight, Return to pick, focus moved to the new row's field through `@FocusState`, "Add a New Holding…" opening the add-holding sheet, and the no-holdings and nothing-left states. Use the same pattern for asset classes. Verify with a view-model test for search and exclusion, and a UI test that picks a holding and types into the focused field.
- [x] 3.4 Build the "Not in plan — counted as 0%" `DisclosureGroup` with current weights and Add actions, collapsed when it has more than five entries. Verify with a view-model test for its contents and initial state.
- [x] 3.5 Build the footer:
  - total and remaining ("Total 82.5% · 17.5% left");
  - the disabled-save reason;
  - Discard, and Save with ⌘S;
  - "Clear Targets" with a `.confirmationDialog` naming the count;
  - row removal registered with `UndoManager` (⌘Z), plus the inline "Removed VOO · Undo".

  Verify with view-model tests for reasons, clear, and undo.
- [x] 3.6 Add the helpers:
  - "Start from Current Allocation": in the empty state, and in a More menu with confirmation on a non-empty draft;
  - "Put Remainder Here" on each row;
  - "Split Remainder Across Empty Rows";
  - "Scale to 100%".

  Verify with view-model tests that each yields exactly 100.0.
- [x] 3.7 Show unavailable holding targets with "No longer in this portfolio", Remove, and "Replace With…" (same popover, keeping the percentage), blocking Save with "Resolve N unavailable holdings". Verify with a view-model test for Replace and the blocked save.
- [x] 3.8 Move the recommendations grid into `GoalsView` for the selected scope, with the "Based on your saved plan" note while the draft is dirty. In the Asset classes scope, show the implied mix with "Use Implied Mix" and the per-class disagreement warnings. Verify with view-model tests for the note, the implied mix, and the warnings.

## 4. Analytics handoff

- [x] 4.1 Remove `GoalsSection` and `GoalsEditorModel` from Analytics. Add an "Edit Goals" button to the allocation header for the holding and asset-class groupings that sets `goalScope` and switches to Goals. Replace `goalSaveErrorsAndSuccess` with Goals tests. Verify that Analytics no longer shows an editor, and that a UI test's "Edit Goals" opens the matching scope.

## 5. Verify

- [x] 5.1 Run the package tests, the app tests in Debug and in Release (`-configuration Release ENABLE_TESTABILITY=YES`), and the UI tests (`apple/YanaMac/test-ui.sh`); verify all pass.
- [ ] 5.2 Manually check, with the keyboard and with VoiceOver, in light and dark mode:
  - existing goal records and an empty portfolio;
  - a holding with no shares and a duplicate attempt;
  - a 0% row and an invalid total;
  - an unavailable holding;
  - switching portfolios with unsaved changes;
  - relaunch restore.

## Workflow follow-up

- Update `apple/README.md` if the section list or test instructions change.
- Decide whether the web version on `web-goals-management` should land too. Until then, the macOS app is stricter than the web app on `main` (membership and upper bound).
- Archive the change after review, and verify the archived specs update `macos-portfolio-workspace` and `native-portfolio-storage`.

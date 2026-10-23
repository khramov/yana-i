# Proposal

## Why

In the macOS app, allocation targets are edited in a small form inside Analytics. It asks for free-text tickers, shows only a total, rejects the whole plan with one combined message, and loses edits when the person switches scope, section, or portfolio. Planning is a core activity that deserves its own place: a goals workspace that is quick to set up, hard to get wrong, safe to leave half-done, and directly useful for deciding what to buy. Every target should also refer to a holding that exists in the portfolio.

## What Changes

- Add a **Goals** section to the sidebar, after Analytics, with Holdings and Asset classes scopes. Each scope label shows its saved target count or "Not set", plus an unsaved-changes marker. The selected scope is restored on relaunch.
- Move goal editing and the rebalancing recommendations out of Analytics. Analytics offers an "Edit Goals" button that opens the Goals section on the matching scope. The button is hidden for the Sector grouping.
- Replace free-text ticker rows with a selective plan. A searchable holding picker lists the portfolio's holdings: ticker, name, and current weight, held positions first, then holdings with no shares labelled "Not held". It excludes holdings already in the plan and moves focus to the new row's target field. "Add a New Holding…" opens the existing add-holding sheet.
- Make the plan's meaning explicit. Holdings and asset classes left out of the plan appear under "Not in plan — counted as 0%". Empty or 0% rows are incomplete and block saving.
- Make reaching 100% easy:
  - an always-visible total and remaining amount;
  - "Start from Current Allocation", "Put Remainder Here", "Split Remainder Across Empty Rows", and "Scale to 100%".
- Target fields accept `.` and `,` as the decimal separator in every locale.
- Show progress for the draft:
  - each row has a current-vs-target bar;
  - the gap is shown in percentage points and base currency, labelled Over, Under, or On target with a 1-point tolerance;
  - a plan summary sits above the rows;
  - the "What to buy now" recommendations sit below them, noted "Based on your saved plan" while there are unsaved changes.
- Protect unsaved work:
  - drafts are kept per portfolio and scope across scope, section, and portfolio switches, and across relaunch;
  - a restored draft says so and can be discarded;
  - a notice appears when the saved plan changed underneath the draft (for example, through iCloud sync);
  - clearing a plan asks for confirmation;
  - removing a row can be undone, inline and with ⌘Z;
  - ⌘S saves.
- Tighten goal persistence:
  - holding targets must refer to a live holding of the portfolio;
  - targets must be greater than 0 and at most 100;
  - errors identify each offending target, so the editor shows them on the right rows;
  - an invalid save changes nothing.
- Show targets whose holding was deleted, or arrived through sync without it, as "No longer in this portfolio". Each offers Remove and "Replace With…", which keeps the percentage. Saving stays blocked until every such target is resolved.
- In the Asset classes scope, show the asset-class mix implied by the holding plan, with "Use Implied Mix", and warn for each class where the two saved plans disagree.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `macos-portfolio-workspace`:
  - "Desktop navigation" gains the Goals section.
  - "Goals and rebalancing recommendations" moves from Analytics to the Goals section.
  - New requirements cover the goals workspace: selecting holdings, plan semantics, editing and saving, helpers, unsaved drafts, unavailable targets, progress, the Analytics handoff, and consistency between the two plans.
- `native-portfolio-storage`: "Allocation goals" adds holding membership, an upper bound of 100%, and per-target error reporting.

## Impact

- **YanaKit (`YanaDomain`)**:
  - `GoalScopeDraft.validated()` gains an optional holding-membership check and an upper bound;
  - `ValidationIssue` can name the target key it refers to;
  - new pure goal-plan helpers: percent parsing, remainder and rounding helpers, drift classification, implied asset-class mix.
- **YanaMac**:
  - a new `Features/Goals` folder: workspace model, views, and picker;
  - `AppSection.goals`;
  - Analytics loses `GoalsSection` and `GoalsEditorModel`;
  - `PortfolioRepository.saveGoals` checks membership against the portfolio's live holdings;
  - drafts are stored locally in `UserDefaults`, never synced.
- **Data**: no schema or sync payload change. Existing goal records keep their shape. Goals that reference missing holdings stay stored and appear as unavailable.
- **Tests**: YanaKit unit tests, YanaMac view-model and repository tests, and a UI test for the Goals section.
- **Cross-platform**:
  - the web app on `main` is unchanged: its Analytics goal modal and API rules stay as they are;
  - the web version of this work is parked on the `web-goals-management` branch;
  - after this change, the macOS app is stricter than the web app on `main` (it checks membership and the upper bound).

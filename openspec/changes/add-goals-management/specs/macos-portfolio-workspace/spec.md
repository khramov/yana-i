# Spec Delta

## MODIFIED Requirements

### Requirement: Desktop navigation
The main window SHALL provide a sidebar with Dashboard, Holdings, Transactions, Income, Dividends, Analytics, and Goals sections, plus a portfolio switcher. It SHALL restore the last selected portfolio and section on relaunch.

#### Scenario: Switch portfolio
- **WHEN** a person selects a different portfolio in the switcher
- **THEN** every section shows that portfolio's data in its base currency

#### Scenario: Relaunch restores place
- **WHEN** a person quits while viewing Dividends for "Long term" and relaunches
- **THEN** the app opens on Dividends for "Long term"

#### Scenario: Open Goals from the sidebar
- **WHEN** a person selects Goals in the sidebar
- **THEN** the app shows the goals workspace for the selected portfolio

### Requirement: Goals and rebalancing recommendations
The Goals section SHALL include an editor for holding and asset-class goals and, below it, the rebalancing recommendations for the saved goals of the selected scope. For each key the recommendations SHALL show current %, target %, drift, and the base-currency amount to buy to reach the target (never negative). For holdings with a price, they SHALL also show the share count that amount buys.

#### Scenario: Underweight holding
- **WHEN** a portfolio worth 10,000 has VTI at 30% and a VTI target of 40%, and VTI costs 250 in the base currency
- **THEN** VTI shows drift −10%, buy amount 1,000, and 4 shares

#### Scenario: Overweight holding
- **WHEN** a holding is above its target
- **THEN** its buy amount is 0 and its drift is positive

#### Scenario: Recommendations while editing
- **WHEN** the person has unsaved changes in the selected scope
- **THEN** the recommendations still reflect the saved goals and say "Based on your saved plan"

## ADDED Requirements

### Requirement: Goal scopes in the Goals section
The Goals section SHALL show the Holdings and Asset classes scopes separately. Each scope label SHALL show its number of saved targets or "Not set", and mark unsaved changes. The app SHALL restore the last selected scope on relaunch.

#### Scenario: Scope labels
- **WHEN** a portfolio has 5 saved holding targets and no asset-class targets
- **THEN** the scopes read "Holdings · 5 targets" and "Asset classes · Not set"

#### Scenario: Unsaved scope
- **WHEN** the person edits a holding target without saving
- **THEN** the Holdings scope shows an unsaved-changes marker that VoiceOver announces

### Requirement: Selecting holdings for a plan
The holding scope SHALL offer a searchable picker of the selected portfolio's holdings that are not already in the plan. Each option SHALL show ticker, name when known, and current weight. Held positions SHALL come first, then holdings with no shares, labelled "Not held". Search SHALL match ticker or name. Choosing an option SHALL add a row with an empty target and move keyboard focus to that row's target field.

#### Scenario: Adding a holding
- **WHEN** the person picks VOO in the holding picker
- **THEN** a VOO row with an empty target is added, its target field has keyboard focus, and VOO no longer appears in the picker

#### Scenario: Searching by name
- **WHEN** the person types "apple" in the picker
- **THEN** the picker lists AAPL "Apple Inc." and hides holdings that match neither ticker nor name

#### Scenario: Planning a holding that is not held
- **WHEN** the portfolio has a holding with no shares
- **THEN** the picker lists it after held positions, labelled "Not held", and the person can add it

#### Scenario: Portfolio without holdings
- **WHEN** the selected portfolio has no holdings
- **THEN** the holding scope explains that holdings are needed first and offers to add one

#### Scenario: Asset classes
- **WHEN** the person opens the Asset classes scope
- **THEN** the picker offers the asset classes that are not yet in the plan, with their current weights

### Requirement: Explicit plan semantics
The workspace SHALL treat holdings and asset classes that are not in a plan as a 0% target. It SHALL list those with a current value under "Not in plan — counted as 0%", with their current weight and an Add action. The list SHALL start collapsed when it has more than five entries. A row whose target is empty or 0 SHALL be marked incomplete.

#### Scenario: Held position left out
- **WHEN** the portfolio holds KO and the holding plan has no KO target
- **THEN** KO appears under "Not in plan — counted as 0%" with its current weight

#### Scenario: Zero target
- **WHEN** a plan row has an empty or 0% target
- **THEN** the row says "Enter a target above 0 or remove this row" and saving is blocked

### Requirement: Editing and saving a plan
The workspace SHALL always show the draft's total and the amount left or over. Target fields SHALL accept `.` or `,` as the decimal separator in any locale. When saving is not possible, the reason SHALL appear next to Save. ⌘S SHALL save a valid draft. Saving an empty draft over a saved plan SHALL ask for confirmation. Removing a row SHALL be undoable, both inline and with ⌘Z.

#### Scenario: Total off
- **WHEN** the targets add up to 82.5%
- **THEN** the footer reads "Total 82.5% · 17.5% left" and Save is disabled with "Add 17.5% to save"

#### Scenario: Decimal comma
- **WHEN** a person using the en_US locale types `12,5` as a target
- **THEN** the target is 12.5%

#### Scenario: Clearing a plan
- **WHEN** the person removes every holding target of a saved 5-target plan and saves
- **THEN** the app asks "Remove all 5 holding targets?" and clears them only after confirmation

#### Scenario: Undoing a removal
- **WHEN** the person removes the VOO row and then presses ⌘Z
- **THEN** the VOO row returns with its previous target

### Requirement: Plan building helpers
The workspace SHALL offer actions to start from the current allocation, put the remaining amount on one row, split the remaining amount across empty rows, and scale all targets proportionally to 100%. Each SHALL round targets to 0.1 percentage points and leave the plan at exactly 100%. Starting from the current allocation SHALL ask for confirmation when the draft is not empty.

#### Scenario: Start from current allocation
- **WHEN** a plan is empty and the person chooses "Start from Current Allocation"
- **THEN** each open position gets a row at its current weight, and the targets total exactly 100%

#### Scenario: Split remainder
- **WHEN** the plan totals 70% with two empty rows and the person chooses "Split Remainder Across Empty Rows"
- **THEN** each empty row gets 15%

#### Scenario: Scale to 100%
- **WHEN** every row has a target, the total is 80%, and the person chooses "Scale to 100%"
- **THEN** every target is multiplied by 1.25, rounded to 0.1, and the total is exactly 100%

### Requirement: Unsaved goal drafts
The app SHALL keep a separate draft for each portfolio and scope, preserved across scope, section, and portfolio switches and across relaunch. Drafts SHALL stay on this Mac. A restored draft SHALL say so and offer Discard. If the saved plan changes underneath a draft, the workspace SHALL say so. A draft SHALL only be saved to the portfolio it was made for.

#### Scenario: Switching portfolios
- **WHEN** the person edits the holding plan of "Long term", switches to "Trading", and back
- **THEN** the "Long term" edits are still there and marked unsaved

#### Scenario: Relaunch with unsaved changes
- **WHEN** the person quits with unsaved goal edits and relaunches
- **THEN** the draft is restored with "Restored unsaved changes" and a Discard action

#### Scenario: Plan changed through sync
- **WHEN** another Mac saves the same scope while this Mac has a draft for it
- **THEN** the workspace says the saved plan changed since the draft started, and Discard loads the saved plan

#### Scenario: Draft's portfolio deleted
- **WHEN** the portfolio a draft belongs to is deleted
- **THEN** the draft is removed and nothing is saved to any other portfolio

### Requirement: Unavailable holding targets
The workspace SHALL show a saved holding target whose holding no longer exists in the portfolio as "No longer in this portfolio", without deleting it automatically. It SHALL offer Remove and "Replace With…", which swaps in another holding and keeps the percentage. Saving SHALL stay blocked until every unavailable target is resolved.

#### Scenario: Holding deleted after its target was saved
- **WHEN** a saved 20% target refers to a holding that was deleted
- **THEN** the row reads "No longer in this portfolio" and Save says "Resolve 1 unavailable holding"

#### Scenario: Replacing an unavailable target
- **WHEN** the person chooses "Replace With…" on that row and picks VXUS
- **THEN** the row becomes VXUS at 20%

#### Scenario: Error on the row
- **WHEN** a save is rejected because of a specific target
- **THEN** the error appears on that target's row and VoiceOver reads it with the target field

### Requirement: Goal progress
For each row with a target, the workspace SHALL show the current weight, a bar comparing it with the target, and the gap in percentage points and base currency. Each gap SHALL be labelled Over, Under, or On target, with a 1-point tolerance. A summary SHALL state how many targets are on target and name the largest gap. Progress SHALL follow unsaved edits immediately.

#### Scenario: Underweight row
- **WHEN** a portfolio worth 10,000 has VXUS at 15.8% and a VXUS target of 20%
- **THEN** the row reads "Under 4.2 pt" with the base-currency gap of 420

#### Scenario: Live preview
- **WHEN** the person changes a target without saving
- **THEN** that row's gap and the summary update immediately

#### Scenario: No valuation
- **WHEN** the portfolio has no valued open positions
- **THEN** progress shows a neutral placeholder and targets stay editable

### Requirement: Analytics goal handoff
The Analytics section SHALL NOT edit goals. For the holding and asset-class groupings, it SHALL offer an "Edit Goals" action that opens the Goals section on the matching scope.

#### Scenario: Editing from Analytics
- **WHEN** the person chooses "Edit Goals" in Analytics while grouping by asset class
- **THEN** the app shows the Goals section on the Asset classes scope

### Requirement: Consistent holding and asset-class plans
When a holding plan exists, the Asset classes scope SHALL show the asset-class mix it implies and offer to use that mix as the draft. When both plans are saved and any class differs from the implied mix by more than 1 percentage point, it SHALL warn for each differing class. The warnings SHALL NOT block saving.

#### Scenario: Plans disagree
- **WHEN** the saved holding plan implies 12% bonds and the saved asset-class plan targets 20% bonds
- **THEN** the Asset classes scope says "Your holding plan implies Bond 12%, but this plan targets 20%"

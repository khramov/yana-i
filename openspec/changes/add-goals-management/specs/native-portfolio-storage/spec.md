# Spec Delta

## MODIFIED Requirements

### Requirement: Allocation goals
A portfolio SHALL have independent goal sets for two scopes: holding (keyed by ticker) and asset class. Saving a scope SHALL replace all of its targets. Each target SHALL be greater than zero and at most 100, keys SHALL be unique after normalization, holding targets SHALL refer to a live holding of that portfolio, and non-empty target sets SHALL add up to 100% within ±0.5 percentage points. An invalid save SHALL change nothing and SHALL identify each offending target.

#### Scenario: Targets do not add up
- **WHEN** a person saves asset-class targets of 60% stock and 30% bond
- **THEN** the targets are not saved and the person is told they currently add up to 90.0%

#### Scenario: Clear a scope
- **WHEN** a person saves an empty holding-scope target list
- **THEN** all holding goals for that portfolio are removed and asset-class goals are unchanged

#### Scenario: One target per key
- **WHEN** a portfolio already has a 40% stock asset-class goal and the person saves 50% stock
- **THEN** the portfolio has exactly one stock asset-class goal, at 50%

#### Scenario: Holding from another portfolio
- **WHEN** a person saves a holding target for VXUS, which is a holding of a different portfolio only
- **THEN** nothing is saved and the error names VXUS as not a holding of this portfolio

#### Scenario: Duplicate after normalization
- **WHEN** a person saves holding targets for `vti` and `VTI`
- **THEN** nothing is saved and the error names VTI as appearing more than once

#### Scenario: Existing goal for a deleted holding
- **WHEN** a holding with a saved goal is deleted, or a goal arrives through sync without its holding
- **THEN** the goal stays stored until the person removes or replaces it

# R01-TA-BF-06

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $0.6797273999999999
Duration: 115535ms, turns: 32

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a new startup-time config-consistency check that raises `ConfigurationError` when a user's config explicitly sets both `available_capital` and `tradable_balance_ratio`, since only one of these ever takes effect at runtime (wallets.py silently prefers `available_capital`). The check must run inside the existing `validate_config_consistency` phase in `freqtrade/configuration/config_validation.py`, mirroring the existing `_validate_trailing_stoploss`/`_validate_unlimited_amount` pattern, plus an accompanying unit test in `tests/test_configuration.py`.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| freqtrade/configuration | Owns `Configuration.load_config()`, whose documented algorithm step 4 ("Validate final consistency") is exactly where `validate_config_consistency` and its `_validate_*` helpers live in `config_validation.py` | High |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| freqtrade/configuration | Sole owner of the validation phase being extended; no other cell participates in startup config consistency checks |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| freqtrade (wallets.py) | Read-only reference for understanding *why* the conflict matters (precedence logic). Not modified — precedence behavior must not change, so no behavioral participation in this change |
| freqtrade/config_schema | Defines the JSON schema (incl. `tradable_balance_ratio` default of 0.99) but schema validation runs *after* the consistency phase; no changes needed there — the new check intentionally checks raw key presence before defaults are applied |

## Usage Relationships

| Usage | Relevance |
|---|---|
| None declared for this cell (`usages: []` in schema) | No practice files gate this change |

## Semantic Participation Summary
Only `freqtrade/configuration` participates behaviorally. The change is an internal addition to the existing "validate final consistency" step already documented in `Configuration.load_config()`'s algorithm — it introduces a new private helper function alongside siblings like `_validate_trailing_stoploss`, called from `validate_config_consistency`. No new public type, no signature change, no cross-cell dependency.

## Final Investigation Scope
- freqtrade/configuration (config_validation.py, CODEMANIFEST)

## Scope Risks
- Under-scoping risk is low: the change is fully self-contained to one file's internal validation logic.
- Slight risk of over-scoping into wallets.py — explicitly excluded since precedence logic there is not to be touched, only read for context.

## Notes
`validate_config_consistency` and its `_validate_*` helpers are not listed as manifest types/entities in CODEMANIFEST — they are private implementation details realizing the documented algorithm step "Validate final consistency" under `Configuration.load_config()`. This suggests manifest reconciliation likely requires no structural change, only confirming the existing algorithm text still accurately covers this addition (it's a sub-detail, not a new step).

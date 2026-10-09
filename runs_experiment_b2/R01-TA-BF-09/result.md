# R01-TA-BF-09

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.8
Dangerous success: False
Goga engagement signal: True
Cost: $1.2822006
Duration: 298488ms, turns: 46

## Agent's own summary

This confirms `validate_config_consistency` runs during `FreqtradeBot.__init__` startup, so the new check fires immediately at bot startup — exactly per the requirement.

## Summary

Added `_validate_capital_config` in `freqtrade/configuration/config_validation.py`, wired into `validate_config_consistency` (the same startup consistency-check phase that already catches trailing-stop conflicts, unlimited stake/trades, etc.). It raises a `ConfigurationError` when both `available_capital` and `tradable_balance_ratio` are present in the config, since `wallets.py` only ever honors `available_capital` and silently ignores `tradable_balance_ratio` when both are set.

- Fixed an unrelated pre-existing test (`tests/optimize/test_hyperopt.py::test_max_open_trades_consistency`) that incidentally set both keys.
- Added `test_validate_capital_config` in `tests/test_configuration.py`.
- Verified: `goga lint` passes (0 errors); full `test_configuration.py`, `test_hyperopt.py`, `test_backtesting.py` suites pass (228 tests).

This is an internal implementation detail of the `freqtrade/configuration` cell's already-documented "validate final consistency" step, so no CODEMANIFEST/contract changes were needed.

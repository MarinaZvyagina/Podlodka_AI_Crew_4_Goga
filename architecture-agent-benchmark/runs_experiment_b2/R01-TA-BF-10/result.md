# R01-TA-BF-10

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $1.4491829999999997
Duration: 269852ms, turns: 52

## Agent's own summary

## Change Plan

### Task Classification
**Feature** — new startup-time configuration-consistency check (additive validation), following the existing `_validate_*` pattern in `freqtrade/configuration/config_validation.py`.

### Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `freqtrade/configuration` | `freqtrade/configuration/config_validation.py` | Add `_validate_available_capital(conf)` function; wire it into `validate_config_consistency` |
| `freqtrade/configuration` (test surface) | `tests/test_configuration.py` | Add 3 new unit tests |

### Root Cause Analysis
`Wallets.get_starting_balance()` / `get_total_stake_amount()` (`freqtrade/wallets.py`, outside the documented cell spine) silently prefer `available_capital` over `tradable_balance_ratio` when both are configured, with no warning anywhere. No existing check in `config_validation.py` catches this combination at startup, so users only discover the ignored setting indirectly (wrong capital sizing), generating support requests. Root cause is an absent validation, not a defect in existing logic — precedence itself stays unchanged.

### Trace Summary
- `validate_config_consistency` (config_validation.py:73-99) runs all `_validate_*` checks against `conf` **before** its trailing `validate_config_schema(conf, ...)` call injects JSON-schema defaults (e.g. `tradable_balance_ratio: 0.99`) into `conf` in place.
- `Configuration.load_config()` (configuration.py:91) snapshots the raw, pre-default, file+env-merged config into `conf["original_config"]` — this never receives schema defaults.
- Multi-call flows (`setup_utils_configuration` preliminary pass → `optimize/backtesting.py`'s second non-preliminary pass) mean `conf` itself can already carry an injected `tradable_balance_ratio` default by the second call, but `original_config` stays pristine — so the check must read `original_config` when present.
- `tests/conftest.py`'s `default_conf` fixture sets `original_config` to `{}` (present-but-empty) while also setting `tradable_balance_ratio: 0.99` at the top level — a plain `.get("original_config", conf)` would silently never fall back to `conf` in tests. Must use `conf.get("original_config") or conf` (falls back on both missing *and* empty).

### Change Strategy
1. In `freqtrade/configuration/config_validation.py`, add:
   ```python
   def _validate_available_capital(conf: dict[str, Any]) -> None:
       """
       available_capital and tradable_balance_ratio are mutually exclusive ways to size
       starting capital - only one takes effect (available_capital wins), the other is
       silently ignored. Use the raw user-supplied config so this doesn't false-positive
       once tradable_balance_ratio's schema default has been injected into `conf`.
       """
       raw = conf.get("original_config") or conf
       if "available_capital" in raw and "tradable_balance_ratio" in raw:
           raise ConfigurationError(
               "Both `available_capital` and `tradable_balance_ratio` are set in the "
               "configuration. Only one of these two settings is used to determine your "
               "starting trading capital — the other is silently ignored. "
               "Please remove one of them from your configuration."
           )
   ```
2. Call `_validate_available_capital(conf)` from `validate_config_consistency`, grouped with the other `_validate_*` calls (e.g. next to `_validate_unlimited_amount(conf)`), before the trailing `validate_config_schema(conf, preliminary=preliminary)` call.
3. No changes to `freqtrade/wallets.py` — precedence logic stays exactly as-is.

### Specification Impact
None. `freqtrade/configuration`'s CODEMANIFEST documents `Configuration`, `TimeRange`, `load_config_file`, `load_from_files`, `setup_utils_configuration` as its public surface; `validate_config_consistency`/`_validate_*` helpers are internal implementation detail not itemized at this granularity in the manifest (consistent with how the 10+ existing `_validate_*` siblings are already unmanifested). No CODEMANIFEST edit required.

### Usage Impact
None. No `.usages/` files exist for `freqtrade/configuration`, and this change doesn't alter the cell's public consumer-facing API (`Configuration`/`setup_utils_configuration` signatures and behavior for valid configs are unchanged) — only previously-unvalidated, invalid configs are now rejected earlier and more clearly.

### Compatibility Verification
**Backward compatible for all valid/single-setting configs.** For the narrow case of a config that explicitly sets *both* `available_capital` and `tradable_balance_ratio`, `validate_config_consistency` now raises `ConfigurationError` where it previously silently returned — this is the explicit, intended deliverable of the task (fail-fast on a misconfiguration users are currently hitting blind), not a regression of any documented guarantee. Confirmed via repo-wide grep that no existing test currently sets both keys together on `default_conf`, so no existing test will start failing.

### Test Strategy
Add to `tests/test_configuration.py`, next to `test_validate_max_open_trades`/`test_validate_tsl`:
1. `test_validate_capital_conflict` — `deepcopy(default_conf)`, set `conf["available_capital"] = 100`, keep existing `tradable_balance_ratio: 0.99` → `pytest.raises(ConfigurationError, match=...)` calling `validate_config_consistency(conf)`.
2. Only-`available_capital`-set variant — `del conf["tradable_balance_ratio"]`, set `available_capital` → no error.
3. Only-`tradable_balance_ratio`-set (default state, nothing to delete) → no error — can be folded into test 2 as a parametrized case or a second assertion, matching existing terse style in this file (e.g. `test_validate_whitelist`'s use of `pytest.mark.parametrize` or sequential asserts).

Rationale: covers the three-way matrix (both/one/neither) called out in the task, using the same fixture/call pattern as sibling tests in the file, and exercises the public `validate_config_consistency` entry point rather than the private function directly (matching how `test_validate_tsl` etc. already test through the public function).

### Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `conf.get("original_config") or conf` still misses a caller that builds `conf` bypassing `Configuration.load_config()` *and* doesn't set `original_config` at all | Low | Low | `.get(...)` returns `None` when key absent → `None or conf` falls back to `conf` directly, so absence is already handled correctly |
| Future refactor moves `original_config` assignment or renames it | Low | Medium | Function has a one-line docstring explaining the "why"; behavior degrades gracefully (falls back to `conf`) rather than crashing if the key disappears |
| Message wording judged too terse/not actionable enough by reviewers | Low | Low | Message explicitly names both settings, states one is ignored, and tells user to remove one, per task's explicit ask ("we don't need to guess which one") |

---

Do you approve this plan? Proceed to implementation?

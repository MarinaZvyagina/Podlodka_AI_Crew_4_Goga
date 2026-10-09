# R01-TB-BF-02

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $2.64472575
Duration: 502682ms, turns: 57

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (new configurable safety limit) — additive, opt-in, no default-on behavior change.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| *(undocumented)* wallets | `freqtrade/wallets.py` | New `_check_exposure_limit(pair, stake_amount)` helper; call it inside `get_trade_stake_amount`; new import of `ExposureLimitExceeded` |
| *(undocumented)* exceptions | `freqtrade/exceptions.py` | New `ExposureLimitExceeded(DependencyException)` class |
| freqtrade/optimize (documented) | `freqtrade/optimize/backtesting.py` | New `except ExposureLimitExceeded` branch (before the existing generic `except DependencyException`) in `get_valid_entry_price_and_stake`, incrementing `self.rejected_trades` |
| freqtrade/resolvers (documented) | `freqtrade/resolvers/strategy_resolver.py` | New `("max_exposure_per_currency", None)` entry in the `attributes` override list |
| *(undocumented)* config_schema | `freqtrade/config_schema/config_schema.py` | New `max_exposure_per_currency` JSON schema property |
| freqtrade/configuration (documented, internal file) | `freqtrade/configuration/config_validation.py` | New `_validate_exposure_cap` cross-field check, wired into `validate_config_consistency` |
| docs | `docs/configuration.md` | New table row + narrative subsection under "Configuring amount per trade" |
| tests | `tests/test_wallets.py` | New unit tests: no-effect, resize, skip, grouping (spot+futures), live/backtest parity |
| tests | `tests/optimize/test_backtesting.py` (verify exact file) | Optional: one test confirming `rejected_trades` increments on exposure-cap skip in backtest |

No file outside this list is touched — `freqtrade/exchange/exchange.py` and `freqtrade/persistence/trade_model.py` are consumed read-only, unchanged.

## Root Cause Analysis
Freqtrade has no mechanism to cap exposure by underlying currency across simultaneously open trades. `Wallets.get_trade_stake_amount` (`wallets.py:387-408`) is the single method both live (`freqtradebot.py:723`) and backtest (`backtesting.py:1062`) call to size a new entry, and is the only point where such a cap can be enforced once for both modes.

## Trace Summary
`StrategyResolver.load_strategy` resolves `config["max_exposure_per_currency"]` before `Wallets` is constructed in both hosts (`freqtradebot.py:100→109`, `backtesting.py:184/189→307`) → `Wallets.get_trade_stake_amount` reads it directly off `self._config`, groups open trades via `self._exchange.get_pair_base_currency` (same convention as `wallets.py:130`/`485`), sums via `Trade.get_open_trades()` (identical live/backtest abstraction) → resizes or raises `ExposureLimitExceeded` → propagates through each host's pre-existing `DependencyException` handling unchanged. `get_trade_stake_amount` is called only for new-entry sizing in both hosts (never for DCA/position-adjustment — confirmed no second call site in either `freqtradebot.py` or the `pos_adjust` branch of `backtesting.py`), so scope is naturally limited to new trades as required.

## Change Strategy
1. **`freqtrade/exceptions.py`**: add `class ExposureLimitExceeded(DependencyException):` with a short docstring, placed near the other `DependencyException` subclasses (`PricingError`, `ExchangeError`).
2. **`freqtrade/wallets.py`**:
   - Import `ExposureLimitExceeded` from `freqtrade.exceptions`.
   - Add `_check_exposure_limit(self, pair: str, stake_amount: float) -> float`:
     - Read `max_exposure = self._config.get("max_exposure_per_currency")`; if falsy (unset/`None`), return `stake_amount` unchanged (opt-in, no-op by default).
     - `base_currency = self._exchange.get_pair_base_currency(pair)`.
     - `committed = sum(t.stake_amount for t in Trade.get_open_trades() if self._exchange.get_pair_base_currency(t.pair) == base_currency)`.
     - `currency_cap = self.get_total_stake_amount() * max_exposure`.
     - `available_for_currency = currency_cap - committed`.
     - If `available_for_currency <= 0`: raise `ExposureLimitExceeded` with a message naming the pair, base currency, committed amount, and cap (mirrors the existing `_check_available_stake_amount` message style).
     - If `stake_amount > available_for_currency`: `self._local_log(...)` (info level, same helper existing clamps use) and return `available_for_currency`.
     - Else return `stake_amount` unchanged.
   - In `get_trade_stake_amount`, after the `stake_amount` is determined (fixed or unlimited-calculated) and before `_check_available_stake_amount`, insert: `stake_amount = self._check_exposure_limit(pair, stake_amount)`.
3. **`freqtrade/optimize/backtesting.py`**: in `get_valid_entry_price_and_stake`, change:
   ```python
   try:
       stake_amount = self.wallets.get_trade_stake_amount(...)
   except DependencyException:
       return 0, 0, 0, 0
   ```
   to catch `ExposureLimitExceeded` first (increment `self.rejected_trades`) and keep the generic `DependencyException` branch unchanged below it, per Python's first-match except ordering (subclass before base class).
4. **`freqtrade/resolvers/strategy_resolver.py`**: add `("max_exposure_per_currency", None)` to the `attributes` list (`strategy_resolver.py:58-83`), same slot style as other optional float-like knobs (e.g. `stake_amount`).
5. **`freqtrade/config_schema/config_schema.py`**: add a `max_exposure_per_currency` property, `type: number`, `minimum` exclusive-of-zero via `exclusiveMinimum: 0` (JSON-Schema Draft4 uses `"exclusiveMinimum": true` with `"minimum": 0` — verify draft syntax against an existing exclusive-bound property before writing, or use `minimum: 0` + validate `> 0` in `config_validation.py` if Draft4 boolean-form is required), `maximum: 1`, description, no default (absence = disabled).
6. **`freqtrade/configuration/config_validation.py`**: add `_validate_exposure_cap(conf)` validating `0 < max_exposure_per_currency <= 1` when present (schema already enforces the range; this function exists only if a cross-field check beyond single-key range is warranted — if the schema alone fully expresses the constraint, skip this step to avoid redundant validation code per "don't add validation beyond what's needed"). Call it from `validate_config_consistency` only if added.
7. **`docs/configuration.md`**: add a parameters-table row (Strategy Override tag, like `max_open_trades`) and a short narrative subsection near "Amend last stake amount" explaining the cap, grouping-by-base-currency semantics, and resize-vs-skip behavior.
8. **Tests**: extend `tests/test_wallets.py` per the Test Strategy below.

## Specification Impact
No CODEMANIFEST requires modification. `freqtrade/optimize/CODEMANIFEST` and `freqtrade/resolvers/CODEMANIFEST` document only type-level responsibilities, not the internal methods being touched (`get_valid_entry_price_and_stake`, `trade_slot_available`, `_override_attribute_helper`'s `attributes` list) — none of these method-level manifests exist to update. `freqtrade/configuration/CODEMANIFEST` does not document `config_validation.py` at all (only `configuration.py`, `timerange.py`, `config_setup.py`, `load_config.py` are manifested locations). No manifest reconciliation is expected at Step 7 of the outer pipeline; this will be confirmed, not skipped, when that step runs.

## Usage Impact
No `.usages/` files exist for any of `freqtrade/optimize`, `freqtrade/resolvers`, `freqtrade/configuration` (confirmed during investigation — no `<cell>/.usages/` directories present). No usage file requires creation or update; none of these cells' public facades change (only internal/undocumented methods and files are touched).

## Compatibility Verification
**Backward compatible.** `max_exposure_per_currency` is absent from every existing config/strategy/test fixture; `self._config.get("max_exposure_per_currency")` returns `None` → `_check_exposure_limit` is a pure pass-through → `get_trade_stake_amount`'s return value is byte-for-byte identical to today for every existing caller and test. `ExposureLimitExceeded` subclasses `DependencyException`, so every existing `except DependencyException` handler continues to catch it without modification. No signature, file path, or return-semantic changes.

## Test Strategy
Add to `tests/test_wallets.py`, following the existing `test_get_trade_stake_amount_*` (`:107-179`) and table-driven `test_validate_stake_amount` (`:182-233`) patterns:
1. **No-effect**: `max_exposure_per_currency` unset → `get_trade_stake_amount` result unchanged from current behavior (regression guard).
2. **Resize**: one open trade in a base currency near the cap; a new trade in the same base currency gets sized down to exactly fill remaining room, not raise.
3. **Skip**: committed exposure already at/above cap → `get_trade_stake_amount` raises `ExposureLimitExceeded` (subclass check, per existing `pytest.raises(DependencyException, ...)` style, plus an explicit `isinstance`/exact-type assertion).
4. **Grouping correctness**: two pairs with different quote currencies but the same base (e.g. `ETH/USDT`, `ETH/BTC`) count against the same cap; a pair with a different base does not.
5. **Futures grouping**: repeat resize/skip cases with `trading_mode=futures`, confirming `get_pair_base_currency` grouping still applies (positions tracked via `Trade`/`LocalTrade`, not the separate `_positions` dict, since `get_trade_stake_amount` operates pre-entry).
6. **Live/backtest parity**: one test constructing `Wallets` twice (`is_backtest=False` and `is_backtest=True`) with equivalent `Trade`/`LocalTrade` open-trade fixtures and identical config, asserting `get_trade_stake_amount` returns the same value (or raises the same exception type) in both — the test that most directly encodes the user's primary acceptance criterion.
7. Optionally, a `tests/optimize/test_backtesting.py` test confirming `rejected_trades` increments when `get_valid_entry_price_and_stake` hits the new exception.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Exception-ordering bug (`except DependencyException` shadowing `except ExposureLimitExceeded` if misordered) in `backtesting.py` | Medium (easy Python mistake) | High — silently loses the new visibility feature | Place `except ExposureLimitExceeded` strictly before `except DependencyException`; cover with the backtest rejection-counter test |
| Double-counting or wrong grouping if `get_pair_base_currency` returns `""` for malformed/unlisted pairs | Low | Medium — could lump unrelated pairs under one empty-string group | Existing behavior of `get_pair_base_currency` already returns `""` as a degenerate case elsewhere in `wallets.py` (`_update_dry`); no new failure mode introduced, but note as a pre-existing edge case, not something to newly guard against |
| JSON-Schema Draft4 exclusive-minimum syntax mismatch (boolean-form vs Draft7 numeric-form) | Low | Low — schema validation error at startup, caught immediately by existing config validation | Verify against an existing exclusive-bound property in `config_schema.py` before writing; if none exists, use `minimum: 0` and treat `0` as "disabled" equivalently to `None`/absent, avoiding the exclusivity question entirely |
| Redundant validation layer if schema `minimum`/`maximum` already fully expresses the constraint | Low | Low — unnecessary code, against "don't add abstractions beyond what's needed" guidance | Skip `_validate_exposure_cap` in `config_validation.py` if schema bounds alone suffice — decide during implementation by checking whether `tradable_balance_ratio` (an exact structural analog) uses a similar dedicated validator (it does not) |

---

Do you approve this plan? Proceed to implementation?

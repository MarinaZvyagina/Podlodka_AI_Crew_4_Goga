# PLAUSIBILITY_CHECK.md — R01 (freqtrade)

## When this check was performed

`tasks/R01/task_A.md` through `task_D.md` were read for the first time **after** `SCOPE.md` was
written and frozen, and after all 10 CODEMANIFEST files were authored, materialized, linted,
and drift-checked — per the assignment's explicit ordering requirement. No content in the
architecture forest was revised in response to reading the tasks (see "Outcome" below for the
one case that needed the closest look).

## The four task prompts (quoted)

- **Task A**: catch, at startup config-validation time, a specific misconfiguration where a user
  sets both a fixed starting-capital amount and a tradable-balance-percentage, "the same phase
  where we already catch other conflicting or nonsensical config combinations, e.g.
  contradictory stoploss/trailing-stop settings."
- **Task B**: add a configurable per-strategy cap on how much capital may be committed to
  positions sharing the same "underlying currency" at once (concentration-risk limit), which
  "needs to behave identically whether someone is running the bot live/dry-run or running a
  backtest."
- **Task C**: add a consecutive-loss-streak detector, per-pair and bot-wide, that locks out new
  entries for a configurable cooldown once a configurable number of consecutive losses occurs,
  surfaced "through whatever channel the bot already uses to let users know trading has been
  automatically interrupted, consistent with how similar automatic pauses are already
  surfaced."
- **Task D**: add a short-lived (few-second) cache for repeated current-price lookups within a
  short window, live/dry-run only, with backtesting explicitly unaffected.

## Term-level check: no task-specific vocabulary appears in the forest

Grepped all 10 CODEMANIFEST files for the task-specific terms each prompt turns on: none of
"consecutive loss", "loss streak", "cooldown", "concentration", "underlying currency",
"exposure cap", "tradable_balance_ratio", "available_capital", "price cache", "ticker cache",
"rate limit" appear anywhere in the forest. The forest never says anything shaped like "add
caching here" or "implement a loss-streak lock" — every annotation describes what a real,
already-existing class/method does today, in the codebase's own vocabulary (e.g. `IProtection`,
`StoplossGuard`, `ProtectionReturn`, `custom_stake_amount`, `Configuration.load_config`),
consistent with `TREATMENT_DESIGN.md` §4's required phrasing style.

## Where genuine overlap exists, and why it's expected rather than leakage

Three of the four tasks (A, B, C) touch functionality that lives near or inside cells this
forest documents — this is unavoidable and, per the treatment design, *intended*: a real
architecture doc-set should make a repository's existing extension points and validation phases
discoverable, and RQ7/RQ9 of the benchmark specifically ask whether the Goga treatment changes
existing-extension-point usage and how effect varies by task type. Providing accurate,
task-agnostic documentation of a real extension point is not the same as hinting at a specific
task built on top of it:

- **Task C ↔ `freqtrade/plugins/protections`**: this is the closest overlap. Task C's
  "consecutive-loss streak + cooldown, per-pair and bot-wide" is a near-textbook new
  `IProtection` (the forest's `Usages.extension_point` says exactly: "subclass `IProtection`,
  set `has_global_stop`/`has_local_stop`, implement `short_desc`, `global_stop`, and
  `stop_per_pair`... register the class name"). This is Task C's category by design ("Existing
  Extension Point... prompt does not name it — agent must discover it or fail to") — the forest
  describes the *mechanism* (what `IProtection`/`StoplossGuard`/`ProtectionManager` are and how
  they compose) using only real, pre-existing names; it never mentions loss streaks, cooldowns,
  or anything from the task prompt itself. An agent still has to recognize that Task C's request
  *is* a protection and map "cooldown" → `ProtectionReturn.until`/`calculate_lock_end` — the
  forest doesn't do that mapping for it. Judgment call: kept as-is, since documenting this real
  extension point generically is precisely the mechanism the Goga condition is meant to test,
  not an accidental giveaway of the answer.
- **Task A ↔ `freqtrade/configuration`**: the forest's `Configuration.load_config` annotation
  mentions, generically, that config loading "run[s] each `_process_*` step... Validate final
  consistency" — it does not name `tradable_balance_ratio`, `available_capital`, or any
  stoploss/trailing-stop setting, and doesn't say a new check should be added there. This is
  weaker overlap than Task C's — it tells an agent *that* a startup-validation phase exists at
  all (real, load-bearing architecture fact), not *what* to check for.
- **Task B ↔ `freqtrade/strategy`/`freqtrade/optimize`**: the forest documents
  `custom_stake_amount`/`adjust_trade_position` (pre-existing `IStrategy` hooks) and notes that
  `Backtesting` "composes... the same kind of objects the live bot would use... so strategy code
  sees an identical runtime environment in backtest and live modes" — this is a true, generic
  architectural fact (relevant to Task B's live/backtest-parity requirement) stated without any
  reference to currency concentration, exposure caps, or margin/futures pairs.
- **Task D ↔ `freqtrade/exchange`**: no overlap found. The forest documents `Exchange.get_rate`/
  `fetch_ticker` as plain pass-through methods with no caching behavior mentioned anywhere —
  Task D's short-lived price cache is not hinted at in any way.

## Outcome

No revision was made to the architecture forest as a result of this check. The one genuine
close-overlap case (Task C / `plugins/protections`) was judged to be the expected, in-scope
operation of documenting a real, load-bearing extension point — not task-specific hint content —
and is disclosed here explicitly rather than papered over, per `TREATMENT_DESIGN.md` §4's
"independent plausibility check" requirement. If a stricter standard is wanted for future repos
in this benchmark, one option would be to phrase extension-point `Usages` blocks even more
abstractly (omit the "subclass X, implement Y, register Z" recipe and only name the interface
type); this was not done retroactively here to avoid the appearance of hand-tuning the artifact
after seeing the task list, which itself would be a worse violation of the freeze discipline
than leaving an honestly-disclosed, architecturally-justified overlap in place.

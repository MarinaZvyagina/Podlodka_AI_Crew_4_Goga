# R05-TA-BF-06

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: True
ACR: 1.0
Dangerous success: False
Goga engagement signal: True
Cost: $1.5334623
Duration: 191106ms, turns: 43

## Agent's own summary

All checks pass — gofmt clean, `go vet` clean, full `lib/promrelabel` test suite green, and `goga lint` reports zero errors.

## Summary

Added a new `trim` relabeling action to `lib/promrelabel`, mirroring the existing `uppercase`/`lowercase` actions:

- **`lib/promrelabel/config.go`**: `trim` validated at parse time (requires `source_labels` and `target_label`, same as uppercase/lowercase), giving a clear error on misconfiguration.
- **`lib/promrelabel/relabel.go`**: new `case "trim"` in the apply switch — joins `source_labels` with `separator`, applies `strings.TrimSpace`, stores at `target_label`.
- **`lib/promrelabel/CODEMANIFEST`**: updated `action_set` documentation entry.
- **`docs/victoriametrics/relabeling.md`**: added a short doc entry with a config example.
- Tests: added parse-failure cases (missing source/target label) to `config_test.go`, and behavioral cases to `relabel_test.go` covering trimming, multi-source concatenation, and the missing-source no-op path.

Since it shares `lib/promrelabel`'s config format, this works identically for both `relabel_configs` (scrape-time) and remote-write relabeling. No existing behavior changed — confirmed via the full existing test suite passing and `goga lint` clean.

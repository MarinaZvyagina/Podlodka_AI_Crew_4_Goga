# R05-TA-BF-04

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: False
Cost: $1.2294228
Duration: 172644ms, turns: 42

## Agent's own summary

# Change Plan

## Task Classification
Feature (extension) — additive new relabel action, no modification of existing action behavior.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `lib/promrelabel` | `config.go` | Add `"trim_space"` to the action validation `switch` in `parseRelabelConfig`, requiring non-empty `source_labels` and `target_label` |
| `lib/promrelabel` | `relabel.go` | Add `case "trim_space":` to the apply `switch`, using `strings.TrimSpace` on the concatenated source-label value, writing to `target_label` |
| `lib/promrelabel` | `config_test.go` | Add validation test: missing `target_label` for `action=trim_space` → parse error |
| `lib/promrelabel` | `relabel_test.go` | Add behavior test: `trim_space` action trims whitespace from concatenated source label value into target label |
| (non-cell) | `docs/victoriametrics/relabeling.md` | Add a new bullet under "Relabeling Enhancements" documenting `trim_space`, with a "Try it" playground-style example matching sibling entries |

## Root Cause Analysis
Not a bugfix. Investigation confirmed `uppercase`/`lowercase` are the closest analogous actions: both are validated in one `switch` block in `config.go` (requiring `source_labels` + `target_label`) and applied in one `switch` block in `relabel.go` (concatenate source labels via `concatLabelValues`, transform the string, `setLabelValue` into `target_label`). `trim_space` follows the identical shape, substituting `strings.TrimSpace` for the case-conversion call.

## Trace Summary
- `config.go:parseRelabelConfig` (~line 260-394): action validation switch — add case.
- `relabel.go:apply` (~line 163-431): action apply switch — add case, positioned next to `"uppercase"`/`"lowercase"` for readability.
- No other call sites branch on `Action` string (confirmed: `String()` uses `ruleOriginal`, not `Action`; no marshalling logic keys off `Action`).
- Consumers (`lib/promscrape`, `app/vmagent`, `app/vminsert`, `lib/streamaggr`, `app/vmalert`, `app/vmselect`) are unaffected — they invoke `ParseRelabelConfigs`/`Apply` generically.

## Change Strategy
1. **`config.go`**: insert `case "trim_space":` immediately after the `case "uppercase", "lowercase":` block (or grouped alongside it), with the same two checks:
   - `if len(sourceLabels) == 0 { return nil, fmt.Errorf("missing `source_labels` for `action=trim_space`") }`
   - `if targetLabel == "" { return nil, fmt.Errorf("missing `target_label` for `action=trim_space`") }`
2. **`relabel.go`**: insert `case "trim_space":` after the `"lowercase"` case, reusing `concatLabelValues`/`bytesutil.InternBytes`/`relabelBufPool`, calling `strings.TrimSpace(valueStr)` in place of `strings.ToUpper`/`strings.ToLower`, then `setLabelValue`.
3. **Docs**: add one bullet in `docs/victoriametrics/relabeling.md` under "Relabeling Enhancements" (alongside `replace_all`, `labelmap_all`, etc.), with a YAML example (`source_labels` with a whitespace-padded value → `target_label`) and a "Try the above config" playground link matching sibling entries' style (link is optional/best-effort — will omit if it can't be safely hand-constructed, since it's not required by the ticket).
4. **Tests**: add one `config_test.go` case exercising the missing-`target_label` error path, and one `relabel_test.go` case exercising `trim_space` transforming `"  foo  "` → `"foo"`.

## Specification Impact
None. `lib/promrelabel`'s CODEMANIFEST models `RelabelConfig`/`ParsedConfigs` as opaque types without enumerating the closed action set as a contractual guarantee (confirmed in Investigation Report). No CODEMANIFEST edits required; this is implementation detail within already-declared type behavior ("parse and apply relabeling rules").

## Usage Impact
No `.usages/*.md` files reference the relabel action set by name (confirmed no cell-level usages directory exists for `lib/promrelabel` beyond what's tracked in the manifest). Only the external, non-cell doc `docs/victoriametrics/relabeling.md` needs a new entry, per the ticket's explicit requirement — this is documentation for external users, not a goga practice file.

## Compatibility Verification
**Backward compatible.** No existing action's validation or apply branch is touched. New `case` arms only execute for the new `action: trim_space` string; the `default:` unknown-action error path in `config.go` and the `default: logger.Panicf` in `relabel.go` remain reachable only for genuinely unrecognized actions, which `trim_space` no longer is once added. All existing tests remain valid since none reference `trim_space`.

## Test Strategy
- **Validation test** (`config_test.go`): assert that a `RelabelConfig{Action: "trim_space", SourceLabels: [...]}` with empty `TargetLabel` fails `ParseRelabelConfigs` with an error mentioning `target_label` and `action=trim_space` — mirrors existing `uppercase` validation test shape at lines ~515-609.
- **Apply test** (`relabel_test.go`): assert that given labels `{foo="  bar  "}` and a rule `source_labels: [foo], target_label: baz, action: trim_space`, the resulting labels include `baz="bar"` — mirrors existing uppercase/lowercase apply test pattern.
- Run `go test ./lib/promrelabel/...` to confirm no regressions.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Action name collision with a future/reserved name | Low | Low | Confirmed via grep no existing `trim`/`trim_space` action string in codebase |
| Missed validation symmetry (e.g. forgetting `source_labels` check) | Low | Medium | Explicitly mirror both checks from `uppercase`/`lowercase` case |
| Doc example uses an invalid/broken playground link | Low | Low | Omit or hand-verify link format against sibling examples; not required by ticket |
| Test placement inconsistent with existing table-driven test structure | Low | Low | Read existing test functions' structure before inserting new cases |

Do you approve the plan? Proceed to implementation?

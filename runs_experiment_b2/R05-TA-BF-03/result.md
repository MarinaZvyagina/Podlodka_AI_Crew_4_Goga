# R05-TA-BF-03

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: False
Cost: $1.5192572999999996
Duration: 157328ms, turns: 42

## Agent's own summary

Good — there's a `## tip` section in `CHANGELOG.md` (the "unreleased" file) where I'll add a `FEATURE:` entry. Now producing the Change Plan.

# Change Plan

## Task Classification
Feature (additive extension of an existing, well-established pattern — new relabel action).

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `lib/promrelabel` | `config.go` | Add `case "trim":` to the validation switch in `parseRelabelConfig`, requiring non-empty `sourceLabels` and `targetLabel` |
| `lib/promrelabel` | `relabel.go` | Add `case "trim":` to the execution switch in `(*parsedRelabelConfig).apply`, using `strings.TrimSpace` on the concatenated source values |
| `lib/promrelabel` | `CODEMANIFEST` | Append `trim` to the `action_set` Usage enumeration |
| `lib/promrelabel` | `config_test.go` | Add two failure cases to `TestParseRelabelConfigsFailure`: `trim` missing `source_labels`, `trim` missing `target_label` |
| `lib/promrelabel` | `relabel_test.go` | Add success case(s) to the `upper-lower-case` block in `TestParsedConfigsApply` (or equivalent `f`-based test) covering `trim` |
| N/A (docs, non-cell) | `docs/victoriametrics/relabeling.md` | Add a `trim` bullet to the "Relabeling Enhancements" new-actions list |
| N/A (docs, non-cell) | `docs/victoriametrics/changelog/CHANGELOG.md` | Add a `FEATURE:` bullet under `## tip` |

## Root Cause Analysis
Not a bug — a gap in the action set. `uppercase`/`lowercase` are the only existing actions that transform a value from `source_labels` into `target_label` without filtering/dropping the series, and they occupy two exact loci: validation (`config.go:381-387`) and execution (`relabel.go:411-426`). `trim` needs the identical shape with `strings.TrimSpace` substituted for the case transform.

## Trace Summary
`RelabelConfig{Action:"trim", SourceLabels, TargetLabel}` (YAML) → `parseRelabelConfig` (action lowercased at `config.go:216`, validated at new `case "trim":`) → `parsedRelabelConfig{Action:"trim", SourceLabels, Separator, TargetLabel}` stored in `ParsedConfigs.prcs` → per-sample `apply()` new `case "trim":` → `concatLabelValues` → `strings.TrimSpace` → `setLabelValue(labels, labelsOffset, prc.TargetLabel, valueStr)`. No other file in the trace graph (`debug.go`, `if_expression.go`, `graphite.go`, `scrape_url.go`) branches on action name, so none of them require changes.

## Change Strategy
1. **`config.go`**: insert `case "trim":` immediately after (or adjacent to, alphabetically grouped with) `case "uppercase", "lowercase":` (currently lines 381-387), with body:
   ```go
   case "trim":
       if len(sourceLabels) == 0 {
           return nil, fmt.Errorf("missing `source_labels` for `action=%s`", action)
       }
       if targetLabel == "" {
           return nil, fmt.Errorf("missing `target_label` for `action=%s`", action)
       }
   ```
2. **`relabel.go`**: insert `case "trim":` after the `lowercase` case (currently ending line 426), body:
   ```go
   case "trim":
       bb := relabelBufPool.Get()
       bb.B = concatLabelValues(bb.B[:0], src, prc.SourceLabels, prc.Separator)
       valueStr := bytesutil.InternBytes(bb.B)
       relabelBufPool.Put(bb)
       valueStr = strings.TrimSpace(valueStr)
       labels = setLabelValue(labels, labelsOffset, prc.TargetLabel, valueStr)
       return labels
   ```
   No new import required — `strings` already imported.
3. **`CODEMANIFEST`**: update the `action_set` Usage value to insert `trim` into the enumerated action list (placed next to `uppercase, lowercase` since it is the same value-transform family), keeping every other word of that Usage unchanged.
4. **`docs/victoriametrics/relabeling.md`**: add one bullet to the "new actions" list (after `drop_metrics`/`graphite` or near a natural fit) titled `**`trim` action**`, one-sentence description + a minimal YAML example, following the exact formatting of the surrounding bullets (bold action name, sentence, fenced YAML with `hl_lines`, no "Try it" playground link required since not all bullets have one — `keep_if_contains` etc. do have links; check exact prior bullets — actually all bullets in that list do include a "Try the above config" playground link. Skip the playground link since we cannot generate a real one without executing the actual playground URL-encoder; a bare example is acceptable and consistent with ticket's "short entry" ask).
5. **`docs/victoriametrics/changelog/CHANGELOG.md`**: add one `FEATURE:` bullet under `## tip`, referencing `lib/promrelabel`/relabeling in the same style as the existing `uppercase`/`lowercase` 2022 entry (component tag + short description), placed among the other `FEATURE:` bullets at the top of the `## tip` section.
6. **Tests**: as below.

## Specification Impact
Only the `action_set` Usage in `lib/promrelabel/CODEMANIFEST`'s Header changes (its text now includes `trim`). No Body type (`RelabelConfig`, `ParsedConfigs`, `IfExpression`, etc.) signature changes — `trim` reuses existing fields (`SourceLabels`, `Separator`, `TargetLabel`) with no new struct members, so no Body edits are needed. The Annotations block's instruction ("Use `action_set` when implementing or reasoning about a new relabel rule's runtime behavior") remains valid as-is.

## Usage Impact
No `.usages/*.md` files exist for `lib/promrelabel` (confirmed via earlier directory listing — only `CODEMANIFEST` is present, no `.usages/` subdirectory) and no cell imports `lib/promrelabel`'s Usages. The only "usage" artifact is the inline `action_set` Usage inside the CODEMANIFEST itself, covered above. External documentation (`docs/victoriametrics/relabeling.md`) is a product-doc, not a Goga Usage file, but is updated per the ticket's explicit requirement.

## Compatibility Verification
Backward compatible. Confirmed: no existing `case` branch in either switch is altered; `trim` is unreachable for any config that doesn't explicitly set `action: trim`; `parsedRelabelConfig` struct and all existing exported functions keep identical signatures; existing tests are untouched, only appended to.

## Test Strategy
- `config_test.go` → `TestParseRelabelConfigsFailure`: add
  - `trim` with `TargetLabel` set but no `SourceLabels` → expect error (mirrors `uppercase-missing-sourceLabels`)
  - `trim` with `SourceLabels` set but no `TargetLabel` → expect error (mirrors `lowercase-missing-targetLabel`)
- `relabel_test.go` → within the `upper-lower-case` test block (or a new adjacent `trim` comment block) using the same `f(configYAML, inputLabels, matchExpected, outputExpected)` helper: add a case such as
  ```yaml
  - action: trim
    source_labels: ["foo"]
    target_label: foo
  ```
  with input `{foo=" bar "}` and expected output `{foo="bar"}`, verifying both a value with surrounding whitespace and (optionally) a multi-source-label join case for parity with the `lowercase` multi-label test.
- Run `go test ./lib/promrelabel/...` to confirm both new and pre-existing tests pass.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Placing `trim` in the wrong switch (only one of the two) leaves it either unvalidated or unexecuted (panics via `logger.Panicf("BUG: unknown action")`) | Low | High (panic in prod) | Implement both cases together; test success path exercises both validation and execution |
| Doc/CHANGELOG wording drifts from existing style, causing lint/review friction | Low | Low | Mirror exact phrasing/format of adjacent `uppercase`/`lowercase` and `replace_all` entries |
| CODEMANIFEST `action_set` text edited inconsistently with actual switch cases (drift) | Low | Medium | Update `action_set` in the same change as the code, verified in Step 7 (Manifest Reconciliation) of the pipeline |

Do you approve the plan? Proceed to implementation?

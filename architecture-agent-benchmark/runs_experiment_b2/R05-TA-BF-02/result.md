# R05-TA-BF-02

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: True
Cost: $1.1808731999999997
Duration: 133005ms, turns: 37

## Agent's own summary

Good, that confirms the test harness pattern (`f` closure at line 201 for `TestParseRelabelConfigsFailure`). Now I have full evidence. Producing the Investigation Report.

# Investigation Report

## Task Summary
Add a new `trim` relabel action to `lib/promrelabel` that strips leading/trailing whitespace from the value obtained by joining `source_labels` (via `separator`) and stores the result in `target_label`, exactly mirroring the existing `uppercase`/`lowercase` actions. This satisfies a user-facing need to remove stray whitespace from label values without hand-crafted regex `replace` rules, for both scrape-time and remote-write relabeling, which share this one engine.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `lib/promrelabel` | Sole owner of `RelabelConfig` parsing (`config.go`) and `parsedRelabelConfig.apply` execution (`relabel.go`); contains the exact `uppercase`/`lowercase` pattern to mirror | High |

## Tracing Summary
Confirmed via `goga-change-tracer`: `RelabelConfig.Action` (raw YAML string) → `parseRelabelConfig` lowercases it and validates it through a `switch action` block (`config.go:260-394`) → builds `parsedRelabelConfig.Action` → `ParsedConfigs.Apply`/`ApplyDebug` iterate `prcs` and call `prc.apply(labels, labelsOffset)` → a second `switch prc.Action` (`relabel.go:173-430`) executes the transform. `uppercase`/`lowercase` follow this identical flow: validate `source_labels` and `target_label` are non-empty in the config-side switch, then in the relabel-side switch join `source_labels` via `concatLabelValues`, transform, and `setLabelValue` into `target_label`. Both `lib/promscrape` (scrape-time) and `app/vmagent`/`app/vminsert`'s remote-write wrappers call only the opaque `ParsedConfigs.Apply`/`ParseRelabelConfigs` facade — they never branch on individual action strings, so a new action added inside `lib/promrelabel` is automatically available on both paths with zero changes to callers.

## Data Flow Analysis
1. YAML `action: trim` → `RelabelConfig.Action` (config.go:22).
2. `parseRelabelConfig` (config.go:210): `action := strings.ToLower(rc.Action)` → canonical lowercase form.
3. Validation switch (config.go:260, right after `case "uppercase", "lowercase":` at line 381) must gain a `case "trim":` (or fold into the existing `uppercase`/`lowercase` case) requiring `len(sourceLabels) > 0` and `targetLabel != ""`, returning `fmt.Errorf("missing \`source_labels\` for \`action=%s\`", action)` / `fmt.Errorf("missing \`target_label\` for \`action=%s\`", action)` on violation — identical error shape to the existing cases (config.go:382-387).
4. On success, `prc.Action = "trim"` is stored (config.go:416) inside the returned `*parsedRelabelConfig`.
5. At runtime, `apply()` (relabel.go:163) needs a new `case "trim":` block between/near `uppercase`/`lowercase` (relabel.go:411-426): get a pooled buffer, `concatLabelValues(bb.B[:0], src, prc.SourceLabels, prc.Separator)`, intern to string, `strings.TrimSpace(valueStr)`, `setLabelValue(labels, labelsOffset, prc.TargetLabel, valueStr)`, return labels.
6. No other field (`Regex`, `Modulus`, `Replacement`, `Match`, `Labels`) is read by `uppercase`/`lowercase`, and none should be read by `trim` either — consistent with the minimal-field pattern.

## Manifest Algorithm Analysis
`lib/promrelabel/CODEMANIFEST`'s `Usages.action_set` inline practice enumerates the exhaustive valid action set consumed by `ParseRelabelConfigs`'s documented algorithm ("Validate and normalize each rule's action against `action_set`"). This string must be updated to append `trim` alongside `uppercase, lowercase`. No `Algorithm:` block exists per-action (the switch itself is the algorithm, referenced generically), so no other manifest text requires modification beyond this one inline enumeration. This is a text-only manifest edit with no signature/type changes, since `trim` reuses the existing `RelabelConfig`/`parsedRelabelConfig` types and the existing `ParsedConfigs.Apply` method signature.

## Affected Usages

| Usage | Cell | Classification | Reason |
|---|---|---|---|
| `action_set` (inline Usages string) | `lib/promrelabel` | DIRECTLY AFFECTED | Enumerates valid actions; must list `trim` so the annotation stays accurate per DSL requirement that annotations must be sufficient for implementation |
| `docs/victoriametrics/relabeling.md` "Relabeling Enhancements" section | N/A (external doc, not a `.goga/usages` file) | DIRECTLY AFFECTED (per explicit ticket requirement, outside CODEMANIFEST system) | Ticket requirement (5) explicitly asks for a short doc entry describing the new action |

## Rejected Hypotheses
- **Hypothesis: implement trimming via a new field/option on the existing `replace` action instead of a new top-level action.** Rejected — ticket explicitly requires configuration "mirroring how existing rules that transform a label value ... are configured (i.e. via source label(s) and a target label)", which is precisely the `uppercase`/`lowercase` shape, not a `replace` variant. Overloading `replace` would also violate "no changes to existing relabeling behavior."
- **Hypothesis: this change could require touching `app/vmagent`/`app/vminsert` remotewrite wrapper cells to "enable" the new action for remote-write.** Rejected — traced call flow shows these wrappers call the shared `ParseRelabelConfigs`/`ParsedConfigs.Apply` facade with no per-action logic of their own; the action becomes available identically on both paths purely by being added to `lib/promrelabel`.
- **Hypothesis: a new action requires a new exported type or CODEMANIFEST Entity/Routine.** Rejected — `uppercase`/`lowercase` introduced no new manifest-level type when they were added (only the inline `action_set` string documents them); `trim` follows the same precedent, confirmed by CODEMANIFEST's current structure containing zero per-action type entries.

## Confirmed Root Cause
Not a bug fix — a net-new additive feature. The implementation surface is exactly two Go `switch` statements in `lib/promrelabel` (validation in `config.go:260-394`, execution in `relabel.go:173-430`) plus one inline CODEMANIFEST string and one doc-file addition, with test coverage added via the pre-existing `f` closure harnesses in `config_test.go` (`TestParseRelabelConfigsFailure`, line 201) and `relabel_test.go` (`TestParsedConfigsApply`-style harness, `f(config, metric, isFinalize, resultExpected string)`).

## Confidence Level
**HIGH** — every code location, existing pattern, and test harness signature was read directly from source (not inferred), and the `uppercase`/`lowercase` precedent is byte-for-byte analogous to the requested `trim` behavior (join source labels → transform → set target label), with identical validation requirements (`source_labels` and `target_label` both required).

## Breaking Change Assessment
1. Will existing function call with same arguments produce different behavior? **NO** — `trim` is a new `case` value; all existing `case` branches (`replace`, `uppercase`, `lowercase`, etc.) are untouched, and the `default:` panic branch only fires for genuinely unknown actions, which `trim` no longer is once added — this only affects configs that previously would have errored with "unknown `action`" for `action: trim`, which is not existing supported behavior.
2. Will existing file paths change? **NO** — no files renamed or moved; only new `case` blocks and one appended enum entry in existing files.
3. Will output format change? **NO** — `LabelsToString`, `DebugStep`, and all other output-producing code paths are untouched.
4. Will return value semantics change? **NO** — `parseRelabelConfig` and `apply` keep identical signatures; only a new branch is added to each switch.
5. Will manifest-defined guarantees be altered? **NO** — the only manifest edit is appending `trim` to the `action_set` enumeration string; no existing guarantee text is removed or contradicted.
6. Will existing tests break? **NO** — new test cases are additive (`f(...)` calls appended to existing test functions); no existing assertions are modified.

**No breaking change detected.** Pipeline may proceed to Planning.

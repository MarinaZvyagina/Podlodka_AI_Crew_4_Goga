# R05-TA-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: False
Cost: $0.6737697
Duration: 71080ms, turns: 27

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a new relabel action (working name `trim`) to the shared relabeling engine that strips leading/trailing whitespace from a value computed from `source_labels`, storing the result into `target_label` — following the same configuration shape as the existing `uppercase`/`lowercase` actions. Because scrape-time (`relabel_configs`) and remote-write relabeling both compile and execute through the same engine, a single change to this shared engine satisfies both. Misconfiguration (e.g. missing `target_label`) must fail config parsing with a clear error, consistent with existing validation for `uppercase`/`lowercase`. No existing action's behavior may change. The change must include a short docs entry and a unit test.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| lib/promrelabel | Owns `RelabelConfig` (YAML shape), `parseRelabelConfig` (validation), and `parsedRelabelConfig.apply` (execution) — the action_set, its validation, and its runtime behavior all live here | High |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| lib/promrelabel | Sole owner of the action_set and its parse/apply logic; this is where the new action is declared, validated, and executed |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| lib/promscrape | Consumes `ParsedConfigs.Apply`/`LoadRelabelConfigs` opaquely; dispatches to whatever actions `lib/promrelabel` recognizes without action-specific logic — no code change needed, purely transitive benefit |
| app/vmagent | Its `remotewrite`/relabel wrapper subpackage compiles the same `RelabelConfig` YAML through `lib/promrelabel`; no action-specific logic to touch — transitive benefit only |
| app/vminsert | Same as app/vmagent — relabel wrapper is a pass-through to `lib/promrelabel`; no behavioral participation in adding a new action |
| app/vmselect, app/vmstorage, lib/storage, lib/mergeset | No relationship to relabeling; unaffected by this change |
| lib/promscrape/discovery/kubernetes | Service-discovery label production, not relabel action execution; irrelevant to this task |

## Usage Relationships

| Usage | Relevance |
|---|---|
| `action_set` (lib/promrelabel/CODEMANIFEST) | Must be updated to list the new action name — this is the canonical enumeration of recognized actions referenced by the manifest's own Annotations |

## Semantic Participation Summary
Only `lib/promrelabel` participates behaviorally. It owns the full lifecycle of a relabel action: the YAML config struct (`RelabelConfig`), the per-action validation switch in `parseRelabelConfig` (config.go), and the per-action execution switch in `parsedRelabelConfig.apply` (relabel.go). Since scrape-time and remote-write relabeling both funnel through `ParsedConfigs` compiled by this cell, adding the action here transparently covers both surfaces without touching `lib/promscrape`, `app/vmagent`, or `app/vminsert`. Documentation for relabeling actions lives outside the cell forest (in `docs/`), so the docs entry is a non-cell documentation change made alongside the cell change, not a CODEMANIFEST-governed contract change.

## Final Investigation Scope
- lib/promrelabel (config.go, relabel.go, CODEMANIFEST, relabel_test.go)
- docs/ relabeling reference (non-cell, plain documentation update)

## Scope Risks
- **Under-scoping risk**: low — the action dispatch pattern is fully centralized; no other cell branches on individual action names.
- **Over-scoping risk**: would be introduced by unnecessarily touching `lib/promscrape` or the `app/vmagent`/`app/vminsert` relabel wrappers, which require zero changes since they treat the action set opaquely.
- **Docs risk**: the relabeling documentation lives outside the CODEMANIFEST forest; must locate the correct existing doc (mirroring where `uppercase`/`lowercase` are already documented) rather than inventing a new doc location.

## Notes
The existing `uppercase`/`lowercase` actions in config.go (validation, lines ~381-387) and relabel.go (execution, lines ~411-426) are the direct structural template for this addition — same validation rule (`source_labels` and `target_label` both required) and same execution shape (`concatLabelValues` → transform → `setLabelValue`). This confirms the change is additive and localized to a single `case` arm in each switch statement, with no modification to shared helper functions.

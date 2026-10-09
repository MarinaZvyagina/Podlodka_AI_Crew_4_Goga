# R03-TA-BF-08

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: True
Cost: $0.8309262
Duration: 137821ms, turns: 34

## Agent's own summary

# Change Plan

## Task Classification
**Extension** — additive new HTTP exception subclass following an existing, fully-documented pattern within its cell.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `packages/common/exceptions` | `too-many-requests.exception.ts` (new), `index.ts` (add export line) | New `TooManyRequestsException` class bound to `HttpStatus.TOO_MANY_REQUESTS` (429); re-exported from the cell facade |
| `packages/common/test/exceptions` | `too-many-requests.exception.spec.ts` (new) | Test coverage mirroring `conflict.exception.spec.ts` |

No other cells are touched (per Scope Resolution Report — `core/router` and both platform adapters depend only on the `HttpException` base contract or specific unrelated subclasses).

## Root Cause Analysis
Gap, not a bug: `HttpStatus.TOO_MANY_REQUESTS = 429` exists in the enum but no concrete `HttpException` subclass binds to it, forcing callers to hand-construct `new HttpException(body, 429)`.

## Trace Summary
`objectOrError`/`descriptionOrOptions` → `HttpException.extractDescriptionAndOptionsFrom` → `HttpException.createBody` → `super(body, status, options)` → `HttpException` sets `message`/`name`/`cause`/`errorCode`, exposes via `getResponse()`/`getStatus()`. Identical to every sibling (`ConflictException` traced as proxy). No other code path touches this class by name.

## Change Strategy
1. Create `packages/common/exceptions/too-many-requests.exception.ts`: `TooManyRequestsException extends HttpException`, JSDoc copied/adapted from `ConflictException` (429 / "Too Many Requests" substituted throughout), default `descriptionOrOptions = 'Too Many Requests'`, body built via `HttpException.createBody(objectOrError, description, HttpStatus.TOO_MANY_REQUESTS)`.
2. Add `export * from './too-many-requests.exception.js';` to `packages/common/exceptions/index.ts`, alphabetically positioned (after `service-unavailable.exception.js`, before `unauthorized.exception.js`).
3. Create `packages/common/test/exceptions/too-many-requests.exception.spec.ts`, structurally identical to `conflict.exception.spec.ts` (status code, default message, custom message, custom body object, cause option, `instanceof HttpException`/`Error`).
4. No CODEMANIFEST body edit (see Specification Impact below).

## Specification Impact
No CODEMANIFEST body entry is added. Evidence: the manifest documents `BadRequestException` in full as the canonical example and its annotation explicitly generalizes — "Every other concrete exception in this directory... follows this identical constructor shape and status-code binding pattern" — over an already-open set. The header `types` list (7 entries) is confirmed, via `goga schema`, to already omit multiple existing siblings that share this exact pattern (`ConflictException`, `GoneException`, `PayloadTooLargeException`, etc. have no body entries either). Giving `TooManyRequestsException` a dedicated entry while its structural twins have none would be an inconsistent, unrequested documentation change to unrelated pre-existing types — out of scope and against the cookbook's "annotations must not duplicate" guidance, since the generalizing annotation already covers it. The global `Annotations` section (mutation-chain description) and `Description` footer remain accurate without edits — both describe the pattern in general terms, not by exhaustive enumeration.

## Usage Impact
None — the cell declares no `Usages`/`Imports`; no `.usages/*.md` files exist to update.

## Compatibility Verification
**Backward compatible.** New file, new export, new test file only. No existing class, export ordering (barring the alphabetical insertion, which is append-only and non-breaking for named ES module exports), or test is modified.

## Test Strategy
New spec file asserting, matching sibling coverage exactly:
- `getStatus()` returns 429
- default response body is `{ message: 'Too Many Requests', statusCode: 429 }`
- custom string message produces `{ message, error: 'Too Many Requests', statusCode: 429 }`
- custom object replaces the entire body verbatim
- `{ cause }` option is captured on `.cause`
- instance is `instanceof HttpException` and `instanceof Error`

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Alphabetical export placement missed, causing lint/style inconsistency | Low | Low | Insert per existing sort order in `index.ts`, verify with a diff read after edit |
| Spec drifts from sibling test conventions (naming, describe block) | Low | Low | Copy `conflict.exception.spec.ts` structure verbatim, substitute status/message only |
| CODEMANIFEST reviewers expect a body entry | Low | Low | Reasoning documented above; reversible — an entry can be added later without conflict if convention changes |

---

Do you approve the plan? Proceed to implementation?

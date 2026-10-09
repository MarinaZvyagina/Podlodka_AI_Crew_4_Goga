# R03-TA-BF-04

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: True
Cost: $1.2653061000000003
Duration: 167659ms, turns: 45

## Agent's own summary

# Change Plan

## Task Classification
**Extension** — additive, non-breaking new sibling type in an existing, well-established hierarchy.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `packages/common/exceptions` | `too-many-requests.exception.ts` (new), `index.ts` (add one export line) | New `TooManyRequestsException extends HttpException` class bound to `HttpStatus.TOO_MANY_REQUESTS` (429), default message `'Too Many Requests'`; new export line inserted alphabetically |
| `packages/common/test/exceptions` (non-cell, test directory) | `too-many-requests.exception.spec.ts` (new) | Unit test suite mirroring `conflict.exception.spec.ts` |

## Root Cause Analysis
No existing file implements HTTP 429 despite `HttpStatus.TOO_MANY_REQUESTS` already existing in the enum and 20+ sibling status codes already having dedicated exception classes. Users currently must fall back to `new HttpException(msg, 429)`, losing the consistent default-message/JSDoc/constructor ergonomics every other common status code gets. Fix: add one new file following the uniform pattern.

## Trace Summary
Construction: `new TooManyRequestsException()` → `HttpException.extractDescriptionAndOptionsFrom()` → `HttpException.createBody()` → `super(body, 429, options)` → base `HttpException` lifecycle (`initMessage`/`initName`/`initCause`/`initErrorCode`) — identical to `ConflictException`/`GoneException`. Consumption: `BaseExceptionFilter.catch()` dispatches purely via `instanceof HttpException` + `getStatus()`/`getResponse()`, with no per-status branching — confirmed in `packages/core/exceptions/base-exception-filter.ts:26-48`. No cross-cell code changes required.

## Change Strategy
1. Create `packages/common/exceptions/too-many-requests.exception.ts`, copying the structure of `gone.exception.ts` verbatim in shape:
   - Import `HttpStatus` from `../enums/http-status.enum.js` and `HttpException`, `HttpExceptionOptions` from `./http.exception.js`.
   - Class `TooManyRequestsException extends HttpException`.
   - JSDoc: class-level doc block ("Defines an HTTP exception for *Too Many Requests* type errors", `@see` link, `@publicApi`), constructor-level doc block (`@example throw new TooManyRequestsException()`, `@usageNotes` describing status 429, default message `'Too Many Requests'`, `@param` tags) — matching `ConflictException`/`GoneException` wording pattern exactly, substituting "Too Many Requests" / 429 / `TOO_MANY_REQUESTS`.
   - Constructor signature: `(objectOrError?: any, descriptionOrOptions: string | HttpExceptionOptions = 'Too Many Requests')`, destructuring `description`/`httpExceptionOptions` via `HttpException.extractDescriptionAndOptionsFrom`, then `super(HttpException.createBody(objectOrError, description, HttpStatus.TOO_MANY_REQUESTS), HttpStatus.TOO_MANY_REQUESTS, httpExceptionOptions)`.
2. Insert `export * from './too-many-requests.exception.js';` into `packages/common/exceptions/index.ts` in alphabetical position — between `service-unavailable.exception.js` (line 20) and `unauthorized.exception.js` (line 21), since `t` sorts after `s` and before `u`.
3. Create `packages/common/test/exceptions/too-many-requests.exception.spec.ts`, copying `conflict.exception.spec.ts` structure: status-code assertion (429), default-message assertion (`'Too Many Requests'`), custom-message assertion, custom-object assertion, cause-option assertion, `instanceof HttpException`/`Error` assertion.

No other files change.

## Specification Impact
None. Per the established precedent (`ConflictException`, `GoneException`, and 18 other siblings are implemented but not individually enumerated in the CODEMANIFEST body or in `goga schema`'s `types` list — the manifest generalizes the constructor algorithm once under `BadRequestException` and explicitly defers to "the remaining status-code exceptions"), no CODEMANIFEST body edit is required. This will be re-verified mechanically in Step 7 (Manifest Reconciliation) rather than assumed.

## Usage Impact
None. The cell has zero `.usages` entries and no `codemanifest.usages`/`codemanifest.annotations` project-level config exists (`goga config codemanifest.usages` → "Option not found"). No usage files exist to update.

## Compatibility Verification
**Backward compatible.** No existing file's behavior, exports, or output format changes. `index.ts` gains one additive export line only; insertion point does not reorder or touch existing lines beyond the single insertion. No existing test is modified.

## Test Strategy
Add `packages/common/test/exceptions/too-many-requests.exception.spec.ts` with the same six assertions `conflict.exception.spec.ts` uses, adapted to 429/`'Too Many Requests'`:
1. `getStatus()` returns `429`
2. Default `getResponse()` equals `{ message: 'Too Many Requests', statusCode: 429 }`
3. Custom string message → `{ message: 'Custom error', error: 'Too Many Requests', statusCode: 429 }`
4. Custom object passthrough → `{ foo: 'bar' }`
5. `{ cause }` option → `exc.cause === cause`
6. `instanceof HttpException` and `instanceof Error`

This matches existing sibling test coverage depth exactly — no more, no less. No integration/e2e test is added since no sibling exception has one and the generic exception-filter behavior (uncaught → correct status code) is already covered by the shared `BaseExceptionFilter`/`HttpException` code path, not per-exception-class tests.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Alphabetical export-order drift (repo may enforce sorted exports via lint) | Low | Low | Insert at the alphabetically correct position (`s` < `t` < `u`); verify with `goga lint` / project lint in Step 6 |
| Mismatched JSDoc wording vs. sibling convention | Low | Low | Copy `gone.exception.ts` structure verbatim, substituting only the status name/code |
| Test suite naming/description drift from sibling pattern | Low | Low | Copy `conflict.exception.spec.ts` structure verbatim, substituting only the status name/code |

---

Do you approve the plan? Proceed to implementation?

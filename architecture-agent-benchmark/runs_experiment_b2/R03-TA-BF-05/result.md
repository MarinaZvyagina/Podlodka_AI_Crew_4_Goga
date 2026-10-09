# R03-TA-BF-05

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $0.8636417999999998
Duration: 126595ms, turns: 32

## Agent's own summary

# Change Plan

## Task Classification
Extension (additive, non-breaking) — new built-in HTTP exception type.

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `packages/common/exceptions` | `too-many-requests.exception.ts` (new), `index.ts` | New `TooManyRequestsException` class; new export line |
| N/A (undocumented) | `packages/common/utils/http-error-by-code.util.ts` | Add `HttpStatus.TOO_MANY_REQUESTS` to `ErrorHttpStatusCode` union and `HttpErrorByCode` map |
| N/A (undocumented, test dir) | `packages/common/test/exceptions/too-many-requests.exception.spec.ts` (new) | Test coverage mirroring `conflict.exception.spec.ts` |

## Root Cause Analysis
No subclass implements `HttpStatus.TOO_MANY_REQUESTS` (429), forcing callers to hand-construct `HttpException` with a raw status code — inconsistent with every other common status code, which has a dedicated class.

## Trace Summary
Constructor flow: `(objectOrError?, descriptionOrOptions = 'Too Many Requests')` → `HttpException.extractDescriptionAndOptionsFrom` → `HttpException.createBody(objectOrError, description, HttpStatus.TOO_MANY_REQUESTS)` → `super(body, HttpStatus.TOO_MANY_REQUESTS, httpExceptionOptions)`. No other cell (router, adapters) needs modification — they handle `HttpException` generically.

## Change Strategy
1. Create `packages/common/exceptions/too-many-requests.exception.ts`: `TooManyRequestsException extends HttpException`, default description `'Too Many Requests'`, JSDoc matching `ConflictException`'s style (`@usageNotes` block states status 429).
2. Add `export * from './too-many-requests.exception.js';` to `index.ts`, alphabetically between `service-unavailable` and `unauthorized`.
3. Create `packages/common/test/exceptions/too-many-requests.exception.spec.ts` mirroring `conflict.exception.spec.ts`'s 6 test cases (status code, default message, custom message, custom object, cause option, `instanceof` checks), substituting 429/`Too Many Requests`.
4. Add `HttpStatus.TOO_MANY_REQUESTS` to `ErrorHttpStatusCode` union (alphabetical, after `SERVICE_UNAVAILABLE`, before `UNAUTHORIZED`) and `[HttpStatus.TOO_MANY_REQUESTS]: TooManyRequestsException` to the `HttpErrorByCode` map (same position), plus the corresponding import in that file.
5. CODEMANIFEST: no body entry needed — the existing `BadRequestException` entry's annotation already generalizes to "every other concrete exception in this directory... follows this identical constructor shape and status-code binding pattern," which covers the new class exactly as it covers `ConflictException`/`GoneException` today. No header/footer change needed either (no new imports, no new usages introduced).

## Specification Impact
None required. The generalization clause in the existing `BadRequestException` manifest entry already covers this addition by design — adding a redundant per-file entry would contradict the manifest's own stated intent to describe the pattern once. Reconciliation step will confirm this is still accurate post-implementation (i.e., the new file doesn't deviate from the documented shape).

## Usage Impact
None — cell has no `.usages/` directory and no header `Usages`/`Imports`.

## Compatibility Verification
Backward compatible. No existing export, signature, or behavior is modified — only new files and additive lines in `index.ts` and `http-error-by-code.util.ts`.

## Test Strategy
Mirror `conflict.exception.spec.ts` exactly for `TooManyRequestsException`:
- default status code 429
- default response body `{ message: 'Too Many Requests', statusCode: 429 }`
- custom string message → adds `error: 'Too Many Requests'`
- custom object → used verbatim as body
- `cause` option propagation
- `instanceof HttpException` / `instanceof Error`

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Doc-style drift from siblings (wrong default message casing, wrong status) | Low | Low | Copy `ConflictException` structure verbatim, substitute only name/status/message |
| Missed alphabetical placement in `index.ts`/util file | Low | Very Low (cosmetic) | Explicit placement verified against existing file ordering before editing |
| `http-error-by-code.util.ts` edit treated as in-scope for a cell it doesn't belong to | Low | Very Low | Explicitly justified in scope resolution — task explicitly requested it for consistency |

Do you approve the plan? Proceed to implementation?

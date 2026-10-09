# R03-TA-BF-09

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: True
Cost: $0.9346977000000001
Duration: 155944ms, turns: 35

## Agent's own summary

# Change Plan

## Task Classification
**Feature** — additive extension of an existing, well-established pattern (one new concrete `HttpException` subclass).

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `packages/common/exceptions` | `too-many-requests.exception.ts` (new), `index.ts` (edit) | New `TooManyRequestsException` class extending `HttpException`; new export line inserted alphabetically |
| `packages/common/test/exceptions` | `too-many-requests.exception.spec.ts` (new) | Test suite mirroring `conflict.exception.spec.ts` |

## Root Cause Analysis
Feature gap, not a defect: `HttpStatus.TOO_MANY_REQUESTS = 429` already exists; the generic `HttpException` base fully supports it, but no purpose-built subclass exists, forcing consumers to hand-construct `HttpException(body, 429)`. Confirmed HIGH confidence, no breaking change.

## Trace Summary
Throw site → `TooManyRequestsException` constructor → `HttpException.extractDescriptionAndOptionsFrom(descriptionOrOptions)` → `HttpException.createBody(objectOrError, description, HttpStatus.TOO_MANY_REQUESTS)` → `super(body, status, options)` → `IntrinsicException`/`HttpException` base sets `message`/`name`/`cause`/`errorCode` → router/platform-adapter exception handling calls `getStatus()`/`getResponse()` to produce the HTTP response. Identical path to `ConflictException`/`GoneException`; no other cell touches this path.

## Change Strategy
1. Create `packages/common/exceptions/too-many-requests.exception.ts`, copying the structure of `conflict.exception.ts` verbatim except: class name `TooManyRequestsException`, JSDoc description "*Too Many Requests*", default description/message `'Too Many Requests'`, status `HttpStatus.TOO_MANY_REQUESTS`, doc comment "will be 429" / "value 429".
2. Insert `export * from './too-many-requests.exception.js';` into `index.ts` in alphabetical position — between `service-unavailable.exception.js` and `unauthorized.exception.js`.
3. Create `packages/common/test/exceptions/too-many-requests.exception.spec.ts`, copying `conflict.exception.spec.ts`'s six test cases (status code, default message, custom message, custom object body, cause option, `instanceof HttpException`/`Error`) with `TooManyRequestsException` / 429 / `'Too Many Requests'` substituted.
4. No changes to `http.exception.ts`, the enum, or any other subclass.

## Specification Impact
None. CODEMANIFEST's `BadRequestException::HttpException` entry already states "the remaining status-code exceptions... follow this identical constructor shape and status-code binding pattern," which already covers this addition the same way it silently covers `ConflictException`/`GoneException`/etc. today. No CODEMANIFEST edit is required to remain accurate; adding a dedicated entry would create an inconsistency (singling this one status code out from ~17 undocumented siblings).

## Usage Impact
None — the cell has no `Usages` directive and no `.usages/` directory; nothing to update.

## Compatibility Verification
**Backward compatible.** Purely additive: one new file, one new export line, one new test file. No existing export, class, signature, or test is modified.

## Test Strategy
Mirror `conflict.exception.spec.ts` exactly for behavioral parity:
- `getStatus()` returns 429
- default `getResponse()` body is `{ message: 'Too Many Requests', statusCode: 429 }`
- custom string message produces `{ message, error: 'Too Many Requests', statusCode: 429 }`
- custom object body passed through verbatim
- `{ cause }` option surfaces on `exc.cause`
- instance is `instanceof HttpException` and `instanceof Error`

This covers all four required behaviors from the task: default message, message/body override, description-or-options pattern, and correct status code end-to-end (via `getStatus()`, which is what router/adapters use to set the actual HTTP response code).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Alphabetical ordering mistake in `index.ts` | Low | Cosmetic only (no functional effect either way) | Verify placement between `service-unavailable` and `unauthorized` entries |
| Divergence from sibling pattern (e.g., wrong default message casing) | Low | Inconsistent API surface | Copy `conflict.exception.ts` structurally and only substitute status-specific tokens |
| `goga lint` flags an undocumented type | Low | Would require manifest update | Manifest text already generalizes over remaining exceptions; re-run `goga lint` after implementation to confirm |

Do you approve the plan? Proceed to implementation?

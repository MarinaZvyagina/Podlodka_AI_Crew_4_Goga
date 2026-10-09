# R03-TA-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $1.0073277
Duration: 141610ms, turns: 35

## Agent's own summary

Confirmed strict alphabetical ordering. `too-many-requests.exception.js` slots between `service-unavailable` and `unauthorized`.

# Change Plan

## Task Classification
**Type: feature (extension)** — additive new HTTP exception subclass, no modification to existing behavior.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `packages/common/exceptions` | `too-many-requests.exception.ts` (new), `index.ts` (add one export line), `CODEMANIFEST` (add one type entry) | New `TooManyRequestsException` class, barrel export, manifest documentation |
| `packages/common/test/exceptions` | `too-many-requests.exception.spec.ts` (new) | Test coverage matching sibling spec pattern |

## Root Cause Analysis
No dedicated exception class exists for HTTP 429. `HttpStatus.TOO_MANY_REQUESTS` already exists in the enum, but application code must currently hand-construct `new HttpException(body, 429)`, unlike every other common status code which has a purpose-built subclass. Fix: add `TooManyRequestsException` following the exact template used by `BadRequestException`/`ConflictException`/`NotFoundException`.

## Trace Summary
`TooManyRequestsException` constructor → `HttpException.extractDescriptionAndOptionsFrom(descriptionOrOptions)` → `HttpException.createBody(objectOrError, description, HttpStatus.TOO_MANY_REQUESTS)` → `super(body, HttpStatus.TOO_MANY_REQUESTS, httpExceptionOptions)`. No shared code (`HttpException`, `IntrinsicException`, `HttpStatus` enum) requires modification — 429 already defined at `http-status.enum.ts:50`.

## Change Strategy
1. Create `packages/common/exceptions/too-many-requests.exception.ts`: copy `conflict.exception.ts` structure verbatim, renaming `ConflictException` → `TooManyRequestsException`, `'Conflict'` → `'Too Many Requests'`, `HttpStatus.CONFLICT` → `HttpStatus.TOO_MANY_REQUESTS`, and updating JSDoc (class description, `@example`, status code references 409→429, message references).
2. Insert `export * from './too-many-requests.exception.js';` into `index.ts` between `service-unavailable.exception.js` and `unauthorized.exception.js` (alphabetical order preserved).
3. Create `packages/common/test/exceptions/too-many-requests.exception.spec.ts`: copy `conflict.exception.spec.ts`, renaming the class and expected values (429 / `'Too Many Requests'`).
4. Insert one new body entry into `CODEMANIFEST` after `HttpException::InternalServerErrorException`, in the same one-line style as `UnauthorizedException`/`ForbiddenException`/`NotFoundException` entries: `"HttpException::TooManyRequestsException(objectOrError: any, descriptionOrOptions: string | Object<string, any>)"` with annotation `429 Too Many Requests, constructed identically to \`BadRequestException\`.`

## Specification Impact
`CODEMANIFEST` body section gains exactly one new type entry (no existing entries edited). The header's `Annotations` and the `BadRequestException` entry's narrative ("every other concrete exception... follows this identical pattern") already generalize to cover the new type — no header changes needed.

## Usage Impact
None — this cell declares no `Usages` and has no `.usages/` directory to update.

## Compatibility Verification
**Backward compatible.** No existing file is modified in a way that changes behavior — only one new export line is added to `index.ts`, and one new node is added to `CODEMANIFEST`'s body. All existing exceptions, exports, and tests remain byte-for-byte unchanged.

## Test Strategy
New spec file mirrors `conflict.exception.spec.ts` exactly in shape, covering:
- default status code (429)
- default message body (`{ message: 'Too Many Requests', statusCode: 429 }`)
- custom string message (adds `error: 'Too Many Requests'`)
- custom object body override (used verbatim)
- `cause` option propagation
- `instanceof HttpException` / `instanceof Error`

This matches existing sibling coverage exactly — no gaps, no extra scope.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Alphabetical placement in `index.ts` incorrect, causing lint/style drift | Low | Low | Verified exact alphabetical slot (`service-unavailable` < `too-many-requests` < `unauthorized`) before editing |
| Manifest entry style diverges from siblings | Low | Low | Copying exact one-line annotation phrasing used by `UnauthorizedException`/`ForbiddenException` entries |
| Test expectations mismatch actual `HttpException.createBody` behavior | Low | Medium | Pattern copied 1:1 from a passing existing spec (`ConflictException`), only substituting status/message |

---

Do you approve the plan? Proceed to implementation?

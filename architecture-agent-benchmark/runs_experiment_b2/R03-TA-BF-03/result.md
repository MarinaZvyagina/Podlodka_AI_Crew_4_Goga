# R03-TA-BF-03

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $1.1526534000000002
Duration: 143756ms, turns: 41

## Agent's own summary

# Change Plan

## Task Classification
**Feature (extension)** — additive new sibling class within an established, well-documented pattern family; no modification to existing behavior.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `packages/common/exceptions` | `too-many-requests.exception.ts` (new), `index.ts` (edit), `CODEMANIFEST` (edit) | New `TooManyRequestsException` class; new facade export; manifest entry documenting the new type |
| `packages/common/test/exceptions` | `too-many-requests.exception.spec.ts` (new) | New spec file covering the new class |

## Root Cause Analysis
No `HttpException` subclass currently binds to `HttpStatus.TOO_MANY_REQUESTS` (429). Callers must hand-construct `new HttpException(msg, 429)`, which is verbose and inconsistent with how every other common status code is handled. The manifest's `BadRequestException` annotation explicitly states remaining status-code exceptions follow its identical constructor shape and status-code binding pattern — this class was simply never added.

## Trace Summary
- Constructor path: `objectOrError`, `descriptionOrOptions` → `HttpException.extractDescriptionAndOptionsFrom` → `{description, httpExceptionOptions}` → `HttpException.createBody(objectOrError, description, HttpStatus.TOO_MANY_REQUESTS)` → `super(body, 429, httpExceptionOptions)`.
- Uncaught propagation: `base-exception-filter.ts` reads `exception.getStatus()` / `exception.getResponse()` generically — new class needs no changes there, confirmed non-breaking and self-sufficient.

## Change Strategy
1. Create `packages/common/exceptions/too-many-requests.exception.ts`: `TooManyRequestsException extends HttpException`, default description `'Too Many Requests'`, status `HttpStatus.TOO_MANY_REQUESTS`, byte-for-byte structural match to `conflict.exception.ts` (imports, JSDoc shape — class-level doc, `@example`, `@usageNotes` block, `@param` tags — constructor body calling `extractDescriptionAndOptionsFrom` then `super(createBody(...), HttpStatus.TOO_MANY_REQUESTS, httpExceptionOptions)`).
2. Add `export * from './too-many-requests.exception.js';` to `index.ts`, keeping the existing alphabetical ordering (falls after `service-unavailable`, before `unauthorized` — verify exact position against current file content since NestJS's own alphabetization is by full class/file name).
3. Add `packages/common/test/exceptions/too-many-requests.exception.spec.ts`, structurally mirroring `conflict.exception.spec.ts`: status-code check, default-message check, custom-message check (with `error` field), custom-object-body check, cause-option check, `instanceof HttpException`/`Error` check.
4. Add a manifest entry for `TooManyRequestsException` in `packages/common/exceptions/CODEMANIFEST`, matching the style of the existing `ForbiddenException`/`NotFoundException` entries (short annotation referencing `BadRequestException`'s canonical pattern), to keep the manifest's documented sample current with the newly added type — optional per Investigation Report (manifest is already a non-exhaustive sample) but included for documentation completeness and consistency with the "matching documentation style" requirement.

## Specification Impact
`packages/common/exceptions/CODEMANIFEST` body gains one new type-declaration block: `"HttpException::TooManyRequestsException(objectOrError: any, descriptionOrOptions: string | Object<string, any>)"`, `location: too-many-requests.exception.ts`, annotation: `429 Too Many Requests, constructed identically to BadRequestException.` No existing manifest entries change; no algorithm text is altered.

## Usage Impact
None. Cell has no `.usages` directory and declares no `Usages`/`Imports` — confirmed in Investigation Report. No usage files exist to update.

## Compatibility Verification
**Backward compatible.** No existing file is modified in a way that changes behavior: `index.ts` only gains one new export line; `CODEMANIFEST` only gains one new type block, none of which alters the meaning of any existing block. No existing public API signature, return format, or test changes. Confirmed via Investigation Report's Breaking Change Assessment (all six questions answered NO).

## Test Strategy
Add one spec file (`too-many-requests.exception.spec.ts`) covering, matching sibling coverage exactly:
- `getStatus()` returns 429
- default `getResponse()` body is `{ message: 'Too Many Requests', statusCode: 429 }`
- custom string message produces `{ message, error: 'Too Many Requests', statusCode: 429 }`
- custom object replaces the entire response body verbatim
- `descriptionOrOptions` as `{ cause }` sets `exc.cause`
- instance is `instanceof HttpException` and `instanceof Error`

No modification to existing test files; no integration/e2e test needed since no existing e2e suite tests individual exception classes (confirmed in earlier research — only `HttpErrorByCode`-consuming pipes have such coverage, out of scope).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Incorrect alphabetical placement in `index.ts` breaks convention (not correctness) | Low | Low | Read current `index.ts` content immediately before editing; insert in correct sorted position |
| Manifest entry drifts from actual implementation wording | Low | Low | Copy exact phrasing pattern from existing `ForbiddenException`/`NotFoundException` entries, substitute status code/name only |
| Test expectations diverge from actual `createBody` behavior (e.g. `error` field only present with custom message, not default) | Low | Medium | Mirror `conflict.exception.spec.ts` assertions exactly, which are already verified against `createBody`'s real branching logic |

---

Do you approve the plan? Proceed to implementation?

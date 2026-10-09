# R03-TA-GC-02

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: True
Cost: $1.0584951000000002
Duration: 170445ms, turns: 36

## Agent's own summary

# Change Plan

## Task Classification
**Type: extension** (additive — new sibling exception class in an existing, closed hierarchy; no existing code is modified)

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `packages/common/exceptions` | `too-many-requests.exception.ts` (new), `index.ts` (append 1 export line), `CODEMANIFEST` (append 1 body entry) | New `TooManyRequestsException` class + its export + its manifest documentation |
| `packages/common/test/exceptions` | `too-many-requests.exception.spec.ts` (new) | New test spec mirroring sibling coverage |

## Root Cause Analysis
Confirmed via Investigation Report: `packages/common/exceptions` implements one concrete `HttpException` subclass per common status code but has none bound to `HttpStatus.TOO_MANY_REQUESTS` (429, already defined in `packages/common/enums/http-status.enum.ts:50`). This forces callers to hand-construct a generic `HttpException` with the raw status code. Confidence: HIGH, purely additive, no breaking change.

## Trace Summary
Every sibling subclass funnels through the same chain: constructor → `HttpException.extractDescriptionAndOptionsFrom(descriptionOrOptions)` → `HttpException.createBody(objectOrError, description, status)` → `super(body, status, httpExceptionOptions)`. `TooManyRequestsException` will instantiate this identical chain bound to `HttpStatus.TOO_MANY_REQUESTS` and default message `'Too Many Requests'`. No shared/mutable state is touched; no other cell (`core/router`, platform adapters) enumerates or needs to reference this new class.

## Change Strategy

1. **Create `packages/common/exceptions/too-many-requests.exception.ts`**, modeled byte-for-byte on `service-unavailable.exception.ts`'s structure:
   ```ts
   import { HttpStatus } from '../enums/http-status.enum.js';
   import { HttpException, HttpExceptionOptions } from './http.exception.js';

   /**
    * Defines an HTTP exception for *Too Many Requests* type errors.
    *
    * @see [Built-in HTTP exceptions](https://docs.nestjs.com/exception-filters#built-in-http-exceptions)
    *
    * @publicApi
    */
   export class TooManyRequestsException extends HttpException {
     /**
      * Instantiate a `TooManyRequestsException` Exception.
      *
      * @example
      * `throw new TooManyRequestsException()`
      *
      * @usageNotes
      * The HTTP response status code will be 429.
      * - The `objectOrError` argument defines the JSON response body or the message string.
      * - The `descriptionOrOptions` argument contains either a short description of the HTTP error or an options object used to provide an underlying error cause.
      *
      * By default, the JSON response body contains two properties:
      * - `statusCode`: this will be the value 429.
      * - `message`: the string `'Too Many Requests'` by default; override this by supplying
      * a string in the `objectOrError` parameter.
      *
      * If the parameter `objectOrError` is a string, the response body will contain an
      * additional property, `error`, with a short description of the HTTP error. To override the
      * entire JSON response body, pass an object instead. Nest will serialize the object
      * and return it as the JSON response body.
      *
      * @param objectOrError string or object describing the error condition.
      * @param descriptionOrOptions either a short description of the HTTP error or an options object used to provide an underlying error cause
      */
     constructor(
       objectOrError?: any,
       descriptionOrOptions: string | HttpExceptionOptions = 'Too Many Requests',
     ) {
       const { description = 'Too Many Requests', httpExceptionOptions } =
         HttpException.extractDescriptionAndOptionsFrom(descriptionOrOptions);

       super(
         HttpException.createBody(
           objectOrError,
           description,
           HttpStatus.TOO_MANY_REQUESTS,
         ),
         HttpStatus.TOO_MANY_REQUESTS,
         httpExceptionOptions,
       );
     }
   }
   ```

2. **Edit `packages/common/exceptions/index.ts`** — insert `export * from './too-many-requests.exception.js';` alphabetically between `service-unavailable.exception.js` and `unauthorized.exception.js` (`s` < `t` < `u`).

3. **Edit `packages/common/exceptions/CODEMANIFEST`** — append a body entry immediately after `UnprocessableEntityException` (422) and before `NotImplementedException` (501), matching sibling terseness:
   ```yaml
   "HttpException::TooManyRequestsException(objectOrError: any, descriptionOrOptions: string | Object<string, any>)":
     location: too-many-requests.exception.ts
     annotations: |
       429 Too Many Requests, constructed identically to `BadRequestException`.
       Default message: 'Too Many Requests'.
   ```
   Also add `"TooManyRequestsException"` to the cell's `types` list wherever schema output enumerates it (this is derived by `goga schema` from the manifest body, not a separate list to hand-edit).

4. **Create `packages/common/test/exceptions/too-many-requests.exception.spec.ts`**, mirroring `service-unavailable.exception.spec.ts`: status-code check (429), default-message check, custom-message check, custom-object check, cause-option check, `instanceof HttpException`/`Error` check.

## Specification Impact
`CODEMANIFEST`'s Body section gains exactly one new type entry (`TooManyRequestsException`), following the established shorthand convention ("constructed identically to `BadRequestException`. Default message: '...'"). No existing entry is altered. Header (`Annotations`) and Footer (`Author`/`CreatedAt`/`Description`) are unchanged — the existing header annotation already generically covers "one concrete subclass per common HTTP status code," which remains accurate.

## Usage Impact
None. The cell declares no `.usages/` practices and no project-level `codemanifest.usages`/`codemanifest.annotations` exist. No usage file needs creation or modification.

## Compatibility Verification
**Backward compatible.** No existing file, export, class, or manifest entry is modified — only new additions. All 6 breaking-change questions from the Investigation Report were answered NO. Proceeding.

## Test Strategy
Add `too-many-requests.exception.spec.ts` covering, consistent with every sibling spec:
- `getStatus()` returns `429`
- default `getResponse()` body is `{ message: 'Too Many Requests', statusCode: 429 }`
- custom string message produces `{ message, error: 'Too Many Requests', statusCode: 429 }`
- custom object argument overrides the entire body verbatim
- `{ cause }` option is propagated to `exc.cause`
- instance is `instanceof HttpException` and `instanceof Error`

No modification to existing tests is needed since no existing behavior changes.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Alphabetical mis-placement in `index.ts` breaks lint/style consistency | Low | Low | Verified exact slot (`s` < `too-many-requests` < `u`) before editing |
| CODEMANIFEST entry placed in wrong numeric-status order, confusing future readers | Low | Low | Verified slot: after `UnprocessableEntityException` (422), before `NotImplementedException` (501) |
| Test spec drifts from sibling pattern (e.g. missing a case) | Low | Medium | Directly mirror `service-unavailable.exception.spec.ts` structure, only renaming class/status/message |
| Related `HttpErrorByCode` util (`packages/common/utils/http-error-by-code.util.ts`) still lacks a 429 mapping | Known, out of scope | None (pre-existing gap, already excludes several other codes) | Not touched — outside investigation scope; flagged as a possible independent follow-up, not part of this change |

Do you approve the plan? Proceed to implementation?

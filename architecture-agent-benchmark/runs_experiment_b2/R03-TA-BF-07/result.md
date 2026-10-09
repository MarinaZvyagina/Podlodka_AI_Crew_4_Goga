# R03-TA-BF-07

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Goga engagement signal: True
Cost: $1.7563779000000002
Duration: 204911ms, turns: 57

## Agent's own summary

Clean, minimal diff. Summary:

**Added** `TooManyRequestsException` (429) matching the existing sibling exceptions exactly — same constructor shape (`objectOrError`, `descriptionOrOptions`), default message `'Too Many Requests'`, cause/errorCode support via `HttpExceptionOptions`, and full JSDoc in the same style.

Files touched:
- `packages/common/exceptions/too-many-requests.exception.ts` — new exception class (modeled on `conflict.exception.ts`/`gone.exception.ts`)
- `packages/common/exceptions/index.ts` — export it
- `packages/common/test/exceptions/too-many-requests.exception.spec.ts` — new unit spec covering status, default/custom message, custom body, cause, and `instanceof` checks
- `packages/common/utils/http-error-by-code.util.ts` — added it to the `ErrorHttpStatusCode` union and `HttpErrorByCode` map (used by things like `HttpException.createBody`-adjacent code that resolves exceptions from a status code)
- `packages/common/test/utils/http-error-by-code.util.spec.ts` and `packages/common/test/exceptions/http.exception.spec.ts` — extended the existing table-driven tests to include the new exception, in the same alphabetical/status-ordered positions as its siblings

Verified: `goga lint` (0 errors), full `packages/common` test suite (706/706 passing), `tsc --noEmit`, and a manual smoke check confirming `getStatus() === 429`, correct default/custom body shape, and cause propagation. No CODEMANIFEST change was needed — the `packages/common/exceptions` cell's manifest already documents the shared constructor pattern generically ("every other concrete exception in this directory... follows this identical constructor shape and status-code binding pattern") without listing each sibling individually, so `TooManyRequestsException` is covered by that existing contract.

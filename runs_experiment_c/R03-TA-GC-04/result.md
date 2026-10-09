# R03-TA-GC-04

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Goga engagement signal: False
Cost: $0.8544077999999998
Duration: 91314ms, turns: 32

## Agent's own summary

Added `TooManyRequestsException` (429) to `packages/common/exceptions/`, matching the existing sibling exceptions exactly:

- **`too-many-requests.exception.ts`** — same constructor shape (`objectOrError`, `descriptionOrOptions`), default message `'Too Many Requests'`, supports message override, full body override, and the cause/options pattern via `HttpException.extractDescriptionAndOptionsFrom`.
- **`exceptions/index.ts`** — exported alongside the others.
- **`utils/http-error-by-code.util.ts`** — added to `ErrorHttpStatusCode` and the `HttpErrorByCode` map, so `429` resolves correctly wherever that lookup is used.
- **`exceptions/CODEMANIFEST`** — documented the new class in the cell contract, consistent with siblings.
- **Tests** — new `too-many-requests.exception.spec.ts` mirroring `forbidden.exception.spec.ts`/`not-found.exception.spec.ts` (status code, default message, custom message, custom body, cause option, `instanceof HttpException`/`Error`), plus updated `http-error-by-code.util.spec.ts` to include `HttpStatus.TOO_MANY_REQUESTS` in the expected code list.

Verified: all 258 tests in `packages/common/test/exceptions` and `test/utils` pass, and `tsc --noEmit` on `packages/common` is clean.

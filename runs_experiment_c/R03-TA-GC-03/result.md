# R03-TA-GC-03

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Goga engagement signal: False
Cost: $1.2044328
Duration: 164038ms, turns: 41

## Agent's own summary

All 706 tests pass across `packages/common`.

## Summary

Added `TooManyRequestsException` (HTTP 429) matching the pattern of the other built-in HTTP exceptions:

- **`packages/common/exceptions/too-many-requests.exception.ts`** — new class extending `HttpException`, default message `'Too Many Requests'`, same `objectOrError`/`descriptionOrOptions` constructor shape (message override, full body override, cause/options support) as `ConflictException` etc.
- **`packages/common/exceptions/index.ts`** — exported it.
- **`packages/common/utils/http-error-by-code.util.ts`** — added `HttpStatus.TOO_MANY_REQUESTS` to the `ErrorHttpStatusCode` union and the `HttpErrorByCode` map.
- **`packages/common/exceptions/CODEMANIFEST`** — documented the new class alongside its siblings.
- **Tests**: added `packages/common/test/exceptions/too-many-requests.exception.spec.ts` (mirrors `conflict.exception.spec.ts`), and extended the shared parametrized tables in `http.exception.spec.ts` and `http-error-by-code.util.spec.ts` to include it.

Ran the full `packages/common` test suite and a standalone `tsc --noEmit` — 706 tests pass, no type errors.

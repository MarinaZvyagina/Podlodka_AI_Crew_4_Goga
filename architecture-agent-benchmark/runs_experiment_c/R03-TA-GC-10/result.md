# R03-TA-GC-10

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Goga engagement signal: False
Cost: $1.3846722
Duration: 167687ms, turns: 41

## Agent's own summary

Added `TooManyRequestsException` (429) as a first-class NestJS built-in HTTP exception, matching the existing siblings exactly:

- **`packages/common/exceptions/too-many-requests.exception.ts`** — new class extending `HttpException`, default message `'Too Many Requests'`, same `(objectOrError, descriptionOrOptions)` constructor pattern (message override, full body override, description-or-options-with-cause support).
- **`exceptions/index.ts`** — exported it so it's importable from `@nestjs/common` like `GoneException` etc.
- **`utils/http-error-by-code.util.ts`** — added `HttpStatus.TOO_MANY_REQUESTS` to `ErrorHttpStatusCode` and wired it into `HttpErrorByCode`.
- **`exceptions/CODEMANIFEST`** — added the contract entry alongside the other status-code exceptions.
- Tests: new `too-many-requests.exception.spec.ts` (status code, default/custom message, custom body, cause, `instanceof` checks — mirrors `gone.exception.spec.ts`), plus updated `http.exception.spec.ts` and `http-error-by-code.util.spec.ts` to include it in their shared test-case tables.

Ran the full `packages/common` exceptions/utils vitest suite (258 tests, all passing) and a `tsc --noEmit` type-check (clean).

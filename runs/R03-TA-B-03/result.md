# R03-TA-B-03

Condition: baseline
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Cost: $1.0494651000000002
Duration: 218209ms, turns: 40

## Agent's own summary

Added `TooManyRequestsException` for HTTP 429, matching the existing exception classes exactly:

- **`packages/common/exceptions/too-many-requests.exception.ts`** — new class with default message `'Too Many Requests'`, the same `objectOrError`/`descriptionOrOptions` constructor signature (custom message, custom body, cause option) as `ConflictException` etc.
- **`packages/common/exceptions/index.ts`** — exported it, so it's importable the same way as any other built-in (`import { TooManyRequestsException } from '@nestjs/common'`).
- **`packages/common/utils/http-error-by-code.util.ts`** — registered it in `ErrorHttpStatusCode`/`HttpErrorByCode` alongside the others.
- Test coverage: new `too-many-requests.exception.spec.ts` (status code, default/custom message, custom body, cause option, `HttpException`/`Error` inheritance) plus updated the shared `http.exception.spec.ts` and `http-error-by-code.util.spec.ts` parametrized tables to include it.

Confirmed correct behavior on an actual thrown/uncaught exception: `BaseExceptionFilter` (`packages/core/exceptions/base-exception-filter.ts`) replies using `exception.getStatus()`/`getResponse()` generically for any `HttpException` subclass, so no core changes were needed for the 429 to surface correctly in the HTTP response. Ran the full `packages/common` suite (706 tests, 81 files) and `tsc --noEmit` — all green.

# R03-TA-B-08

Condition: baseline
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Cost: $0.6063044999999999
Duration: 85400ms, turns: 25

## Agent's own summary

Added `TooManyRequestsException` (429), matching the existing sibling exception classes exactly:

- **`packages/common/exceptions/too-many-requests.exception.ts`** — new class with the same constructor signature (`objectOrError`, `descriptionOrOptions`), default message `'Too Many Requests'`, JSDoc in the same style, extends `HttpException`.
- **`packages/common/exceptions/index.ts`** — exported it from the barrel (alphabetically after `service-unavailable`).
- **`packages/common/utils/http-error-by-code.util.ts`** — added `HttpStatus.TOO_MANY_REQUESTS` to `ErrorHttpStatusCode` and the `HttpErrorByCode` map, so `429` resolves to the new class wherever that map is used (e.g. converting raw status codes to exceptions).
- **`packages/common/test/exceptions/too-many-requests.exception.spec.ts`** — new spec covering default status/message, custom message, custom body override, cause option, and `instanceof` checks, mirroring `conflict.exception.spec.ts`.
- **`packages/common/test/utils/http-error-by-code.util.spec.ts`** — added the new status to `expectedCodes` so the existing exhaustiveness/status-mapping tests cover it too.

Ran the exceptions/utils test suite (258 tests, all passing) and `tsc --noEmit` on the common package (clean). `TooManyRequestsException` is now importable from `@nestjs/common` the same way as `ConflictException` etc., and thrown uncaught from a handler it'll produce a 429 response the same way the built-in exception filter handles the others.

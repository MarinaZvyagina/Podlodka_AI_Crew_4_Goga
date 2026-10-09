# R03-TA-G-06-RETRY1

Condition: goga
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Cost: $0.7069794000000001
Duration: 132136ms, turns: 29

## Agent's own summary

Confirmed — the base exception filter is generic over `HttpException.getStatus()`, so `TooManyRequestsException` thrown uncaught from a route handler correctly returns a 429 automatically, same as its siblings.

## Summary

Added `TooManyRequestsException` for HTTP 429, matching the existing sibling exceptions exactly:

- **`packages/common/exceptions/too-many-requests.exception.ts`** — new class, default message `'Too Many Requests'`, same constructor shape (`objectOrError`, `descriptionOrOptions`) and JSDoc style as `ConflictException`/`GoneException`.
- **`packages/common/exceptions/index.ts`** — exported it so it's importable as `import { TooManyRequestsException } from '@nestjs/common'`.
- **`packages/common/utils/http-error-by-code.util.ts`** — added it to `ErrorHttpStatusCode` and the `HttpErrorByCode` map.
- **`packages/common/test/exceptions/too-many-requests.exception.spec.ts`** — new test file mirroring `gone.exception.spec.ts`/`conflict.exception.spec.ts` (status code, default message, custom message, custom body, cause option, `instanceof` checks).
- **`packages/common/test/utils/http-error-by-code.util.spec.ts`** — added `HttpStatus.TOO_MANY_REQUESTS` to the expected-codes list so that test stays accurate.

Ran the full `packages/common` vitest suite: 706/706 tests pass.

# R03-TA-B-10

Condition: baseline
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Cost: $1.1345565000000002
Duration: 134734ms, turns: 42

## Agent's own summary

Added `TooManyRequestsException` (429) as a new built-in HTTP exception:

- **`packages/common/exceptions/too-many-requests.exception.ts`** — new class matching the existing siblings' shape (default message `'Too Many Requests'`, overridable body/message, `descriptionOrOptions` pattern with cause support).
- **`packages/common/exceptions/index.ts`** — exported it so it's importable like the other built-ins.
- **`packages/common/utils/http-error-by-code.util.ts`** — registered it in `ErrorHttpStatusCode` and `HttpErrorByCode` for status-code-driven lookup.
- **`packages/common/test/exceptions/too-many-requests.exception.spec.ts`** — new dedicated spec mirroring `conflict.exception.spec.ts`.
- **`packages/common/test/exceptions/http.exception.spec.ts`** and **`test/utils/http-error-by-code.util.spec.ts`** — added it to the existing table-driven coverage shared across all built-in exceptions.

The base exception filter (`packages/core/exceptions/base-exception-filter.ts`) already generically uses `exception.getStatus()`/`getResponse()` for any `HttpException` subclass, so throwing `TooManyRequestsException` uncaught from a route handler correctly yields a 429 response with no extra wiring needed. Verified: `tsc --noEmit` compiles clean, and the full `packages/common` suite passes (81 files, 706 tests).

# R03-TA-GC-01

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Goga engagement signal: False
Cost: $1.4719542
Duration: 149716ms, turns: 44

## Agent's own summary

Everything looks consistent. Summary of changes:

- Added `TooManyRequestsException` (`packages/common/exceptions/too-many-requests.exception.ts`) — 429, default message `'Too Many Requests'`, same constructor shape (`objectOrError`, `descriptionOrOptions`) and JSDoc style as its siblings (e.g. `ConflictException`).
- Exported it from `packages/common/exceptions/index.ts` (and thus `@nestjs/common`), and documented it in the exceptions cell's `CODEMANIFEST`.
- Registered it in `HttpErrorByCode`/`ErrorHttpStatusCode` (`http-error-by-code.util.ts`) so it's on par with every other built-in exception in that exhaustive status→exception map.
- Added a dedicated spec (`too-many-requests.exception.spec.ts`) mirroring `conflict.exception.spec.ts` (status code, default/custom message, custom body, cause option, `HttpException`/`Error` inheritance), and extended the shared parameterized suites in `http.exception.spec.ts` and `http-error-by-code.util.spec.ts` to include it.

Verified: `tsc --noEmit` on `packages/common` is clean, `oxlint` is clean, and the full `packages/common` test suite passes (706/706).

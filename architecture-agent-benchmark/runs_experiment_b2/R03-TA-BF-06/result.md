# R03-TA-BF-06

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Goga engagement signal: True
Cost: $1.3207041
Duration: 171763ms, turns: 43

## Agent's own summary

Everything's in place. Summary:

- **`packages/common/exceptions/too-many-requests.exception.ts`** (new) — `TooManyRequestsException`, 429, built identically to `ConflictException`/`GoneException`: default message `'Too Many Requests'`, `objectOrError` for message/full-body override, `descriptionOrOptions` for short description or options-with-cause.
- **`packages/common/exceptions/index.ts`** — exports it, alphabetically placed with the other exceptions.
- **`packages/common/utils/http-error-by-code.util.ts`** — added it to the `ErrorHttpStatusCode` union and `HttpErrorByCode` map, the registry pipes use to resolve an exception class from a status code, so it's wired in the same way as every other status code.
- **`packages/common/test/exceptions/too-many-requests.exception.spec.ts`** (new) — mirrors `conflict.exception.spec.ts`: status code, default message, custom message, custom body, cause option, `instanceof HttpException`/`Error`.
- **`packages/common/test/utils/http-error-by-code.util.spec.ts`** — added `TOO_MANY_REQUESTS` to the expected-codes list so the existing exhaustiveness/mapping tests cover it too.

Verified with `goga lint`/`goga contract` (clean, consistent with how `ConflictException`/`GoneException` are intentionally left undocumented in the exceptions CODEMANIFEST since it only calls out the pattern once), `tsc --noEmit`, `oxlint`, `prettier --check`, and the full `packages/common` vitest suite (706 tests passing, up from 700).

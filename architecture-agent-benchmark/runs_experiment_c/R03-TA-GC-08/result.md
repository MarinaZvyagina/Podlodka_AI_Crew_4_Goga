# R03-TA-GC-08

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Goga engagement signal: False
Cost: $0.8490332999999999
Duration: 89002ms, turns: 31

## Agent's own summary

Added `TooManyRequestsException` (429) matching the existing built-in exception pattern:

- **`packages/common/exceptions/too-many-requests.exception.ts`** — new class, default message `'Too Many Requests'`, same constructor signature (`objectOrError`, `descriptionOrOptions`) as `ConflictException`/`ServiceUnavailableException`, supports overriding message, replacing the whole body, and the description-or-cause-options pattern.
- **`packages/common/exceptions/index.ts`** — exported it (re-exported transitively from `packages/common/index.ts`, so it's directly importable like the others).
- **`packages/common/utils/http-error-by-code.util.ts`** — registered it in `HttpErrorByCode` and the `ErrorHttpStatusCode` union so it's wired into the same status-code-driven behavior as its siblings.
- **`packages/common/test/exceptions/too-many-requests.exception.spec.ts`** — new spec mirroring `conflict.exception.spec.ts` (status code, default message, custom message, custom body, cause option, inheritance).
- **`packages/common/test/utils/http-error-by-code.util.spec.ts`** — added `TOO_MANY_REQUESTS` to the expected-codes list so the existing coverage map test accounts for the new entry.

Full `packages/common` test suite (706 tests) and `tsc --noEmit` both pass.

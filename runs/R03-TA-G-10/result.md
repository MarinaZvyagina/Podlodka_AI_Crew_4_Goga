# R03-TA-G-10

Condition: goga
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Cost: $0.7712319
Duration: 118591ms, turns: 33

## Agent's own summary

Added `TooManyRequestsException` (429) to `packages/common/exceptions/`, matching every sibling exception's constructor shape, docs, and default-message pattern exactly. It's exported from the exceptions barrel (so it's importable the same way as `ConflictException`, `NotFoundException`, etc.), wired into `HttpErrorByCode`/`ErrorHttpStatusCode` in `http-error-by-code.util.ts`, documented in the exceptions cell's `CODEMANIFEST`, and covered by a new test file mirroring `conflict.exception.spec.ts` (status code, default message, custom message, custom body, cause option, `HttpException`/`Error` inheritance). All 170 exception tests plus the `http-error-by-code` util tests pass, and `tsc --noEmit` is clean.

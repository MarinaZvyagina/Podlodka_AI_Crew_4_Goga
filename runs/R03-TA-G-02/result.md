# R03-TA-G-02

Condition: goga
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Cost: $1.3074039
Duration: 148368ms, turns: 48

## Agent's own summary

Added `TooManyRequestsException` (429) to `packages/common/exceptions/too-many-requests.exception.ts`, following the exact constructor pattern, JSDoc style, and options handling of `ConflictException` and its siblings. Wired it into the exceptions barrel export and `HttpErrorByCode` (used by the framework's automatic status-to-exception mapping), and extended the existing test suites (`http.exception.spec.ts`, `http-error-by-code.util.spec.ts`) plus added a dedicated `too-many-requests.exception.spec.ts` mirroring `conflict.exception.spec.ts`. Verified with `tsc -b`, `oxlint`, `prettier --check`, and `vitest run` (49/49 passing).

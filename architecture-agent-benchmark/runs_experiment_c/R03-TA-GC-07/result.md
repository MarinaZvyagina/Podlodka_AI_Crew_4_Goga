# R03-TA-GC-07

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $0.7986681000000001
Duration: 90001ms, turns: 25

## Agent's own summary

All 23 exception test files (170 tests) pass, and `tsc --noEmit` is clean. Summary of changes:

- **`packages/common/exceptions/too-many-requests.exception.ts`** (new): `TooManyRequestsException` extending `HttpException`, status 429, default message `'Too Many Requests'`, same constructor shape (`objectOrError`, `descriptionOrOptions`) and JSDoc style as its siblings (e.g. `ConflictException`).
- **`packages/common/exceptions/index.ts`**: exported the new class (already surfaced at the package root via the existing `export * from './exceptions/index.js'`).
- **`packages/common/exceptions/CODEMANIFEST`**: added the contract entry documenting the new type, matching the format of its siblings.
- **`packages/common/test/exceptions/too-many-requests.exception.spec.ts`** (new): mirrors `conflict.exception.spec.ts` — status code, default message, custom message, custom body override, `cause` option, `instanceof HttpException`/`Error`.

Left `http-error-by-code.util.ts` untouched — that's a separate status→exception lookup used by pipes and wasn't part of what was asked.

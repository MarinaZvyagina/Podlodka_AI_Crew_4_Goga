# R03-TA-GC-05

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Goga engagement signal: False
Cost: $0.8992464
Duration: 96790ms, turns: 31

## Agent's own summary

All 258 tests pass.

## Summary

Added `TooManyRequestsException` (HTTP 429) to `packages/common/exceptions/`, matching the existing sibling classes exactly:

- **`too-many-requests.exception.ts`** — new class extending `HttpException`, default message `'Too Many Requests'`, same constructor shape (`objectOrError`, `descriptionOrOptions`) as `ConflictException`/`ForbiddenException`, with full JSDoc in the same style.
- **`exceptions/index.ts`** — exported the new class (alphabetically placed), so it's importable from `@nestjs/common` the same way as the others.
- **`utils/http-error-by-code.util.ts`** — added `TOO_MANY_REQUESTS` to `ErrorHttpStatusCode` and the `HttpErrorByCode` map, since this repo's map is the canonical status-code→exception registry.
- **`exceptions/CODEMANIFEST`** — documented the new subclass consistent with the other entries.
- **Tests** — added `too-many-requests.exception.spec.ts` mirroring `conflict.exception.spec.ts` (status code, default message, custom message, custom body, cause option, `instanceof` checks), and updated `http-error-by-code.util.spec.ts`'s expected-codes list.

Verified with `tsc --noEmit` (clean) and the full exceptions/utils test suite (258 tests passing).

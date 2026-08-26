# Architecture Contracts

This repository includes machine-readable architecture contracts, stored as `CODEMANIFEST` files inside the directories they describe. Each `CODEMANIFEST` documents that directory's public interface: the types, functions, and methods other parts of the codebase are expected to rely on, expressed in a small YAML-based DSL (the `qarium/codemanifest` specification).

## Format

Each `CODEMANIFEST` has three sections, separated by `---`:

1. **Header** — `Imports` (types/practices brought in from other documented directories), `Usages` (named conventions and patterns relevant to this directory), `Annotations` (general notes about this directory's role).
2. **Body** — declared types. An entity looks like:
   ```yaml
   "TypeName(constructorArgs)":
     location: relative/file/name.ext
     annotations: |
       What this type is for.
     properties:
       "propName -> Type": |
         What this property holds.
     methods:
       "methodName(args) -> result:ReturnType": |
         What this method does, including any preconditions or constraints.
   ```
   A routine (a standalone function, not tied to a type) looks like:
   ```yaml
   "functionName(args) -> result:ReturnType":
     location: relative/file/name.ext
     annotations: |
       What this function does.
   ```
3. **Footer** — authorship metadata (not part of the contract itself).

## What this covers

These contracts describe this repository's real, existing architecture as of the commit they were generated against — the components, their responsibilities, their dependency relationships, and (where relevant) their designed extension points. Coverage is not necessarily exhaustive across the whole codebase; each directory's `CODEMANIFEST` only exists where one was generated. Directories without a `CODEMANIFEST` are simply undocumented by this system — that says nothing about their importance.

## How to use this

Treat a `CODEMANIFEST` the same way you would treat a well-maintained `ARCHITECTURE.md` or module-level docstring: a starting point for understanding how a part of the system is organized and what already exists, before writing new code that touches it. Prefer extending or composing with the types and mechanisms these files document over introducing a parallel mechanism that duplicates one already described here.

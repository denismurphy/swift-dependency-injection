# 0006. Throw typed errors from the container, trap in `@Inject`

Status: accepted

## Context

A missing registration is a programming error in most applications, but a
library cannot assume that. A property wrapper getter cannot throw, so
`@Inject` has to do something other than propagate the error.

## Decision

- `Container.resolve` and `Resolver.resolve` use typed throws:
  `throws(DependencyError)`. Callers can handle `notRegistered`,
  `circularDependency`, `typeMismatch` and `factoryFailed` exhaustively.
- Errors thrown by a factory are wrapped as `factoryFailed`, except a
  `DependencyError` from a nested resolution, which passes through unchanged so
  the error names the key that is actually missing.
- `@Inject` and `Dependency` call `preconditionFailure` with the error's
  description, which names the key and says how to fix it.
- `resolveIfRegistered`, `@InjectIfRegistered` express "may be absent" without
  trapping. They return `nil` only when the requested key is unregistered; a
  failure inside a dependency still surfaces.

## Consequences

- Code that can recover uses `resolve`; code that treats a missing
  registration as a bug uses `@Inject` and gets a precise message.
- The trap is a deliberate trade-off. A wrapper that returned an optional would
  push `nil` handling onto every use site for a failure that cannot be
  handled locally.

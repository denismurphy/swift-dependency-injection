# 0001. Guard container state with a mutex, not an actor

Status: accepted

## Context

`@Inject` is a property wrapper. Its `wrappedValue` getter is synchronous and
cannot be `async`, and it is read from initialisers, view bodies and
nonisolated code alike. A container that is an actor would force every read
through `await`, which a property wrapper cannot express.

## Decision

`Container` is a `final class` marked `Sendable`. Its mutable state (the
registration table and the singleton cache) lives in a
`Synchronization.Mutex<State>`. The lock is held only for dictionary lookups
and updates, never while a factory runs.

## Consequences

- Resolution is synchronous and callable from any isolation domain.
- The compiler checks the isolation story: `Container` is `Sendable` without
  `@unchecked`, because `Mutex` is.
- `Mutex` requires iOS 18 or macOS 15. The package targets iOS 26 and macOS 26,
  so the requirement is already met.
- Singleton construction needs a second lock because factories run outside the
  state lock; see ADR 0005.

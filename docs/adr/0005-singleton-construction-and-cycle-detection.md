# 0005. Serialise singleton construction per container and detect cycles by path

Status: accepted

## Context

Factories receive a `Resolver` so a registration can build itself from other
registrations. That raises three problems: two threads may race to build the
same singleton, a factory may resolve a dependency that is mid-construction,
and two threads building mutually dependent singletons may each hold half the
cycle.

## Decision

- The state lock is released before a factory runs. A second, recursive lock per
  container serialises singleton construction. After taking it, the resolver
  checks the cache again, so a thread that waited reuses the winner's instance.
- Recursion lets a singleton factory resolve other singletons.
- The keys being built are tracked in a task-local array. A key reached again
  while it is in that array raises `DependencyError.circularDependency(path:)`
  with the full path. Because every factory call goes through one function,
  the check also catches a cycle closed by an `@Inject` read inside the
  constructed object's initialiser.
- After construction the instance is cached only if the key still carries the
  registration that started the build, so a re-registration during construction
  is not overwritten by a stale instance.

## Consequences

- A singleton is built exactly once under concurrent first resolution.
- Cycles are reported with a readable path instead of recursing or deadlocking.
- Singleton construction within one container is serial. Construction is
  expected to be cheap; do not block a singleton factory on work that needs
  another thread to resolve a singleton from the same container.
- A child container and its parent have separate construction locks. Locks are
  only ever taken child first, then parent, because singletons resolve against
  the container that owns them (ADR 0004), so the order cannot invert.

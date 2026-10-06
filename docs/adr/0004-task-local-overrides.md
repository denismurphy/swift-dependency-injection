# 0004. Scope overrides to a task tree with a child container

Status: accepted

## Context

Tests replace dependencies with doubles. Replacing registrations in a shared
container makes parallel tests interfere, and forces tests to restore state.

## Decision

`Container.current` is a `@TaskLocal` that defaults to `Container.shared`.
`Container.withOverride(_:operation:)` creates a child container whose parent is
the present `current`, registers the assembly in it, and binds it as `current`
for the duration of the operation. Lookups that miss in the child fall through
to the parent.

Two construction rules keep overrides from leaking:

- A transient registration resolves its dependencies against the container that
  was asked, so an override of a dependency is visible to a parent's transient.
- A singleton resolves its dependencies against the container that owns it, so
  an override can never be captured by an instance that outlives the scope.

## Consequences

- Concurrent tests each see their own overrides.
- Child tasks created with `async let` or a task group inherit the binding.
  `Task.detached` and detached-by-default APIs do not, and then see
  `Container.shared`.
- Re-registering a key (`Container.register(_:)`) is the tool for replacing
  a registration for the whole process; it discards the cached singleton for
  that key.

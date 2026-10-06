# 0003. Do not cache resolved instances inside `@Inject`

Status: accepted

## Context

An injected property could remember what it last resolved and skip the
container on later reads. Holding that reference strongly would extend the
lifetime of a transient dependency beyond what its scope promises. Holding it
weakly does not work for transients: nothing else owns a freshly built
instance, so a weak reference is released between the store and the first use.

## Decision

`@Inject` stores only its `DependencyKey`, computed once when the wrapper is
created. Every read goes to `Container.current`.

## Consequences

- A transient registration yields a new instance on each read, which is what
  `.transient` means. Assign to a local when one instance is needed for a
  scope of code.
- Singleton lifetime is owned by the container alone.
- Reads cost one lookup. Making that lookup cheap is the job of the key
  (ADR 0002) and the lock (ADR 0001), not of a per-property cache.

# 0002. Key registrations by type identity, not by type name

Status: accepted

## Context

A registration is filed under a type and an optional binding name. Keying on
`String(describing:)` or `String(reflecting:)` allocates and demangles on every
lookup, and two types with the same name in different modules can collide when
the module is omitted.

## Decision

`DependencyKey` hashes and compares `ObjectIdentifier(type)` together with the
binding name. The metatype is stored alongside only so that errors can print a
readable name; it takes no part in equality.

## Consequences

- Building a key allocates nothing and cannot collide across modules.
- Resolving `Foo?` does not find the registration for `Foo`. Use
  `@InjectIfRegistered` or `resolveIfRegistered` for the optional case, which
  keeps the semantics explicit.
- Equality is by metadata address, so the same type reached through two
  dynamically loaded copies of a module is two keys. This matches Swift's own
  type identity.

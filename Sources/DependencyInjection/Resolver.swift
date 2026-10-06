/// Handed to factories so that a registration can pull in its own
/// dependencies.
///
/// A transient registration resolves against the container that was asked.
/// A singleton resolves against the container that owns it, so a scoped
/// override can never leak into a cached instance.
public struct Resolver: Sendable {
    let container: Container

    public func resolve<T: Sendable>(
        _ type: T.Type = T.self,
        name: String? = nil
    ) throws(DependencyError) -> T {
        try container.resolve(type, name: name)
    }

    public func resolveIfRegistered<T: Sendable>(
        _ type: T.Type = T.self,
        name: String? = nil
    ) throws(DependencyError) -> T? {
        try container.resolveIfRegistered(type, name: name)
    }
}

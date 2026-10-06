/// Why a resolution failed.
public enum DependencyError: Error, Sendable, CustomStringConvertible {
    /// Nothing is registered for the key.
    case notRegistered(DependencyKey)

    /// The key was reached again while it was still being built. `path` runs
    /// from the outermost request to the repeated key, inclusive.
    case circularDependency(path: [DependencyKey])

    /// The registered value is not the requested type, for example an alias
    /// registered for a protocol the concrete type does not conform to.
    case typeMismatch(key: DependencyKey, actual: any Any.Type)

    /// The registration's factory threw.
    case factoryFailed(DependencyKey, underlying: any Error)

    public var description: String {
        switch self {
        case .notRegistered(let key):
            "No registration for \(key). Register it in an Assembly and pass that to Container.register(_:) before resolving."
        case .circularDependency(let path):
            "Circular dependency: \(path.map(\.description).joined(separator: " -> "))."
        case .typeMismatch(let key, let actual):
            "Registration for \(key) produced a \(String(reflecting: actual)), which is not the requested type. Check the 'as:' type of the registration."
        case .factoryFailed(let key, let underlying):
            "The factory for \(key) threw: \(underlying)."
        }
    }
}

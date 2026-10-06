/// One entry in a container: what to build, under which key, and for how long
/// the result lives.
struct Registration: Sendable {
    typealias Make = @Sendable (Resolver) throws(DependencyError) -> any Sendable

    let key: DependencyKey
    let scope: Scope
    let make: Make
}

/// Wraps a user factory so that a `DependencyError` raised by a nested
/// resolution passes through unchanged and anything else is reported against
/// the key being built.
func erase<T: Sendable>(
    key: DependencyKey,
    _ factory: @escaping @Sendable (Resolver) throws -> T
) -> Registration.Make {
    { resolver throws(DependencyError) in
        do {
            return try factory(resolver)
        } catch let error as DependencyError {
            throw error
        } catch {
            throw .factoryFailed(key, underlying: error)
        }
    }
}

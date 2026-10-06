/// A single declaration inside an `Assembly`.
///
/// ```swift
/// Register(Clock.self, scope: .singleton) { _ in SystemClock() }
/// Register(Repository.self, as: (any RepositoryProtocol).self) { r in
///     Repository(clock: try r.resolve())
/// }
/// ```
public struct Register: Sendable {
    let registrations: [Registration]

    /// Registers `factory` for `T`.
    public init<T: Sendable>(
        _ type: T.Type = T.self,
        name: String? = nil,
        scope: Scope = .transient,
        factory: @escaping @Sendable (Resolver) throws -> T
    ) {
        let key = DependencyKey(type, name: name)
        registrations = [Registration(key: key, scope: scope, make: erase(key: key, factory))]
    }

    /// Registers `factory` for `T` and also makes it resolvable as `P`.
    ///
    /// Both keys resolve to the same instance when `scope` is `.singleton`,
    /// because the `P` key is an alias for the `T` key rather than a second
    /// registration.
    public init<T: Sendable, P: Sendable>(
        _ type: T.Type,
        as protocolType: P.Type,
        name: String? = nil,
        scope: Scope = .transient,
        factory: @escaping @Sendable (Resolver) throws -> T
    ) {
        let concrete = DependencyKey(type, name: name)
        let alias = DependencyKey(protocolType, name: name)
        registrations = [
            Registration(key: concrete, scope: scope, make: erase(key: concrete, factory)),
            Registration(key: alias, scope: .transient, make: { resolver throws(DependencyError) in
                try resolver.resolve(type, name: name)
            }),
        ]
    }

    /// Registers a `@MainActor` factory. The registration must then be
    /// resolved on the main thread; resolving it elsewhere traps with a
    /// message from the runtime's isolation check.
    @MainActor
    public static func mainActor<T: Sendable>(
        _ type: T.Type = T.self,
        name: String? = nil,
        scope: Scope = .transient,
        factory: @escaping @MainActor @Sendable (Resolver) throws -> T
    ) -> Register {
        Register(type, name: name, scope: scope) { resolver in
            try MainActor.assumeIsolated { try factory(resolver) }
        }
    }
}

@resultBuilder
public enum AssemblyBuilder {
    public static func buildExpression(_ expression: Register) -> [Register] { [expression] }
    public static func buildBlock(_ components: [Register]...) -> [Register] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [Register]?) -> [Register] { component ?? [] }
    public static func buildEither(first component: [Register]) -> [Register] { component }
    public static func buildEither(second component: [Register]) -> [Register] { component }
    public static func buildArray(_ components: [[Register]]) -> [Register] { components.flatMap { $0 } }
}

/// An ordered set of registrations. Later entries replace earlier ones that
/// share a key.
public struct Assembly: Sendable {
    var registrations: [Registration] = []

    public init() {}

    public init(@AssemblyBuilder _ content: () -> [Register]) {
        registrations = content().flatMap(\.registrations)
    }

    public mutating func add(_ register: Register) {
        registrations.append(contentsOf: register.registrations)
    }

    public static func + (lhs: Assembly, rhs: Assembly) -> Assembly {
        var result = lhs
        result.registrations.append(contentsOf: rhs.registrations)
        return result
    }
}

import Foundation
import Synchronization

/// Holds registrations and resolves them.
public final class Container: Sendable {
    struct Entry: Sendable {
        let registration: Registration
        let id: UInt64
    }

    struct State: Sendable {
        var entries: [DependencyKey: Entry] = [:]
        var singletons: [DependencyKey: any Sendable] = [:]
        var nextID: UInt64 = 0
    }

    /// The process-wide container.
    public static let shared = Container()

    /// Keys currently being built on this thread's task, outermost first.
    /// Every route into a factory goes through `build`, so this sees a cycle
    /// whether it closes through a `Resolver` or through an `@Inject` read in
    /// the constructed object's initialiser.
    @TaskLocal private static var resolving: [DependencyKey] = []

    let parent: Container?
    let state = Mutex(State())

    /// Serialises singleton construction for this container. Recursive so a
    /// singleton factory can resolve other singletons. One lock per container,
    /// not per key, so two threads building mutually dependent singletons
    /// queue instead of each holding half of the cycle.
    let constructionLock = NSRecursiveLock()

    public init(parent: Container? = nil) {
        self.parent = parent
    }

    public convenience init(parent: Container? = nil, @AssemblyBuilder _ content: () -> [Register]) {
        self.init(parent: parent)
        register(Assembly(content))
    }

    /// Adds the assembly's registrations. A registration for a key that is
    /// already present replaces it and discards any singleton cached for that
    /// key, so the next resolution uses the new registration.
    @discardableResult
    public func register(_ assembly: Assembly) -> Container {
        state.withLock { state in
            for registration in assembly.registrations {
                state.nextID += 1
                state.entries[registration.key] = Entry(registration: registration, id: state.nextID)
                state.singletons.removeValue(forKey: registration.key)
            }
        }
        return self
    }

    /// Removes every registration and cached singleton from this container.
    public func reset() {
        state.withLock { state in
            state.entries.removeAll()
            state.singletons.removeAll()
        }
    }

    public func resolve<T: Sendable>(
        _ type: T.Type = T.self,
        name: String? = nil
    ) throws(DependencyError) -> T {
        let key = DependencyKey(type, name: name)
        let value = try resolveAny(key)
        guard let typed = value as? T else {
            throw .typeMismatch(key: key, actual: Swift.type(of: value))
        }
        return typed
    }

    /// `nil` when nothing is registered for the key. Any other failure,
    /// including a failure inside a dependency, is still thrown.
    public func resolveIfRegistered<T: Sendable>(
        _ type: T.Type = T.self,
        name: String? = nil
    ) throws(DependencyError) -> T? {
        let key = DependencyKey(type, name: name)
        guard find(key) != nil else { return nil }
        return try resolve(type, name: name)
    }

    func find(_ key: DependencyKey) -> (owner: Container, entry: Entry)? {
        if let entry = state.withLock({ $0.entries[key] }) {
            return (self, entry)
        }
        return parent?.find(key)
    }

    func resolveAny(_ key: DependencyKey) throws(DependencyError) -> any Sendable {
        guard let (owner, entry) = find(key) else { throw .notRegistered(key) }

        switch entry.registration.scope {
        case .transient:
            return try build(entry.registration, resolver: Resolver(container: self))

        case .singleton:
            if let cached = owner.cachedSingleton(for: key) { return cached }

            owner.constructionLock.lock()
            defer { owner.constructionLock.unlock() }

            // Another thread may have finished building it while this one waited.
            if let cached = owner.cachedSingleton(for: key) { return cached }

            let value = try build(entry.registration, resolver: Resolver(container: owner))
            owner.state.withLock { state in
                // Skip the cache if the key was re-registered mid-build; the
                // caller still gets the instance it asked for.
                if state.entries[key]?.id == entry.id {
                    state.singletons[key] = value
                }
            }
            return value
        }
    }

    private func cachedSingleton(for key: DependencyKey) -> (any Sendable)? {
        state.withLock { $0.singletons[key] }
    }

    private func build(
        _ registration: Registration,
        resolver: Resolver
    ) throws(DependencyError) -> any Sendable {
        let path = Container.resolving
        if path.contains(registration.key) {
            throw .circularDependency(path: path + [registration.key])
        }
        let result = Container.$resolving.withValue(path + [registration.key]) {
            Result<any Sendable, DependencyError> { () throws(DependencyError) in
                try registration.make(resolver)
            }
        }
        return try result.get()
    }
}

/// Resolves a dependency from `Container.current` on every read.
///
/// A property wrapper cannot throw, so a missing or broken registration traps
/// with the `DependencyError` description. Use `Container.resolve` where the
/// failure must be handled.
@propertyWrapper
public struct Inject<Value: Sendable>: Sendable {
    let key: DependencyKey

    public init(name: String? = nil) {
        key = DependencyKey(Value.self, name: name)
    }

    public var wrappedValue: Value {
        do {
            return try Container.current.resolve(Value.self, name: key.name)
        } catch {
            preconditionFailure("\(error)")
        }
    }
}

/// Like `Inject`, but `nil` when nothing is registered. Other failures trap.
@propertyWrapper
public struct InjectIfRegistered<Value: Sendable>: Sendable {
    let key: DependencyKey

    public init(name: String? = nil) {
        key = DependencyKey(Value.self, name: name)
    }

    public var wrappedValue: Value? {
        do {
            return try Container.current.resolveIfRegistered(Value.self, name: key.name)
        } catch {
            preconditionFailure("\(error)")
        }
    }
}

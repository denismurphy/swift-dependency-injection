import DependencyInjection
import SwiftUI

extension EnvironmentValues {
    /// The container that `Dependency` resolves from inside a view hierarchy.
    @Entry public var container: Container = .shared
}

extension View {
    /// Makes `container` the one `Dependency` properties resolve from in this
    /// view and its descendants.
    public func container(_ container: Container) -> some View {
        environment(\.container, container)
    }
}

/// Resolves a dependency from the environment's container.
///
/// `Inject` reads a task-local binding, which a view body is never inside, so
/// views use this wrapper to honour `.container(_:)`.
@propertyWrapper
public struct Dependency<Value: Sendable>: DynamicProperty {
    @Environment(\.container) private var container
    private let name: String?

    public init(name: String? = nil) {
        self.name = name
    }

    public var wrappedValue: Value {
        do {
            return try container.resolve(Value.self, name: name)
        } catch {
            preconditionFailure("\(error)")
        }
    }
}

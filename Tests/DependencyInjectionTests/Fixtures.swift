import DependencyInjection
import Synchronization
import Testing

/// Counts how many times a factory ran.
final class Counter: Sendable {
    private let value = Mutex(0)

    var count: Int { value.withLock { $0 } }

    @discardableResult
    func next() -> Int {
        value.withLock { value in
            value += 1
            return value
        }
    }
}

final class Service: Sendable {
    let id: Int
    init(id: Int = 0) { self.id = id }
}

protocol Greeter: Sendable {
    var greeting: String { get }
}

final class English: Greeter {
    let greeting = "hello"
}

/// Mutable state on a shared instance, to observe whether two reads reached
/// the same object.
final class Settings: Sendable {
    private let stored = Mutex("default")

    var value: String {
        get { stored.withLock { $0 } }
        set { stored.withLock { $0 = newValue } }
    }
}

final class Repository: Sendable {
    let settings: Settings
    init(settings: Settings) { self.settings = settings }
}

final class NodeA: Sendable {
    let b: NodeB
    init(b: NodeB) { self.b = b }
}

final class NodeB: Sendable {
    let a: NodeA
    init(a: NodeA) { self.a = a }
}

/// Resolves itself from the current container while being built, which closes
/// a cycle that never appears as a `Resolver` call inside a factory.
final class Loop: Sendable {
    init() throws {
        _ = try Container.current.resolve(Loop.self)
    }
}

struct Consumer: Sendable {
    @Inject var service: Service
    @Inject(name: "alt") var alternate: Service
    @InjectIfRegistered var optional: Settings?
}

struct BrokenFactory: Error {}

/// The `DependencyError` thrown by `body`, or `nil` if it did not throw.
/// Any other error type is a test failure.
func failure<T>(_ body: () throws -> T) -> DependencyError? {
    do {
        _ = try body()
        return nil
    } catch let error as DependencyError {
        return error
    } catch {
        Issue.record("unexpected error type: \(error)")
        return nil
    }
}

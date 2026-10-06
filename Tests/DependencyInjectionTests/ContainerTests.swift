import Foundation
import Synchronization
import Testing

@testable import DependencyInjection

@Suite("Scopes and keys")
struct ScopeTests {
    @Test func transientBuildsANewInstanceEachTime() throws {
        let counter = Counter()
        let container = Container {
            Register(Service.self) { _ in Service(id: counter.next()) }
        }
        let first = try container.resolve(Service.self)
        let second = try container.resolve(Service.self)
        #expect(first !== second)
        #expect(counter.count == 2)
    }

    @Test func singletonBuildsOnceAndIsShared() throws {
        let counter = Counter()
        let container = Container {
            Register(Service.self, scope: .singleton) { _ in Service(id: counter.next()) }
        }
        let first = try container.resolve(Service.self)
        let second = try container.resolve(Service.self)
        #expect(first === second)
        #expect(counter.count == 1)
    }

    @Test func singletonIsLazy() throws {
        let counter = Counter()
        _ = Container {
            Register(Service.self, scope: .singleton) { _ in Service(id: counter.next()) }
        }
        #expect(counter.count == 0)
    }

    @Test func namedBindingsAreSeparateRegistrations() throws {
        let container = Container {
            Register(Service.self) { _ in Service(id: 1) }
            Register(Service.self, name: "alt") { _ in Service(id: 2) }
        }
        #expect(try container.resolve(Service.self).id == 1)
        #expect(try container.resolve(Service.self, name: "alt").id == 2)
        #expect(failure { try container.resolve(Service.self, name: "other") } != nil)
    }

    @Test func protocolAndConcreteSingletonResolveToOneInstance() throws {
        let counter = Counter()
        let container = Container {
            Register(English.self, as: (any Greeter).self, scope: .singleton) { _ in
                counter.next()
                return English()
            }
        }
        let viaProtocol = try container.resolve((any Greeter).self)
        let viaConcrete = try container.resolve(English.self)
        #expect(viaProtocol as AnyObject === viaConcrete)
        #expect(counter.count == 1)
    }

    @Test func aliasForAProtocolTheTypeDoesNotAdoptReportsTypeMismatch() {
        let container = Container {
            Register(Service.self, as: (any Greeter).self) { _ in Service() }
        }
        guard case .typeMismatch(let key, let actual)? = failure({ try container.resolve((any Greeter).self) }) else {
            Issue.record("expected typeMismatch")
            return
        }
        #expect(ObjectIdentifier(key.type) == ObjectIdentifier((any Greeter).self))
        #expect(ObjectIdentifier(actual) == ObjectIdentifier(Service.self))
    }
}

@Suite("Registration and reset")
struct RegistrationTests {
    @Test func reregisteringReplacesTheFactoryAndDiscardsTheCachedSingleton() throws {
        let container = Container {
            Register(Service.self, scope: .singleton) { _ in Service(id: 1) }
        }
        #expect(try container.resolve(Service.self).id == 1)
        container.register(Assembly { Register(Service.self, scope: .singleton) { _ in Service(id: 2) } })
        #expect(try container.resolve(Service.self).id == 2)
    }

    @Test func reregisteredSingletonKeepsStateAcrossReads() throws {
        let container = Container {
            Register(Settings.self, scope: .singleton) { _ in Settings() }
        }
        container.register(Assembly { Register(Settings.self, scope: .singleton) { _ in Settings() } })
        try container.resolve(Settings.self).value = "changed"
        #expect(try container.resolve(Settings.self).value == "changed")
    }

    @Test func reregisteringCanTurnASingletonIntoATransient() throws {
        let container = Container {
            Register(Service.self, scope: .singleton) { _ in Service() }
        }
        let cached = try container.resolve(Service.self)
        container.register(Assembly { Register(Service.self) { _ in Service() } })
        let first = try container.resolve(Service.self)
        let second = try container.resolve(Service.self)
        #expect(first !== cached)
        #expect(first !== second)
    }

    @Test func registrationReplacedDuringConstructionIsNotOverwrittenByTheStaleInstance() throws {
        let container = Container()
        container.register(Assembly {
            Register(Service.self, scope: .singleton) { _ in
                container.register(Assembly { Register(Service.self, scope: .singleton) { _ in Service(id: 2) } })
                return Service(id: 1)
            }
        })
        #expect(try container.resolve(Service.self).id == 1)
        #expect(try container.resolve(Service.self).id == 2)
    }

    @Test func laterEntriesInOneAssemblyWin() throws {
        let container = Container {
            Register(Service.self) { _ in Service(id: 1) }
            Register(Service.self) { _ in Service(id: 2) }
        }
        #expect(try container.resolve(Service.self).id == 2)
    }

    @Test func resetRemovesRegistrationsAndSingletons() throws {
        let container = Container {
            Register(Service.self, scope: .singleton) { _ in Service() }
        }
        _ = try container.resolve(Service.self)
        container.reset()
        #expect(failure { try container.resolve(Service.self) } != nil)
    }
}

@Suite("Errors")
struct ErrorTests {
    @Test func unregisteredTypeNamesTheTypeAndTheBinding() {
        let container = Container()
        let error = failure { try container.resolve(Service.self, name: "primary") }
        guard case .notRegistered(let key)? = error else {
            Issue.record("expected notRegistered, got \(String(describing: error))")
            return
        }
        #expect(key == DependencyKey(Service.self, name: "primary"))
        let text = error.map { String(describing: $0) } ?? ""
        #expect(text.contains("Service"))
        #expect(text.contains("primary"))
    }

    @Test func throwingFactoryIsReportedAgainstItsKey() {
        let container = Container {
            Register(Service.self) { _ in throw BrokenFactory() }
        }
        guard case .factoryFailed(let key, let underlying)? = failure({ try container.resolve(Service.self) }) else {
            Issue.record("expected factoryFailed")
            return
        }
        #expect(key == DependencyKey(Service.self))
        #expect(underlying is BrokenFactory)
    }

    @Test func missingNestedDependencyIsNotWrappedAsFactoryFailure() {
        let container = Container {
            Register(Repository.self) { r in Repository(settings: try r.resolve()) }
        }
        guard case .notRegistered(let key)? = failure({ try container.resolve(Repository.self) }) else {
            Issue.record("expected notRegistered for the nested key")
            return
        }
        #expect(key == DependencyKey(Settings.self))
    }

    @Test func resolveIfRegisteredReturnsNilOnlyForTheRequestedKey() throws {
        let container = Container {
            Register(Repository.self) { r in Repository(settings: try r.resolve()) }
        }
        #expect(try container.resolveIfRegistered(Service.self) == nil)
        #expect(failure { try container.resolveIfRegistered(Repository.self) } != nil)
    }
}

@Suite("Nested resolution")
struct NestedResolutionTests {
    @Test func factoryCanResolveItsOwnDependencies() throws {
        let container = Container {
            Register(Settings.self, scope: .singleton) { _ in Settings() }
            Register(Repository.self) { r in Repository(settings: try r.resolve()) }
        }
        let first = try container.resolve(Repository.self)
        let second = try container.resolve(Repository.self)
        #expect(first !== second)
        #expect(first.settings === second.settings)
    }

    @Test func singletonFactoryCanResolveAnotherSingleton() throws {
        let container = Container {
            Register(Settings.self, scope: .singleton) { _ in Settings() }
            Register(Repository.self, scope: .singleton) { r in Repository(settings: try r.resolve()) }
        }
        let repository = try container.resolve(Repository.self)
        #expect(repository.settings === (try container.resolve(Settings.self)))
    }

    @Test func cycleThroughFactoriesThrowsWithThePath() {
        let container = Container {
            Register(NodeA.self) { r in NodeA(b: try r.resolve()) }
            Register(NodeB.self) { r in NodeB(a: try r.resolve()) }
        }
        guard case .circularDependency(let path)? = failure({ try container.resolve(NodeA.self) }) else {
            Issue.record("expected circularDependency")
            return
        }
        #expect(path == [DependencyKey(NodeA.self), DependencyKey(NodeB.self), DependencyKey(NodeA.self)])
    }

    @Test func singletonCycleThrowsInsteadOfDeadlocking() {
        let container = Container {
            Register(NodeA.self, scope: .singleton) { r in NodeA(b: try r.resolve()) }
            Register(NodeB.self, scope: .singleton) { r in NodeB(a: try r.resolve()) }
        }
        guard case .circularDependency? = failure({ try container.resolve(NodeA.self) }) else {
            Issue.record("expected circularDependency")
            return
        }
    }

    @Test func cycleClosedThroughTheCurrentContainerDuringConstructionIsDetected() {
        let container = Container {
            Register(Loop.self) { _ in try Loop() }
        }
        let outcome: DependencyError? = Container.$current.withValue(container) {
            failure { try Container.current.resolve(Loop.self) }
        }
        guard case .circularDependency? = outcome else {
            Issue.record("expected circularDependency, got \(String(describing: outcome))")
            return
        }
    }

    @Test func concurrentFirstResolutionBuildsTheSingletonOnce() async throws {
        let counter = Counter()
        let container = Container {
            Register(Service.self, scope: .singleton) { _ in
                counter.next()
                Thread.sleep(forTimeInterval: 0.002)
                return Service()
            }
        }
        let instances = try await withThrowingTaskGroup(of: ObjectIdentifier.self) { group in
            for _ in 0..<1000 {
                group.addTask { ObjectIdentifier(try container.resolve(Service.self)) }
            }
            var seen = Set<ObjectIdentifier>()
            for try await id in group { seen.insert(id) }
            return seen
        }
        #expect(counter.count == 1)
        #expect(instances.count == 1)
    }
}

@Suite("Scoped overrides")
struct OverrideTests {
    @Test func overrideShadowsTheParentAndFallsThroughForEverythingElse() throws {
        let base = Container {
            Register(Service.self) { _ in Service(id: 1) }
            Register(Settings.self, scope: .singleton) { _ in Settings() }
        }
        try Container.$current.withValue(base) {
            try Container.withOverride(Assembly { Register(Service.self) { _ in Service(id: 99) } }) {
                let overridden = try Container.current.resolve(Service.self).id
                let shared = try Container.current.resolve(Settings.self)
                #expect(overridden == 99)
                #expect(shared === (try base.resolve(Settings.self)))
            }
            let restored = try Container.current.resolve(Service.self).id
            #expect(restored == 1)
        }
    }

    @Test func transientRegistrationInTheParentSeesTheOverriddenDependency() throws {
        let base = Container {
            Register(Settings.self) { _ in Settings() }
            Register(Repository.self) { r in Repository(settings: try r.resolve()) }
        }
        let fake = Settings()
        fake.value = "fake"
        try Container.$current.withValue(base) {
            try Container.withOverride(Assembly { Register(Settings.self) { _ in fake } }) {
                let settings = try Container.current.resolve(Repository.self).settings
                #expect(settings === fake)
            }
        }
    }

    @Test func singletonInTheParentIsNotBuiltAgainstAnOverride() throws {
        let base = Container {
            Register(Settings.self) { _ in Settings() }
            Register(Repository.self, scope: .singleton) { r in Repository(settings: try r.resolve()) }
        }
        let fake = Settings()
        try Container.$current.withValue(base) {
            try Container.withOverride(Assembly { Register(Settings.self) { _ in fake } }) {
                let settings = try Container.current.resolve(Repository.self).settings
                #expect(settings !== fake)
            }
        }
    }

    @Test func concurrentOverridesDoNotSeeEachOther() async throws {
        let base = Container {
            Register(Service.self) { _ in Service(id: 0) }
        }
        try await Container.$current.withValue(base) {
            let ids = try await withThrowingTaskGroup(of: Int.self) { group in
                for id in 1...50 {
                    group.addTask {
                        try await Container.withOverride(Assembly { Register(Service.self) { _ in Service(id: id) } }) {
                            await Task.yield()
                            return try Container.current.resolve(Service.self).id
                        }
                    }
                }
                var seen = [Int]()
                for try await id in group { seen.append(id) }
                return seen.sorted()
            }
            #expect(ids == Array(1...50))
            #expect(try Container.current.resolve(Service.self).id == 0)
        }
    }
}

@Suite("Property wrappers")
struct InjectTests {
    @Test func injectResolvesFromTheCurrentContainerOnEveryRead() throws {
        let counter = Counter()
        let container = Container {
            Register(Service.self) { _ in Service(id: counter.next()) }
            Register(Service.self, name: "alt") { _ in Service(id: -1) }
        }
        Container.$current.withValue(container) {
            let consumer = Consumer()
            #expect(consumer.service.id == 1)
            #expect(consumer.service.id == 2)
            #expect(consumer.alternate.id == -1)
            #expect(consumer.optional == nil)
        }
    }

    @Test func injectIfRegisteredReturnsTheValueWhenPresent() {
        let container = Container {
            Register(Service.self) { _ in Service() }
            Register(Service.self, name: "alt") { _ in Service() }
            Register(Settings.self) { _ in Settings() }
        }
        Container.$current.withValue(container) {
            #expect(Consumer().optional != nil)
        }
    }
}

@Suite("Main actor registrations")
@MainActor
struct MainActorTests {
    @MainActor
    final class ViewModel: Sendable {
        let title = "home"
    }

    @Test func mainActorFactoryBuildsOnTheMainActor() throws {
        let container = Container {
            Register.mainActor(ViewModel.self, scope: .singleton) { _ in ViewModel() }
        }
        let first = try container.resolve(ViewModel.self)
        let second = try container.resolve(ViewModel.self)
        #expect(first === second)
        #expect(first.title == "home")
    }
}

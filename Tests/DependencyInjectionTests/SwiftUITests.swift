import DependencyInjection
import DependencyInjectionSwiftUI
import SwiftUI
import Synchronization
import Testing

@Suite("SwiftUI environment")
@MainActor
struct SwiftUITests {
    /// A decoy in the default container, so a view that ignores the
    /// environment resolves a wrong value instead of trapping.
    init() {
        Container.shared.register(Assembly { Register(Service.self) { _ in Service(id: -1) } })
    }

    private struct Probe: View {
        @Dependency var service: Service
        let report: @MainActor (Int) -> Void

        var body: some View {
            report(service.id)
            return Color.clear
        }
    }

    private func render(_ container: Container?) -> Int? {
        var seen: Int?
        let probe = Probe { seen = $0 }
        let renderer: ImageRenderer<AnyView> = if let container {
            ImageRenderer(content: AnyView(probe.container(container)))
        } else {
            ImageRenderer(content: AnyView(probe))
        }
        _ = renderer.cgImage
        return seen
    }

    @Test func dependencyResolvesFromTheContainerInTheEnvironment() {
        let container = Container {
            Register(Service.self) { _ in Service(id: 42) }
        }
        #expect(render(container) == 42)
    }

    @Test func innerContainerShadowsTheOuterOne() {
        let outer = Container { Register(Service.self) { _ in Service(id: 1) } }
        let inner = Container { Register(Service.self) { _ in Service(id: 2) } }
        var seen: Int?
        let probe = Probe { seen = $0 }
        let renderer = ImageRenderer(content: probe.container(inner).container(outer))
        _ = renderer.cgImage
        #expect(seen == 2)
    }
}

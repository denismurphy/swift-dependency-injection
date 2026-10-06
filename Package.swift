// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DependencyInjection",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "DependencyInjection", targets: ["DependencyInjection"]),
        .library(name: "DependencyInjectionSwiftUI", targets: ["DependencyInjectionSwiftUI"]),
    ],
    targets: [
        // Container, assemblies, @Inject. Foundation and Synchronization only.
        .target(
            name: "DependencyInjection",
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),

        // Environment-based container for SwiftUI view hierarchies.
        .target(
            name: "DependencyInjectionSwiftUI",
            dependencies: ["DependencyInjection"],
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),

        .testTarget(
            name: "DependencyInjectionTests",
            dependencies: ["DependencyInjection", "DependencyInjectionSwiftUI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

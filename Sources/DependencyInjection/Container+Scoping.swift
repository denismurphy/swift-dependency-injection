extension Container {
    /// The container `@Inject` reads from. Bound per task, so concurrently
    /// running tests can each have their own.
    @TaskLocal public static var current: Container = .shared

    /// Runs `operation` with `current` set to a child of the present
    /// `current` that carries `assembly`. Registrations in the assembly shadow
    /// the parent's; everything else falls through to it.
    ///
    /// The binding follows structured concurrency: child tasks inherit it,
    /// `Task.detached` does not.
    public static func withOverride<R>(
        _ assembly: Assembly,
        operation: () throws -> R
    ) rethrows -> R {
        let child = Container(parent: current)
        child.register(assembly)
        return try $current.withValue(child, operation: operation)
    }

    public nonisolated(nonsending) static func withOverride<R>(
        _ assembly: Assembly,
        operation: nonisolated(nonsending) () async throws -> R
    ) async rethrows -> R {
        let child = Container(parent: current)
        child.register(assembly)
        return try await $current.withValue(child, operation: operation)
    }
}

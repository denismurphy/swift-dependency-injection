/// How long a resolved instance lives.
public enum Scope: Sendable {
    /// A new instance for every resolution.
    case transient

    /// One instance per owning container, created on first resolution.
    case singleton
}

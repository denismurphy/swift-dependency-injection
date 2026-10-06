/// What a registration is filed under: the type it was registered for and an
/// optional binding name.
///
/// Equality and hashing use the address of the type's metadata
/// (`ObjectIdentifier`), so building a key allocates nothing and never
/// demangles a type name. The metatype itself is kept only to produce readable
/// diagnostics.
public struct DependencyKey: Hashable, Sendable, CustomStringConvertible {
    public let type: any Any.Type
    public let name: String?

    public init(_ type: any Any.Type, name: String? = nil) {
        self.type = type
        self.name = name
    }

    public static func == (lhs: DependencyKey, rhs: DependencyKey) -> Bool {
        ObjectIdentifier(lhs.type) == ObjectIdentifier(rhs.type) && lhs.name == rhs.name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(type))
        hasher.combine(name)
    }

    public var description: String {
        let typeName = String(reflecting: type)
        guard let name else { return typeName }
        return "\(typeName) (name: \"\(name)\")"
    }
}

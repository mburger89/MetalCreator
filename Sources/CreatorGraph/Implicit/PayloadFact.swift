/// One line the inspector shows about an implicit solid or a mesh (implicit spec §5.2): "Triangles" and "1,234,000".
public struct PayloadFact: Hashable, Sendable {
    public var label: String
    public var value: String

    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

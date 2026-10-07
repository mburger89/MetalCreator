/// A selection of edges on one solid, produced by selection-rule nodes.
public struct EdgeSet: Sendable {
    public var solid: Solid
    public var edges: [EdgeID]

    public init(solid: Solid, edges: [EdgeID]) {
        self.solid = solid
        self.edges = edges
    }
}

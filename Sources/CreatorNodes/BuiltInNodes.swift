import CreatorGraph

/// The node types of the vertical slice (spec §7.1), in palette order.
public enum BuiltInNodes {
    public static let all: [any NodeDefinition.Type] = [
        NumberNode.self, IntegerNode.self, VectorNode.self, PlaneNode.self, GraphParameterNode.self,
        SeriesNode.self, RangeNode.self, GridPointsNode.self,
        RectangleNode.self, RoundedRectangleNode.self, CircleNode.self, RegularPolygonNode.self, PolylineNode.self,
        ExtrudeNode.self, RevolveNode.self, LoftNode.self, BooleanNode.self, TransformNode.self,
    ]

    /// Create nodes with `registry.makeNode(_:at:)`: it seeds `defaultSettings` and flags
    /// Output nodes, the same way the editor's palette does.
    public static let registry = NodeRegistry(all)
}

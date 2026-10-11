import CreatorGraph

/// The built-in node types in palette order: the vertical slice's 26 (spec §7.1), the sketcher's Plane from Face and
/// Sketch (sketcher spec §7, S4) and the Lists & Trees nodes (7a spec §4).
public enum BuiltInNodes {
    public static let all: [any NodeDefinition.Type] = [
        NumberNode.self, IntegerNode.self, VectorNode.self, PlaneNode.self, PlaneFromFaceNode.self, GraphParameterNode.self,
        SeriesNode.self, RangeNode.self, GridPointsNode.self,
        RectangleNode.self, RoundedRectangleNode.self, CircleNode.self, RegularPolygonNode.self, PolylineNode.self,
        SketchNode.self,
        ExtrudeNode.self, RevolveNode.self, LoftNode.self, BooleanNode.self, TransformNode.self,
        EdgesByTagNode.self, EdgesByDirectionNode.self, EdgeFilterNode.self, AllEdgesNode.self, EdgeSetOpNode.self,
        FilletNode.self, ChamferNode.self,
        FlattenNode.self, GraftNode.self, PartitionNode.self, TreeStatisticsNode.self,
        OutputNode.self,
    ]

    /// Create nodes with `registry.makeNode(_:at:)`: it seeds `defaultSettings` and flags
    /// Output nodes, the same way the editor's palette does.
    public static let registry = NodeRegistry(all)
}

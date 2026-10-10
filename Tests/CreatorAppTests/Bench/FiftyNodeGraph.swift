// Test fixture file: spec §7.3's 50-node graph.
import CreatorGeometry
import CreatorGraph
import CreatorNodes
import Testing

/// Spec §7.3's "50-node graph": ten rows of Rectangle → Extrude → All Edges → Fillet → Output, so every node is
/// upstream of an Output and evaluates (a node that isn't has no result and draws idle). 50 nodes and 40 wires over
/// about 1,150 × 2,500 stored points, so a docked panel shows a few rows at zoom 1 and most of the graph zoomed out.
enum FiftyNodeGraph {
    static let rows = 10
    static let columnSpacing = 240.0
    static let rowSpacing = 260.0

    static func make() -> Graph {
        var builder = GraphBuilder()
        for row in 0..<rows {
            func at(_ column: Int) -> Vector2 { Vector2(Double(column) * columnSpacing, Double(row) * rowSpacing) }
            let rectangle = builder.add(RectangleNode.self, ["width": .number(Double(20 + row))], at: at(0))
            let extrude = builder.add(ExtrudeNode.self, ["distance": .number(5)], at: at(1))
            let edges = builder.add(AllEdgesNode.self, at: at(2))
            let fillet = builder.add(FilletNode.self, at: at(3))
            let output = builder.add(OutputNode.self, at: at(4))
            builder.wire(rectangle, "profile", to: extrude, "profile")
            builder.wire(extrude, "solid", to: edges, "solid")
            builder.wire(edges, "edges", to: fillet, "edges")
            builder.wire(fillet, "solid", to: output, "solid")
        }
        return builder.graph
    }
}

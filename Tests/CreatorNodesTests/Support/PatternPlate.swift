// Test fixture file: a plate with its top face on z = 0 and a grid of placements facing up from it.
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// The pattern nodes' test bed: a 60 × 40 × 6 plate standing on z = −6…0 (so Grid Points, which lie on z = 0, are on
/// its top face), a 2 × 2 grid at (±20, ±10) turned into placements facing +Z. Every shortcut and Place test starts here.
struct PatternPlate {
    var h = Harness()
    let plate: Node
    let grid: Node
    let placements: Node

    init(columns: Int = 2, rows: Int = 2, spacingX: Double = 40, spacingY: Double = 20) {
        plate = h.box(60, 40, 6, at: Vector3(0, 0, -6))
        grid = h.add(GridPointsNode.self, ["countX": .integer(columns), "countY": .integer(rows), "spacingX": .number(spacingX),
                                           "spacingY": .number(spacingY),
        ])
        placements = h.add(PointsToPlacementsNode.self)
        h.wire(grid, "points", to: placements, "points")
    }

    /// A cylinder tool of `diameter` standing from `bottom` to `top` on the Z axis (a circle on a plane at `bottom`).
    /// The Circle node that `cylinder(diameter:from:to:)` built `extrude` from.
    func circle(of extrude: Node) -> Node {
        let link = h.links.first { $0.to == Endpoint(node: extrude.id, socket: "profile") }
        return h.nodes[link?.from.node ?? extrude.id] ?? extrude
    }

    mutating func cylinder(diameter: Double, from bottom: Double, to top: Double) -> Node {
        let circle = h.add(CircleNode.self, ["diameter": .number(diameter), "plane": .plane(Plane.xy.offset(by: bottom))])
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(top - bottom)])
        h.wire(circle, "profile", to: extrude, "profile")
        return extrude
    }

    /// The volume of a Ø`diameter` cylinder `length` long.
    static func cylinderVolume(_ diameter: Double, _ length: Double) -> Double {
        Double.pi * diameter * diameter / 4 * length
    }

    static let plateVolume = 60.0 * 40 * 6
}

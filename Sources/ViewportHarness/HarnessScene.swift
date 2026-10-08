import CreatorGeometry
import CreatorKernel
import CreatorViewport

/// A bracket-like part made straight from kernel calls, so the viewport can be seen before the M3 nodes exist:
/// a 60 × 40 × 6 plate with four Ø5 holes, a 30 mm flange along the back, and R3 fillets on the vertical convex
/// edges. Also two handles: a linear one at the plate top and a radial one at a fillet.
enum HarnessScene {
    static func build(_ kernel: any Kernel, ghost: Bool, selectTop: Bool) async throws
        -> (items: [ViewportItem], handles: [ViewportHandle]) {
        let plate = try await kernel.extrude(.rectangle(width: 60, height: 40, plane: .xy), distance: 6, mode: .oneSided,
                                             tag: NodeTag(node: NodeID(), item: 0))
        let holeNode = NodeID()
        var holes: [Solid] = []
        for (item, centre) in [Vector2(-20, -12), Vector2(20, -12), Vector2(-20, 12), Vector2(20, 12)].enumerated() {
            holes.append(try await kernel.extrude(.circle(radius: 2.5, center: centre, plane: Plane.xy.offset(by: -1)),
                                                  distance: 8, mode: .oneSided, tag: NodeTag(node: holeNode, item: item)))
        }
        let drilled = try await kernel.boolean(.subtract, plate, holes, tag: NodeTag(node: NodeID(), item: 0))
        let flangePlane = Plane(origin: Vector3(0, 20, 15), normal: Vector3(0, -1, 0), xAxis: .unitX)
        let flange = try await kernel.extrude(.rectangle(width: 60, height: 30, plane: flangePlane), distance: 6,
                                              mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        let bracket = try await kernel.boolean(.union, drilled, [flange], tag: NodeTag(node: NodeID(), item: 0))
        let vertical = bracket.topology.edges.filter { edge in
            edge.kind == .line && !edge.isSeam && edge.convexity == .convex
                && abs((edge.direction ?? .zero).dot(.unitZ)) > 0.999
        }
        let part: Solid
        do {
            part = try await kernel.fillet(bracket, edges: vertical.map(\.id), radius: 3, tag: NodeTag(node: NodeID(), item: 0))
        } catch {
            print("ViewportHarness: the R3 fillet on \(vertical.count) vertical edges failed, showing the part without it: \(error)")
            part = bracket
        }
        var item = ViewportItem(solid: part, isGhost: ghost)
        if selectTop,
           let top = part.topology.faces.filter({ ($0.normal ?? .zero).dot(.unitZ) > 0.999 })
               .max(by: { $0.centroid.z < $1.centroid.z }) {
            item.selectedFaces = [top.id]
            item.selectedEdges = Set(part.topology.edges.filter { !$0.isSeam && $0.faces.contains(top.id) }.map(\.id))
        }
        let corner = vertical.first?.midpoint ?? Vector3(30, -20, 3)
        let handles = [
            ViewportHandle(id: "plate.distance", anchor: Vector3(0, -10, 0), direction: .unitZ, value: 6,
                           range: 0.5...50, style: .linear, tint: .solid),
            ViewportHandle(id: "fillet.radius", anchor: corner, direction: Vector3(corner.x, corner.y, 0), value: 3,
                           range: 0.1...10, style: .radial, tint: .feature),
        ]
        return ([item], handles)
    }
}

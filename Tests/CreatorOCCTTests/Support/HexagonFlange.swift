// Test fixture file: spec §8's polygon swap, plate and hexagon flange only, built through the kernel.
import CreatorGeometry
import CreatorKernel

/// The §7.2 bracket's plate (60 × 40, R4 corners, 6 thick) united with §8's hexagon flange (r 15, turned 30° so two
/// sides stand upright, on the XZ plane at y = 20, 8 thick, lifted 15 mm), and the four vertical edges of those two
/// upright sides, which the bracket's Fillet rounds. OCCT builds them at R3 but its checker rejects the solid
/// (spec Errata (Kernel: invalid blends)).
struct HexagonFlange {
    let union: Solid
    let uprightEdges: [EdgeID]

    static func make(_ kernel: any Kernel) async throws -> HexagonFlange {
        let plate = try await kernel.extrude(.roundedRectangle(width: 60, height: 40, radius: 4, plane: .xy), distance: 6,
                                             mode: .oneSided, tag: newTag())
        let hexagon = try await kernel.extrude(.regularPolygon(sides: 6, radius: 15, rotation: .degrees(30),
                                                               plane: Plane.xz.offset(by: -20)),
                                               distance: 8, mode: .oneSided, tag: newTag())
        let lifted = try await kernel.transform(hexagon, by: Transform(translation: Vector3(0, 0, 15)), tag: newTag())
        let union = try await kernel.boolean(.union, plate, [lifted], tag: newTag())
        let upright = union.topology.edges.filter { edge in
            edge.kind == .line && edge.convexity == .convex && !edge.isSeam && abs((edge.direction ?? .zero).dot(.unitZ)) > 0.999
        }
        return HexagonFlange(union: union, uprightEdges: upright.map(\.id))
    }
}

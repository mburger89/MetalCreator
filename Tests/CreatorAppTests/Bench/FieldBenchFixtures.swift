// Test fixture file: the fields and points the field benchmarks sample (fields spec §7).
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes

/// What `FieldBench` measures, built here so a plain `swift test` can check it is what the benchmark says it is.
enum FieldBenchFixtures {
    /// Row 1: a source, a remap, noise, a multiply and a clamp (five nodes, no kernel distance).
    static let fiveNodeField: Field = {
        let radial = Field.radialGradient(center: Vector3(5, -3, 2), radius: 40)
        let remapped = Field.remap(radial, fromLow: 0, fromHigh: 1, toLow: 1, toHigh: 0, clamped: true)
        let noise = Field.noise(seed: 4, scale: 8, octaves: 2)
        return .clamp(.multiply(remapped, noise), low: 0, high: 1)
    }()

    /// `count` points spread over a 100 × 80 × 20 region, the same every time.
    static func points(_ count: Int) -> [Vector3] {
        (0..<count).map { index in
            Vector3(Double(index % 101) - 50, Double((index * 7) % 81) - 40, Double((index * 3) % 21) - 5)
        }
    }

    /// Row 2: the plate whose signed distance is sampled, 60 × 40 × 6 with R4 corners.
    static func plate(_ kernel: any Kernel) async throws -> Solid {
        try await kernel.extrude(.roundedRectangle(width: 60, height: 40, radius: 4, plane: .xy), distance: 6, mode: .oneSided,
                                 tag: NodeTag(node: NodeID(), item: 0))
    }

    /// Row 2b: a smooth loft through three circles (Ø10, Ø6 and Ø12 at 0, 10 and 20 mm), whose faces are B-spline, not planes and
    /// cylinders: the cost of a point against a solid the 100 ms target was never measured on.
    static func loft(_ kernel: any Kernel) async throws -> Solid {
        let sections = [(0.0, 5.0), (10, 3), (20, 6)].map { height, radius in
            Profile2D.circle(radius: radius, center: .zero, plane: Plane.xy.offset(by: height))
        }
        return try await kernel.loft(sections, ruled: false, tag: NodeTag(node: NodeID(), item: 0))
    }

    /// Row 3b: `rows` branches of `columns` placements 4 mm apart, as a Grid Pattern makes them.
    static func placements(rows: Int, columns: Int) -> DataTree {
        let branches = (0..<rows).map { row in
            DataTree.list((0..<columns).map { column in .plane(.through(Vector3(Double(column) * 4, Double(row) * 4, 0))) })
        }
        return DataTree(depth: 2, branches: branches) ?? .empty(depth: 2)
    }

    /// Row 3b's field: noise plus a radial gradient over the placements' region.
    static let placementField = Field.add(.noise(seed: 9, scale: 12, octaves: 2), .radialGradient(center: Vector3(100, 80, 0), radius: 160))

    /// Row 3: a 120 × 120 × 6 plate (top on z = 0) and the pick of its top face, which Field Scatter fills.
    static func scatterPlate(_ kernel: any Kernel) async throws -> (solid: Solid, pick: FacePick) {
        let solid = try await kernel.extrude(.rectangle(width: 120, height: 120, plane: Plane.xy.offset(by: -6)), distance: 6,
                                             mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        let tops = solid.topology.faces.filter { $0.kind == .plane && $0.normal == .unitZ }
        guard let top = tops.max(by: { $0.centroid.z < $1.centroid.z }), let pick = solid.topology.facePick(for: top.id) else {
            throw KernelError.operationFailed(operation: "fixture", reason: "the plate has no top face")
        }
        return (solid, pick)
    }

    /// Row 3's field: the distance from the face's middle over 60 mm, so the points are 1.4 mm apart in the middle and 2.4 mm
    /// apart from 60 mm out, with no kernel distance.
    static let scatterField = Field.radialGradient(center: .zero, radius: 60)

    /// Row 3's inputs to Field Scatter: the plate, the field, spacing 1.4 to 2.4 mm, a 3 mm margin, seed 5.
    static func scatterInputs(_ solid: Solid) -> NodeInputs {
        NodeInputs(item: 0, slots: [
            "solid": .item(.solid(solid)), "field": .item(.field(scatterField)), "minSpacing": .item(.number(1.4)),
            "maxSpacing": .item(.number(2.4)), "margin": .item(.number(3)), "seed": .item(.integer(5)),
        ])
    }

    /// The context of a Field Scatter node holding the face pick.
    static func scatterContext(pick: FacePick) -> EvalContext {
        var node = BuiltInNodes.registry.makeNode(FieldScatterNode.typeID)
        node.inputValues[NodeSetting.face] = .facePick(pick)
        return EvalContext(node: node, item: 0, parameters: [:])
    }
}

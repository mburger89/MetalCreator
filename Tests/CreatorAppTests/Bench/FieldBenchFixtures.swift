// Test fixture file: the fields and points the field benchmarks sample (fields spec §7).
import CreatorGeometry
import CreatorGraph
import CreatorKernel

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

    /// Row 3: `rows` branches of `columns` placements 4 mm apart, as a Grid Pattern makes them.
    static func placements(rows: Int, columns: Int) -> DataTree {
        let branches = (0..<rows).map { row in
            DataTree.list((0..<columns).map { column in .plane(.through(Vector3(Double(column) * 4, Double(row) * 4, 0))) })
        }
        return DataTree(depth: 2, branches: branches) ?? .empty(depth: 2)
    }

    /// Row 3's field: noise plus a radial gradient over the placements' region.
    static let placementField = Field.add(.noise(seed: 9, scale: 12, octaves: 2), .radialGradient(center: Vector3(100, 80, 0), radius: 160))
}

import CreatorGeometry
import CreatorGraph
import CreatorImplicit

/// One solid of every kind, for the tests that run over all of them.
enum ImplicitFixtures {
    static let sphere = ImplicitSolid.sphere(radius: 10)
    static let box = ImplicitSolid.box(halfSize: Vector3(8, 6, 4), cornerRadius: 1.5)
    static let cylinder = ImplicitSolid.cylinder(radius: 5, halfHeight: 7)

    /// 1 + z / 20: between 0.5 and 1.5 for |z| ≤ 10, slope 0.05 per mm.
    static let graded = Grading(field: .add(.constant(1), .linearGradient(plane: .xy, length: 20)), range: 0.5...1.5, slope: 0.05)

    /// Noise remapped to 0.6 ... 1.6 mm, with the slope `Field.slopeBound` declares for it.
    static var noisy: Grading {
        let field = Field.remap(.noise(seed: 4, scale: 6, octaves: 2), fromLow: 0, fromHigh: 1, toLow: 0.6, toHigh: 1.6, clamped: true)
        return Grading(field: field, range: 0.6...1.6, slope: field.slopeBound.value)
    }

    static var moved: ImplicitSolid {
        let move = RigidMove(plane: Plane(origin: Vector3(12, -3, 5), normal: Vector3(1, 1, 0.5), xAxis: Vector3(0, 0, 1)))
        return .moved(box, move ?? .identity)
    }

    static var baked: ImplicitSolid {
        let blocks = BlocksFixture.make(origin: Vector3(-16, -16, -16), spacing: 1, blocks: 4) { $0.length - 9 }
        return .baked(blocks, label: "Ball")
    }

    /// Where |p| / 20 is below 0.5, i.e. a ball of radius 10, clipped to ±15.
    static let isosurface = ImplicitSolid.isosurface(
        Grading(field: .radialGradient(center: .zero, radius: 20), range: 0...2, slope: 0.05), level: 0.5, maxSlope: 0.05,
        region: BoundingBox(min: Vector3(-15, -15, -15), max: Vector3(15, 15, 15)))

    static let all: [(name: String, solid: ImplicitSolid)] = [
        ("sphere", sphere), ("box", box), ("cylinder", cylinder), ("moved", moved),
        ("union", .union([sphere, .moved(box, RigidMove(origin: Vector3(9, 0, 0), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ))],
                         blend: .constant(0))),
        ("smooth union", .union([sphere, cylinder], blend: .constant(3))),
        ("graded smooth union", .union([sphere, cylinder], blend: graded)),
        ("subtract", .subtract([sphere, cylinder], blend: .constant(0))),
        ("smooth subtract", .subtract([sphere, cylinder, box], blend: .constant(2))),
        ("intersect", .intersect([sphere, box], blend: .constant(0))),
        ("smooth intersect", .intersect([sphere, box], blend: .constant(2.5))),
        ("offset", .offset(box, distance: .constant(2))),
        ("graded offset", .offset(sphere, distance: graded)),
        ("inward shell", .shell(sphere, thickness: .constant(2), side: .inward)),
        ("outward shell", .shell(box, thickness: .constant(1.5), side: .outward)),
        ("graded centred shell", .shell(sphere, thickness: graded, side: .centred)),
        ("noisy shell", .shell(box, thickness: noisy, side: .inward)),
        ("noisy smooth union", .union([sphere, cylinder], blend: noisy)),
        ("baked", baked), ("isosurface", isosurface),
    ]
}

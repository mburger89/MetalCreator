import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// A solid with no geometry, only an identity, for the distance targets of baked gradings.
final class StandInStorage: SolidStorage {
    var estimatedBytes: Int { 64 }
}

/// The solids the GPU is checked against the CPU on: every fixture, and one for each kind of field.
enum GPUFixtures {
    static let stand = Solid(topology: Topology(faces: [], edges: []), bounds: BoundingBox(min: .zero, max: Vector3(1, 1, 1)),
                             storage: StandInStorage())

    /// A 6 × 5 picture with a gradient and some steps.
    static let picture = GreyImage(width: 6, height: 5, pixels: (0..<30).map { UInt16(($0 * 2_017 + ($0 % 4) * 9_000) % 65_536) })

    static func graded(_ field: Field, range: ClosedRange<Double> = 0...2, baked: [Grading.Baked] = []) -> Grading {
        Grading(field: field, baked: baked, range: range, slope: max(field.slopeBound.value, 0.05))
    }

    static var bakedGrading: Grading {
        let blocks = BlocksFixture.make(origin: Vector3(-20, -20, -20), spacing: 1.25, blocks: 4) { $0.length - 8 }
        let baked = Grading.Baked(target: DistanceTarget.solid(stand).identity, signed: true, blocks: blocks)
        let field = Field.remap(.distance(.kernel(.solid(stand)), signed: true), fromLow: -8, fromHigh: 8, toLow: 0.4, toHigh: 1.6,
                                clamped: true)
        return graded(field, range: 0.4...1.6, baked: [baked])
    }

    /// Fixtures that agree in value (`GPUAgreementTests`, 1e-4 mm) but whose meshes sit up to 1.7 times past D17's allowance in the GPU
    /// mesh comparison, which therefore allows them twice it: their lattice coordinates reach 40 to 70 mm (a mapping about an axis 30 mm
    /// to the side of the region, or round a cylinder 20 mm to its side), where Float rounds a coordinate by up to 4e-6 mm and a
    /// near-tangent mesh edge turns that into a slide of 1.1e-4 to 1.7e-4 mm along the surface's normal (spec Errata D20).
    static let meshMarginal: Set<String> = [
        "bcc struts, graded cell, blended, cylindrical beside", "diamond, graded cell, spherical beside the region",
        "voronoi foam, face outside a cylinder",
    ]

    /// What the pipeline comparison multiplies D17's allowance by for the fixture `name`.
    static func meshAllowanceFactor(_ name: String) -> Float { meshMarginal.contains(name) ? 2 : 1 }

    static var all: [(name: String, solid: ImplicitSolid)] {
        let sphere = ImplicitSolid.sphere(radius: 10)
        let noise = Field.noise(seed: 21, scale: 7, octaves: 3)
        let stretched = Field.remap(noise, fromLow: 0, fromHigh: 1, toLow: -1, toHigh: 2, clamped: true)
        let maths = Field.smoothMinimum(
            .multiply(.clamp(.linearGradient(plane: .xy, length: 12), low: 0, high: 1),
                      .radialGradient(center: Vector3(1, 2, 3), radius: 9)),
            .remap(.distance(.point(Vector3(-2, 0, 4)), signed: false), fromLow: 0, fromHigh: 20, toLow: 1.5, toHigh: 0.5, clamped: false),
            width: 0.7)
        var fixtures = ImplicitFixtures.all + LatticeFixtures.mappedAll + LatticeFixtures.faceOutsideAll
        fixtures += [
            ("noise offset", .offset(sphere, distance: graded(stretched))),
            ("noise tile image", .shell(sphere, thickness: graded(.add(.constant(0.5), picture.map {
                .image($0, plane: .xy, width: 25, height: 20, edges: .tile)
            } ?? .constant(0))), side: .outward)),
            ("clamped image", .offset(sphere, distance: graded(picture.map {
                .image($0, plane: Plane(origin: Vector3(1, -2, 0), normal: .unitZ, xAxis: Vector3(1, 1, 0)), width: 14, height: 9,
                       edges: .clamp)
            } ?? .constant(0), range: 0...1))),
            ("maths", .union([sphere, ImplicitFixtures.cylinder], blend: graded(maths, range: -5...5))),
            ("kernel distance", .shell(sphere, thickness: bakedGrading, side: .centred)),
            ("empty union", .union([], blend: .constant(0))),
            ("empty intersect", .intersect([], blend: .constant(0))),
            ("empty subtract", .subtract([], blend: .constant(0))),
            ("implicit leaf", .offset(sphere, distance: graded(.implicit(ImplicitSolid.sphere(radius: 4).reference), range: -4...30))),
        ]
        return fixtures
    }

    /// 600 points around the origin, from a fixed seed.
    static let points: [SIMD3<Float>] = {
        let random = SeededRandom(seed: 99, stream: 4)
        return (0..<600).map { SIMD3(Float(random.unit(at: 3 * $0) * 36 - 18), Float(random.unit(at: 3 * $0 + 1) * 36 - 18),
                                     Float(random.unit(at: 3 * $0 + 2) * 36 - 18)) }
    }()
}

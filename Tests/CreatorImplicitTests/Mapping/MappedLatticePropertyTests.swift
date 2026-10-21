import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// What every lattice must keep under every mapping (implicit spec §7: "a Lipschitz property test on random point pairs for every node
/// and every mapping"): the surface stays inside the bounds, and the constant holds on random pairs, on pairs across the cut of the
/// angle, and on pairs next to the singular set, where the lattice fades into the solid.
struct MappedLatticePropertyTests {
    static var names: [String] { LatticeFixtures.mappedAll.map(\.name) }

    func solid(_ name: String) throws -> ImplicitSolid {
        try #require(LatticeFixtures.mappedAll.first { $0.name == name }?.solid)
    }

    @Test(arguments: MappedLatticePropertyTests.names)
    func nothingIsInsideOutsideTheBounds(_ name: String) throws {
        let solid = try solid(name)
        let box = solid.bounds
        let outside = ImplicitSolidPropertyTests.points(in: ImplicitSolid.grown(box, by: 6), count: 4000, stream: 1).filter { point in
            point.x < box.min.x || point.x > box.max.x || point.y < box.min.y || point.y > box.max.y
                || point.z < box.min.z || point.z > box.max.z
        }
        #expect(outside.count > 500)
        #expect(solid.signedDistances(at: outside).allSatisfy { $0 > -1e-9 }, "\(name)")
    }

    @Test(arguments: MappedLatticePropertyTests.names)
    func theLipschitzConstantHoldsOnRandomPairs(_ name: String) throws {
        let solid = try solid(name)
        let region = ImplicitSolid.grown(solid.bounds, by: 3)
        let first = ImplicitSolidPropertyTests.points(in: region, count: 4000, stream: 2)
        let second = ImplicitSolidPropertyTests.points(in: region, count: 4000, stream: 3)
        let (a, b) = (solid.signedDistances(at: first), solid.signedDistances(at: second))
        var worst = 0.0
        for index in first.indices {
            let gap = (first[index] - second[index]).length
            guard gap > 1e-9 else { continue }
            worst = max(worst, abs(a[index] - b[index]) / gap)
        }
        #expect(worst <= solid.lipschitz + 1e-9, "\(name): measured \(worst) against L = \(solid.lipschitz)")
    }

    /// Pairs a hair apart in a box around the crossing point, where the singular set, its fade and the cut all are.
    @Test(arguments: MappedLatticePropertyTests.names)
    func nearbyPairsNextToTheSingularSetAndTheCutAreWithinTheConstantToo(_ name: String) throws {
        let solid = try solid(name)
        let centre = LatticeFixtures.crossing
        let box = BoundingBox(min: centre - Vector3(4, 4, 14), max: centre + Vector3(4, 4, 14))
        let nudge = Vector3(0.01, -0.02, 0.015)
        let first = ImplicitSolidPropertyTests.points(in: box, count: 3000, stream: 5)
        let (a, b) = (solid.signedDistances(at: first), solid.signedDistances(at: first.map { $0 + nudge }))
        let worst = zip(a, b).map { abs($0 - $1) / nudge.length }.max() ?? 0
        #expect(worst <= solid.lipschitz + 1e-6, "\(name): measured \(worst) against L = \(solid.lipschitz)")
    }

    @Test func aMappingRaisesTheBoundByItsStretch() throws {
        let straight = LatticeFixtures.tpmsAll[0].solid
        func wrapped(through x: Double) -> Double {
            LatticeFixtures.mapped(straight, LatticeFixtures.cylinder(through: Vector3(x, 4, 0), cell: 8, radius: 9)).lipschitz
        }
        // The region reaches x = -6, and the bound is made over the region grown by 4 mm: an axis at -60 is 50 mm from it, one at -12
        // is 2 mm from it (stretch 4.5), and one at 8 crosses it, where the exclusion and the fade are in play.
        #expect(wrapped(through: -60) <= straight.lipschitz * 1.0001, "a mapping 50 mm away does not stretch")
        #expect(wrapped(through: -12) > straight.lipschitz * 3)
        #expect(wrapped(through: 8) > wrapped(through: -12))
        let crossing = try solid("gyroid, cylindrical through the region")
        #expect(crossing.lipschitz == wrapped(through: 8))
    }
}

import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// Properties every node must have (implicit spec §7): bounds contain the surface, and the lipschitz constant holds on random
/// point pairs.
struct ImplicitSolidPropertyTests {
    /// Points from a seeded generator, so a failure is the same every time.
    static func points(in box: BoundingBox, count: Int, stream: Int) -> [Vector3] {
        let random = SeededRandom(seed: 7, stream: stream)
        return (0..<count).map { index in
            Vector3(box.min.x + box.size.x * random.unit(at: 3 * index), box.min.y + box.size.y * random.unit(at: 3 * index + 1),
                    box.min.z + box.size.z * random.unit(at: 3 * index + 2))
        }
    }

    @Test(arguments: ImplicitFixtures.all.map(\.name))
    func nothingIsInsideOutsideTheBounds(_ name: String) throws {
        let solid = try #require(ImplicitFixtures.all.first { $0.name == name }?.solid)
        let box = solid.bounds
        let region = ImplicitSolid.grown(box, by: 6)
        let outside = Self.points(in: region, count: 4000, stream: 1).filter { point in
            point.x < box.min.x || point.x > box.max.x || point.y < box.min.y || point.y > box.max.y
                || point.z < box.min.z || point.z > box.max.z
        }
        #expect(outside.count > 500)
        let values = solid.signedDistances(at: outside)
        #expect(values.allSatisfy { $0 > -1e-9 }, "\(name): the smallest value outside the bounds is \(values.min() ?? 0)")
    }

    @Test(arguments: ImplicitFixtures.all.map(\.name))
    func theLipschitzConstantHoldsOnRandomPairs(_ name: String) throws {
        let solid = try #require(ImplicitFixtures.all.first { $0.name == name }?.solid)
        let region = ImplicitSolid.grown(solid.bounds, by: 3)
        let first = Self.points(in: region, count: 3000, stream: 2), second = Self.points(in: region, count: 3000, stream: 3)
        let (a, b) = (solid.signedDistances(at: first), solid.signedDistances(at: second))
        var worst = 0.0
        for index in first.indices {
            let gap = (first[index] - second[index]).length
            guard gap > 1e-9 else { continue }
            worst = max(worst, abs(a[index] - b[index]) / gap)
        }
        #expect(worst <= solid.lipschitz + 1e-9, "\(name): measured \(worst) against L = \(solid.lipschitz)")
    }

    @Test func nearbyPairsAreWithinTheConstantToo() throws {
        // Close pairs probe the local gradient, where a missing derivative term (a graded blend) would show.
        for (name, solid) in ImplicitFixtures.all {
            let region = solid.bounds
            let first = Self.points(in: region, count: 2000, stream: 4)
            let nudged = first.map { $0 + Vector3(0.01, -0.02, 0.015) }
            let (a, b) = (solid.signedDistances(at: first), solid.signedDistances(at: nudged))
            let gap = Vector3(0.01, -0.02, 0.015).length
            let worst = zip(a, b).map { abs($0 - $1) / gap }.max() ?? 0
            #expect(worst <= solid.lipschitz + 1e-6, "\(name): measured \(worst) against L = \(solid.lipschitz)")
        }
    }
}

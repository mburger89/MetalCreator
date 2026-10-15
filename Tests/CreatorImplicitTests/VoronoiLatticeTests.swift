import CreatorGeometry
import CreatorGraph
import Foundation
import Testing
@testable import CreatorImplicit

/// The Voronoi lattice (implicit spec §3.4, §7): the seed grid, exact wall distances for a few seeds, the strut scale at an edge of
/// three equal cells, the window against a search over every seed, holes, and the constants.
struct VoronoiLatticeTests {
    static let box = BoundingBox(min: Vector3(-100, -100, -100), max: Vector3(100, 100, 100))

    func lattice(_ points: [Vector3], _ form: VoronoiForm, thickness: Double = 0, radius: Double = 50) -> ImplicitSolid {
        LatticeFixtures.voronoi(points, form, thickness: .constant(thickness), radius: radius, in: Self.box)
    }

    // MARK: The grid

    @Test func everySeedIsInTheGridOnceInTheCellThatContainsIt() {
        let points = LatticeFixtures.seeds(200, in: BoundingBox(min: Vector3(-30, 5, 0), max: Vector3(30, 60, 25)), seed: 8)
        let seeds = VoronoiSeeds(points: points, radius: 7)
        #expect(seeds.entries.sorted() == (0..<200).map(Int32.init))
        #expect(seeds.starts.count == seeds.counts.reduce(1, *) + 1 && seeds.starts.last == 200)
        for cell in 0..<seeds.counts.reduce(1, *) {
            for entry in Int(seeds.starts[cell])..<Int(seeds.starts[cell + 1]) {
                let point = points[Int(seeds.entries[entry])] - seeds.origin
                let (x, y, z) = (Int(point.x / seeds.radius), Int(point.y / seeds.radius), Int(point.z / seeds.radius))
                #expect((min(z, seeds.counts[2] - 1) * seeds.counts[1] + min(y, seeds.counts[1] - 1)) * seeds.counts[0]
                    + min(x, seeds.counts[0] - 1) == cell)
            }
        }
    }

    @Test func aHugeGridGetsLargerCellsAndASingleSeedMakesOneCell() {
        let spread = VoronoiSeeds(points: [Vector3(0, 0, 0), Vector3(1_000_000, 1_000_000, 1_000_000)], radius: 1)
        #expect(spread.counts.reduce(1, *) <= VoronoiSeeds.maximumCells && spread.radius > 1)
        let single = VoronoiSeeds(points: [Vector3(3, 4, 5)], radius: 2)
        #expect(single.counts == [1, 1, 1] && single.radius == 2)
    }

    @Test func theSearchRadiusIsTwiceTheMeanSpacing() {
        let region = BoundingBox(min: .zero, max: Vector3(20, 20, 20))
        #expect(abs(VoronoiSeeds.searchRadius(count: 8, in: region) - 20) < 1e-12)
    }

    @Test func theNearestDistanceSeesOnlyTheWindow() {
        let seeds = VoronoiSeeds(points: [Vector3(0, 0, 0), Vector3(30, 0, 0)], radius: 5)
        #expect(seeds.nearestDistance(to: Vector3(3, 4, 0)) == 5)
        #expect(seeds.nearestDistance(to: Vector3(15, 0, 0)) == nil, "farther than a cell from every seed")
        #expect(seeds.nearestDistance(to: Vector3(500, 0, 0)) == nil && seeds.nearestDistance(to: Vector3(-500, 9, 9)) == nil)
    }

    @Test func gapsAreSeedsThatDoNotReachTheRegion() {
        let region = BoundingBox(min: .zero, max: Vector3(40, 40, 40))
        let spread = VoronoiSeeds(points: LatticeFixtures.seeds(200, in: region, seed: 5),
                                  radius: VoronoiSeeds.searchRadius(count: 200, in: region))
        #expect(spread.uncoveredFraction(in: region) == 0)
        let corner = BoundingBox(min: .zero, max: Vector3(8, 8, 8))
        let clustered = VoronoiSeeds(points: LatticeFixtures.seeds(200, in: corner, seed: 5),
                                     radius: VoronoiSeeds.searchRadius(count: 200, in: region))
        #expect(clustered.uncoveredFraction(in: region) > 0.5)
    }

    // MARK: Walls

    @Test func foamIsTheDistanceToTheNearestPlaneHalfWayToAnotherSeed() {
        let two = lattice([Vector3(0, 0, 0), Vector3(10, 0, 0)], .foam, thickness: 0.6)
        #expect(abs(two.signedDistance(at: Vector3(3, 2, 1)) - (2 - 0.3)) < 1e-12, "the wall is the plane x = 5")
        #expect(abs(two.signedDistance(at: Vector3(5, 7, -3)) + 0.3) < 1e-12, "on the wall")
        #expect(abs(two.signedDistance(at: Vector3(8, 0, 0)) - (3 - 0.3)) < 1e-12, "the other side")
        let three = lattice([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 6, 0)], .foam)
        #expect(abs(three.signedDistance(at: Vector3(1, 1, 0)) - 2) < 1e-12, "the plane y = 3 is nearer than x = 5")
    }

    @Test func foamChangesByNoMoreThanTheDistanceWalked() {
        let points = LatticeFixtures.seeds(30, in: BoundingBox(min: Vector3(-20, -20, -20), max: Vector3(20, 20, 20)), seed: 4)
        let solid = lattice(points, .foam)
        for probe in LatticeFixtures.seeds(60, in: BoundingBox(min: Vector3(-15, -15, -15), max: Vector3(15, 15, 15)), seed: 6) {
            let here = solid.signedDistance(at: probe)
            let nearestSeed = points.min { ($0 - probe).length < ($1 - probe).length } ?? .zero
            // Walking away from the nearest seed: the value can only fall by the step.
            let step = (probe - nearestSeed).normalized ?? .unitX
            #expect(solid.signedDistance(at: probe + step * 0.5) >= here - 0.5 - 1e-9)
        }
    }

    // MARK: Edges

    /// A triangular lattice of seeds 10 mm apart in the plane z = 0: cells are hexagonal prisms, and three equal cells meet at each edge.
    func triangularSeeds() -> [Vector3] {
        (-6...6).flatMap { j in (-6...6).map { Vector3(10 * Double($0) + 5 * Double(j), 5 * 3.0.squareRoot() * Double(j), 0) } }
    }

    @Test func strutsGrowAtOnePointFiveOverTheStrutScaleFromAnEdgeOfThreeEqualCells() {
        let solid = lattice(triangularSeeds(), .struts, thickness: 0)
        let edge = Vector3(5, 5 / 3.0.squareRoot(), 0)
        #expect(abs(solid.signedDistance(at: edge)) < 1e-9, "on the edge d₃ = d₁")
        let towardsSeed = (Vector3.zero - edge).normalized ?? .unitX
        for offset in [0.2, 0.4] {
            let value = solid.signedDistance(at: edge + towardsSeed * offset)
            #expect(abs(value / offset - 1) < 0.03, "\(offset) mm from the edge the value is \(value)")
        }
        let alongWall = Vector3(5, 0, 0)
        #expect(solid.signedDistance(at: alongWall) > 2, "the middle of a wall is far from an edge")
    }

    @Test func aStrutsDiameterIsTheThickness() {
        let solid = lattice(triangularSeeds(), .struts, thickness: 1)
        let edge = Vector3(5, 5 / 3.0.squareRoot(), 0)
        #expect(abs(solid.signedDistance(at: edge) + 0.5) < 1e-9)
        #expect(solid.signedDistance(at: edge + Vector3(0, 0.45, 0)) < 0.05 && solid.signedDistance(at: edge + Vector3(0, 0.7, 0)) > 0)
    }

    // MARK: Equivalence, holes

    /// The same two values from every seed instead of the 27 cells: the reference the window must reproduce.
    func everySeed(_ points: [Vector3], radius: Double, _ form: VoronoiForm, at p: Vector3) -> Double {
        let distances = points.map { (p - $0).length }.sorted()
        switch form {
        case .struts:
            return (min(distances.count > 2 ? distances[2] : .infinity, radius) - min(distances[0], radius)) / VoronoiLattice.strutScale
        case .foam:
            guard let nearest = points.indices.min(by: { distances2(points[$0], p) < distances2(points[$1], p) }) else { return 0 }
            var wall = max(0, (radius - distances[0]) / 2)
            for (index, position) in points.enumerated() where index != nearest {
                let across = position - points[nearest]
                wall = min(wall, across.dot((points[nearest] + position) * 0.5 - p) / across.length)
            }
            return wall
        }
    }

    func distances2(_ a: Vector3, _ b: Vector3) -> Double { (a - b).dot(a - b) }

    @Test(arguments: [VoronoiForm.struts, .foam])
    func theWindowOf27CellsGivesWhatEverySeedGives(_ form: VoronoiForm) {
        let points = LatticeFixtures.seeds(120, in: BoundingBox(min: Vector3(-30, -30, -30), max: Vector3(30, 30, 30)), seed: 12)
        let radius = VoronoiSeeds.searchRadius(count: 120, in: BoundingBox(min: Vector3(-30, -30, -30), max: Vector3(30, 30, 30)))
        let solid = lattice(points, form, thickness: 0, radius: radius)
        guard case .voronoi(let made) = solid else { Issue.record("not a Voronoi lattice"); return }
        #expect(made.seeds.radius == radius)
        for probe in LatticeFixtures.seeds(400, in: BoundingBox(min: Vector3(-45, -45, -45), max: Vector3(45, 45, 45)), seed: 13) {
            let expected = everySeed(points, radius: radius, form, at: probe)
            #expect(abs(solid.signedDistance(at: probe) - expected) < 1e-9, "\(form.name) at \(probe)")
        }
    }

    @Test(arguments: [VoronoiForm.struts, .foam])
    func aPointWithNoSeedInReachIsOnAWall(_ form: VoronoiForm) {
        let solid = lattice([Vector3.zero, Vector3(4, 0, 0)], form, thickness: 0.8, radius: 5)
        #expect(abs(solid.signedDistance(at: Vector3(60, 0, 0)) + 0.4) < 1e-12, "a hole is solid, not a gap")
        #expect(solid.signedDistance(at: Vector3(-90, 40, 20)) <= -0.4 + 1e-12)
    }

    @Test func duplicateSeedsAndASingleSeedAreHarmless() {
        let duplicates = lattice([Vector3(1, 1, 1), Vector3(1, 1, 1), Vector3(9, 1, 1)], .foam, thickness: 0.2)
        #expect(duplicates.signedDistance(at: Vector3(2, 2, 2)).isFinite)
        let one = lattice([Vector3(1, 1, 1)], .struts, thickness: 0.2)
        #expect(one.signedDistance(at: Vector3(2, 2, 2)).isFinite)
        #expect(lattice([Vector3(1, 1, 1)], .foam, thickness: 0).signedDistance(at: Vector3(1, 1, 1)) == 25, "(50 - 0) / 2: the cap")
    }

    // MARK: Region, constants, recipe

    @Test func theLatticeIsCutOffAtTheRegionsBox() {
        let region = BoundingBox(min: .zero, max: Vector3(10, 10, 10))
        let solid = LatticeFixtures.voronoi(LatticeFixtures.seeds(20, in: region, seed: 2), .foam, thickness: .constant(0.5), in: region)
        #expect(solid.bounds == region)
        #expect(solid.signedDistance(at: Vector3(14, 5, 5)) >= 4 - 1e-12)
    }

    @Test func theConstantsAreOneForFoamAndTwoOverTheStrutScaleForStruts() {
        let points = LatticeFixtures.seeds(10, seed: 1)
        #expect(LatticeFixtures.voronoi(points, .foam, thickness: .constant(1)).lipschitz == 1)
        #expect(abs(LatticeFixtures.voronoi(points, .struts, thickness: .constant(1)).lipschitz - 2 / 1.5) < 1e-12)
        #expect(abs(LatticeFixtures.voronoi(points, .foam, thickness: ImplicitFixtures.graded).lipschitz - 1.025) < 1e-12)
    }

    @Test func theRecipeCountsTheSeeds() {
        let points = LatticeFixtures.seeds(25, seed: 3)
        #expect(LatticeFixtures.voronoi(points, .foam, thickness: .constant(0.8)).description == "voronoi foam(25 seeds, t = 0.8 mm)")
        #expect(LatticeFixtures.voronoi(points, .struts, thickness: .constant(1)).description == "voronoi struts(25 seeds, t = 1 mm)")
    }

    @Test func theSeedsAreInTheByteEstimate() {
        let few = LatticeFixtures.voronoi(LatticeFixtures.seeds(10, seed: 3), .foam, thickness: .constant(1))
        let many = LatticeFixtures.voronoi(LatticeFixtures.seeds(1_000, seed: 3), .foam, thickness: .constant(1))
        #expect(many.estimatedBytes > few.estimatedBytes + 24_000)
    }
}

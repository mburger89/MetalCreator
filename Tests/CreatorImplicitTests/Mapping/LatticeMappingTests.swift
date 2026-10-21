import CreatorGeometry
import Foundation
import Testing
@testable import CreatorImplicit

/// The cylindrical and spherical maps (implicit spec §3.5, §7): hand-worked coordinates, the stretch bound, the singular set, the
/// join that leaves it solid, the mean radius and the rounding of a turn to whole cells.
struct LatticeMappingTests {
    static let region = BoundingBox(min: Vector3(-30, -30, -20), max: Vector3(30, 30, 20))
    static let pi = Double.pi

    func cylinder(radius: Double = 10, over box: BoundingBox = region, plane: Plane = .xy) throws -> LatticeMapping {
        .cylindrical(try #require(CylindricalMap(axis: plane, radius: radius, over: box)))
    }

    func sphere(radius: Double = 10, centre: Vector3 = .zero, over box: BoundingBox = region) throws -> LatticeMapping {
        .spherical(try #require(SphericalMap(centre: centre, radius: radius, over: box)))
    }

    /// True when the whole segment a-b is at least the exclusion from the singular set (sampled finely; the distance is convex in
    /// the plane transverse to the axis, so its minimum along a segment is found well by sampling).
    func segmentStaysOutsideTheExclusion(_ map: LatticeMapping, _ a: Vector3, _ b: Vector3) -> Bool {
        (0...64).allSatisfy { map.singularDistance(at: a + (b - a) * (Double($0) / 64)) >= LatticeMapping.exclusion }
    }

    func near(_ a: Vector3, _ b: Vector3, _ tolerance: Double = 1e-9) -> Bool { (a - b).length < tolerance }

    // MARK: Straight

    @Test func straightIsTheIdentityAndHasNoSingularSet() {
        let p = Vector3(3, -4, 5)
        #expect(LatticeMapping.straight.coordinates(at: p) == p)
        #expect(LatticeMapping.straight.singularDistance(at: p) == .infinity)
        #expect(LatticeMapping.straight.stretch == 1)
        #expect(LatticeMapping.straight.join(2.5, at: p) == 2.5)
        #expect(LatticeMapping.straight.lipschitz(base: 3, valueBound: 9) == 3)
        #expect(LatticeMapping.straight.singularNoun == nil)
        #expect(LatticeMapping.straight.reach(straight: 7) == 7)
    }

    // MARK: Cylindrical

    @Test func aCylindricalPointIsAngleTimesRadiusHeightAndDistance() throws {
        let map = try cylinder(radius: 10)
        #expect(near(map.coordinates(at: Vector3(5, 0, 3)), Vector3(0, 3, 5)))
        #expect(near(map.coordinates(at: Vector3(0, 8, -2)), Vector3(Self.pi / 2 * 10, -2, 8)))
        #expect(near(map.coordinates(at: Vector3(0, -8, 0)), Vector3(-Self.pi / 2 * 10, 0, 8)))
        #expect(near(map.coordinates(at: Vector3(6, 6, 1)), Vector3(Self.pi / 4 * 10, 1, 72.0.squareRoot())))
    }

    @Test func theAxisAndTheAngleStartFollowThePlane() throws {
        // A plane facing +X through (0, 0, 5): the axis is the line along X at z = 5; its x axis +Y starts the angle.
        let plane = Plane(origin: Vector3(0, 0, 5), normal: .unitX, xAxis: .unitY)
        let map = try cylinder(radius: 4, plane: plane)
        // Height is x, the start direction is +Y, and 90° counter-clockwise seen from +X is +Z (X × Y = Z).
        #expect(near(map.coordinates(at: Vector3(7, 3, 5)), Vector3(0, 7, 3)))
        #expect(near(map.coordinates(at: Vector3(-2, 0, 8)), Vector3(Self.pi / 2 * 4, -2, 3)))
    }

    @Test func theAngleJumpsByAFullTurnAtTheCut() throws {
        let map = try cylinder(radius: 10)
        let above = map.coordinates(at: Vector3(-5, 0.001, 0)).x, below = map.coordinates(at: Vector3(-5, -0.001, 0)).x
        #expect(abs((above - below) - 2 * Self.pi * 10) < 0.01, "a full turn of 2π × radius apart")
        guard case .cylindrical(let made) = map else { Issue.record("not cylindrical"); return }
        #expect(abs(made.turn - 2 * Self.pi * 10) < 1e-12)
        #expect(map.periods.first == made.turn && map.periods.second == nil)
    }

    @Test func aBadPlaneOrRadiusMakesNoMap() {
        let flat = Plane(origin: .zero, normal: .zero, xAxis: .unitX)
        #expect(CylindricalMap(axis: flat, radius: 5, over: Self.region) == nil)
        #expect(CylindricalMap(axis: .xy, radius: 0, over: Self.region) == nil)
        #expect(CylindricalMap(axis: .xy, radius: .nan, over: Self.region) == nil)
        #expect(SphericalMap(centre: Vector3(.infinity, 0, 0), radius: 5, over: Self.region) == nil)
        #expect(SphericalMap(centre: .zero, radius: -1, over: Self.region) == nil)
    }

    @Test func theCylindricalSingularSetIsTheAxis() throws {
        let map = try cylinder()
        #expect(abs(map.singularDistance(at: Vector3(3, 4, 99)) - 5) < 1e-12)
        #expect(map.singularNoun == "the axis")
    }

    // MARK: Spherical

    @Test func aSphericalPointIsLongitudeLatitudeAndDistance() throws {
        let map = try sphere(radius: 10)
        #expect(near(map.coordinates(at: Vector3(5, 0, 0)), Vector3(0, 0, 5)))
        #expect(near(map.coordinates(at: Vector3(0, 7, 0)), Vector3(Self.pi / 2 * 10, 0, 7)))
        let latitude = Self.pi / 6
        let p = Vector3(8 * cos(latitude), 0, 8 * sin(latitude))
        #expect(near(map.coordinates(at: p), Vector3(0, latitude * 10, 8)))
        #expect(near(map.coordinates(at: Vector3(0, 0, -4)), Vector3(0, -Self.pi / 2 * 10, 4)))
    }

    @Test func theCentreMovesTheSphericalOrigin() throws {
        let map = try sphere(radius: 10, centre: Vector3(10, 0, 0))
        #expect(near(map.coordinates(at: Vector3(15, 0, 0)), Vector3(0, 0, 5)))
        #expect(abs(map.singularDistance(at: Vector3(13, 4, 7)) - 5) < 1e-12)
        #expect(map.singularNoun == "the polar axis")
    }

    // MARK: Stretch

    @Test func theStretchIsTheRadiusOverTheNearestApproachOutsideTheExclusion() throws {
        // A region from 20 to 40 mm of the axis, grown by the 4 mm margin, comes within 16 mm.
        let ring = BoundingBox(min: Vector3(20, -5, -5), max: Vector3(40, 5, 5))
        let far = try cylinder(radius: 24, over: ring)
        #expect(abs(far.stretch - 24.0 / 16) < 1e-12)
        #expect(!far.reachesSingularity)
        // Across the axis the nearest approach is 0, so the exclusion is the floor.
        let across = try cylinder(radius: 24)
        #expect(abs(across.stretch - 24) < 1e-12)
        #expect(across.reachesSingularity)
        // A small radius over a distant region is never below 1.
        #expect(try cylinder(radius: 2, over: ring).stretch == 1)
        let ball = try sphere(radius: 12, over: ring)
        // The spherical stretch is the same radius over the distance from the polar axis, so 12/16 floors at 1 and 24/16 does not.
        #expect(ball.stretch == 1)
        #expect(abs(try sphere(radius: 24, over: ring).stretch - 24.0 / 16) < 1e-12)
    }

    @Test func theStretchHoldsOnRandomPairsOutsideTheExclusion() throws {
        // Both maps, over a region the axis crosses; pairs whose whole segment stays at least the exclusion from the singular set. The longitude's
        // cut is a full turn of jump, so pairs that straddle it are left out (the pattern repeats there).
        for map in [try cylinder(radius: 9), try sphere(radius: 9)] {
            let random = SeededRandom(seed: 5, stream: 11)
            var worst = 0.0
            for index in 0..<4000 {
                func point(_ at: Int) -> Vector3 {
                    Vector3(60 * random.unit(at: 6 * index + at) - 30, 60 * random.unit(at: 6 * index + at + 1) - 30,
                            40 * random.unit(at: 6 * index + at + 2) - 20)
                }
                let (a, b) = (point(0), point(3))
                let gap = (a - b).length
                guard gap > 1e-6, segmentStaysOutsideTheExclusion(map, a, b),
                      !(a.x < 0 && b.x < 0 && a.y * b.y < 0) else { continue }
                worst = max(worst, (map.coordinates(at: a) - map.coordinates(at: b)).length / gap)
            }
            #expect(worst <= map.stretch + 1e-9, "measured \(worst) against S = \(map.stretch)")
            #expect(worst > 1, "the test sees stretching")
        }
    }

    // MARK: The singular set is left solid

    @Test func theSingularSetIsSolidAndTheLatticeFadesIn() throws {
        let map = try cylinder()
        let body = 3.0
        // On the axis the value is minus the exclusion; at the exclusion it is 0; within the fade it blends; past it, the body.
        #expect(map.join(body, at: Vector3(0, 0, 4)) == -LatticeMapping.exclusion)
        #expect(map.join(body, at: Vector3(LatticeMapping.exclusion, 0, 0)) == 0)
        let middle = map.join(body, at: Vector3(LatticeMapping.exclusion + LatticeMapping.fadeWidth / 2, 0, 0))
        #expect(middle > 0 && middle < body)
        #expect(map.join(body, at: Vector3(LatticeMapping.exclusion + LatticeMapping.fadeWidth, 0, 0)) == body)
        #expect(map.join(body, at: Vector3(5, 0, 0)) == body)
        #expect(map.join(.nan, at: Vector3(0.5, 0, 0)) == -0.5, "inside the exclusion the body is never read")
    }

    @Test func theJoinAddsTheBlendToTheLipschitzBoundOnlyWhereItCanBeReached() throws {
        let near = try cylinder()
        #expect(near.lipschitz(base: 10, valueBound: 5) == 10 + 1 + (5 + 0.5) / 0.5)
        let ring = BoundingBox(min: Vector3(20, -5, -5), max: Vector3(40, 5, 5))
        #expect(try cylinder(over: ring).lipschitz(base: 10, valueBound: 5) == 10)
    }

    /// The steepest change of `join` of a periodic body per millimetre of the point, over pairs that lie within the fade or just
    /// beside it (0.01 to 2 mm apart, each within 3 mm of the singular set). The body is `valueBound · sin(2π · first / turn)` of the
    /// mapped coordinates, so its own constant in lattice coordinates is `valueBound · 2π / turn` and it repeats across the cut.
    func steepestJoin(_ map: LatticeMapping, turn: Double, valueBound: Double) -> Double {
        func body(_ p: Vector3) -> Double { valueBound * sin(2 * Self.pi * map.coordinates(at: p).x / turn) }
        let random = SeededRandom(seed: 9, stream: 3)
        var worst = 0.0
        for index in 0..<30000 {
            func value(_ at: Int) -> Double { random.unit(at: 8 * index + at) }
            let angle = 2 * Self.pi * value(0), height = 10 * value(1) - 5, ring = 3 * value(2)
            let a = Vector3(ring * cos(angle), ring * sin(angle), height)
            let step = 0.01 + 1.99 * value(3), heading = 2 * Self.pi * value(4), lift = 2 * value(5) - 1
            let direction = Vector3(cos(heading), sin(heading), lift)
            let b = a + direction * (step / direction.length)
            let gap = (a - b).length
            guard gap > 1e-6, !(a.x < 0 && b.x < 0 && a.y * b.y < 0) else { continue }
            worst = max(worst, abs(map.join(body(a), at: a) - map.join(body(b), at: b)) / gap)
        }
        return worst
    }

    @Test(arguments: [1.0, 9.0], [true, false])
    func theJoinChangesNoFasterThanItsBoundSays(_ radius: Double, _ cylindrical: Bool) throws {
        let map = cylindrical ? try cylinder(radius: radius) : try sphere(radius: radius)
        let valueBound = 5.0
        let turn = 2 * Self.pi * radius
        let own = valueBound * 2 * Self.pi / turn
        let bound = map.lipschitz(base: map.stretch * own, valueBound: valueBound)
        let worst = steepestJoin(map, turn: turn, valueBound: valueBound)
        #expect(worst <= bound, "measured \(worst) against \(bound)")
        // The bound without the weight's change, `base + 1`, is too small for the unit radius: the fade term is needed.
        if radius == 1 {
            #expect(worst > map.stretch * own + 1, "the test sees the blend: \(worst)")
        }
    }

    @Test func theJoinChangesNoFasterThanItsBoundSays() throws {
        // A body that is the same large number everywhere: all of the change is the fade from solid to body.
        let map = try cylinder()
        let body = 5.0
        let bound = map.lipschitz(base: 0, valueBound: body)
        var worst = 0.0
        var previous = map.join(body, at: Vector3(0, 0, 0))
        for step in 1...3000 {
            let x = Double(step) * 0.001
            let value = map.join(body, at: Vector3(x, 0, 0))
            worst = max(worst, abs(value - previous) / 0.001)
            previous = value
        }
        #expect(worst > 5 && worst <= bound, "measured \(worst) against \(bound)")
    }

    // MARK: Radius

    @Test func theMeanRadiusOfASolidSphereAboutItsCentreIsThreeQuartersOfItsRadius() {
        let ball = ImplicitSolid.sphere(radius: 20)
        let mean = LatticeMapping.meanRadius(of: ball) { $0.length }
        #expect(abs(mean - 15) < 0.4, "3R/4 = 15, got \(mean)")
    }

    @Test func theMeanRadiusOfASolidCylinderAboutItsAxisIsTwoThirdsOfItsRadius() {
        let post = ImplicitSolid.cylinder(radius: 15, halfHeight: 20)
        let mean = LatticeMapping.meanRadius(of: post) { Vector3($0.x, $0.y, 0).length }
        #expect(abs(mean - 10) < 0.35, "2R/3 = 10, got \(mean)")
    }

    /// `solid` moved along X by `distance`.
    func moved(_ solid: ImplicitSolid, _ distance: Double) -> ImplicitSolid {
        .moved(solid, RigidMove(origin: Vector3(distance, 0, 0), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ))
    }

    @Test func aRegionOutsideTheCentreHasItsOwnMeanAndAnEmptyOneFallsBack() {
        let mean = LatticeMapping.meanRadius(of: moved(.sphere(radius: 4), 30)) { $0.length }
        #expect(abs(mean - 30) < 1, "got \(mean)")
        let nothing = ImplicitSolid.intersect([.sphere(radius: 2), moved(.sphere(radius: 2), 50)], blend: .constant(0))
        #expect(LatticeMapping.meanRadius(of: nothing) { $0.length } >= LatticeMapping.exclusion)
    }

    /// (mean radius, cell, whole cells round): 2π × 6 = 37.7 mm is 4.7 cells of 8, so five; of 100 it is less than one, so one; a tiny
    /// radius still gets one cell.
    static let turns: [[Double]] = [[6, 8, 5], [6, 100, 1], [0.2, 8, 1]]

    @Test(arguments: LatticeMappingTests.turns)
    func aTurnIsRoundedToWholeCells(_ turn: [Double]) {
        let (mean, cell, whole) = (turn[0], turn[1], turn[2])
        let radius = LatticeMapping.turnRadius(mean: mean, cell: cell)
        #expect(abs(2 * Double.pi * radius - whole * cell) < 1e-9)
    }

    @Test func withoutACellTheTurnKeepsTheMeanRadius() {
        #expect(LatticeMapping.turnRadius(mean: 6.5, cell: nil) == 6.5)
        #expect(LatticeMapping.turnRadius(mean: 6.5, cell: 0) == 6.5)
    }

    // MARK: Box projection

    @Test func theNearestApproachOfABoxToALine() {
        let box = BoundingBox(min: Vector3(10, -3, -50), max: Vector3(20, 3, 50))
        let range = BoxProjection.radialRange(of: box, origin: .zero, xAxis: .unitX, yAxis: .unitY)
        #expect(abs(range.nearest - 10) < 1e-12 && abs(range.farthest - (400 + 9).squareRoot()) < 1e-12)
        let through = BoxProjection.radialRange(of: BoundingBox(min: Vector3(-1, -1, -1), max: Vector3(1, 1, 1)), origin: .zero,
                                                xAxis: .unitX, yAxis: .unitY)
        #expect(through.nearest == 0)
        // A tilted line: the box seen along the line is a hexagon, and the line misses it on the side.
        let tilted = BoxProjection.radialRange(of: BoundingBox(min: Vector3(5, 5, 0), max: Vector3(6, 6, 1)), origin: .zero,
                                               xAxis: .unitX, yAxis: .unitY)
        #expect(abs(tilted.nearest - 50.0.squareRoot()) < 1e-12)
    }
}

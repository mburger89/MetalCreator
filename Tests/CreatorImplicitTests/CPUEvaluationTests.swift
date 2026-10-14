import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorImplicit

/// The reference distances at hand-worked points (implicit spec §7).
struct CPUEvaluationTests {
    func distance(_ solid: ImplicitSolid, _ x: Double, _ y: Double, _ z: Double) -> Double {
        solid.signedDistance(at: Vector3(x, y, z))
    }

    /// `solid` moved `x` millimetres along X.
    func moved(_ solid: ImplicitSolid, x: Double) -> ImplicitSolid {
        .moved(solid, RigidMove(origin: Vector3(x, 0, 0), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ))
    }

    func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

    @Test func aSphereIsTheDistanceFromItsCentreLessItsRadius() {
        let sphere = ImplicitSolid.sphere(radius: 10)
        #expect(distance(sphere, 0, 0, 0) == -10)
        #expect(distance(sphere, 10, 0, 0) == 0)
        #expect(near(distance(sphere, 3, 4, 12), 13 - 10))
    }

    @Test func aBoxIsExactOutsideAlongFacesEdgesAndCorners() {
        let box = ImplicitSolid.box(halfSize: Vector3(5, 5, 5), cornerRadius: 0)
        #expect(distance(box, 0, 0, 0) == -5)
        #expect(near(distance(box, 8, 0, 0), 3))
        #expect(near(distance(box, 8, 8, 0), 18.0.squareRoot()))
        #expect(near(distance(box, 8, 9, 11), (9 + 16 + 36.0).squareRoot()))
        #expect(near(distance(box, 4, 1, 2), -1), "inside: the nearest face")
    }

    @Test func aRoundedBoxCutsItsCorners() {
        let box = ImplicitSolid.box(halfSize: Vector3(5, 5, 5), cornerRadius: 1)
        #expect(near(distance(box, 5, 5, 5), 3.0.squareRoot() - 1))
        #expect(near(distance(box, 8, 0, 0), 3), "faces are unchanged")
        // Past the rounded edge: the edge's centre line is at (4, 4), the point is √5 from it, less the radius 1.
        #expect(near(distance(box, 6, 5, 0), 5.0.squareRoot() - 1))
    }

    @Test func aCylinderHasItsAxisAlongZ() {
        let cylinder = ImplicitSolid.cylinder(radius: 3, halfHeight: 5)
        #expect(distance(cylinder, 0, 0, 0) == -3)
        #expect(near(distance(cylinder, 5, 0, 0), 2))
        #expect(near(distance(cylinder, 0, 0, 8), 3))
        #expect(near(distance(cylinder, 5, 0, 8), 13.0.squareRoot()))
        #expect(near(distance(cylinder, 0, 2, 4.5), -0.5))
    }

    @Test func aMoveSeesTheChildThroughTheInverse() throws {
        let move = try #require(RigidMove(plane: Plane(origin: Vector3(10, 0, 0), normal: .unitZ, xAxis: .unitX)))
        let moved = ImplicitSolid.moved(.sphere(radius: 4), move)
        #expect(distance(moved, 10, 0, 0) == -4)
        #expect(near(distance(moved, 0, 0, 0), 6))
        let alongX = try #require(RigidMove(plane: Plane(origin: .zero, normal: .unitX, xAxis: .unitY)))
        let turned = ImplicitSolid.moved(.cylinder(radius: 1, halfHeight: 5), alongX)
        // The axis now runs along X.
        #expect(near(distance(turned, 4, 0, 0), -1) && near(distance(turned, 0, 3, 0), 2))
    }

    @Test func aSharpUnionIsTheSmallerValue() {
        let union = ImplicitSolid.union([.sphere(radius: 5), moved(.sphere(radius: 5), x: 8)], blend: .constant(0))
        #expect(near(distance(union, 4, 0, 0), -1))
        #expect(near(distance(union, 0, 0, 0), -5))
    }

    @Test func aSmoothUnionDipsByAQuarterOfTheBlendWhereTheChildrenMeet() {
        let two = [ImplicitSolid.sphere(radius: 5), moved(.sphere(radius: 5), x: 10)]
        // At the midpoint both children read 0, so a width of 2 gives 0 − 2 / 4.
        #expect(near(distance(.union(two, blend: .constant(2)), 5, 0, 0), -0.5))
        #expect(near(distance(.union(two, blend: .constant(0)), 5, 0, 0), 0))
        // Far from the join the blend does nothing.
        #expect(near(distance(.union(two, blend: .constant(2)), 0, 0, 0), -5))
    }

    @Test func subtractCutsEveryLaterChildFromTheFirst() {
        let hole = moved(.sphere(radius: 5), x: 10)
        let cut = ImplicitSolid.subtract([.sphere(radius: 10), hole], blend: .constant(0))
        #expect(near(distance(cut, 10, 0, 0), 5), "the centre of the cutter is outside the result")
        #expect(near(distance(cut, -5, 0, 0), -5))
        #expect(near(distance(.subtract([.sphere(radius: 10)], blend: .constant(0)), 0, 0, 0), -10), "one child is that child")
    }

    @Test func intersectKeepsWhatEveryChildHas() {
        let box = ImplicitSolid.box(halfSize: Vector3(5, 5, 5), cornerRadius: 0)
        let both = ImplicitSolid.intersect([.sphere(radius: 6), box], blend: .constant(0))
        #expect(near(distance(both, 5.5, 0, 0), 0.5), "outside the box, inside the sphere")
        #expect(near(distance(both, 0, 0, 0), -5))
    }

    @Test func anOffsetMovesTheSurface() {
        #expect(near(distance(.offset(.sphere(radius: 10), distance: .constant(2)), 12, 0, 0), 0))
        #expect(near(distance(.offset(.sphere(radius: 10), distance: .constant(-2)), 8, 0, 0), 0))
    }

    @Test func aShellIsAWallOnTheChosenSide() {
        let sphere = ImplicitSolid.sphere(radius: 10)
        let inward = ImplicitSolid.shell(sphere, thickness: .constant(2), side: .inward)
        #expect(near(distance(inward, 10, 0, 0), 0) && near(distance(inward, 8, 0, 0), 0))
        #expect(near(distance(inward, 9, 0, 0), -1) && near(distance(inward, 0, 0, 0), 8))
        let outward = ImplicitSolid.shell(sphere, thickness: .constant(2), side: .outward)
        #expect(near(distance(outward, 12, 0, 0), 0) && near(distance(outward, 11, 0, 0), -1) && near(distance(outward, 9, 0, 0), 1))
        let centred = ImplicitSolid.shell(sphere, thickness: .constant(2), side: .centred)
        #expect(near(distance(centred, 10, 0, 0), -1) && near(distance(centred, 11, 0, 0), 0) && near(distance(centred, 9, 0, 0), 0))
    }

    @Test func aGradedSettingIsReadAtEachPoint() {
        // Thickness 1 + z / 20: 1.5 at z = 10, 0.5 at z = −10.
        let box = ImplicitSolid.box(halfSize: Vector3(30, 30, 30), cornerRadius: 0)
        let shell = ImplicitSolid.shell(box, thickness: ImplicitFixtures.graded, side: .inward)
        // At z = 29.25 the thickness is 1 + 29.25 / 20 = 2.4625 and the box surface is 0.75 away, inside the wall's middle.
        let thickness = 1 + 29.25 / 20
        #expect(near(distance(shell, 0, 0, 29.25), abs(-0.75 + thickness / 2) - thickness / 2))
    }

    @Test func aBakedSolidReadsItsBlocks() {
        let value = distance(ImplicitFixtures.baked, 3, 4, 0)
        #expect(near(value, 5 - 9, 1e-5))
    }

    @Test func anIsosurfaceIsTheFieldBelowItsLevelClippedToItsRegion() {
        let solid = ImplicitFixtures.isosurface
        #expect(near(distance(solid, 10, 0, 0), 0, 1e-9) && near(distance(solid, 0, 0, 0), -10, 1e-9))
        #expect(near(distance(solid, 14, 0, 0), 4, 1e-9))
        // Past the region the box distance wins: the field alone would say 20 − 10 = 10, the box 5.
        #expect(near(distance(solid, 20, 0, 0), 10, 1e-9))
        #expect(near(distance(solid, 0, 0, 0), -10, 1e-9))
    }

    @Test func aFieldLeafOfAnImplicitIsItsOwnDistance() {
        let inner = ImplicitSolid.sphere(radius: 3)
        let grading = Grading(field: .implicit(inner.reference), range: -3...20, slope: 1)
        let shell = ImplicitSolid.offset(.sphere(radius: 10), distance: grading)
        // At (10, 0, 0) the inner sphere reads 7, so the offset is sphere − 7.
        #expect(near(distance(shell, 10, 0, 0), 0 - 7))
    }

    @Test func batchesAgreeWithSinglePoints() {
        let solid = ImplicitFixtures.all[6].solid
        let points = (0..<20).map { Vector3(Double($0) - 10, Double($0 % 5), Double($0 % 3)) }
        #expect(solid.signedDistances(at: points) == points.map { solid.signedDistance(at: $0) })
    }
}

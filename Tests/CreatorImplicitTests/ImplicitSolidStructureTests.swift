import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorImplicit

/// Bounds, lipschitz constants, reach, sizes and recipes of the solid tree (implicit spec §2.1, §3.3).
struct ImplicitSolidStructureTests {
    let sphere = ImplicitSolid.sphere(radius: 10)
    let cube = ImplicitSolid.box(halfSize: Vector3(5, 5, 5), cornerRadius: 0)

    func slopeGrading(_ value: Double, slope: Double) -> Grading {
        Grading(field: .linearGradient(plane: .xy, length: 1 / slope), range: value...value, slope: slope)
    }

    @Test func primitivesHaveTheirBoxes() {
        #expect(sphere.bounds == BoundingBox(min: Vector3(-10, -10, -10), max: Vector3(10, 10, 10)))
        #expect(ImplicitSolid.box(halfSize: Vector3(1, 2, 3), cornerRadius: 0.5).bounds
            == BoundingBox(min: Vector3(-1, -2, -3), max: Vector3(1, 2, 3)))
        #expect(ImplicitSolid.cylinder(radius: 4, halfHeight: 6).bounds == BoundingBox(min: Vector3(-4, -4, -6), max: Vector3(4, 4, 6)))
    }

    @Test func aMoveBoundsTheMovedBox() throws {
        let move = try #require(RigidMove(plane: Plane(origin: Vector3(100, 0, 0), normal: .unitX, xAxis: .unitY)))
        let bounds = ImplicitSolid.moved(cube, move).bounds
        // +Z goes to +X, so the box keeps its size and is centred on the plane's origin.
        #expect((bounds.center - Vector3(100, 0, 0)).length < 1e-9)
        #expect((bounds.size - Vector3(10, 10, 10)).length < 1e-9)
    }

    @Test func combinersBoundTheirChildren() {
        let shifted = ImplicitSolid.moved(cube, RigidMove(origin: Vector3(20, 0, 0), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ))
        let union = ImplicitSolid.union([sphere, shifted], blend: .constant(0))
        #expect(union.bounds == BoundingBox(min: Vector3(-10, -10, -10), max: Vector3(25, 10, 10)))
        #expect(ImplicitSolid.subtract([sphere, shifted], blend: .constant(0)).bounds == sphere.bounds)
        #expect(ImplicitSolid.intersect([sphere, cube], blend: .constant(0)).bounds == cube.bounds)
        let apart = ImplicitSolid.intersect([sphere, shifted], blend: .constant(0)).bounds
        #expect(apart.size.length == 0, "no overlap: a point")
    }

    @Test func aSmoothUnionBulgesAQuarterOfItsBlendRadius() {
        let union = ImplicitSolid.union([sphere, cube], blend: .constant(4))
        #expect(union.bounds == BoundingBox(min: Vector3(-11, -11, -11), max: Vector3(11, 11, 11)))
    }

    @Test func offsetsAndShellsGrowByTheirLargestDistance() {
        #expect(ImplicitSolid.offset(sphere, distance: .constant(3)).bounds.max.x == 13)
        #expect(ImplicitSolid.offset(sphere, distance: .constant(-3)).bounds.max.x == 10, "shrinking never widens")
        #expect(ImplicitSolid.shell(sphere, thickness: .constant(2), side: .inward).bounds.max.x == 10)
        #expect(ImplicitSolid.shell(sphere, thickness: .constant(2), side: .outward).bounds.max.x == 12)
        #expect(ImplicitSolid.shell(sphere, thickness: .constant(2), side: .centred).bounds.max.x == 11)
    }

    @Test func lipschitzIsOneForExactNodesAndGrowsWithSlopes() {
        #expect(sphere.lipschitz == 1 && cube.lipschitz == 1)
        #expect(ImplicitSolid.union([sphere, cube], blend: .constant(2)).lipschitz == 1)
        #expect(ImplicitSolid.union([sphere, cube], blend: slopeGrading(2, slope: 0.4)).lipschitz == 1.1)
        #expect(ImplicitSolid.offset(sphere, distance: slopeGrading(1, slope: 0.5)).lipschitz == 1.5)
        #expect(ImplicitSolid.shell(sphere, thickness: slopeGrading(1, slope: 2), side: .centred).lipschitz == 3)
        let region = BoundingBox(min: Vector3(-1, -1, -1), max: Vector3(1, 1, 1))
        #expect(ImplicitSolid.isosurface(slopeGrading(0, slope: 4), level: 0, maxSlope: 2, region: region).lipschitz == 2)
        #expect(ImplicitSolid.isosurface(slopeGrading(0, slope: 4), level: 0, maxSlope: 8, region: region).lipschitz == 1)
    }

    @Test func aBakedDistanceIsExactOnlyWithinItsBand() {
        let blocks = BlocksFixture.make(origin: .zero, spacing: 1, blocks: 1, band: 6) { $0.x - 4 }
        let baked = ImplicitSolid.baked(blocks, label: "Plate")
        #expect(baked.exactReach == 6)
        #expect(ImplicitSolid.offset(baked, distance: .constant(2)).exactReach == 4)
        #expect(ImplicitSolid.shell(baked, thickness: .constant(9), side: .inward).exactReach == 0)
        #expect(ImplicitSolid.union([sphere, baked], blend: .constant(0)).exactReach == 6)
        #expect(sphere.exactReach == .infinity)
    }

    @Test func sizesAreSixtyFourPlusThirtyTwoPerNode() {
        #expect(sphere.nodeCount == 1 && sphere.estimatedBytes == 96)
        let tree = ImplicitSolid.union([sphere, cube], blend: .constant(0))
        #expect(tree.nodeCount == 3)
        // Plus the blend's field (64 + 32).
        #expect(tree.estimatedBytes == 64 + 32 * 3 + Grading.constant(0).estimatedBytes)
    }

    @Test func recipesReadLikeFieldRecipes() {
        #expect(sphere.description == "sphere(radius 10 mm)")
        #expect(ImplicitSolid.box(halfSize: Vector3(10, 5, 2.5), cornerRadius: 1).description
            == "box(20 × 10 × 5 mm, corner radius 1 mm)")
        #expect(cube.description == "box(10 × 10 × 10 mm)")
        #expect(ImplicitSolid.cylinder(radius: 5, halfHeight: 6).description == "cylinder(radius 5 mm, height 12 mm)")
        #expect(ImplicitSolid.union([sphere, cube], blend: .constant(0)).description == "union(sphere(radius 10 mm), box(10 × 10 × 10 mm))")
        #expect(ImplicitSolid.subtract([sphere, cube], blend: .constant(2)).description
            == "subtract(sphere(radius 10 mm), box(10 × 10 × 10 mm), blend 2 mm)")
        #expect(ImplicitSolid.offset(sphere, distance: .constant(-2)).description == "offset(sphere(radius 10 mm), −2 mm)")
        #expect(ImplicitSolid.shell(sphere, thickness: .constant(1.5), side: .inward).description
            == "shell(sphere(radius 10 mm), inward 1.5 mm)")
        let blocks = BlocksFixture.make(origin: .zero, spacing: 1, blocks: 1) { $0.x }
        #expect(ImplicitSolid.baked(blocks, label: "Bracket").description == "implicit(Bracket)")
        let graded = Grading(field: .noise(seed: 1, scale: 5, octaves: 2), range: 0...1, slope: 1)
        #expect(ImplicitSolid.offset(sphere, distance: graded).description.contains("noise(seed 1, scale 5, octaves 2)"))
    }

    @Test func aLongRecipeIsCutForATooltip() {
        let long = ImplicitSolid.union([sphere, sphere, sphere, sphere, sphere], blend: .constant(0))
        let text = long.description(limit: 80)
        #expect(text.count == 80 && text.hasSuffix("…"))
        #expect(sphere.description(limit: 80) == sphere.description)
    }

    @Test func equalSolidsAreEqual() {
        #expect(ImplicitSolid.sphere(radius: 3) == .sphere(radius: 3))
        #expect(ImplicitSolid.sphere(radius: 3) != .sphere(radius: 4))
        let blocks = BlocksFixture.make(origin: .zero, spacing: 1, blocks: 1) { $0.x }
        let other = BlocksFixture.make(origin: .zero, spacing: 1, blocks: 1) { $0.x }
        #expect(ImplicitSolid.baked(blocks, label: "a") == .baked(blocks, label: "a"))
        #expect(ImplicitSolid.baked(blocks, label: "a") != .baked(other, label: "a"), "blocks are equal by identity")
    }
}

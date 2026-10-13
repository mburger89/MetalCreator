import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorNodes

/// The `.image` field through `FieldSampler` (fields spec §5): the projection, the edge modes, the recipe and the size.
struct ImageFieldSamplingTests {
    /// 4 × 2 px: the top row ramps 0, 1/3, 2/3, 1 and the bottom row is its mirror.
    static let ramp = GreyImage(width: 4, height: 2, pixels: [0, 21_845, 43_690, 65_535, 65_535, 43_690, 21_845, 0])

    func field(plane: Plane = .xy, width: Double = 8, height: Double = 4, edges: ImageEdges = .clamp) throws -> Field {
        .image(try #require(Self.ramp), plane: plane, width: width, height: height, edges: edges)
    }

    @Test func aPointMapsToTheImageCentredOnThePlaneWithRowZeroAtTheTop() async throws {
        let field = try field()
        // 8 × 4 mm centred on the origin: x −3 is the centre of column 0, y +1 the centre of row 0.
        let found = try await FieldSampler.sample(field, at: [Vector3(-3, 1, 0), Vector3(3, 1, 0), Vector3(-3, -1, 0), Vector3(3, -1, 0)],
                                                  kernel: FakeKernel())
        #expect(found == [0, 1, 1, 0])
    }

    @Test func theDistanceAlongTheNormalDoesNotMatterBecauseTheImageIsProjected() async throws {
        let found = try await FieldSampler.sample(try field(), at: [Vector3(1, 1, 0), Vector3(1, 1, 50), Vector3(1, 1, -50)],
                                                  kernel: FakeKernel())
        #expect(found[0] == found[1] && found[1] == found[2])
    }

    @Test func aTiltedPlaneProjectsAlongItsOwnNormal() async throws {
        // The front plane: local x is world x, local y is world z, and the normal is −y.
        let field = try field(plane: .xz)
        let points = [Vector3(-3, 7, 1), Vector3(3, -7, 1), Vector3(3, 0, -1)]
        let found = try await FieldSampler.sample(field, at: points, kernel: FakeKernel())
        #expect(found == [0, 1, 0])
    }

    @Test func aMovedPlaneMovesTheImage() async throws {
        let moved = Plane(origin: Vector3(100, 0, 0), normal: .unitZ, xAxis: .unitX)
        let found = try await FieldSampler.sample(try field(plane: moved), at: [Vector3(97, 1, 0), Vector3(-3, 1, 0)], kernel: FakeKernel())
        #expect(found == [0, 0], "the second point is 103 mm left of the image; clamp holds its edge")
    }

    @Test func clampHoldsTheEdgeAndTileRepeats() async throws {
        let far = [Vector3(-3 + 8, 1, 0), Vector3(-3 - 8, 1, 0), Vector3(1000, 1, 0)]
        let clamped = try await FieldSampler.sample(try field(edges: .clamp), at: far, kernel: FakeKernel())
        #expect(clamped == [1, 0, 1])
        let tiled = try await FieldSampler.sample(try field(edges: .tile), at: far, kernel: FakeKernel())
        #expect(tiled[0] == 0 && tiled[1] == 0, "one whole width away is the same pixel")
        #expect((0.0...1.0).contains(tiled[2]))
    }

    @Test func aBatchAgreesExactlyWithOnePointAtATime() async throws {
        let field = try field(edges: .tile)
        let points = (0..<50).map { Vector3(Double($0) * 0.73 - 12, Double($0 % 7) - 3.1, Double($0)) }
        let batch = try await FieldSampler.sample(field, at: points, kernel: FakeKernel())
        for (index, point) in points.enumerated() {
            #expect(try await FieldSampler.sample(field, at: [point], kernel: FakeKernel()) == [batch[index]])
        }
    }

    @Test func nonFinitePointsSampleAsZeroAndNeverTrap() async throws {
        let points = [Vector3(.nan, 0, 0), Vector3(0, .infinity, 0), Vector3(1e300, -1e300, 0)]
        let found = try await FieldSampler.sample(try field(edges: .tile), at: points, kernel: FakeKernel())
        #expect(found[0] == 0 && found[1] == 0)
        #expect((0.0...1.0).contains(found[2]))
    }

    @Test func itComposesWithTheMathsNodesLikeAnyField() async throws {
        let scaled = Field.multiply(try field(), .constant(2))
        let found = try await FieldSampler.sample(scaled, at: [Vector3(3, 1, 0)], kernel: FakeKernel())
        #expect(found == [2])
    }

    @Test func theRecipeNamesTheImageAndItsPlacement() throws {
        #expect(try field(width: 8, height: 4, edges: .tile).description == "image(4 × 2 px over 8 × 4 mm, tile)")
        #expect(try field(width: 1234.5, height: 2, edges: .clamp).description == "image(4 × 2 px over 1,234.5 × 2 mm, clamp)")
    }

    @Test func theFieldCountsItsImagesBytesAndIsAOneNodeLeaf() throws {
        let leaf = try field()
        #expect(leaf.children.isEmpty && leaf.nodeCount == 1)
        #expect(leaf.estimatedBytes == 64 + 32 + 16, "eight 16-bit pixels")
        let sum = Field.add(leaf, .multiply(leaf, .constant(1)))
        #expect(sum.estimatedBytes == 64 + 32 * 5 + 2 * 16)
    }
}

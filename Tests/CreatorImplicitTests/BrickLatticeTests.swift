import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The numbering an engine meshes bricks by (implicit spec Errata D13): keys unique per edge, the same from every brick that reaches the
/// edge, and fitting 32 bits; the table as the shader reads it; sample positions the CPU's, bit for bit.
struct BrickLatticeTests {
    static let bricks: [SIMD3<Int32>] = [SIMD3(-2, 5, 3), SIMD3(-1, 5, 3), SIMD3(-1, 6, 3), SIMD3(0, 6, 4)]

    @Test func noBricksNoWindow() {
        #expect(BrickLattice([]) == nil)
    }

    @Test func theWindowIsTheBoxAroundTheBricks() throws {
        let lattice = try #require(BrickLattice(Self.bricks))
        #expect(lattice.minBrick == SIMD3(-2, 5, 3) && lattice.extent == SIMD3(3, 2, 2))
        #expect(lattice.points == SIMD3(25, 17, 17))
        #expect(lattice.fitsEdgeKeys)
    }

    @Test func everyEdgeOfTheWindowHasItsOwnKeyAndTheKeyNamesTheEdgeBack() throws {
        let lattice = try #require(BrickLattice([SIMD3(4, 4, 4), SIMD3(5, 4, 4)]))
        let size = lattice.points
        var seen = Set<UInt32>()
        for z in 0..<size.z {
            for y in 0..<size.y {
                for x in 0..<size.x {
                    for axis in 0..<3 {
                        let key = lattice.edgeKey(point: SIMD3(x, y, z), axis: axis)
                        #expect(seen.insert(key).inserted)
                        let edge = lattice.edge(of: key)
                        #expect(edge.point == SIMD3(x, y, z) && edge.axis == axis)
                    }
                }
            }
        }
        #expect(seen.count == 3 * size.x * size.y * size.z && !seen.contains(BrickLattice.emptyKey))
    }

    @Test func aBrickFaceEdgeHasOneKeyFromBothBricks() throws {
        // The edge along y at lattice x = 8, z = 2 is the far face of brick (0, 0, 0) and the near face of brick (1, 0, 0).
        let lattice = try #require(BrickLattice([SIMD3(0, 0, 0), SIMD3(1, 0, 0)]))
        let fromFirst = lattice.edgeKey(point: SIMD3(0 * 8 + 8, 3, 2), axis: 1)
        let fromSecond = lattice.edgeKey(point: SIMD3(1 * 8 + 0, 3, 2), axis: 1)
        #expect(fromFirst == fromSecond)
    }

    @Test func bricksAreCountedFromTheWindowsLowestOne() throws {
        let lattice = try #require(BrickLattice(Self.bricks))
        #expect(lattice.relativeBricks(Self.bricks) == [0, 0, 0, 1, 0, 0, 1, 1, 0, 2, 1, 1])
    }

    @Test func aWindowTooBigForThirtyTwoBitKeysIsSaidSo() throws {
        let lattice = try #require(BrickLattice([SIMD3(0, 0, 0), SIMD3(1_200, 1_200, 1_200)]))
        #expect(!lattice.fitsEdgeKeys)
        let far = try #require(BrickLattice([SIMD3(1_000_000, -1_000_000, 70_000)]))
        #expect(far.fitsEdgeKeys, "a lone brick far from the origin is a small window")
        let wide = try #require(BrickLattice([SIMD3(Int32.min, Int32.min, Int32.min), SIMD3(Int32.max, Int32.max, Int32.max)]))
        #expect(!wide.fitsEdgeKeys, "extremes don't overflow the check")
    }

    @Test func theCoordinatesAreTheCPUPlansBitForBit() async throws {
        let solid = ImplicitFixtures.cylinder
        let plan = try await BrickPlan.build(for: solid, resolution: 0.37, using: CPUBatchEvaluator(solid))
        let lattice = try #require(BrickLattice(plan.bricks))
        let request = BrickMeshRequest(plan: plan, snap: true)
        let coordinates = lattice.axisCoordinates(origin: request.origin, resolution: request.resolution)
        let size = lattice.points
        #expect(coordinates.count == size.x + size.y + size.z)
        let first = SIMD3<Int>(Int(lattice.minBrick.x), Int(lattice.minBrick.y), Int(lattice.minBrick.z)) &* BrickPlan.brickSize
        for index in 0..<size.x {
            #expect(coordinates[index] == Float(plan.point(first.x + index, 0, 0).x))
        }
        for index in 0..<size.y {
            #expect(coordinates[size.x + index] == Float(plan.point(0, first.y + index, 0).y))
        }
        for index in 0..<size.z {
            #expect(coordinates[size.x + size.y + index] == Float(plan.point(0, 0, first.z + index).z))
        }
    }

    @Test func theTableBufferIsTheMarchingCubesTable() {
        let words = MarchingCubesBuffers.words
        #expect(words.count == MarchingCubesBuffers.edgesOffset + MarchingCubesTable.triangles.reduce(0) { $0 + $1.count })
        for pattern in 0..<MarchingCubesBuffers.patternCount {
            let starts = MarchingCubesBuffers.startsOffset + pattern
            let base = MarchingCubesBuffers.edgesOffset
            let edges = words[(base + Int(words[starts]))..<(base + Int(words[starts + 1]))].map { UInt8($0) }
            #expect(edges == MarchingCubesTable.triangles[pattern])
        }
        for edge in 0..<12 {
            #expect(Int(words[MarchingCubesBuffers.lowerCornersOffset + edge]) == MarchingCubesTable.edgeCorners[edge].0)
            #expect(Int(words[MarchingCubesBuffers.upperCornersOffset + edge]) == MarchingCubesTable.edgeCorners[edge].1)
        }
    }

    @Test func theTableUsesEveryEdgeAPatternCrossesAndNoOther() {
        // The shader claims a table slot for each edge whose ends differ in sign, and the triangles name vertices by edge.
        for pattern in 0..<MarchingCubesBuffers.patternCount {
            let used = Set(MarchingCubesTable.triangles[pattern])
            let crossing = Set((0..<12).filter { edge in
                let (a, b) = MarchingCubesTable.edgeCorners[edge]
                return (pattern >> a & 1) != (pattern >> b & 1)
            }.map(UInt8.init))
            #expect(used == crossing, "pattern \(pattern)")
        }
    }
}

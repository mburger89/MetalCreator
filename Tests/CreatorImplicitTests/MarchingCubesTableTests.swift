import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The marching cubes table (implicit spec §4.3, §7), checked as a whole instead of entry by entry.
struct MarchingCubesTableTests {
    static let corners: [Vector3] = (0..<8).map { Vector3(Double($0 & 1), Double($0 >> 1 & 1), Double($0 >> 2 & 1)) }

    func midpoint(_ edge: UInt8) -> Vector3 {
        let (a, b) = MarchingCubesTable.edgeCorners[Int(edge)]
        return (Self.corners[a] + Self.corners[b]) * 0.5
    }

    @Test func theTrivialPatternsHaveNoSurface() {
        #expect(MarchingCubesTable.triangles[0].isEmpty && MarchingCubesTable.triangles[255].isEmpty)
        #expect(MarchingCubesTable.triangles.count == 256)
    }

    @Test func aSingleInsideCornerMakesOneTriangleFacingOutwards() throws {
        for corner in 0..<8 {
            let table = MarchingCubesTable.triangles[1 << corner]
            #expect(table.count == 3, "corner \(corner)")
            let points = table.map(midpoint)
            let normal = (points[1] - points[0]).cross(points[2] - points[0])
            // Towards the outside corners: away from the inside corner.
            let outwards = (Vector3(0.5, 0.5, 0.5) - Self.corners[corner])
            #expect(normal.dot(outwards) > 0, "corner \(corner)")
        }
    }

    @Test func swappingInsideAndOutsideFlipsTheTriangles() {
        for pattern in 1..<255 {
            let a = MarchingCubesTable.triangles[pattern], b = MarchingCubesTable.triangles[255 - pattern]
            // The same crossing edges are used; the complement is the same surface seen from the other side.
            #expect(Set(a) == Set(b), "pattern \(pattern)")
        }
    }

    @Test func everyCrossingEdgeIsUsedAndNothingElse() {
        for pattern in 1..<255 {
            let crossing = Set(MarchingCubesTable.edgeCorners.indices.filter { edge in
                let (a, b) = MarchingCubesTable.edgeCorners[edge]
                return (pattern >> a & 1) != (pattern >> b & 1)
            }.map(UInt8.init))
            #expect(Set(MarchingCubesTable.triangles[pattern]) == crossing, "pattern \(pattern)")
        }
    }

    @Test func theTwoDiagonalCornersOfAFaceAreSeparated() {
        // Corners 0 and 3 are diagonal on the z = 0 face: two triangles, one cutting each corner.
        #expect(MarchingCubesTable.triangles[0b1001].count == 6)
    }

    @Test func noTriangleLiesFlatInAFaceOfTheCube() {
        for pattern in 0..<256 {
            let table = MarchingCubesTable.triangles[pattern]
            for base in stride(from: 0, to: table.count, by: 3) {
                #expect(!MarchingCubesTable.lieOnOneFace(Int(table[base]), Int(table[base + 1]), Int(table[base + 2])),
                        "pattern \(pattern): a triangle lies in a face")
            }
        }
    }

    @Test func triangleCountsAreWithinTheKnownBound() {
        let counts = MarchingCubesTable.triangles.map { $0.count / 3 }
        #expect(counts.max() ?? 0 <= 10)
        #expect(counts.filter { $0 == 0 }.count == 2)
    }

    /// The decisive test: random lattices of signs, padded with outside, mesh into closed, consistently oriented surfaces.
    @Test(arguments: 0..<60)
    func randomSignsMakeClosedSurfaces(_ seed: Int) async throws {
        let random = SeededRandom(seed: seed, stream: 17)
        let side = 6
        var inside = [Bool](repeating: false, count: side * side * side)
        for z in 1..<side - 1 { for y in 1..<side - 1 { for x in 1..<side - 1 {
            inside[(z * side + y) * side + x] = random.unit(at: (z * side + y) * side + x) < 0.45
        } } }
        let mesh = Self.surface(of: inside, side: side)
        let topology = MeshTopology(mesh)
        #expect(topology.openEdgeCount == 0, "seed \(seed): open edges")
        #expect(topology.overfullEdgeCount == 0, "seed \(seed): edges with three faces")
        #expect(topology.inconsistentEdgeCount == 0, "seed \(seed): flipped faces")
        #expect(topology.degenerateTriangleCount == 0)
        #expect(topology.nonManifoldVertexCount == 0, "seed \(seed): a vertex with two fans")
        #expect(mesh.signedVolume > 0, "seed \(seed): wound outwards")
    }

    /// Marching cubes on a `side`³ lattice of signs, with the same global edge keys the mesher uses.
    static func surface(of inside: [Bool], side: Int) -> TriangleMesh {
        var positions: [SIMD3<Float>] = []
        var triangles: [UInt32] = []
        var found: [[Int]: UInt32] = [:]
        for z in 0..<side - 1 { for y in 0..<side - 1 { for x in 0..<side - 1 {
            var pattern = 0
            for corner in 0..<8 where inside[((z + corner >> 2) * side + y + (corner >> 1 & 1)) * side + x + (corner & 1)] {
                pattern |= 1 << corner
            }
            for edge in MarchingCubesTable.triangles[pattern] {
                let (a, b) = MarchingCubesTable.edgeCorners[Int(edge)]
                let low = [x + (a & 1), y + (a >> 1 & 1), z + (a >> 2 & 1), (a ^ b) == 1 ? 0 : ((a ^ b) == 2 ? 1 : 2)]
                if let existing = found[low] {
                    triangles.append(existing)
                } else {
                    var point = SIMD3<Float>(Float(low[0]), Float(low[1]), Float(low[2]))
                    point[low[3]] += 0.5
                    found[low] = UInt32(positions.count)
                    triangles.append(UInt32(positions.count))
                    positions.append(point)
                }
            }
        } } }
        return TriangleMesh(positions: positions, triangles: triangles)
    }
}

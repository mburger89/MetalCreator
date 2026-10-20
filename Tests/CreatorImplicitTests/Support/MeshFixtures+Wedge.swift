import CreatorGeometry
import CreatorImplicit
import Foundation

extension MeshFixtures {
    /// The top and the bottom of a wedge that tapers to a knife edge, as two open sheets sharing the edge's vertices: the edge runs along
    /// y at x = 0, and the faces leave it at `halfAngle` radians above and below the xy plane. `topSteps` and `bottomSteps` are the x
    /// positions of the vertex rows on each face, each starting at 0 (the edge itself); the rows are 1 mm apart along y, `rows` of them.
    /// The faces face outward, so a vertex's inward ray crosses the wedge to the other face.
    static func wedge(topSteps: [Double], bottomSteps: [Double], halfAngle: Double, rows: Int = 4) -> TriangleMesh {
        var positions: [SIMD3<Float>] = []
        func add(_ x: Double, _ y: Double, _ z: Double) -> UInt32 {
            positions.append(SIMD3(Float(x), Float(y), Float(z)))
            return UInt32(positions.count - 1)
        }
        let slope = tan(halfAngle)
        let edge = (0..<rows).map { add(0, Double($0), 0) }
        func face(_ steps: [Double], sign: Double) -> [[UInt32]] {
            [edge] + steps.dropFirst().map { x in (0..<rows).map { add(x, Double($0), sign * x * slope) } }
        }
        let top = face(topSteps, sign: 1), bottom = face(bottomSteps, sign: -1)
        var triangles: [UInt32] = []
        func strips(_ grid: [[UInt32]], flipped: Bool) {
            for i in 0..<grid.count - 1 {
                for j in 0..<rows - 1 {
                    let (a, b, c, d) = (grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1])
                    triangles += flipped ? [a, c, b, a, d, c] : [a, b, c, a, c, d]
                }
            }
        }
        strips(top, flipped: false)
        strips(bottom, flipped: true)
        return TriangleMesh(positions: positions, triangles: triangles)
    }
}

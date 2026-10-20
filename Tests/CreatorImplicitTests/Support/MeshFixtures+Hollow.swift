import CreatorGeometry
import CreatorImplicit

extension MeshFixtures {
    /// A cube of `size` with cube-shaped voids inside it: closed shells, the voids wound the other way (their faces look into
    /// them). Each void is (x, y, z, side) from the cube's corner. Each face has `divisions` squares along an edge, so a vertex has
    /// whatever lies straight behind it.
    static func cubeWithVoids(size: Float, divisions: Int, voids: [SIMD4<Float>]) -> TriangleMesh {
        let unit = subdividedCube(divisions: divisions)
        var positions = unit.positions.map { $0 * size }
        var triangles = unit.triangles
        for void in voids {
            let offset = UInt32(positions.count)
            positions += unit.positions.map { $0 * void.w + SIMD3(void.x, void.y, void.z) }
            for base in stride(from: 0, to: unit.triangles.count, by: 3) {
                // Reversed, so the void's faces look into it.
                triangles += [unit.triangles[base] + offset, unit.triangles[base + 2] + offset, unit.triangles[base + 1] + offset]
            }
        }
        return TriangleMesh(positions: positions, triangles: triangles)
    }

    /// A cube of `size` with one cube-shaped void in the middle, a wall of `wall` all round.
    static func hollowCube(size: Float, wall: Float, divisions: Int) -> TriangleMesh {
        cubeWithVoids(size: size, divisions: divisions, voids: [SIMD4(wall, wall, wall, size - 2 * wall)])
    }
}

/// The marching cubes table (implicit spec §4.3), made once by a fixed rule instead of typed in, so its choices are written down:
///
/// - Corner `c` of a cube is at offset (c & 1, c >> 1 & 1, c >> 2 & 1) from the cube's lowest lattice point, and is *inside* when the
///   solid's value there is below 0. Edge numbers are listed in `edgeCorners`.
/// - On each of the six faces, seen from outside, the inside region's outline is drawn as directed segments with the inside on the
///   left. The face's crossings (edges whose ends differ) alternate between *exits* (an inside corner to an outside one, going
///   counter-clockwise round the face) and *entries*; each exit is joined to the crossing just before it. On a face where two inside
///   corners sit diagonally (the ambiguous case) this separates them: **inside corners are never joined across a face**. The rule
///   depends on the face's four corners alone, so the cube on the other side of the face draws the same outline, and the surface has
///   no holes and no extra edges between bricks.
/// - Following the segments from edge to edge closes into loops. Each loop is a polygon whose corners are the crossing edges. The
///   outline keeps the inside on its left, which winds a loop clockwise seen from outside the solid, so a fan from the loop's first
///   corner takes the others in reverse to wind its triangles counter-clockwise seen from outside (towards increasing values).
enum MarchingCubesTable {
    /// The two corners each of the twelve edges joins, lower corner first.
    static let edgeCorners: [(Int, Int)] = [
        (0, 1), (2, 3), (4, 5), (6, 7),
        (0, 2), (1, 3), (4, 6), (5, 7),
        (0, 4), (1, 5), (2, 6), (3, 7),
    ]

    /// For each of the 256 inside/outside patterns, the triangles as triples of edge numbers.
    static let triangles: [[UInt8]] = (0..<256).map { Self.makeTriangles(inside: $0) }

    /// The corners of each cube face in counter-clockwise order seen from outside the cube.
    private static let faces: [[Int]] = (0..<3).flatMap { axis -> [[Int]] in
        let (u, v) = ((axis + 1) % 3, (axis + 2) % 3)
        func corner(_ a: Int, _ du: Int, _ dv: Int) -> Int { a << axis | du << u | dv << v }
        // (u, v, axis) is right-handed, so (0,0) (1,0) (1,1) (0,1) runs counter-clockwise seen from +axis.
        let ring = [(0, 0), (1, 0), (1, 1), (0, 1)]
        return [
            ring.map { corner(1, $0.0, $0.1) },
            ring.reversed().map { corner(0, $0.0, $0.1) },
        ]
    }

    private static func edge(between a: Int, _ b: Int) -> Int {
        edgeCorners.firstIndex { ($0.0 == a && $0.1 == b) || ($0.0 == b && $0.1 == a) } ?? 0
    }

    private static func makeTriangles(inside pattern: Int) -> [UInt8] {
        func isInside(_ corner: Int) -> Bool { pattern >> corner & 1 == 1 }
        // next[e]: the edge the outline reaches after crossing edge `e` (e is an exit of exactly one of its two faces).
        var next: [Int: Int] = [:]
        for face in faces {
            // The crossings in counter-clockwise order: (edge, isExit).
            var crossings: [(edge: Int, exit: Bool)] = []
            for index in 0..<4 {
                let (from, to) = (face[index], face[(index + 1) % 4])
                if isInside(from) != isInside(to) { crossings.append((edge(between: from, to), isInside(from))) }
            }
            for (index, crossing) in crossings.enumerated() where crossing.exit {
                next[crossing.edge] = crossings[(index + crossings.count - 1) % crossings.count].edge
            }
        }
        var result: [UInt8] = []
        var visited = Set<Int>()
        for start in next.keys.sorted() where !visited.contains(start) {
            var loop: [Int] = []
            var edge = start
            while visited.insert(edge).inserted {
                loop.append(edge)
                edge = next[edge] ?? start
            }
            result += fan(of: loop)
        }
        return result
    }

    /// Whether three crossing edges all lie on one face of the cube. A triangle made of them lies flat in that face, and the cube on
    /// the other side could make the very same triangle: two faces on one surface, a vertex that is no longer a single fan.
    static func lieOnOneFace(_ a: Int, _ b: Int, _ c: Int) -> Bool {
        faces.contains { face in [a, b, c].allSatisfy { edge in
            let (from, to) = edgeCorners[edge]
            return face.contains(from) && face.contains(to)
        } }
    }

    /// The loop cut into triangles by a fan from one of its corners: the first corner from which no triangle lies flat in a face (there
    /// is always one, which `MarchingCubesTableTests` checks for every pattern). The triangles run in reverse of the loop.
    private static func fan(of loop: [Int]) -> [UInt8] {
        var best: [UInt8] = []
        for apex in loop.indices {
            let ring = (0..<loop.count).map { loop[(apex + $0) % loop.count] }
            let triangles = (1..<(ring.count - 1)).map { [ring[0], ring[$0 + 1], ring[$0]] }
            best = triangles.flatMap { $0.map(UInt8.init) }
            if !triangles.contains(where: { lieOnOneFace($0[0], $0[1], $0[2]) }) { return best }
        }
        return best
    }
}

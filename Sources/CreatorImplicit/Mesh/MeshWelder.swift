/// Merges the vertices of a mesh that sit on one another (implicit spec §4.7): the mesher's snap can leave two vertices of a sliver
/// closer than a boundary representation can tell apart. Vertices that round to the same cell of `tolerance` become one, triangles that
/// collapse are dropped (which leaves a closed mesh closed: it is an edge collapse), and vertices nothing uses go.
public enum MeshWelder {
    public struct Output: Sendable {
        public var positions: [SIMD3<Float>]
        public var triangles: [UInt32]
    }

    public static func weld(positions: [SIMD3<Float>], triangles: [UInt32], tolerance: Double = 1e-6) -> Output {
        var cells: [SIMD3<Int>: UInt32] = [:]
        var merged: [UInt32] = []
        merged.reserveCapacity(positions.count)
        for position in positions {
            let cell = SIMD3(Int((Double(position.x) / tolerance).rounded()), Int((Double(position.y) / tolerance).rounded()),
                             Int((Double(position.z) / tolerance).rounded()))
            if let existing = cells[cell] {
                merged.append(existing)
            } else {
                cells[cell] = UInt32(merged.count)
                merged.append(UInt32(merged.count))
            }
        }
        var renumber = [UInt32?](repeating: nil, count: positions.count)
        var kept: [SIMD3<Float>] = []
        var result: [UInt32] = []
        result.reserveCapacity(triangles.count)
        for base in stride(from: 0, to: triangles.count - 2, by: 3) {
            let corners = (0..<3).map { Int(triangles[base + $0]) }
            guard corners.allSatisfy({ $0 < positions.count }) else { continue }
            let representatives = corners.map { Int(merged[$0]) }
            guard Set(representatives).count == 3 else { continue }
            for representative in representatives {
                if renumber[representative] == nil {
                    renumber[representative] = UInt32(kept.count)
                    kept.append(positions[representative])
                }
                result.append(renumber[representative] ?? 0)
            }
        }
        return Output(positions: kept, triangles: result)
    }
}

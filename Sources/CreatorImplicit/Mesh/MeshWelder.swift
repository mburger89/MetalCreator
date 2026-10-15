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
            // A position that is not a number, or too far out for a cell index, is never merged: it keeps its own vertex and
            // reaches the kernel, which refuses it in words (a `Double` to `Int` conversion would trap here).
            guard let cell = cell(of: position, tolerance: tolerance) else {
                merged.append(UInt32(merged.count))
                continue
            }
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

    /// The cell of `tolerance` that holds `position`, or nil when a coordinate is not finite or its cell index would not fit an `Int`.
    private static func cell(of position: SIMD3<Float>, tolerance: Double) -> SIMD3<Int>? {
        var cell = SIMD3<Int>()
        for axis in 0..<3 {
            let scaled = (Double(position[axis]) / tolerance).rounded()
            guard scaled.isFinite, abs(scaled) < 1e18 else { return nil }
            cell[axis] = Int(scaled)
        }
        return cell
    }
}

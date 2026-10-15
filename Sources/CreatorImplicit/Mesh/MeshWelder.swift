/// Merges the vertices of a mesh that sit on one another (implicit spec §4.7): the mesher's snap can leave two vertices of a sliver
/// closer than a boundary representation can tell apart. A vertex within `tolerance` (a distance) of an earlier one becomes that one, found among the 27 cells round it so a pair that straddles a cell boundary is merged too, triangles that
/// collapse are dropped (which leaves a closed mesh closed: it is an edge collapse), and vertices nothing uses go.
public enum MeshWelder {
    public struct Output: Sendable {
        public var positions: [SIMD3<Float>]
        public var triangles: [UInt32]
    }

    public static func weld(positions: [SIMD3<Float>], triangles: [UInt32], tolerance: Double = 1e-6) -> Output {
        // Each cell of `tolerance` lists the vertices that stayed (were not merged into an earlier one) in it.
        var cells: [SIMD3<Int>: [UInt32]] = [:]
        var merged: [UInt32] = []
        merged.reserveCapacity(positions.count)
        for (index, position) in positions.enumerated() {
            // A position that is not a number, or too far out for a cell index, is never merged: it keeps its own vertex and
            // reaches the kernel, which refuses it in words (a `Double` to `Int` conversion would trap here).
            guard let cell = cell(of: position, tolerance: tolerance) else {
                merged.append(UInt32(index))
                continue
            }
            if let existing = nearby(position, cell: cell, in: cells, positions: positions, tolerance: tolerance) {
                merged.append(existing)
            } else {
                cells[cell, default: []].append(UInt32(index))
                merged.append(UInt32(index))
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

    /// The earliest kept vertex within `tolerance` of `position`, looking in the cell and the 26 round it.
    private static func nearby(_ position: SIMD3<Float>, cell: SIMD3<Int>, in cells: [SIMD3<Int>: [UInt32]],
                               positions: [SIMD3<Float>], tolerance: Double) -> UInt32? {
        let here = SIMD3<Double>(position)
        var best: UInt32?
        for dx in -1...1 {
            for dy in -1...1 {
                for dz in -1...1 {
                    for candidate in cells[cell &+ SIMD3(dx, dy, dz)] ?? [] {
                        let offset = SIMD3<Double>(positions[Int(candidate)]) - here
                        if (offset * offset).sum().squareRoot() <= tolerance, candidate < best ?? .max { best = candidate }
                    }
                }
            }
        }
        return best
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

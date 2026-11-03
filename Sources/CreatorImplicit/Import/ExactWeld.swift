/// Joins corners that are the same point, bit for bit (mesh import spec, Reading). An STL repeats every vertex once per triangle;
/// welding by exact `Float` value gives back the shared vertices without moving anything, so the mesh the file described is the one
/// that results. A negative zero is read as zero.
public enum ExactWeld {
    private struct Key: Hashable {
        var x: UInt32
        var y: UInt32
        var z: UInt32
    }

    /// `corners` are three per triangle. A triangle with a repeated vertex has no area and is dropped, and counted.
    public static func weld(corners: [SIMD3<Float>]) -> (positions: [SIMD3<Float>], triangles: [UInt32], dropped: Int) {
        var indexOf: [Key: UInt32] = [:]
        // A closed mesh has about one vertex per six corners; the table grows if a file has more.
        indexOf.reserveCapacity(corners.count / 6)
        var positions: [SIMD3<Float>] = []
        var triangles: [UInt32] = []
        triangles.reserveCapacity(corners.count)
        var dropped = 0
        var triple: (UInt32, UInt32, UInt32) = (0, 0, 0)
        for (offset, corner) in corners.enumerated() {
            let point = corner + SIMD3<Float>.zero // -0 + 0 is +0
            let key = Key(x: point.x.bitPattern, y: point.y.bitPattern, z: point.z.bitPattern)
            let index: UInt32
            if let known = indexOf[key] {
                index = known
            } else {
                index = UInt32(positions.count)
                indexOf[key] = index
                positions.append(point)
            }
            switch offset % 3 {
            case 0: triple.0 = index
            case 1: triple.1 = index
            default:
                triple.2 = index
                if triple.0 == triple.1 || triple.1 == triple.2 || triple.0 == triple.2 {
                    dropped += 1
                } else {
                    triangles.append(triple.0)
                    triangles.append(triple.1)
                    triangles.append(triple.2)
                }
            }
        }
        return (positions, triangles, dropped)
    }
}

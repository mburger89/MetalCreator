import COCCT

extension OCCTShape {
    /// A faceted solid from a closed triangle mesh (implicit spec §4.7): a planar face per triangle built on shared vertices and edges, same-domain faces merged,
    /// and checked. `triangles` is three indices per face, counter-clockwise seen from outside.
    static func solid(fromMesh positions: [SIMD3<Float>], triangles: [UInt32]) throws(OCCTError) -> OCCTShape {
        var coordinates: [Double] = []
        coordinates.reserveCapacity(positions.count * 3)
        for position in positions { coordinates += [Double(position.x), Double(position.y), Double(position.z)] }
        return try make { status in
            coordinates.withUnsafeBufferPointer { points in
                triangles.withUnsafeBufferPointer { indices in
                    occt_mesh_to_solid(points.baseAddress, Int32(positions.count), indices.baseAddress, Int32(triangles.count / 3), status)
                }
            }
        }
    }
}

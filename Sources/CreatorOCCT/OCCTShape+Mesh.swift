import COCCT
import CreatorGeometry
import CreatorKernel
import Foundation

extension OCCTShape {
    func mesh(tolerance: Double) throws(OCCTError) -> DisplayMesh {
        var raw = occt_mesh()
        defer { occt_mesh_free(&raw) }
        try Self.check { status in occt_tessellate(self.raw, tolerance, &raw, status) }
        let vertexCount = Int(raw.vertex_count)
        let coordinates = UnsafeBufferPointer(start: raw.positions, count: vertexCount * 3)
        let normalCoordinates = UnsafeBufferPointer(start: raw.normals, count: vertexCount * 3)
        let positions = (0..<vertexCount).map { Vector3(coordinates[$0 * 3], coordinates[$0 * 3 + 1], coordinates[$0 * 3 + 2]) }
        let normals = (0..<vertexCount).map {
            Vector3(normalCoordinates[$0 * 3], normalCoordinates[$0 * 3 + 1], normalCoordinates[$0 * 3 + 2])
        }
        let triangleCount = Int(raw.triangle_count)
        let indices = Array(UnsafeBufferPointer(start: raw.indices, count: triangleCount * 3))
        let triangleFaces = UnsafeBufferPointer(start: raw.triangle_faces, count: triangleCount).map { FaceID(Int($0)) }
        let offsets = UnsafeBufferPointer(start: raw.edge_offsets, count: Int(raw.edge_count) + 1)
        let points = UnsafeBufferPointer(start: raw.edge_points, count: Int(offsets.last ?? 0) * 3)
        var polylines: [EdgeID: [Vector3]] = [:]
        for edge in 0..<Int(raw.edge_count) where offsets[edge + 1] > offsets[edge] {
            polylines[EdgeID(edge)] = (Int(offsets[edge])..<Int(offsets[edge + 1])).map {
                Vector3(points[$0 * 3], points[$0 * 3 + 1], points[$0 * 3 + 2])
            }
        }
        return DisplayMesh(positions: positions, normals: normals, indices: indices, triangleFaces: triangleFaces,
                           edgePolylines: polylines)
    }

    static func compound(_ shapes: [OCCTShape]) throws(OCCTError) -> OCCTShape {
        let pointers: [OpaquePointer?] = shapes.map(\.raw)
        return try pointers.withUnsafeBufferPointer { buffer throws(OCCTError) in
            try make { status in occt_make_compound(buffer.baseAddress, Int32(buffer.count), status) }
        }
    }

    /// Reads a STEP file. Used by the conformance tests; STEP import as a node is deferred (spec §11).
    static func readSTEP(_ url: URL) throws(OCCTError) -> OCCTShape {
        try make { status in url.withUnsafeFileSystemRepresentation { occt_read_step($0, status) } }
    }
}

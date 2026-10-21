import COCCT
import CreatorGeometry

extension OCCTShape {
    /// The parametrization of the face at the 1-based `index` (`occt_face_chart_info_of`). Call under `OCCTKernel.serialized`.
    func faceChartInfo(faceIndex index: Int32) throws(OCCTError) -> occt_face_chart_info {
        var info = occt_face_chart_info()
        try Self.check { status in occt_face_chart_info_of(self.raw, index, &info, status) }
        return info
    }

    /// Where `points` stand against the face at the 1-based `index`: three numbers per point, u, v and the signed distance
    /// (`occt_face_coordinates`). Call under `OCCTKernel.serialized`.
    func faceCoordinates(of points: ArraySlice<Vector3>, faceIndex index: Int32) throws(OCCTError) -> [Double] {
        guard !points.isEmpty else { return [] }
        var coordinates: [Double] = []
        coordinates.reserveCapacity(points.count * 3)
        for point in points {
            coordinates.append(contentsOf: [point.x, point.y, point.z])
        }
        var result = [Double](repeating: 0, count: points.count * 3)
        let count = Int32(points.count)
        try Self.check { status in
            coordinates.withUnsafeBufferPointer { xyz in
                result.withUnsafeMutableBufferPointer { out in
                    occt_face_coordinates(self.raw, index, xyz.baseAddress, count, out.baseAddress, status)
                }
            }
        }
        return result
    }
}

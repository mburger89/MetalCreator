import COCCT
import CreatorGeometry
import CreatorKernel

extension OCCTShape {
    /// The cross-section of this shape by `plane` (`occt_section`). Call under `OCCTKernel.serialized`.
    func section(by plane: Plane, tolerance: Double) throws(OCCTError) -> PlaneSection {
        var raw = occt_section_result()
        defer { occt_section_free(&raw) }
        let origin = [plane.origin.x, plane.origin.y, plane.origin.z]
        let normal = [plane.normal.x, plane.normal.y, plane.normal.z]
        let xAxis = [plane.xAxis.x, plane.xAxis.y, plane.xAxis.z]
        try Self.check { status in occt_section(self.raw, origin, normal, xAxis, tolerance, &raw, status) }
        guard raw.region_count > 0 else { return PlaneSection() }

        let vertexCount = Int(raw.vertex_count)
        let coordinates = UnsafeBufferPointer(start: raw.positions, count: vertexCount * 3)
        let indices = UnsafeBufferPointer(start: raw.indices, count: Int(raw.triangle_count) * 3)
        let triangleOffsets = UnsafeBufferPointer(start: raw.region_triangle_offsets, count: Int(raw.region_count) + 1)
        let pieceCount = Int(raw.piece_count)
        let pieceRegion = UnsafeBufferPointer(start: raw.piece_region, count: pieceCount)
        let pieceKind = UnsafeBufferPointer(start: raw.piece_kind, count: pieceCount)
        let curves = UnsafeBufferPointer(start: raw.piece_curve, count: pieceCount * 11)
        let sources = UnsafeBufferPointer(start: raw.piece_source_face, count: pieceCount)
        let pointOffsets = UnsafeBufferPointer(start: raw.piece_point_offsets, count: pieceCount + 1)
        let points = UnsafeBufferPointer(start: raw.piece_points, count: Int(pointOffsets.last ?? 0) * 3)

        func vector(_ buffer: UnsafeBufferPointer<Double>, _ at: Int) -> Vector3 {
            Vector3(buffer[at], buffer[at + 1], buffer[at + 2])
        }
        var pieces = [[SectionPiece]](repeating: [], count: Int(raw.region_count))
        for piece in 0..<pieceCount {
            let n = piece * 11
            let curve: EdgeCurve?
            switch pieceKind[piece] {
            case 1: curve = .line(start: vector(curves, n), end: vector(curves, n + 3))
            case 2:
                curve = .circle(center: vector(curves, n), axis: vector(curves, n + 3), radius: curves[n + 6],
                                start: vector(curves, n + 7), sweep: curves[n + 10])
            default: curve = nil
            }
            let polyline = (Int(pointOffsets[piece])..<Int(pointOffsets[piece + 1])).map { vector(points, $0 * 3) }
            pieces[Int(pieceRegion[piece])].append(
                SectionPiece(curve: curve, polyline: polyline, sourceFace: sources[piece] >= 0 ? FaceID(Int(sources[piece])) : nil))
        }

        var regions: [SectionRegion] = []
        for region in 0..<Int(raw.region_count) {
            let slice = indices[(Int(triangleOffsets[region]) * 3)..<(Int(triangleOffsets[region + 1]) * 3)]
            // A region's vertices are contiguous in the shared array: take its range and renumber from zero.
            guard let low = slice.min(), let high = slice.max() else { continue }
            let positions = (Int(low)...Int(high)).map { vector(coordinates, $0 * 3) }
            regions.append(SectionRegion(positions: positions, triangles: slice.map { $0 - low }, boundary: pieces[region]))
        }
        return PlaneSection(regions: regions, openOutlines: [])
    }
}

import CreatorGeometry
import CreatorKernel
import CreatorViewport

/// What the Measure session draws over the model: a pick's edge or point.
extension MeasureSession {
    func add(_ pick: MeasurePick, tint: OverlayTint, to overlay: inout ViewportOverlay) {
        switch pick {
        case .face: break
        case let .edge(solid, id):
            let path = edgePath(solid, id)
            for (a, b) in zip(path, path.dropFirst()) { overlay.lines.append(OverlayLine(a, b, tint: tint, width: 3)) }
        case let .corner(_, _, _, point), let .meshPoint(_, point):
            overlay.points.append(OverlayPoint(point, tint: tint, size: 10))
        case let .sectionEdge(_, piece, _):
            for (a, b) in zip(piece.polyline, piece.polyline.dropFirst()) { overlay.lines.append(OverlayLine(a, b, tint: tint, width: 3)) }
        }
    }

    /// The polyline the viewport draws an edge along, else (a display mesh without one) the straight line between its ends.
    func edgePath(_ solidIndex: Int, _ id: EdgeID) -> [Vector3] {
        guard solids.indices.contains(solidIndex) else { return [] }
        let solid = solids[solidIndex]
        if let line = viewport?.displayMesh(of: solid)?.edgePolylines[id], line.count >= 2 { return line }
        if let ends = solid.topology.edge(id)?.curve?.ends, ends.count == 2 { return ends }
        return []
    }
}

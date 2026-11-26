import CreatorGeometry
import CreatorKernel
import Foundation

extension DrawingPick.Picker {
    // MARK: Corners (plan R3)

    func corner(_ clicked: EdgeInfo, at point: Vector2) -> Result<PickedAnchor, DrawingRefusal> {
        let first: EdgePick
        switch name(clicked) {
        case .failure(let refused): return .failure(refused)
        case .success(let named): first = named
        }
        guard let curve = clicked.curve, let end = end(of: curve, nearest: mapping.model(point)),
              (mapping.sheet(frame.place(end.point)) - point).length <= Self.endTolerance,
              isExtremeEnd(end.point, of: first) else { return .failure(refusal(DrawingPick.cornerSentence)) }
        guard let second = neighbour(of: clicked, at: end, run: first) else { return .failure(refusal(DrawingPick.cornerSentence)) }
        let target = AnchorTarget.corner(first, second)
        switch held(target) {
        case .success(let geometry):
            var depth: Double?
            if case .point(let corner) = geometry { depth = corner.dot(frame.direction) }
            return .success(PickedAnchor(target: target, shape: shape(of: geometry), depth: depth))
        case .failure: return .failure(refusal(DrawingPick.cornerSentence))
        }
    }

    /// How far (sheet units) the stroke's end may lie from the edge's own end: a stroke that stops where the edge goes behind
    /// something ends at no vertex.
    private static let endTolerance = 1e-3

    private struct End {
        var point: Vector3
        var leaving: Vector3
    }

    private func end(of curve: EdgeCurve, nearest model: Vector2) -> End? {
        let points = curve.ends
        let directions = curve.endDirections
        guard points.count == 2, directions.count == 2 else { return nil }
        let distances = points.map { (frame.place($0) - model).length }
        let index = distances[0] <= distances[1] ? 0 : 1
        return End(point: points[index], leaving: directions[index])
    }

    /// The clicked end must be an end of its run that no other piece of the run meets: a joint inside a split run is no corner.
    private func isExtremeEnd(_ point: Vector3, of pick: EdgePick) -> Bool {
        let run = topology.edges(matching: pick.key)
        return DrawingAnchorResolver.runEnds(of: run).contains { ($0 - point).length <= DrawingAnchorResolver.joinTolerance }
    }

    /// The lowest-ID edge that meets the clicked end, neither continues the clicked edge nor lies in its run, and can be named.
    private func neighbour(of clicked: EdgeInfo, at end: End, run: EdgePick) -> EdgePick? {
        let inRun = Set(topology.edges(matching: run.key).map(\.id))
        let straightest = -cos(DrawingAnchorResolver.joinAngle)
        for edge in topology.edges.sorted(by: { $0.id.rawValue < $1.id.rawValue })
        where edge.id != clicked.id && !inRun.contains(edge.id) {
            guard let curve = edge.curve else { continue }
            let points = curve.ends
            let directions = curve.endDirections
            guard points.count == directions.count else { continue }
            let meets = points.indices.contains { index in
                (points[index] - end.point).length <= DrawingAnchorResolver.joinTolerance
                    && directions[index].dot(end.leaving) > straightest
            }
            guard meets, case .success(let pick) = name(edge) else { continue }
            return pick
        }
        return nil
    }

    // MARK: Outlines

    func outline(_ id: FaceID) -> Result<PickedAnchor, DrawingRefusal> {
        guard purpose != .holeCallout, purpose != .centreMark else { return .failure(wrong()) }
        guard let face = topology.face(id), face.kind == .cylinder, let axis = face.normal?.normalized,
              let axisPoint = face.axisPoint else { return .failure(refusal(DrawingPick.outlineOnlySentence)) }
        guard AnchorNaming.isLasting(face.tags) else { return .failure(refusal(wording.noCylinderName)) }
        guard let pick = topology.facePick(for: id), topology.faces(matching: pick).count == 1 else {
            return .failure(refusal(wording.sharedCylinder))
        }
        if !takesLeaders, abs(axis.dot(frame.direction)) > 1e-9 { return .failure(refusal(wording.cylinder)) }
        let target: AnchorTarget = purpose == .centreLine
            ? .axis(pick) : .outline(pick, side: side(axisPoint: axisPoint, axis: axis))
        switch held(target) {
        case .success(let geometry): return .success(PickedAnchor(target: target, shape: shape(of: geometry)))
        case .failure(let refused): return .failure(refused)
        }
    }

    /// The unit sheet vector from the axis toward the clicked line.
    private func side(axisPoint: Vector3, axis: Vector3) -> Vector2 {
        let flat = frame.place(axis)
        let length = flat.length
        let along = length > 1e-12 ? flat * (1 / length) : Vector2(1, 0)
        let offset = click - mapping.sheet(frame.place(axisPoint))
        let across = offset - along * (offset.x * along.x + offset.y * along.y)
        let size = across.length
        return size > 1e-12 ? across * (1 / size) : Vector2(-along.y, along.x)
    }
}

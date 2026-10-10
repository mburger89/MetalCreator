import CreatorGeometry
import CreatorSketch

/// Picking on the CPU in plane coordinates (sketcher spec §8): the nearest point within the tolerance, else the
/// nearest curve within it. Points win so a line's endpoint can be picked where the line passes too.
struct SketchPicker {
    let sketch: Sketch
    let solution: SketchSolution

    /// The nearest point entity to `p` within `tolerance` mm, leaving out `excluding`.
    func point(near p: Vector2, tolerance: Double, excluding: Set<SketchEntityID> = []) -> (id: SketchEntityID, at: Vector2)? {
        var best: (id: SketchEntityID, at: Vector2, distance: Double)?
        for id in sketch.entityIDs where !excluding.contains(id) {
            guard case .point? = sketch.entities[id]?.kind,
                  let at = SketchOverlayBuilder.position(id, sketch, solution) else { continue }
            let distance = (at - p).length
            if distance <= tolerance, distance < (best?.distance ?? .infinity) { best = (id, at, distance) }
        }
        return best.map { ($0.id, $0.at) }
    }

    /// The nearest curve (line, arc, circle or projected edge) to `p` within `tolerance` mm.
    func curve(near p: Vector2, tolerance: Double) -> SketchEntityID? {
        var best: (id: SketchEntityID, distance: Double)?
        for id in sketch.entityIDs {
            guard let kind = sketch.entities[id]?.kind else { continue }
            if case .point = kind { continue }
            let polyline = SketchOverlayBuilder.polyline(of: kind, sketch: sketch, solution: solution, id: id)
            let distance = EditorGeometry.distance(from: p, toPolyline: polyline)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) { best = (id, distance) }
        }
        return best?.id
    }

    /// The entity a click at `p` picks: a point first, else a curve.
    func entity(near p: Vector2, tolerance: Double) -> SketchEntityID? {
        point(near: p, tolerance: tolerance)?.id ?? curve(near: p, tolerance: tolerance)
    }

    /// The place on `curve` nearest `p`, at its solved position: on a line's segment, or on an arc's or a circle's
    /// circle (the curve is picked near its drawn span first, so that place is on what's drawn); `nil` for a point.
    func nearestPoint(on curve: SketchEntityID, to p: Vector2) -> Vector2? {
        let at = { (point: SketchEntityID) in SketchOverlayBuilder.position(point, sketch, solution) }
        switch sketch.entities[curve]?.kind {
        case .line(let start, let end)?:
            guard let a = at(start), let b = at(end) else { return nil }
            return EditorGeometry.nearest(to: p, onSegment: a, b)
        case .arc(let center, let start, _)?:
            guard let c = at(center), let s = at(start) else { return nil }
            return EditorGeometry.nearest(to: p, onCircle: c, radius: (s - c).length)
        case .circle(let center, _)?:
            guard let c = at(center), let radius = solution.radii[curve] ?? sketch.radius(of: curve) else { return nil }
            return EditorGeometry.nearest(to: p, onCircle: c, radius: radius)
        case .projected(let source)?:
            switch source.curve {
            case .line(let a, let b): return EditorGeometry.nearest(to: p, onSegment: a, b)
            case .arc(let c, let radius, _, _), .circle(let c, let radius):
                return EditorGeometry.nearest(to: p, onCircle: c, radius: radius)
            }
        case .point?, nil:
            return nil
        }
    }
}

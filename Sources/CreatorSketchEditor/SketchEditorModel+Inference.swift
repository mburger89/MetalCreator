import CreatorGeometry
import CreatorSketch

extension SketchEditorModel {
    /// What a line from `start` to the free point `end` infers, and where its end snaps: tangent to an arc that starts
    /// or ends at the line's start, when the end is within the tolerance of that tangent (sketcher spec §8: "tangent to
    /// the previous arc"; the newest such arc), else horizontal or vertical (`LineInference.infer`). Nothing when ⌘
    /// suppresses it.
    func lineInference(from start: SketchAnchor, to end: Vector2, tolerance: Double, suppressed: Bool) -> (LineInference?, Vector2) {
        if !suppressed, let tangent = tangent(at: start) {
            let offset = end - start.position
            let along = offset.x * tangent.direction.x + offset.y * tangent.direction.y
            let across = abs(offset.x * tangent.direction.y - offset.y * tangent.direction.x)
            if abs(along) > tolerance, across <= tolerance {
                return (.tangent(tangent.arc), start.position + tangent.direction * along)
            }
        }
        return LineInference.infer(from: start.position, to: end, tolerance: tolerance, suppressed: suppressed)
    }

    /// The constraints a click landing on `target` (`anchor`) would infer (sketcher spec §8: "a glyph previews each
    /// inferred constraint"): a new point shares an existing one (coincident) or is held on a curve (point on); a
    /// line's free end snaps tangent, horizontal or vertical. Clicks that place no point (a circle's radius, a 3-point
    /// arc's third point) infer nothing, and an arc's end only shares a point (its end is moved onto the radius
    /// otherwise). ⌘ (`suppressed`) leaves only coincident.
    func inferredConstraints(landing target: SketchAnchor, tolerance: Double, suppressed: Bool) -> [SketchConstraintKind] {
        switch drawState {
        case .idle:
            return tool.placesPoints ? Self.inferred(by: target) : []
        case .lineFrom(let start):
            guard case .free(let at) = target else { return Self.inferred(by: target) }
            return lineInference(from: start, to: at, tolerance: tolerance, suppressed: suppressed).0.map { [$0.kind] } ?? []
        case .arcAround, .arcThroughFrom:
            return Self.inferred(by: target)
        case .arcFrom:
            return target.point == nil ? [] : [.coincident]
        case .circleAround, .arcThrough:
            return []
        }
    }

    /// Coincident on a point, point on for a curve, nothing in free space.
    static func inferred(by anchor: SketchAnchor) -> [SketchConstraintKind] {
        switch anchor {
        case .existing: [.coincident]
        case .onCurve: [.pointOn]
        case .free: []
        }
    }

    /// The newest arc that starts or ends at `start`'s point, and its unit tangent there.
    private func tangent(at start: SketchAnchor) -> (arc: SketchEntityID, direction: Vector2)? {
        guard let point = start.point else { return nil }
        for id in sketch.entityIDs.reversed() {
            guard case .arc(let center, let from, let to)? = sketch.entities[id]?.kind, from == point || to == point,
                  let c = SketchOverlayBuilder.position(center, sketch, solution) else { continue }
            let radius = start.position - c
            let length = radius.length
            guard length > 1e-9 else { continue }
            return (id, Vector2(-radius.y / length, radius.x / length))
        }
        return nil
    }
}

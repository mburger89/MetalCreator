import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Foundation

/// Draws a sketch as a viewport overlay on its plane (sketcher spec §8's colours): each curve and point in its
/// freedom's colour, construction dashed in its own, projected edges in theirs, the selection and the hovered entity
/// over everything, then the tool's rubber band, with the plane's grid underneath. Pure.
enum SketchOverlayBuilder {
    /// Curve and point sizes, in points.
    static let curveWidth = 1.5
    static let selectedWidth = 2.5
    static let pointSize = 6.0

    static func overlay(sketch: Sketch, solution: SketchSolution, plane: Plane, selection: Set<SketchEntityID>,
                        hovered: SketchEntityID?, preview: SketchPreview, fills: [OverlayFill] = [],
                        handleSplines: [SketchEntityID] = [], hoveredKnob: HandleKnob? = nil) -> ViewportOverlay {
        var lines: [OverlayLine] = []
        var points: [OverlayPoint] = []
        for id in sketch.entityIDs {
            guard let entity = sketch.entities[id] else { continue }
            let tint = tint(of: id, entity, solution: solution, selection: selection, hovered: hovered)
            let width = tint == .selected || tint == .hovered ? selectedWidth : curveWidth
            if case .point = entity.kind {
                if let at = position(id, sketch, solution) { points.append(OverlayPoint(plane.point(at), tint: tint, size: pointSize)) }
                continue
            }
            let polyline = self.polyline(of: entity.kind, sketch: sketch, solution: solution, id: id)
            lines += segments(polyline, on: plane, tint: tint, width: width, dashed: entity.isConstruction)
        }
        for spline in handleSplines {
            let handles = handles(of: spline, sketch: sketch, solution: solution, plane: plane, hoveredKnob: hoveredKnob)
            lines += handles.lines
            points += handles.points
        }
        for curve in preview.curves {
            lines += segments(polyline(of: curve), on: plane, tint: .preview, width: curveWidth, dashed: false)
        }
        points += preview.points.map { OverlayPoint(plane.point($0), tint: .preview, size: pointSize) }
        return ViewportOverlay(lines: lines, points: points, fills: fills, gridPlane: plane)
    }

    /// The colour role of one entity: selected, then hovered, then conflicting, a suspended projection (conflicting too:
    /// its pick finds no edge now), construction, projected, then free or fixed.
    static func tint(of id: SketchEntityID, _ entity: SketchEntity, solution: SketchSolution, selection: Set<SketchEntityID>,
                     hovered: SketchEntityID?) -> OverlayTint {
        if selection.contains(id) { return .selected }
        if hovered == id { return .hovered }
        let freedom = solution.freedom[id] ?? .free
        if freedom == .conflicting { return .conflicting }
        if case .projected(let source) = entity.kind, source.isSuspended { return .conflicting }
        if entity.isConstruction { return .construction }
        if case .projected = entity.kind { return .projected }
        return freedom == .fixed ? .fullyConstrained : .underConstrained
    }

    /// A point's solved position, else its stored one.
    static func position(_ id: SketchEntityID, _ sketch: Sketch, _ solution: SketchSolution) -> Vector2? {
        solution.points[id] ?? sketch.position(of: id)
    }

    /// A curve entity as a polyline in plane coordinates, at its solved positions; empty for a curve whose points are
    /// missing.
    static func polyline(of kind: SketchEntityKind, sketch: Sketch, solution: SketchSolution, id: SketchEntityID) -> [Vector2] {
        let at = { (point: SketchEntityID) in position(point, sketch, solution) }
        switch kind {
        case .point:
            return []
        case .line(let start, let end):
            guard let a = at(start), let b = at(end) else { return [] }
            return [a, b]
        case .arc(let center, let start, let end):
            guard let c = at(center), let s = at(start), let e = at(end) else { return [] }
            return EditorGeometry.arcPoints(center: c, start: s, end: e)
        case .circle(let center, _):
            guard let c = at(center), let radius = solution.radii[id] ?? sketch.radius(of: id) else { return [] }
            return EditorGeometry.circlePoints(center: c, radius: radius)
        case .projected(let source):
            return polyline(of: source.curve)
        case .spline:
            // Task 5 draws the real overlay (handles, selection); a polyline of the exact curve keeps it visible and pickable.
            return sketch.splineDefinition(of: id, solution: solution)?.curve().polyline() ?? []
        }
    }

    static func polyline(of curve: ProjectedCurve) -> [Vector2] {
        switch curve {
        case .line(let a, let b):
            return [a, b]
        case .circle(let center, let radius):
            return EditorGeometry.circlePoints(center: center, radius: radius)
        case .arc(let center, let radius, let start, let end):
            let from = center + Vector2(cos(start.radians), sin(start.radians)) * radius
            let to = center + Vector2(cos(end.radians), sin(end.radians)) * radius
            return EditorGeometry.arcPoints(center: center, start: from, end: to)
        }
    }

    static func polyline(of curve: PreviewCurve) -> [Vector2] {
        switch curve {
        case .line(let a, let b): [a, b]
        case .circle(let center, let radius): EditorGeometry.circlePoints(center: center, radius: radius)
        case .arc(let center, let start, let end): EditorGeometry.arcPoints(center: center, start: start, end: end)
        case .spline(let through): splinePolyline(through: through)
        case .fitSpline(let definition): definition.curve().polyline()
        }
    }

    /// A spline through `positions` with automatic handles, as a polyline; the points themselves when it has no length.
    static func splinePolyline(through positions: [Vector2]) -> [Vector2] {
        var distinct: [Vector2] = []
        for position in positions where distinct.last.map({ ($0 - position).length > 1e-6 }) ?? true { distinct.append(position) }
        guard distinct.count >= 2 else { return distinct }
        return SplineDefinition(points: distinct).curve().polyline()
    }

    /// A spline's handles: at each fit point a tangent line with a knob at each end and a curvature arc with its knob, the
    /// automatic ones in the construction colour, the active ones in the under-constrained colour and the hovered knob lit.
    static func handles(of spline: SketchEntityID, sketch: Sketch, solution: SketchSolution, plane: Plane,
                        hoveredKnob: HandleKnob?) -> (lines: [OverlayLine], points: [OverlayPoint]) {
        guard let definition = sketch.splineDefinition(of: spline, solution: solution),
              let states = sketch.splineParts(of: spline)?.handles else { return ([], []) }
        var lines: [OverlayLine] = []
        var points: [OverlayPoint] = []
        for index in definition.points.indices {
            let state = index < states.count ? states[index] : .automatic
            for (knob, at) in SplineHandleGeometry.knobs(of: spline, at: index, definition: definition) {
                let isActive = knob.kind == .tangent ? state.tangent : state.curvature
                let tint: OverlayTint = knob == hoveredKnob ? .hovered : isActive ? .underConstrained : .construction
                lines += segments(SplineHandleGeometry.glyph(of: knob, at: at, point: definition.points[index]), on: plane, tint: tint,
                                  width: curveWidth, dashed: !isActive)
                points.append(OverlayPoint(plane.point(at), tint: tint, size: pointSize))
            }
        }
        return (lines, points)
    }

    static func segments(_ polyline: [Vector2], on plane: Plane, tint: OverlayTint, width: Double, dashed: Bool) -> [OverlayLine] {
        zip(polyline, polyline.dropFirst()).map { a, b in
            OverlayLine(plane.point(a), plane.point(b), tint: tint, width: width, isDashed: dashed)
        }
    }
}

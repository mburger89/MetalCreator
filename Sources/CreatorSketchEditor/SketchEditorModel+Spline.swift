import CreatorGeometry
import CreatorSketch
import CreatorViewport

/// The Spline tool (spec "Behaviour": drawing) and the handle drags and releases.
extension SketchEditorModel {
    /// A click with the Spline tool: the first starts the curve, each later one adds a fit point, and a click on the last
    /// one again (a double click is two) finishes it. A point already in the stroke is ignored.
    func placeSplinePoint(at p: Vector2, tolerance: Double, suppressed: Bool) {
        let target = anchor(at: p, tolerance: tolerance, suppressed: suppressed)
        guard case .splineThrough(var placed) = drawState, let last = placed.last else {
            drawState = .splineThrough([target])
            splineStartSuppressed = suppressed
            return
        }
        if (target.position - last.position).length <= tolerance || (target.point != nil && target.point == last.point) {
            finishSpline(endSuppressed: suppressed)
            return
        }
        if let point = target.point, placed.contains(where: { $0.point == point }) { return }
        placed.append(target)
        drawState = .splineThrough(placed)
    }

    /// Return, Esc, or a click on the last point: the spline through the points placed becomes one step, with a Tangent where
    /// it starts or ends on the end of a line, an arc or another spline (⌘ at that click suppresses it). One point is dropped.
    func finishSpline(endSuppressed: Bool = false) {
        guard case .splineThrough(let placed) = drawState else { return }
        drawState = .idle
        preview = .none
        guard placed.count >= 2 else { return }
        var edited = sketch
        let points = placed.map { $0.point(in: &edited, isConstruction: isConstruction) }
        let spline = edited.addSpline(through: points, isConstruction: isConstruction)
        var joined: [SketchEntityID] = []
        for (point, suppressed) in [(points[0], splineStartSuppressed), (points[points.count - 1], endSuppressed)] where !suppressed {
            guard let other = jointCurve(at: point, excluding: spline, in: edited), !joined.contains(other) else { continue }
            joined.append(other)
            let constraint = SketchConstraint.tangent(spline, other)
            edited.activateHandles(for: constraint)
            edited.add(constraint)
        }
        commit(edited, "Spline", named: SketchStepName.addSpline)
    }

    /// The newest line, arc or spline (other than `spline`) with an end at `point`.
    func jointCurve(at point: SketchEntityID, excluding spline: SketchEntityID? = nil, in sketch: Sketch? = nil) -> SketchEntityID? {
        let sketch = sketch ?? self.sketch
        return sketch.entityIDs.reversed().first { id in
            id != spline && sketch.curveEnds(of: id).contains(point)
        }
    }

    /// The glyph the next click would infer: Tangent when it lands on the end of a curve (⌘ suppresses), else what a point infers.
    func splineInferred(landing target: SketchAnchor, suppressed: Bool) -> [SketchConstraintKind] {
        if !suppressed, let point = target.point, jointCurve(at: point) != nil { return [.tangent] }
        return Self.inferred(by: target)
    }

    /// The rubber band: the spline through what is placed and where a click would land.
    func splineBand(_ placed: [SketchAnchor], landing target: SketchAnchor) -> SketchPreview {
        var positions = placed.map(\.position)
        if let last = positions.last, (target.position - last).length > 1e-6 { positions.append(target.position) }
        return SketchPreview(curves: positions.count >= 2 ? [.spline(through: positions)] : [], points: positions)
    }

    // MARK: Handles

    /// The splines whose handles are shown: the selected ones and the ones through a selected fit point.
    var handleSplines: [SketchEntityID] {
        sketch.entityIDs.filter { id in
            guard let parts = sketch.splineParts(of: id) else { return false }
            return selection.contains(id) || parts.points.contains { selection.contains($0) }
        }
    }

    /// Releases one handle of a fit point (the inspector's Release): automatic again, as one step. A handle a constraint uses
    /// can't be released, and says so.
    public func releaseHandle(of spline: SketchEntityID, at index: Int, _ kind: SplineHandleKind) {
        var edited = sketch
        guard edited.releaseSplineHandle(spline, at: index, kind) else {
            refusal = "A constraint uses that handle, so it can't be released."
            return
        }
        commit(edited, "Release \(kind == .tangent ? "tangent" : "curvature") handle", named: SketchStepName.releaseHandle)
    }

    /// The handle rows of every selected fit point.
    public var handleRows: [SplineHandleRow] {
        var rows: [SplineHandleRow] = []
        for id in sketch.entityIDs {
            guard let parts = sketch.splineParts(of: id) else { continue }
            for (index, point) in parts.points.enumerated() where selection.contains(point) {
                let state = index < parts.handles.count ? parts.handles[index] : .automatic
                for kind in [SplineHandleKind.tangent, .curvature] {
                    let isActive = kind == .tangent ? state.tangent : state.curvature
                    let name = kind == .tangent ? "Tangent" : "Curvature"
                    rows.append(SplineHandleRow(spline: id, index: index, kind: kind, isActive: isActive,
                                                label: "\(name) handle: \(isActive ? "Active" : "Automatic")"))
                }
            }
        }
        return rows
    }

    /// Starts dragging a knob: its handle becomes active at its present value (the curve does not change) and the drag solves
    /// with the knob as a soft target.
    func beginHandleDrag(_ knob: HandleKnob) {
        guard let definition = sketch.splineDefinition(of: knob.spline, solution: solution) else { return }
        dragOrigin = sketch
        var edited = sketch
        edited.activateSplineHandle(knob.spline, at: knob.index, knob.kind)
        sketch = edited
        draggedHandle = HandleDrag(knob: knob, scale: SplineHandleGeometry.scale(points: definition.points, at: knob.index))
        handleMoved = false
        preview = .none
    }

    /// One handle drag step: the vector the pointer stands for is the handle's soft target.
    func dragHandle(to p: Vector2) {
        guard let drag = draggedHandle, let definition = sketch.splineDefinition(of: drag.knob.spline, solution: solution),
              definition.points.indices.contains(drag.knob.index) else { return }
        let point = definition.points[drag.knob.index]
        let resolved = definition.resolvedHandles()[drag.knob.index]
        let value: Vector2?
        switch drag.knob.kind {
        case .tangent:
            let tangent = SplineHandleGeometry.tangentValue(point: point, knob: p, scale: drag.scale, sign: drag.knob.sign)
            value = tangent.length > 1e-6 ? tangent : nil
        case .curvature:
            value = SplineHandleGeometry.curvatureValue(point: point, knob: p, tangent: resolved.tangent, second: resolved.secondDerivative,
                                                        scale: drag.scale)
        }
        guard let value else { return }
        let target = SplineHandleTarget(spline: drag.knob.spline, index: drag.knob.index, kind: drag.knob.kind, value: value)
        let pulled = SketchSolver.solve(sketch, draggingHandles: [target])
        solution = pulled
        sketch = Self.remembering(sketch, pulled)
        handleMoved = true
    }

    func endHandleDrag(at p: Vector2?) {
        guard draggedHandle != nil else { return }
        if let p { dragHandle(to: p) }
        let origin = dragOrigin
        draggedHandle = nil
        dragOrigin = nil
        if !handleMoved, let origin {
            sketch = origin
            solution = SketchSolver.solve(origin)
        } else {
            commit(sketch, "Move Handle", named: SketchStepName.moveHandle)
        }
    }
}

/// A handle being dragged: its knob and the scale its vector is drawn at.
struct HandleDrag: Hashable, Sendable {
    var knob: HandleKnob
    var scale: Double
}

/// One row of the inspector for a selected fit point: a handle, whether it is active, and (when it is) the Release button.
public struct SplineHandleRow: Hashable, Sendable {
    public var spline: SketchEntityID
    public var index: Int
    public var kind: SplineHandleKind
    public var isActive: Bool
    public var label: String

    public var id: String { "\(spline.rawValue):\(index):\(kind.rawValue)" }
}

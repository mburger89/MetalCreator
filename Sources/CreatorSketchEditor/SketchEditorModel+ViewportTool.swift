import CreatorGeometry
import CreatorViewport

/// The viewport's primary input, mapped onto the sketch plane (sketcher spec §8: "intersect the cursor ray with the
/// plane, then take the nearest entity within a few pixels"). The editor claims every click while it is the tool, so
/// a click never selects the model under the sketch. The camera is locked to the plane while sketching (planar
/// navigation: drags off the sketch's points pan, nothing turns the camera), and F frames the sketch.
extension SketchEditorModel: ViewportTool {
    public var navigation: ViewportNavigation { .planar }

    /// The sketch on its plane with a 10% margin (its points, and each circle and arc as its whole circle), or 100 mm
    /// around the plane's origin when that has no size: what entering the sketch and F frame.
    public var framingBounds: BoundingBox? {
        let points = framedPoints().map(plane.point)
        if let box = BoundingBox(points: points), box.size.length > 1e-6 {
            let margin = box.size * 0.1
            return BoundingBox(min: box.min - margin, max: box.max + margin)
        }
        return BoundingBox(points: [plane.point(Vector2(-50, -50)), plane.point(Vector2(50, 50))])
            ?? BoundingBox(min: plane.origin, max: plane.origin)
    }

    /// `pickRadius` points in plane millimetres at the projector's zoom.
    func tolerance(_ projector: ViewportProjector) -> Double {
        Self.pickRadius * projector.millimetresPerPoint
    }

    public func pointerMoved(to point: ScreenPoint?, projector: ViewportProjector) {
        follow(point, projector)
        hover(at: point.flatMap { projector.planePoint(under: $0, on: plane) }, tolerance: tolerance(projector), modifiers: [])
    }

    public func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool {
        follow(point, projector)
        if let p = projector.planePoint(under: point, on: plane) {
            click(at: p, tolerance: tolerance(projector), modifiers: modifiers)
        }
        return true
    }

    /// A drag that starts on a point moves it; any other drag pans (planar navigation).
    public func dragBegan(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool {
        guard let p = projector.planePoint(under: point, on: plane) else { return false }
        return beginDrag(at: p, tolerance: tolerance(projector))
    }

    public func dragMoved(to point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {
        if let p = projector.planePoint(under: point, on: plane) { drag(to: p) }
    }

    public func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {
        endDrag(at: projector.planePoint(under: point, on: plane))
    }

    /// Records where the pointer is on screen, for the readout's chip.
    private func follow(_ point: ScreenPoint?, _ projector: ViewportProjector) {
        if pointerOnScreen != point { pointerOnScreen = point }
        if viewSize != projector.size { viewSize = projector.size }
        if modelArea != projector.modelArea { modelArea = projector.modelArea }
    }

    /// The plane points framing must hold: every point, and the corners of each circle's and arc's square.
    private func framedPoints() -> [Vector2] {
        var points = sketch.entityIDs.compactMap { sketch.position(of: $0) }
        for id in sketch.entityIDs {
            var circle: (center: Vector2, radius: Double)?
            switch sketch.entities[id]?.kind {
            case .circle(let center, _)?:
                if let c = sketch.position(of: center), let r = sketch.radius(of: id) { circle = (c, r) }
            case .arc(let center, let start, _)?:
                if let c = sketch.position(of: center), let s = sketch.position(of: start) { circle = (c, (s - c).length) }
            default:
                break
            }
            guard let circle, circle.radius.isFinite else { continue }
            let r = abs(circle.radius)
            points += [circle.center - Vector2(r, r), circle.center + Vector2(r, r)]
        }
        return points
    }
}

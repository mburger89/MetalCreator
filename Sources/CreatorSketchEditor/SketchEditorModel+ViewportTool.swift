import CreatorGeometry
import CreatorViewport

/// The viewport's primary input, mapped onto the sketch plane (sketcher spec §8: "intersect the cursor ray with the
/// plane, then take the nearest entity within a few pixels"). The editor claims every click while it is the tool, so
/// a click never selects the model under the sketch.
extension SketchEditorModel: ViewportTool {
    /// `pickRadius` points in plane millimetres at the projector's zoom.
    func tolerance(_ projector: ViewportProjector) -> Double {
        Self.pickRadius * projector.millimetresPerPoint
    }

    public func pointerMoved(to point: ScreenPoint?, projector: ViewportProjector) {
        hover(at: point.flatMap { projector.planePoint(under: $0, on: plane) }, tolerance: tolerance(projector), modifiers: [])
    }

    public func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool {
        if let p = projector.planePoint(under: point, on: plane) {
            click(at: p, tolerance: tolerance(projector), modifiers: modifiers)
        }
        return true
    }

    /// A drag that starts on a point moves it; any other drag orbits.
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
}

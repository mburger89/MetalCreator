// Test fixture file: a viewport tool that records what reaches it and claims what it is told to.
import CreatorGeometry
@testable import CreatorViewport

/// Records every call as a short string ("moved 10,20", "clicked 10,20", "began 10,20", "dragged 10,20",
/// "ended 10,20"), and claims clicks and drags while `claims` is true.
@MainActor
final class RecordingTool: ViewportTool {
    var claims = true
    /// Whether the tool takes the pick under a click it declined (`clickedModel`).
    var claimsModel = false
    /// The picks offered to `clickedModel`, in order (`nil`: empty space).
    private(set) var modelPicks: [PickTarget?] = []
    /// How the viewport navigates while this tool is set (free orbit unless a test says otherwise).
    var navigation = ViewportNavigation.free
    /// What F frames while this tool is set.
    var framingBounds: BoundingBox?
    private(set) var calls: [String] = []
    private(set) var lastProjector: ViewportProjector?

    private func record(_ verb: String, _ point: ScreenPoint?, _ projector: ViewportProjector) {
        calls.append(point.map { "\(verb) \(Int($0.x)),\(Int($0.y))" } ?? "\(verb) nowhere")
        lastProjector = projector
    }

    func pointerMoved(to point: ScreenPoint?, projector: ViewportProjector) { record("moved", point, projector) }

    func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool {
        record("clicked", point, projector)
        return claims
    }

    func dragBegan(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool {
        record("began", point, projector)
        return claims
    }

    func dragMoved(to point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {
        record("dragged", point, projector)
    }

    func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {
        record("ended", point, projector)
    }

    func clickedModel(_ target: PickTarget?, at point: ScreenPoint, modifiers: ViewportModifiers,
                      projector: ViewportProjector) -> Bool {
        modelPicks.append(target)
        return claimsModel
    }
}

// Test fixture file: a viewport tool that records the modifiers a hover and a click reach it with.
import CreatorGeometry
@testable import CreatorViewport

/// Claims every click and records, in order, what the viewport tells it: each hover's point and the modifiers held, and
/// each click's modifiers.
@MainActor
final class ModifierProbeTool: ViewportTool {
    struct Hover: Equatable {
        var point: ScreenPoint?
        var modifiers: ViewportModifiers
    }

    private(set) var hovers: [Hover] = []
    private(set) var clicks: [ViewportModifiers] = []

    func pointerMoved(to point: ScreenPoint?, modifiers: ViewportModifiers, projector: ViewportProjector) {
        hovers.append(Hover(point: point, modifiers: modifiers))
    }

    func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool {
        clicks.append(modifiers)
        return true
    }

    func dragBegan(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool { false }
    func dragMoved(to point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {}
    func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {}
}

import CreatorGeometry
import MetalUI
import Testing
@testable import CreatorViewport

/// The pointer's shape (docs/metalui-gaps.md C7 item 5): a crosshair while picking, a closed hand while orbiting
/// or panning, the arrow otherwise.
@MainActor
struct CursorTests {
    func makeModel() -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: CameraPose(target: .zero, distance: 100), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        return model
    }

    @Test func theCursorIsAHandWhileOrbitingOrPanningAndACrosshairWhilePicking() {
        let model = makeModel()
        #expect(model.cursor == nil)
        model.isPicking = true
        #expect(model.cursor == .crosshair)
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(220, 150), modifiers: [], button: .primary)
        #expect(model.activeDragMode == .orbit)
        #expect(model.cursor == .grabbing, "the hand wins while a drag navigates")
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(220, 150), modifiers: [], button: .primary)
        #expect(model.activeDragMode == nil)
        #expect(model.cursor == .crosshair)
        model.isPicking = false
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(220, 150), modifiers: [], button: .middle)
        #expect(model.cursor == .grabbing)
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(220, 150), modifiers: [], button: .middle)
        model.dragChanged(from: model.cubeLayout.center, to: model.cubeLayout.center + ScreenPoint(10, 0), modifiers: [],
                          button: .primary)
        #expect(model.cursor == .grabbing, "dragging the cube orbits")
    }

    @Test func zoomAndHandleDragsKeepTheArrow() {
        let model = makeModel()
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(200, 120), modifiers: .option, button: .primary)
        #expect(model.activeDragMode == .zoom)
        #expect(model.cursor == nil)
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(200, 120), modifiers: .option, button: .primary)
        model.isPicking = true
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(200, 120), modifiers: .option, button: .primary)
        #expect(model.cursor == .crosshair)
    }

    /// A drag whose release was lost leaves no closed hand behind once the primary button is used again
    /// (docs/metalui-gaps.md VI-a).
    @Test func aClickAfterALostDragBringsBackTheArrow() {
        let model = makeModel()
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(220, 150), modifiers: [], button: .middle)
        #expect(model.cursor == .grabbing)
        model.click(at: ScreenPoint(300, 220))
        #expect(model.activeDragMode == nil)
        #expect(model.cursor == nil)
    }

    @Test func cursorsAreMetalUIPointerStyles() {
        #expect(ViewportCursor.crosshair.pointerStyle == .rectSelection)
        #expect(ViewportCursor.grabbing.pointerStyle == .grabActive)
    }
}

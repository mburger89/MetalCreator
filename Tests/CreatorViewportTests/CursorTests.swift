import CreatorGeometry
import Foundation
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

    /// The view cube's drag is its own mode: it orbits like a drag in the view, but a click on it picks a region.
    @Test func aDragFromTheCubeIsTheCubeModeAndAHandCursor() {
        let model = makeModel()
        let from = model.cubeLayout.center
        model.dragChanged(from: from, to: from + ScreenPoint(10, 0), modifiers: [], button: .primary)
        #expect(model.activeDragMode == .cube)
        #expect(model.cursor == .grabbing)
        model.dragEnded(from: from, at: from + ScreenPoint(10, 0), modifiers: [], button: .primary)
        #expect(model.activeDragMode == nil && model.cursor == nil)
    }

    /// A handle's knob drag edits the handle: it keeps the arrow (or the crosshair while picking).
    @Test func aHandleDragKeepsTheArrow() {
        let pose = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0,
                              projection: .orthographic)
        let model = ViewportModel(kernel: StubMeshKernel(), pose: pose, clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.showHandles([ViewportHandle(id: "extrude", anchor: .zero, direction: .unitZ, value: 10, range: 0...100,
                                          style: .linear, tint: .solid),
        ])
        // 40 mm tall in 300 points: the knob at z = 10 is 75 points above the centre.
        model.dragChanged(from: ScreenPoint(200, 75), to: ScreenPoint(200, 60), modifiers: [], button: .primary)
        #expect(model.activeDragMode == .handle("extrude"))
        #expect(model.cursor == nil)
        model.isPicking = true
        #expect(model.cursor == .crosshair)
    }
}

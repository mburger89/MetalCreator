import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// A tool that records what `hoverChanged` reports.
@MainActor
final class HoverRecordingTool: ViewportTool {
    var offersSectionFromFace = false
    private(set) var hovers: [PickTarget?] = []
    private(set) var points: [ScreenPoint?] = []

    func pointerMoved(to point: ScreenPoint?, modifiers: ViewportModifiers, projector: ViewportProjector) {}
    func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool { false }
    func dragBegan(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool { false }
    func dragMoved(to point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {}
    func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {}

    func hoverChanged(_ target: PickTarget?, at point: ScreenPoint?, projector: ViewportProjector) {
        hovers.append(target)
        points.append(point)
    }
}

@MainActor
struct ToolHoverTests {
    func model() async throws -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: CameraPose(target: .zero, distance: 100, yaw: 0.6, pitch: 0.4),
                                  clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.show([ViewportItem(solid: try await fakeBox())])
        await model.waitForMeshes()
        return model
    }

    @Test func aToolHearsTheFaceUnderThePointerAndWhenItLeaves() async throws {
        let model = try await model()
        let tool = HoverRecordingTool()
        model.tool = tool
        var under: PickTarget? = .face(solid: 0, FaceID(2))
        model.pick = { _ in under }
        model.pointerHovered(at: ScreenPoint(300, 200))
        #expect(tool.hovers == [.face(solid: 0, FaceID(2))] && tool.points == [ScreenPoint(300, 200)])
        under = nil
        model.pointerHovered(at: ScreenPoint(301, 200))
        #expect(tool.hovers == [.face(solid: 0, FaceID(2)), nil])
        model.pointerHovered(at: ScreenPoint(302, 200))
        #expect(tool.hovers.count == 2, "an unchanged hover is not reported again")
    }

    @Test func aCameraMoveUnderAStillPointerIsHeard() async throws {
        let model = try await model()
        let tool = HoverRecordingTool()
        model.tool = tool
        var under: PickTarget? = .face(solid: 0, FaceID(2))
        model.pick = { _ in under }
        model.pointerHovered(at: ScreenPoint(300, 200))
        under = .edge(solid: 0, EdgeID(4))
        model.refreshHover()   // what a settled camera animation or a landed pick runs
        #expect(tool.hovers.last == .edge(solid: 0, EdgeID(4)) && tool.points.last == ScreenPoint(300, 200))
    }
}

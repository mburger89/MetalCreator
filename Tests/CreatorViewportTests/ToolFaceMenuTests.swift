import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

@MainActor
struct ToolFaceMenuTests {
    func model() async throws -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: CameraPose(target: .zero, distance: 100, yaw: 0.6, pitch: 0.4),
                                  clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.show([ViewportItem(solid: try await fakeBox())])
        await model.waitForMeshes()
        model.pick = { _ in .face(solid: 0, FaceID(1)) }
        return model
    }

    @Test func aToolThatAsksForItGetsSectionFromFaceOnAFlatFace() async throws {
        let model = try await model()
        let cap = ViewportFaceRef(solidIndex: 0, face: FaceID(1))
        let tool = HoverRecordingTool()
        model.tool = tool
        #expect(model.contextMenuItems(at: ScreenPoint(300, 200)) == [.lookAt(cap)])
        tool.offersSectionFromFace = true
        #expect(model.contextMenuItems(at: ScreenPoint(300, 200)) == [.lookAt(cap), .sectionFromFace(cap)])
        model.tool = nil
        #expect(model.contextMenuItems(at: ScreenPoint(300, 200)).contains(.sectionFromFace(cap)), "no tool: the full menu")
    }
}

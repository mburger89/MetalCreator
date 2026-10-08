import CreatorGeometry
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

@MainActor
struct ViewStateCameraTests {
    @Test func cameraAndHomeRoundTrip() throws {
        let state = ViewState(dock: .bottom, camera: CameraPose(target: Vector3(1, 2, 3), distance: 80, yaw: 0.5,
                                                                 pitch: 0.25, projection: .orthographic),
                              homeCamera: CameraPose())
        #expect(try JSONDecoder().decode(ViewState.self, from: JSONEncoder().encode(state)) == state)
    }

    @Test func olderFilesWithoutACameraStillDecode() throws {
        let decoded = try JSONDecoder().decode(ViewState.self, from: Data(#"{"dock":"left","canvasZoom":2}"#.utf8))
        #expect(decoded.camera == nil)
        #expect(decoded.homeCamera == nil)
        #expect(decoded.canvasZoom == 2)
    }

    @Test func nonFiniteCameraIsRefusedSoTheDocumentStillSaves() throws {
        let document = DocumentModel(file: GraphFile(graph: graph([makeNode(ConstantNode.self)])), registry: testRegistry,
                                     kernel: FakeKernel())
        let good = CameraPose(target: Vector3(1, 2, 3), distance: 50)
        document.viewState.camera = good
        document.viewState.camera = CameraPose(target: Vector3(.nan, 0, 0))
        document.viewState.homeCamera = CameraPose(distance: .infinity)
        #expect(document.viewState.camera == good)
        #expect(document.viewState.homeCamera == nil)
        let reopened = try DocumentModel(data: try document.fileData(), registry: testRegistry, kernel: FakeKernel())
        #expect(reopened.viewState.camera == good)
    }
}

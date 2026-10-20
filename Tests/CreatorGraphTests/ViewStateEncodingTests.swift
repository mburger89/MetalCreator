import CreatorGeometry
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// `DocumentModel` holds the view state as separate observable pieces (so a pan does not invalidate a reader of the dock) and
/// assembles `ViewState` for the file. The file's encoding must not move: an old file decodes, opens, and saves the same bytes.
@MainActor
struct ViewStateEncodingTests {
    /// The view state as an earlier build wrote it (sorted keys, compact), keys all present but the cameras.
    static let oldViewState = #"{"canvasOffset":{"x":-30,"y":12.5},"canvasZoom":1.5,"dock":"bottom","showsLibrary":false}"#

    private func compactEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    @Test func anOldViewStateDecodesAndReEncodesTheSameBytes() throws {
        let data = Data(Self.oldViewState.utf8)
        let state = try JSONDecoder().decode(ViewState.self, from: data)
        #expect(state == ViewState(dock: .bottom, canvasOffset: Vector2(-30, 12.5), canvasZoom: 1.5, showsLibrary: false))
        #expect(try compactEncoder().encode(state) == data, "the coding keys and shape are unchanged")
    }

    @Test func aDocumentOpenedOnAnOldFileSavesTheFilesOwnBytes() throws {
        let state = try JSONDecoder().decode(ViewState.self, from: Data(Self.oldViewState.utf8))
        let camera = CameraPose(target: Vector3(1, 2, 3), distance: 80, yaw: 0.5, pitch: 0.25, projection: .orthographic)
        var full = state
        full.camera = camera
        full.homeCamera = CameraPose()
        for viewState in [state, full] {
            let file = GraphFile(graph: graph([makeNode(ConstantNode.self)]), viewState: viewState)
            let written = try GraphFileIO.encode(file)
            let document = DocumentModel(file: try GraphFileIO.decode(written, registry: testRegistry), registry: testRegistry,
                                         kernel: FakeKernel())
            #expect(document.viewState == viewState)
            #expect(try document.fileData() == written, "the pieces are assembled into the same bytes the file was read from")
        }
    }

    @Test func aPieceWrittenInTheDocumentReachesTheFileAsTheSameKey() throws {
        let document = DocumentModel(file: GraphFile(), registry: testRegistry, kernel: FakeKernel())
        document.canvasOffset = Vector2(4, 5)
        document.canvasZoom = 2
        document.dock = .hidden
        document.showsLibrary = false
        let expected = ViewState(dock: .hidden, canvasOffset: Vector2(4, 5), canvasZoom: 2, showsLibrary: false)
        #expect(document.viewState == expected)
        let reopened = try GraphFileIO.decode(document.fileData(), registry: testRegistry)
        #expect(reopened.viewState == expected)
        #expect(try GraphFileIO.encode(reopened) == document.fileData())
    }
}

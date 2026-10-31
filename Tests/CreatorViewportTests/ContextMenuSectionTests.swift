import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// Section from Face (section spec §3.2) is offered on a part, never on a ghost.
extension ContextMenuTests {
    @Test func noSectionFromFaceOnAGhost() async throws {
        let model = await model(showing: [try await fakeBox()])
        let top = ViewportFaceRef(solidIndex: 0, face: FaceID(1))
        model.pick = { _ in .face(solid: 0, FaceID(1)) }
        #expect(model.contextMenuItems(at: ScreenPoint(300, 200)).contains(.sectionFromFace(top)))
        var received = 0
        model.events.sectionFromFace = { _, _ in received += 1 }
        model.choose(.sectionFromFace(top))
        #expect(received == 1)

        model.show([ViewportItem(solid: model.items[0].solid, isGhost: true)])
        await model.waitForMeshes()
        let ghosted = model.contextMenuItems(at: ScreenPoint(300, 200))
        #expect(!ghosted.isEmpty && !ghosted.contains(.sectionFromFace(top)))
        model.choose(.sectionFromFace(top))
        #expect(received == 1)
    }
}

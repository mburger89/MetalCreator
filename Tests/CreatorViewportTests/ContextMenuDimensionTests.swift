import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// The face menu's Dimension (dimensions spec §3.5), with `ContextMenuTests`' fixtures.
extension ContextMenuTests {
    @Test func aFaceOrEdgeOffersDimension() async throws {
        let model = await model(showing: [try await fakeBox()])
        let edge = try #require(model.items[0].solid.topology.edges.first)
        model.pick = { _ in .edge(solid: 0, edge.id) }
        let items = model.contextMenuItems(at: ScreenPoint(300, 200))
        #expect(items.contains(.dimension(.edge(solid: 0, edge.id))))
        #expect(items.first { $0 == .dimension(.edge(solid: 0, edge.id)) }?.title == "Dimension")
        var received: [PickTarget] = []
        model.events.dimension = { received.append($0) }
        model.choose(.dimension(.edge(solid: 0, edge.id)))
        #expect(received == [.edge(solid: 0, edge.id)])
        model.pick = { _ in .face(solid: 0, FaceID(1)) }
        #expect(model.contextMenuItems(at: ScreenPoint(301, 200)).contains(.dimension(.face(solid: 0, FaceID(1)))))
    }

    @Test func aToolHidesDimension() async throws {
        let model = await model(showing: [try await fakeBox()])
        model.tool = RecordingTool()
        model.pick = { _ in .face(solid: 0, FaceID(1)) }
        #expect(!model.contextMenuItems(at: ScreenPoint(300, 200)).contains { item in
            if case .dimension = item { true } else { false }
        })
    }
}

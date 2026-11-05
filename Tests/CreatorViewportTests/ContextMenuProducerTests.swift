import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

/// "Show Producing Node" lists each node the panel can show once (ui-polish finding 4).
@MainActor
struct ContextMenuProducerTests {
    let size = ViewportSize(width: 400, height: 300)

    func model(showing solids: [Solid]) async -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: CameraPose(target: .zero, distance: 100, yaw: 0.6, pitch: 0.4),
                                  clock: ManualClock())
        model.viewSize = size
        model.show(solids.map { ViewportItem(solid: $0) })
        await model.waitForMeshes()
        return model
    }

    private func mergedFace(_ nodes: [NodeID]) async -> ViewportModel {
        let merged = FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero,
                              tags: Set(nodes.enumerated().map { TopoTag(node: $1, item: 0, role: $0 == 0 ? .endCap : .startCap) }))
        let solid = Solid(topology: Topology(faces: [merged], edges: []),
                          bounds: BoundingBox(min: .zero, max: Vector3(1, 1, 1)), storage: TestStorage())
        let model = await model(showing: [solid])
        model.pick = { _ in .face(solid: 0, FaceID(0)) }
        return model
    }

    @Test func tagsThatStandForOneNodeMakeOneEntry() async throws {
        // Two inner nodes of one group: the panel shows the group node for both.
        let inner = [NodeID(), NodeID()], group = NodeID()
        let model = await mergedFace(inner)
        model.events.producer = { _ in group }
        model.events.nodeName = { $0 == group ? "Rib" : nil }
        let items = model.contextMenuItems(at: ScreenPoint(300, 200)).filter { $0.title.hasPrefix("Show Producing Node") }
        #expect(items.map(\.title) == ["Show Producing Node"])
        #expect(items == [.showProducingNode(group, title: "Show Producing Node")])
    }

    @Test func twoDifferentNodesWithOneNameAreToldApart() async throws {
        let nodes = [NodeID(), NodeID()]
        let model = await mergedFace(nodes)
        model.events.nodeName = { _ in "Extrude" }
        let titles = model.contextMenuItems(at: ScreenPoint(300, 200)).map(\.title).filter { $0.hasPrefix("Show Producing Node") }
        #expect(titles == ["Show Producing Node (Extrude 1 of 2)", "Show Producing Node (Extrude 2 of 2)"])
    }
}

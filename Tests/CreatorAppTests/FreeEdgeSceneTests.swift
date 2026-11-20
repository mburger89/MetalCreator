import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// NS-5 R14: the free edges of a node that asks for them (`NodeDefinition.showsFreeEdges`) are the item's warning edges, also
/// through an Output wired straight from it.
private final class StubStorage: SolidStorage { var estimatedBytes: Int { 0 } }

private enum FreeEdgeStubNode: NodeDefinition {
    static let typeID = "test.freeedges"
    static let displayName = "Free Edges"
    static let category = NodeCategory.solid
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("solid", .solid)]
    static let showsFreeEdges = true
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs([:])
    }
}

private enum PlainStubNode: NodeDefinition {
    static let typeID = "test.plainedges"
    static let displayName = "Plain"
    static let category = NodeCategory.solid
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("solid", .solid)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs([:])
    }
}

@MainActor
struct FreeEdgeSceneTests {
    /// Two faces, edges 0, 1 and 2 on one face each (boundary), edge 3 shared.
    static func sheet() -> Solid {
        func face(_ id: Int) -> FaceInfo {
            FaceInfo(id: FaceID(id), kind: .plane, normal: Vector3(0, 0, 1), area: 1, centroid: .zero, tags: [], isOnOpenShell: true)
        }
        func edge(_ id: Int, _ faces: [Int]) -> EdgeInfo {
            EdgeInfo(id: EdgeID(id), kind: .line, direction: nil, length: 1, midpoint: .zero, convexity: .unknown,
                     faces: faces.map(FaceID.init))
        }
        let topology = Topology(faces: [face(0), face(1)], edges: [edge(0, [0]), edge(1, [0]), edge(2, [1]), edge(3, [0, 1])])
        return Solid(topology: topology, bounds: BoundingBox(min: .zero, max: Vector3(1, 1, 1)), storage: StubStorage())
    }

    let registry = NodeRegistry([FreeEdgeStubNode.self, PlainStubNode.self, OutputNode.self])

    @Test func aFreeEdgeNodesBoundaryIsWarned() {
        let stub = registry.makeNode(FreeEdgeStubNode.typeID)
        let output = registry.makeNode(OutputNode.typeID)
        let link = Link(from: Endpoint(node: stub.id, socket: "solid"), to: Endpoint(node: output.id, socket: "solid"))
        let graph = Graph(nodes: [stub.id: stub, output.id: output], links: [link])
        let outputs: [SocketName: Value] = ["solid": .one(.solid(Self.sheet()))]
        let own = SceneBuilder.items(of: stub, outputs: outputs, isGhost: false, graph: graph, registry: registry)
        #expect(own.first?.item.warningEdges == [EdgeID(0), EdgeID(1), EdgeID(2)])
        let through = SceneBuilder.items(of: output, outputs: outputs, isGhost: false, graph: graph, registry: registry)
        #expect(through.first?.item.warningEdges == [EdgeID(0), EdgeID(1), EdgeID(2)])
    }

    @Test func aNodeWithoutTheFlagWarnsNothing() {
        let plain = registry.makeNode(PlainStubNode.typeID)
        let output = registry.makeNode(OutputNode.typeID)
        let link = Link(from: Endpoint(node: plain.id, socket: "solid"), to: Endpoint(node: output.id, socket: "solid"))
        let graph = Graph(nodes: [plain.id: plain, output.id: output], links: [link])
        let outputs: [SocketName: Value] = ["solid": .one(.solid(Self.sheet()))]
        #expect(SceneBuilder.items(of: plain, outputs: outputs, isGhost: false, graph: graph, registry: registry)
            .first?.item.warningEdges.isEmpty == true)
        #expect(SceneBuilder.items(of: output, outputs: outputs, isGhost: false, graph: graph, registry: registry)
            .first?.item.warningEdges.isEmpty == true)
    }

    @Test func warnedEdgesChangeTheItem() {
        let solid = Self.sheet()
        let plain = ViewportItem(solid: solid)
        let warned = ViewportItem(solid: solid, warningEdges: [EdgeID(0)])
        #expect(!plain.drawsTheSame(as: warned))
        #expect(warned.drawsTheSame(as: ViewportItem(solid: solid, warningEdges: [EdgeID(0)])))
    }
}

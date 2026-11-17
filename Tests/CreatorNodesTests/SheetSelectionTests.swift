#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorOCCT
import Testing
@testable import CreatorNodes

/// NS-1 Task 3: the selection rules see a sheet's boundary edges (ruling R-A: the Planar Surface node itself comes in Task 6).
struct SheetSelectionTests {
    func sheet() async throws -> Solid {
        let kernel = OCCTKernel()
        let tag = NodeTag(node: NodeID(), item: 0)
        let corners = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 20, 0), Vector3(0, 20, 0)]
        let curve = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: tag)
        let hole = try await kernel.makeCurve(
            [.arc(center: Vector3(5, 10, 0), normal: .unitZ, radius: 2, start: Vector3(7, 10, 0), sweep: 2 * .pi)], tag: tag)
        return try await kernel.planarSurface([curve, hole], tag: tag)
    }

    func run(_ definition: any NodeDefinition.Type, _ solid: Solid, extra: [SocketName: NodeInputs.Slot] = [:]) async throws -> EdgeSet {
        var slots: [SocketName: NodeInputs.Slot] = ["solid": .item(.solid(solid))]
        slots.merge(extra) { _, new in new }
        let context = EvalContext(node: BuiltInNodes.registry.makeNode(definition.typeID), item: 0, parameters: [:])
        let outputs = try await definition.evaluate(NodeInputs(item: 0, slots: slots), kernel: FakeKernel(), context: context)
        guard case .edgeSet(let set)? = outputs.values["edges"] else { throw KernelError.invalidInput("no edges") }
        return set
    }

    @Test func allEdgesIncludesTheBoundaryEdges() async throws {
        let solid = try await sheet()
        let edges = try await run(AllEdgesNode.self, solid)
        #expect(edges.edges.count == 5)
        #expect(Set(edges.edges) == Set(solid.topology.edges.map(\.id)))
    }

    @Test func edgesByDirectionFindsTheSheetsStraightEdges() async throws {
        let solid = try await sheet()
        let edges = try await run(EdgesByDirectionNode.self, solid,
                                  extra: ["direction": .item(.vector(.unitX)), "tolerance": .item(.number(1))])
        #expect(edges.edges.count == 2)
    }
}
#endif

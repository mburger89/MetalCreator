import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import Testing
#if canImport(CreatorOCCT)
import CreatorOCCT

/// NS-4 Task 5: a Trim Surface keep pick is renamed by Group and read through each instance's naming (R2, R17).
@MainActor
struct TrimSurfaceGroupTests {
    let registry = BuiltInNodes.registry
    let kernel = OCCTKernel()

    func rig() -> (Harness, Node, [Node]) {
        var h = Harness()
        let number = h.add(NumberNode.self, ["value": .number(10)])
        let rect = h.add(RectangleNode.self, ["width": .number(20), "height": .number(20)])
        let sheet = h.add(PlanarSurfaceNode.self)
        let circle = h.add(CircleNode.self)
        let trim = h.add(TrimSurfaceNode.self)
        let output = h.add(OutputNode.self, output: true)
        h.wire(number, "value", to: circle, "diameter")
        h.wire(rect, "profile", to: sheet, "curves")
        h.wire(sheet, "surface", to: trim, "surface")
        h.wire(circle, "profile", to: trim, "curves")
        h.wire(trim, "surface", to: output, "solid")
        return (h, trim, [rect, sheet, circle])
    }

    @Test func aPickSurvivesGroupingAndTwoInstances() async throws {
        let (h, trim, members) = rig()
        let document = DocumentModel(file: GraphFile(graph: h.graph), registry: registry, kernel: kernel)
        await document.waitForEvaluation()
        let whole = try #require(document.results[trim.id]?.outputs?["pieces"]?.solids?.first,
                                 "\(String(describing: document.results[trim.id]?.state))")
        let faces = whole.topology.faces
        let disk = try #require(faces.firstIndex { face in
            face.tags.contains { if case .cutSide(_, .inside) = $0.role { true } else { false } }
        })
        let region = try #require(TrimRegions.pick(forPiece: disk, pieces: faces.map { [$0.id] }, in: whole.topology))
        try document.perform(.setInput(trim.id, NodeSetting.keepRegions, .regionPicks([region])))
        await document.waitForEvaluation()

        let grouped = try GroupCommands.group(Set(members.map(\.id) + [trim.id]), in: .root, of: document.content, registry: registry)
        try document.perform(grouped.command)
        let group = try #require(grouped.selection.first)
        let groupNode = try #require(document.content.graph.nodes[group])
        let definitionID = try #require(groupNode.inputValues[NodeSetting.group]?.groupID)
        let definition = try #require(document.content.definitions[definitionID])
        let inner = try #require(definition.graph.nodes.values.first { $0.typeID == TrimSurfaceNode.typeID })
        let sockets = registry.withGroups(document.content.definitions)
        let diameter = try #require(sockets.inputs(for: groupNode).first { $0.name == "diameter" }).name

        // A second instance of the same definition with its own diameter.
        var second = sockets.makeGroupNode(GroupNodes.groupTypeID, for: definitionID)
        second.inputValues[diameter] = .number(12)
        try document.perform(.addNode(second))
        await document.waitForEvaluation()

        let report = try await Evaluator(registry: registry, kernel: kernel).evaluate(
            document.content.graph, definitions: document.content.definitions, demand: Set(document.content.graph.nodes.keys))
        func keptArea(_ instance: NodeID) async throws -> (Double, NodeState?) {
            let result = try #require(report.innerResults[[instance, inner.id]])
            let surface = try #require(result.outputs?["surface"]?.solids?.first, "\(String(describing: result.state))")
            return (try await kernel.properties(of: surface).surfaceArea, result.state)
        }
        let (first, firstState) = try await keptArea(group)
        let (other, otherState) = try await keptArea(second.id)
        #expect(isClose(first, 25 * .pi, relative: 1e-6))
        #expect(isClose(other, 36 * .pi, relative: 1e-6))
        for state in [firstState, otherState] {
            if case .ok? = state { continue }
            Issue.record("expected no warning, got \(String(describing: state))")
        }
    }
}
#endif

import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorOCCT

extension BracketAcceptanceTests {
    /// The bracket with its chamfer's top-cap outline picked, as the viewport would.
    func pickedBracket(_ kernel: OCCTKernel) async throws -> (Bracket, Graph) {
        let bracket = Self.makeBracket()
        let document = DocumentModel(file: GraphFile(graph: bracket.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        let filleted = try #require(document.results[bracket.fillet.id]?.outputs?["solid"]?.solids?.first)
        try document.perform(.setInput(bracket.chamferEdges.id, NodeSetting.picks,
                                       .edgePicks(filleted.topology.picks(for: topCapOutline(filleted, plate: bracket.plate)))))
        return (bracket, document.graph)
    }

    /// Groups spec §9: the §7.2 bracket's rib, its L-flange (plane, Rectangle and Extrude), grouped with ⌘G's command
    /// evaluates to the same part: the union and the fillet have the same volume, faces and edges, the fillet's rule
    /// still finds its four edges, the picked chamfer its seven, and nothing warns.
    @Test func theBracketWithItsFlangeGroupedIsTheSamePart() async throws {
        let kernel = OCCTKernel()
        let (bracket, picked) = try await pickedBracket(kernel)
        let plain = DocumentModel(file: GraphFile(graph: picked), registry: BuiltInNodes.registry, kernel: kernel)
        let grouped = DocumentModel(file: GraphFile(graph: picked), registry: BuiltInNodes.registry, kernel: kernel)
        let edit = try GroupCommands.group([bracket.flangePlane.id, bracket.flangeProfile.id, bracket.flange.id], in: .root,
                                           of: grouped.content, registry: grouped.registry)
        try grouped.perform(edit.command)
        let definition = try #require(grouped.definitions.values.first)
        #expect(definition.inputs.map(\.name) == ["width"])
        #expect(definition.outputs == [SocketSpec("solid", .solid)])
        await plain.waitForEvaluation()
        await grouped.waitForEvaluation()

        let node = try #require(edit.selection.first)
        #expect(grouped.results[node]?.state.isSuccess == true)
        for id in [bracket.union.id, bracket.fillet.id] {
            let expected = try #require(plain.results[id]?.outputs?["solid"]?.solids?.first)
            let actual = try #require(grouped.results[id]?.outputs?["solid"]?.solids?.first)
            #expect(isClose(try await volume(actual, kernel), try await volume(expected, kernel)))
            #expect(actual.topology.faces.count == expected.topology.faces.count)
            #expect(actual.topology.edges.count == expected.topology.edges.count)
            #expect(isClose(actual.bounds.size, expected.bounds.size, tolerance: 1e-6))
        }
        #expect(try edgeSet(grouped, bracket.filletEdges).edges.count == 4)
        #expect(try edgeSet(grouped, bracket.chamferEdges).edges.count == 7)
        expectAllOK(plain, "plain")
        expectAllOK(grouped, "flange grouped")
    }

    /// Grouping the picked plate itself: its faces are made under a scoped ID inside the group, and Group renames the
    /// chamfer's picks to it, so the chamfer still finds its seven edges and nothing warns.
    @Test func groupingThePickedPlateKeepsTheChamfer() async throws {
        let kernel = OCCTKernel()
        let (bracket, picked) = try await pickedBracket(kernel)
        let document = DocumentModel(file: GraphFile(graph: picked), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        let chamferKeys = keys(try edgeSet(document, bracket.chamferEdges)).count
        let edit = try GroupCommands.group([bracket.plate.id, bracket.cut.id], in: .root, of: document.content,
                                           registry: document.registry)
        try document.perform(edit.command)
        await document.waitForEvaluation()
        let node = try #require(edit.selection.first)
        #expect(document.graph.nodes[bracket.chamferEdges.id] != picked.nodes[bracket.chamferEdges.id], "the picks were renamed")
        #expect(try edgeSet(document, bracket.chamferEdges).edges.count == 7)
        #expect(keys(try edgeSet(document, bracket.chamferEdges)).count == chamferKeys)
        #expect(keys(try edgeSet(document, bracket.chamferEdges)).allSatisfy { key in
            key.first.union(key.second).contains { $0.node == NodeID.scoped([node, bracket.plate.id]) }
        })
        expectAllOK(document, "plate grouped")
    }
}

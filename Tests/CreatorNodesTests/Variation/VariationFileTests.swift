import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing

/// The variation nodes' two text settings are saved with the graph (format 6, which does not change: User decision U17) and a
/// reopened graph evaluates exactly as it did.
struct VariationFileTests {
    func roundTrip(_ file: GraphFile) throws -> GraphFile {
        try GraphFileIO.decode(try GraphFileIO.encode(file), registry: BuiltInNodes.registry)
    }

    @Test func cullPatternAndCullIndexSettingsSurviveSaveAndReload() async throws {
        var h = Harness()
        let source = h.source(count: 8, rows: 4)
        let pattern = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 1 0"), "scope": .integer(1)])
        let index = h.add(CullIndexNode.self, [NodeSetting.cullIndices: .text("1, {0;3}")])
        h.wire(source, to: pattern, "tree")
        h.wire(pattern, "tree", to: index, "tree")
        let before = try await h.run([index])

        let reopened = try roundTrip(GraphFile(graph: h.graph))
        #expect(reopened.formatVersion == GraphFile.currentFormatVersion && GraphFile.currentFormatVersion == 10)
        #expect(reopened.graph.nodes[pattern.id]?.inputValues[NodeSetting.cullPattern] == .text("1 1 0"))
        #expect(reopened.graph.nodes[pattern.id]?.inputValues["scope"] == .integer(1))
        #expect(reopened.graph.nodes[index.id]?.inputValues[NodeSetting.cullIndices] == .text("1, {0;3}"))

        let after = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
            .evaluate(reopened.graph, demand: [index.id])
        #expect(after.value(index, "tree")?.outline == before.value(index, "tree")?.outline)
        #expect(after.positions(index) == before.positions(index) && before.positions(index) != nil)
    }

    @Test func aFormatFiveFileStillOpensWithTheVariationNodesAvailable() throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["count": .integer(4)])
        let older = try roundTrip(GraphFile(formatVersion: 5, graph: h.graph))
        #expect(older.formatVersion == 5, "a file keeps the version it was written with until it is saved")
        #expect(older.graph.nodes[series.id]?.inputValues["count"] == .integer(4))
    }
}

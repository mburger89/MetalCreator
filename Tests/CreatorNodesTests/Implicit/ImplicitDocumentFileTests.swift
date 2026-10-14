import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation
import Testing
@testable import CreatorNodes

/// A document of Implicit nodes saved and reopened (implicit spec §5.4): their settings are the existing integer and number
/// settings, and the solids themselves are recomputed, never saved.
///
/// Lane A of 7c-core has no Mesh node and no Output `mesh` socket yet (Tasks 13 and 14, after the join), so this file holds the
/// parts of the brief that do not need them; the join adds the Mesh node to `graph` and the Output's empty `mesh` socket check.
struct ImplicitDocumentFileTests {
    func graph(_ h: inout Harness) -> (sphere: Node, shell: Node) {
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(7)])
        let shell = h.add(ImplicitShellNode.self, ["thickness": .number(1.5), "side": .integer(2)], output: true)
        h.wire(sphere, "implicit", to: shell, "implicit")
        return (sphere, shell)
    }

    @Test func theSettingsSurviveASaveAndReopen() async throws {
        var h = Harness()
        let nodes = graph(&h)
        let data = try GraphFileIO.encode(GraphFile(graph: h.graph))
        let file = try GraphFileIO.decode(data, registry: BuiltInNodes.registry)
        #expect(file.formatVersion == 8 && file.graph.nodes == h.graph.nodes)
        #expect(Set(file.graph.links) == Set(h.graph.links), "the links are kept in an order of their own")
        #expect(file.graph.nodes[nodes.shell.id]?.inputValues["side"] == .integer(2))
        #expect(file.graph.nodes[nodes.sphere.id]?.inputValues["radius"] == .number(7))
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
            .evaluate(file.graph, demand: [nodes.shell.id])
        let solid = try #require(report.implicitSolid(nodes.shell))
        #expect(solid.distance(0, 0, 0) > 0, "the shell is hollow at the centre")
    }

    @Test func noSolidIsWrittenToTheFile() throws {
        var h = Harness()
        _ = graph(&h)
        let text = try #require(String(bytes: try GraphFileIO.encode(GraphFile(graph: h.graph)), encoding: .utf8))
        #expect(!text.contains("positions") && !text.contains("triangles") && !text.contains("halfSize"))
        #expect(text.contains("creator.implicitSphere") && text.contains("creator.implicitShell"))
    }

    @Test func aFormatSevenFileWithoutImplicitNodesOpensAndEvaluatesAsBefore() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let output = h.add(OutputNode.self, output: true)
        h.wire(box, "solid", to: output, "solid")
        let seven = GraphFile(formatVersion: 7, graph: h.graph)
        let file = try GraphFileIO.decode(try GraphFileIO.encode(seven), registry: BuiltInNodes.registry)
        #expect(file.formatVersion == 7)
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
            .evaluate(file.graph, demand: [output.id])
        #expect(report.value(output, "solid")?.solids?.count == 1)
    }
}

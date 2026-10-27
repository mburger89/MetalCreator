import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation
import Testing
@testable import CreatorNodes

/// A document of Implicit and Mesh nodes saved and reopened (implicit spec §5.4): their settings are the existing integer and number
/// settings, and the solids and meshes themselves are recomputed, never saved.
struct ImplicitDocumentFileTests {
    func graph(_ h: inout Harness) -> (sphere: Node, shell: Node, mesh: Node, output: Node) {
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(7)])
        let shell = h.add(ImplicitShellNode.self, ["thickness": .number(1.5), "side": .integer(2)])
        let mesh = h.add(MeshNode.self, ["export resolution": .number(0.25), "preview resolution": .number(2)])
        let output = h.add(OutputNode.self, output: true)
        h.wire(sphere, "implicit", to: shell, "implicit")
        h.wire(shell, "implicit", to: mesh, "implicit")
        h.wire(mesh, "mesh", to: output, "mesh")
        return (sphere, shell, mesh, output)
    }

    @Test func theSettingsSurviveASaveAndReopen() async throws {
        var h = Harness()
        let nodes = graph(&h)
        let data = try GraphFileIO.encode(GraphFile(graph: h.graph))
        let file = try GraphFileIO.decode(data, registry: BuiltInNodes.registry)
        #expect(file.formatVersion == 9 && file.graph.nodes == h.graph.nodes)
        #expect(Set(file.graph.links) == Set(h.graph.links), "the links are kept in an order of their own")
        #expect(file.graph.nodes[nodes.shell.id]?.inputValues["side"] == .integer(2))
        #expect(file.graph.nodes[nodes.mesh.id]?.inputValues["export resolution"] == .number(0.25))
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
            .evaluate(file.graph, demand: [nodes.output.id])
        let mesh = try #require(report.value(nodes.output, "mesh")?.triangleMeshes?.first)
        #expect(mesh.resolution == 2 && MeshTopology(mesh).isClosedManifold)
    }

    @Test func noSolidOrMeshIsWrittenToTheFile() throws {
        var h = Harness()
        _ = graph(&h)
        let text = try #require(String(bytes: try GraphFileIO.encode(GraphFile(graph: h.graph)), encoding: .utf8))
        #expect(!text.contains("positions") && !text.contains("triangles") && !text.contains("halfSize"))
        #expect(text.contains("creator.implicitSphere") && text.contains("creator.mesh"))
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
        #expect(report.value(output, "mesh")?.items.isEmpty == true, "the Output's new socket is simply empty")
    }
}

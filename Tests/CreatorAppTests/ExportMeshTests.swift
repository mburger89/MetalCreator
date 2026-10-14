import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// Exporting meshes (implicit spec §5.3): STL written from an export-quality evaluation, STEP refusing them, a summary of warnings, and
/// Cancel.
@MainActor
struct ExportMeshTests {
    /// Sphere → Mesh (export resolution 0.5) → Output named `name`.
    func sphereGraph(radius: Double = 3, export: Double = 0.5, name: String = "Insole") -> (graph: Graph, mesh: Node, output: Node) {
        var builder = GraphBuilder()
        let sphere = builder.add(ImplicitSphereNode.self, ["radius": .number(radius)])
        let mesh = builder.add(MeshNode.self, ["export resolution": .number(export)])
        var output = builder.add(OutputNode.self)
        builder.wire(sphere, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: output, "mesh")
        output.name = name
        builder.replace(output)
        return (builder.graph, mesh, output)
    }

    /// A place to export to that is cleaned up when the test is done.
    final class Target {
        let url: URL

        init(_ name: String = "out.stl") {
            url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(name)")
        }

        deinit {
            try? FileManager.default.removeItem(at: url)
        }

        var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
    }

    /// How many triangles the document's own (preview) mesh of `node` has.
    func previewTriangles(_ app: AppModel, _ node: Node) -> Int? {
        guard case .mesh(let payload)? = app.document.results[node.id]?.outputs?["mesh"]?.items.first else { return nil }
        return payload.triangleCount
    }

    func stl(_ url: URL) throws -> STLFile {
        try #require(STLFile(try Data(contentsOf: url)))
    }

    @Test func aMeshOutputIsWrittenAsStlAtExportResolution() async throws {
        let fixture = sphereGraph()
        let app = await makeApp(fixture.graph)
        let target = Target()
        let picker = ScriptedPicker([target.url])
        await app.exportDocument(.stl, using: picker)
        #expect(app.alert == nil && app.exportRun == nil)
        #expect(picker.asked.count == 1 && picker.asked[0].name == "Insole.stl")
        let file = try stl(target.url)
        // The file is the export mesh, not the preview one: a 3 mm sphere at 0.5 mm has about 2,000 triangles, a preview far more.
        #expect(file.triangles.count > 200 && file.triangles.count != previewTriangles(app, fixture.mesh))
        let exact = 4.0 / 3 * Double.pi * 27
        #expect(abs(file.volume - exact) / exact < 0.02, "volume \(file.volume) against \(exact)")
    }

    @Test func theDocumentsOwnResultsAreStillThePreview() async throws {
        let fixture = sphereGraph()
        let app = await makeApp(fixture.graph)
        let target = Target()
        try await app.export(.stl, to: target.url)
        guard case .mesh(let payload)? = app.document.results[fixture.mesh.id]?.outputs?["mesh"]?.items.first else {
            Issue.record("no mesh")
            return
        }
        #expect((payload as? TriangleMesh)?.quality == .preview)
    }

    @Test func stepRefusesAMeshInTheSpecsWords() async throws {
        let fixture = sphereGraph()
        let app = await makeApp(fixture.graph)
        let picker = ScriptedPicker([Target("out.step").url])
        await app.exportDocument(.step, using: picker)
        #expect(app.alert == .problem(AppProblem(
            "The part can't be exported as STEP",
            "Output 'Insole' is a mesh; STEP needs solids. Export STL or 3MF, or convert it with Mesh to Solid.")))
        #expect(picker.asked.isEmpty, "refused before asking where to save")
    }

    @Test func anImplicitWiredStraightIntoAnOutputIsMeshedAtTheDefaultSettings() async throws {
        var builder = GraphBuilder()
        let sphere = builder.add(ImplicitSphereNode.self, ["radius": .number(1)])
        let output = builder.add(OutputNode.self)
        builder.wire(sphere, "implicit", to: output, "mesh")
        let app = await makeApp(builder.graph)
        let target = Target()
        try await app.export(.stl, to: target.url)
        // 1 mm sphere at 0.1 mm: a few hundred triangles.
        #expect(try stl(target.url).triangles.count > 200)
    }

    @Test func aSolidAndAMeshShareOneStl() async throws {
        let fixture = sphereGraph()
        var builder = GraphBuilder()
        builder.graph = fixture.graph
        let box = builder.solid()
        builder.wire(box.extrude, "solid", to: fixture.output, "solid")
        let app = await makeApp(builder.graph)
        let target = Target(), alone = Target()
        try await app.export(.stl, to: target.url)
        let meshOnly = await makeApp(fixture.graph)
        try await meshOnly.export(.stl, to: alone.url)
        let (both, justMesh) = (try stl(target.url).triangles.count, try stl(alone.url).triangles.count)
        #expect(both == justMesh + 12, "FakeKernel tessellates a box as 12 triangles")
    }

    @Test func warningsAreSummarisedAfterTheFile() async throws {
        var builder = GraphBuilder()
        let spheres = builder.add(ImplicitSphereNode.self, ["radius": .number(2)])
        let gradient = builder.add(LinearGradientNode.self, ["length": .number(10)])
        let union = builder.add(ImplicitUnionNode.self)
        let output = builder.add(OutputNode.self)
        builder.wire(spheres, "implicit", to: union, "shapes")
        builder.wire(gradient, "field", to: union, "blend radius")
        builder.wire(union, "implicit", to: output, "mesh")
        let app = await makeApp(builder.graph)
        let target = Target()
        try await app.export(.stl, to: target.url)
        #expect(app.alert == .problem(AppProblem("Exported with 1 warning",
                                                 "Union: “blend radius” is below 0 in places; it is held at 0 there.")))
    }

    @Test func solidsOnlyExportsSummariseTheirWarningsToo() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        _ = box
        #expect(Self.warnings(in: app).isEmpty)
        #expect(AppModel.warnings(in: [:], graph: Graph(), outputs: []).isEmpty)
    }

    static func warnings(in app: AppModel) -> [String] {
        AppModel.warnings(in: app.document.results, graph: app.document.graph, outputs: app.outputNodes)
    }

    @Test func aWarningOnlyCountsWhenItIsUpstreamOfAnOutput() {
        var graph = Graph()
        let upstream = BuiltInNodes.registry.makeNode(ImplicitSphereNode.typeID)
        let aside = BuiltInNodes.registry.makeNode(ImplicitBoxNode.typeID)
        let output = BuiltInNodes.registry.makeNode(OutputNode.typeID)
        for node in [upstream, aside, output] { graph.nodes[node.id] = node }
        graph.links.append(Link(from: Endpoint(node: upstream.id, socket: "implicit"), to: Endpoint(node: output.id, socket: "mesh")))
        let results: [NodeID: NodeResult] = [
            upstream.id: NodeResult(state: .warning("one\ntwo")), aside.id: NodeResult(state: .warning("elsewhere")),
            output.id: NodeResult(state: .ok(duration: .zero)),
        ]
        #expect(AppModel.warnings(in: results, graph: graph, outputs: [output.id]) == ["Sphere: one", "Sphere: two"])
    }

    @Test func theSummaryCountsInTheSingularAndThePlural() {
        let app = AppModel(kernel: FakeKernel())
        app.summarize([])
        #expect(app.alert == nil)
        app.summarize(["A: x", "B: y"])
        #expect(app.alert == .problem(AppProblem("Exported with 2 warnings", "A: x\nB: y")))
    }

    @Test func aMeshTooBigForMemoryIsRefusedWithTheNodeThatSaysSo() async throws {
        let fixture = sphereGraph(radius: 1000, export: 0.01)
        let app = await makeApp(fixture.graph)
        let target = Target()
        await app.exportDocument(.stl, using: ScriptedPicker([target.url]))
        guard case .problem(let problem)? = app.alert else { Issue.record("no alert"); return }
        #expect(problem.title == "“Mesh” can't be exported")
        #expect(problem.message.hasPrefix("This needs about ") && problem.message.hasSuffix(" mm or split the part."))
        #expect(!target.exists && app.exportRun == nil)
    }

    @Test func cancelStopsTheExportAndLeavesNoFile() async throws {
        // A 10 mm sphere at 0.05 mm takes long enough to cancel.
        let fixture = sphereGraph(radius: 10, export: 0.05)
        let app = await makeApp(fixture.graph)
        let target = Target()
        let url = target.url
        let task = Task { try await app.export(.stl, to: url) }
        var attempts = 0
        while app.exportRun == nil, attempts < 2000 {
            try await Task.sleep(for: .milliseconds(5))
            attempts += 1
        }
        let run = try #require(app.exportRun)
        #expect(run.title == "Exporting “Insole”" && !run.isCancelling)
        run.cancel()
        #expect(run.isCancelling)
        try await task.value
        #expect(app.exportRun == nil && app.alert == nil)
        #expect(!target.exists)
    }
}

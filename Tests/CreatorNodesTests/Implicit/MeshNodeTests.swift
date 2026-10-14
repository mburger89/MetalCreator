import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation
import Synchronization
import Testing
@testable import CreatorNodes

/// Mesh (implicit spec §3.6, §4.3) and Output taking meshes (implicit spec §2.3).
struct MeshNodeTests {
    func meshOfASphere(_ h: inout Harness, radius: Double = 6, _ settings: [SocketName: ConstantValue] = [:]) -> Node {
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(radius)])
        let mesh = h.add(MeshNode.self, settings)
        h.wire(sphere, "implicit", to: mesh, "implicit")
        return mesh
    }

    @Test func aPreviewIsTheFirstCoarsePassAndRemembersWhatToRefine() async throws {
        var h = Harness()
        let mesh = meshOfASphere(&h)
        let report = try await h.run([mesh])
        let made = try #require(report.triangleMesh(mesh))
        // 128 cells across the largest dimension: a 12 mm sphere is meshed every 12 / 128 mm.
        #expect(abs(made.resolution - 12.0 / 128) < 1e-12 && made.quality == .preview)
        let topology = MeshTopology(made)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2)
        let source = try #require(made.source)
        #expect(source.target == .automatic && source.solid.description == "sphere(radius 6 mm)")
        #expect(report.isOK(mesh))
    }

    @Test func aPreviewResolutionCoarserThanTheFirstPassIsTheOnlyPass() async throws {
        var h = Harness()
        let mesh = meshOfASphere(&h, ["preview resolution": .number(1)])
        let made = try #require(try await h.run([mesh]).triangleMesh(mesh))
        #expect(made.resolution == 1 && made.source?.target == .fixed(1))
    }

    @Test func anExportMeshesAtTheExportResolution() async throws {
        var h = Harness()
        let mesh = meshOfASphere(&h, ["export resolution": .number(0.5)])
        let report = try await h.runForExport([mesh])
        let made = try #require(report.triangleMesh(mesh))
        #expect(made.resolution == 0.5 && made.quality == .export && made.source == nil)
        #expect(MeshTopology(made).isClosedManifold)
        let exact = 4.0 / 3 * Double.pi * 216
        #expect(abs(made.signedVolume - exact) / exact < 0.01)
    }

    @Test func aPreviewAndAnExportAreNotTheSameResult() async throws {
        var h = Harness()
        let mesh = meshOfASphere(&h, ["export resolution": .number(0.5)])
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
        let preview = try await evaluator.evaluate(h.graph, demand: [mesh.id])
        let export = try await evaluator.evaluate(h.graph, demand: [mesh.id], meshQuality: .export)
        #expect(preview.evaluatedNodes.contains(mesh.id) && export.evaluatedNodes.contains(mesh.id))
        #expect(preview.triangleMesh(mesh)?.quality == .preview && export.triangleMesh(mesh)?.quality == .export)
        let again = try await evaluator.evaluate(h.graph, demand: [mesh.id])
        #expect(!again.evaluatedNodes.contains(mesh.id), "the preview is still cached")
    }

    @Test func progressIsReported() async throws {
        var h = Harness()
        let mesh = meshOfASphere(&h, ["export resolution": .number(0.5)])
        let seen = Mutex<[Double]>([])
        let progress = MeshProgress { value in seen.withLock { $0.append(value) } }
        _ = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
            .evaluate(h.graph, demand: [mesh.id], meshQuality: .export, progress: progress)
        let values = seen.withLock { $0 }
        #expect(values.first == 0 && values.last == 1 && values == values.sorted())
    }

    @Test func theInspectorFactsAreTheCountTheResolutionTheTimeAndTheMemory() async throws {
        var h = Harness()
        let mesh = meshOfASphere(&h, ["export resolution": .number(0.5)])
        let made = try #require(try await h.runForExport([mesh]).triangleMesh(mesh))
        let facts = made.inspectorFacts
        #expect(facts.map(\.label) == ["Triangles", "Resolution", "Meshing time", "Memory"])
        #expect(facts[0].value == made.triangleCount.formatted(.number.locale(.messages)) && facts[1].value == "0.5 mm")
        #expect(facts[2].value.hasSuffix(" s"))
        let preview = try #require(try await h.run([mesh]).triangleMesh(mesh))
        #expect(preview.inspectorFacts[1].value == "Preview 0.094 mm")
    }

    @Test func settingsAreChecked() async throws {
        var h = Harness()
        let coarse = meshOfASphere(&h, ["export resolution": .number(0.005)])
        let negative = meshOfASphere(&h, ["preview resolution": .number(-1)])
        let report = try await h.run([coarse, negative])
        #expect(report.error(coarse) == "“export resolution” must be at least 0.01 mm.")
        #expect(report.error(negative) == "“preview resolution” must be 0 (Auto) or more.")
    }

    @Test func nonFiniteResolutionsAreRefused() async throws {
        var h = Harness()
        let nanPreview = meshOfASphere(&h, ["preview resolution": .number(.nan)])
        let infinitePreview = meshOfASphere(&h, ["preview resolution": .number(.infinity)])
        let nanExport = meshOfASphere(&h, ["export resolution": .number(.nan)])
        let report = try await h.run([nanPreview, infinitePreview, nanExport])
        #expect(report.error(nanPreview) == "“preview resolution” must be 0 (Auto) or more.")
        #expect(report.error(infinitePreview) == "“preview resolution” must be 0 (Auto) or more.")
        #expect(report.error(nanExport) == "“export resolution” must be at least 0.01 mm.")
    }

    @Test func aPartFarFromTheOriginWarnsAboutSinglePrecision() async throws {
        var h = Harness()
        let far = meshOfASphere(&h, radius: 12_000, ["preview resolution": .number(5_000)])
        let near = meshOfASphere(&h, radius: 12)
        let report = try await h.run([far, near])
        #expect(report.warning(far) == "This part reaches 12,000 mm from the origin; beyond 10,000 mm the GPU's single-precision "
            + "coordinates blur its surface.")
        #expect(report.isOK(near))
    }

    @Test func aShapeTooSmallToMeshIsRefusedWithAMessage() async throws {
        var h = Harness()
        let mesh = meshOfASphere(&h, radius: 0.0001, ["preview resolution": .number(5)])
        #expect(try await h.run([mesh]).error(mesh) == ImplicitMeshingError.empty.userMessage)
    }

    @Test func anExportTooBigForMemoryIsRefusedWithTheSpecsMessage() async throws {
        // Physical memory is whatever this Mac has, so ask for an absurd resolution of a big part.
        var h = Harness()
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(1000)])
        let mesh = h.add(MeshNode.self, ["export resolution": .number(0.01)])
        h.wire(sphere, "implicit", to: mesh, "implicit")
        let message = try #require(try await h.runForExport([mesh]).error(mesh))
        #expect(message.hasPrefix("This needs about ") && message.contains(" GB at 0.01 mm; coarsen to "))
        #expect(message.hasSuffix(" mm or split the part."))
    }

    // MARK: Output

    @Test func anOutputTakesMeshesAndKeepsTheSolidsApart() async throws {
        var h = Harness()
        let mesh = meshOfASphere(&h)
        let box = h.box(10, 10, 10)
        let output = h.add(OutputNode.self, output: true)
        h.wire(mesh, "mesh", to: output, "mesh")
        h.wire(box, "solid", to: output, "solid")
        let report = try await h.run([output])
        #expect(report.value(output, "solid")?.solids?.count == 1)
        #expect(report.value(output, "mesh")?.triangleMeshes?.count == 1)
        #expect(report.isOK(output))
    }

    @Test func anImplicitWiredIntoAnOutputsMeshSocketIsMeshedAtTheDefaultSettings() async throws {
        var h = Harness()
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(1)])
        let output = h.add(OutputNode.self, output: true)
        h.wire(sphere, "implicit", to: output, "mesh")
        let preview = try #require(try await h.run([output]).value(output, "mesh")?.triangleMeshes?.first)
        #expect(preview.quality == .preview && preview.resolution == PreviewSchedule.finest, "2 / 128 mm is finer than a preview goes")
        let export = try #require(try await h.runForExport([output]).value(output, "mesh")?.triangleMeshes?.first)
        #expect(export.quality == .export && export.resolution == MeshNode.defaultExportResolution)
        #expect(MeshTopology(export).isClosedManifold)
    }

    @Test func aListOfImplicitsMakesAListOfMeshes() async throws {
        var h = Harness()
        let radii = h.add(SeriesNode.self, ["start": .number(2), "step": .number(2), "count": .integer(2)])
        let spheres = h.add(ImplicitSphereNode.self)
        let output = h.add(OutputNode.self, output: true)
        h.wire(radii, "values", to: spheres, "radius")
        h.wire(spheres, "implicit", to: output, "mesh")
        let meshes = try #require(try await h.run([output]).value(output, "mesh")?.triangleMeshes)
        #expect(meshes.count == 2 && meshes[1].signedVolume > meshes[0].signedVolume)
    }

    @Test func aSolidCannotBeWiredIntoAMeshSocket() {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let output = h.add(OutputNode.self, output: true)
        let problem = h.graph.connectionProblem(from: Endpoint(node: box.id, socket: "solid"),
                                                to: Endpoint(node: output.id, socket: "mesh"), registry: BuiltInNodes.registry)
        #expect(problem == .typeMismatch(from: .solid, to: .mesh))
    }

    @Test func anImplicitCanBeWiredIntoAMeshSocketAndAMeshIntoNothingElse() {
        var h = Harness()
        let sphere = h.add(ImplicitSphereNode.self)
        let mesh = h.add(MeshNode.self)
        let output = h.add(OutputNode.self, output: true)
        let graph = h.graph
        let registry = BuiltInNodes.registry
        #expect(graph.connectionProblem(from: Endpoint(node: sphere.id, socket: "implicit"),
                                        to: Endpoint(node: output.id, socket: "mesh"), registry: registry) == nil)
        #expect(graph.connectionProblem(from: Endpoint(node: mesh.id, socket: "mesh"),
                                        to: Endpoint(node: output.id, socket: "solid"), registry: registry)
            == .typeMismatch(from: .mesh, to: .solid))
        #expect(graph.connectionProblem(from: Endpoint(node: mesh.id, socket: "mesh"),
                                        to: Endpoint(node: sphere.id, socket: "radius"), registry: registry)
            == .typeMismatch(from: .mesh, to: .number))
    }
}

import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif

/// The mesh nodes while an export streams (implicit spec Errata D12): the Mesh node hands over a stream, Decimate adds a stage, the
/// checks look at a copy and let the stream through, Mesh to Solid meshes the stream into memory.
struct StreamedMeshNodeTests {
    /// A hollow ball (a shell of 0.3 mm), through Mesh at 0.1 mm, `tools` after it.
    func hollowBall(_ h: inout Harness) -> (shell: Node, mesh: Node) {
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(2)])
        let shell = h.add(ImplicitShellNode.self, ["thickness": .number(0.3)])
        let mesh = h.add(MeshNode.self, ["export resolution": .number(0.1)])
        h.wire(sphere, "implicit", to: shell, "implicit")
        h.wire(shell, "implicit", to: mesh, "implicit")
        return (shell, mesh)
    }

    @Test func theMeshNodeHandsOverAStreamAtTheExportResolution() async throws {
        var h = Harness()
        let (shell, mesh) = hollowBall(&h)
        let report = try await h.runStreamed([mesh])
        let stream = try #require(report.meshStream(mesh))
        #expect(stream.resolution == 0.1 && stream.stages.isEmpty && stream.solid == report.implicitSolid(shell))
        #expect(report.isOK(mesh))
    }

    @Test func aPreviewAndAnInMemoryExportAreNotStreams() async throws {
        var h = Harness()
        let (_, mesh) = hollowBall(&h)
        #expect(try await h.run([mesh]).triangleMesh(mesh) != nil)
        #expect(try await h.runForExport([mesh]).triangleMesh(mesh)?.quality == .export)
    }

    @Test func outputPassesAStreamAndMakesOneOfAnImplicitWiredStraightIn() async throws {
        var h = Harness()
        let (_, mesh) = hollowBall(&h)
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(1)])
        let passed = h.add(OutputNode.self)
        let made = h.add(OutputNode.self)
        h.wire(mesh, "mesh", to: passed, "mesh")
        h.wire(sphere, "implicit", to: made, "mesh")
        let report = try await h.runStreamed([passed, made])
        #expect(report.meshStream(passed)?.resolution == 0.1)
        #expect(report.meshStream(made)?.resolution == MeshNode.defaultExportResolution, "meshed at the defaults, as a stream")
    }

    @Test func decimateAddsAStageAndTwoAddTwo() async throws {
        var h = Harness()
        let (_, mesh) = hollowBall(&h)
        let first = h.add(DecimateNode.self, ["tolerance": .number(0.02)])
        let second = h.add(DecimateNode.self, ["tolerance": .number(0.05)])
        h.wire(mesh, "mesh", to: first, "mesh")
        h.wire(first, "mesh", to: second, "mesh")
        let report = try await h.runStreamed([second])
        #expect(try #require(report.meshStream(second)).stages == [.decimate(tolerance: 0.02), .decimate(tolerance: 0.05)])
        #expect(try #require(report.meshStream(first)).stages == [.decimate(tolerance: 0.02)], "each node keeps its own")
    }

    @Test func aCheckWarnsAboutThePartAndLetsTheStreamThrough() async throws {
        var h = Harness()
        let (_, mesh) = hollowBall(&h)
        let check = h.add(CheckThinWallsNode.self)
        h.wire(mesh, "mesh", to: check, "mesh")
        let report = try await h.runStreamed([check])
        let message = try #require(report.warning(check))
        #expect(message.hasPrefix("Walls thinner than 0.4 mm in 1 place (thinnest 0.3"), "\(message)")
        #expect(!message.contains("approximate"), "the copy is at the export resolution")
        #expect(try #require(report.meshStream(check)) == MeshStream(solid: try #require(report.meshStream(mesh)).solid, resolution: 0.1))
    }

    @Test func theTrappedVolumeCheckAlsoLooksAtACopy() async throws {
        var h = Harness()
        let radii = h.add(SeriesNode.self, ["start": .number(3), "step": .number(-1.5), "count": .integer(2)])
        let spheres = h.add(ImplicitSphereNode.self)
        let subtract = h.add(ImplicitSubtractNode.self)
        let mesh = h.add(MeshNode.self, ["export resolution": .number(0.2)])
        let check = h.add(CheckTrappedVolumesNode.self)
        h.wire(radii, "values", to: spheres, "radius")
        h.wire(spheres, "implicit", to: subtract, "shapes")
        h.wire(subtract, "implicit", to: mesh, "implicit")
        h.wire(mesh, "mesh", to: check, "mesh")
        let report = try await h.runStreamed([check])
        #expect(report.warning(check) == "1 enclosed void can't drain.")
        #expect(report.meshStream(check) != nil)
    }

    @Test func aStreamTooBigToPlanIsRefusedByTheMeshNode() async throws {
        var h = Harness()
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(1_000)])
        let mesh = h.add(MeshNode.self, ["export resolution": .number(0.01)])
        h.wire(sphere, "implicit", to: mesh, "implicit")
        let message = try #require(try await h.runStreamed([mesh]).error(mesh))
        #expect(message.hasPrefix("This needs about ") && message.hasSuffix(" mm or split the part."), "\(message)")
    }

    @Test func aBigPartThatStreamsIsNotRefusedForMemory() async throws {
        // 40 mm at 0.02 mm would be some 160 million triangles in memory; as a stream it only has to be planned.
        var h = Harness()
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(20)])
        let mesh = h.add(MeshNode.self, ["export resolution": .number(0.1)])
        h.wire(sphere, "implicit", to: mesh, "implicit")
        #expect(try await h.runStreamed([mesh]).meshStream(mesh) != nil)
    }

    @Test func meshToSolidSaysWhatTheKernelCannotDoAndWhatTheLimitIs() async throws {
        var h = Harness()
        let (_, mesh) = hollowBall(&h)
        let solid = h.add(MeshToSolidNode.self)
        h.wire(mesh, "mesh", to: solid, "mesh")
        let report = try await h.runStreamed([solid])
        #expect(report.error(solid) == "Mesh to solid isn't supported by this kernel yet.", "the stream was meshed, the kernel refused")
    }

    #if canImport(CreatorOCCT)
    @Test func meshToSolidTakesAStreamWithItsDecimationApplied() async throws {
        var h = Harness()
        let box = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(8, 6, 4))])
        let mesh = h.add(MeshNode.self, ["export resolution": .number(0.25)])
        let decimate = h.add(DecimateNode.self, ["tolerance": .number(0.02)])
        let solid = h.add(MeshToSolidNode.self)
        h.wire(box, "implicit", to: mesh, "implicit")
        h.wire(mesh, "mesh", to: decimate, "mesh")
        h.wire(decimate, "mesh", to: solid, "mesh")
        let kernel = OCCTKernel()
        let report = try await h.runStreamed([solid], kernel: kernel)
        #expect(report.isOK(solid), "\(String(describing: report.state(solid)))")
        let made = try onlySolid(report, solid)
        let found = try await volume(made, kernel)
        #expect(abs(found - 192) / 192 < 0.02, "\(found) against 192")
        #expect(made.topology.faces.count < 200, "decimated, so few facets")
    }
    #endif
}

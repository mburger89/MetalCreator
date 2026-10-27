import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation
import Testing
@testable import CreatorNodes

/// The lattices meshed and saved (implicit spec §7): every lattice makes a watertight manifold mesh with the volume it should have, the
/// same graph makes the same mesh twice, and a document of lattice nodes saved and reopened still works. Meshes are made on the CPU.
struct LatticeMeshTests {
    struct Lattices {
        var tpms: Node
        var struts: Node
        var voronoi: Node
        /// The Mesh node and the Output of each lattice, in the order TPMS, Strut Lattice, Voronoi Lattice.
        var meshes: [Node]
        var outputs: [Node]
    }

    /// A 20 mm cube filled by each lattice in turn, each into a Mesh at `resolution` and an Output.
    func graph(_ h: inout Harness, skin: Double = 0, resolution: Double = 1) -> Lattices {
        let cube = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(20, 20, 20))])
        let tpms = h.add(TPMSNode.self, ["cell size": .number(10), "thickness": .number(0.8), "skin": .number(skin)])
        let struts = h.add(StrutLatticeNode.self, [
            "cell": .integer(StrutCell.bcc.rawValue), "cell size": .number(10), "strut radius": .number(1.2), "skin": .number(skin),
        ])
        let voronoi = h.add(VoronoiLatticeNode.self, [
            "count": .integer(30), "form": .integer(VoronoiForm.foam.rawValue), "thickness": .number(1), "skin": .number(skin),
        ])
        var meshes: [Node] = [], outputs: [Node] = []
        for lattice in [tpms, struts, voronoi] {
            h.wire(cube, "implicit", to: lattice, "region")
            let mesh = h.add(MeshNode.self, ["export resolution": .number(resolution)])
            let output = h.add(OutputNode.self, output: true)
            h.wire(lattice, "implicit", to: mesh, "implicit")
            h.wire(mesh, "mesh", to: output, "mesh")
            meshes.append(mesh)
            outputs.append(output)
        }
        return Lattices(tpms: tpms, struts: struts, voronoi: voronoi, meshes: meshes, outputs: outputs)
    }

    func mesh(_ report: EvaluationReport, _ output: Node) throws -> TriangleMesh {
        try #require(report.value(output, "mesh")?.triangleMeshes?.first, "no mesh: \(String(describing: report.state(output)))")
    }

    @Test func everyLatticeMakesAWatertightManifoldMesh() async throws {
        var h = Harness()
        let lattices = graph(&h)
        let report = try await h.runForExport(lattices.outputs)
        for output in lattices.outputs {
            let made = try mesh(report, output)
            #expect(MeshTopology(made).isClosedManifold && made.signedVolume > 0, "\(output.name)")
        }
    }

    @Test func aSkinKeepsTheMeshWatertightAndAddsTheWallsVolume() async throws {
        var h = Harness()
        let plain = graph(&h)
        var skinned = Harness()
        let withSkin = graph(&skinned, skin: 2)
        let (a, b) = (try await h.runForExport(plain.outputs), try await skinned.runForExport(withSkin.outputs))
        for (first, second) in zip(plain.outputs, withSkin.outputs) {
            let (without, with) = (try mesh(a, first), try mesh(b, second))
            #expect(MeshTopology(with).isClosedManifold)
            // A 2 mm skin on a 20 mm cube is 20³ − 16³ = 3,904 mm³ of wall (two voxels thick: a wall of one voxel falls between the
            // samples); the lattice that was there before is part of it now.
            #expect(with.signedVolume > without.signedVolume + 1_000, "skin: \(with.signedVolume) against \(without.signedVolume)")
        }
    }

    /// Spec §7: "a gyroid sheet's volume fraction against its known value". A gyroid's surface is 3.0915 a² per cell; this cube holds
    /// 2 × 2 × 2 cells of 10 mm, so a 0.8 mm wall holds 8 × 3.0915 × 100 × 0.8 = 1,978 mm³.
    @Test func aGyroidSheetHoldsTheVolumeOfItsSurfaceTimesItsWall() async throws {
        var h = Harness()
        let lattices = graph(&h, resolution: 0.5)
        let report = try await h.runForExport([lattices.outputs[0]])
        let volume = try mesh(report, lattices.outputs[0]).signedVolume
        let expected = 8 * 3.0915 * 100 * 0.8
        #expect(abs(volume / expected - 1) < 0.04, "volume \(volume) against \(expected)")
    }

    @Test func theSameGraphMakesTheSameMeshTwice() async throws {
        var h = Harness()
        let lattices = graph(&h)
        let first = try await h.runForExport(lattices.outputs), second = try await h.runForExport(lattices.outputs)
        for output in lattices.outputs {
            let (a, b) = (try mesh(first, output), try mesh(second, output))
            #expect(a.positions == b.positions && a.triangles == b.triangles)
        }
    }

    @Test func aRoundRegionGivesARoundLattice() async throws {
        var h = Harness()
        let ball = h.add(ImplicitSphereNode.self, ["radius": .number(9)])
        let tpms = h.add(TPMSNode.self, ["type": .integer(1), "cell size": .number(6), "thickness": .number(0.8)])
        let mesh = h.add(MeshNode.self, ["export resolution": .number(0.6)])
        let output = h.add(OutputNode.self, output: true)
        h.wire(ball, "implicit", to: tpms, "region")
        h.wire(tpms, "implicit", to: mesh, "implicit")
        h.wire(mesh, "mesh", to: output, "mesh")
        let made = try self.mesh(try await h.runForExport([output]), output)
        #expect(MeshTopology(made).isClosedManifold)
        let farthest = made.positions.map { Vector3(Double($0.x), Double($0.y), Double($0.z)).length }.max() ?? 0
        #expect(farthest <= 9 + 0.6, "nothing past the ball (and a voxel): \(farthest)")
    }

    // MARK: Files

    @Test func theSettingsSurviveASaveAndReopen() async throws {
        var h = Harness()
        let lattices = graph(&h)
        let file = try GraphFileIO.decode(try GraphFileIO.encode(GraphFile(graph: h.graph)), registry: BuiltInNodes.registry)
        #expect(file.formatVersion == 9 && file.graph.nodes == h.graph.nodes)
        #expect(file.graph.nodes[lattices.struts.id]?.inputValues["cell"] == .integer(StrutCell.bcc.rawValue))
        #expect(file.graph.nodes[lattices.voronoi.id]?.inputValues["form"] == .integer(VoronoiForm.foam.rawValue))
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
        let reopened = try await evaluator.evaluate(file.graph, demand: Set(lattices.outputs.map(\.id)), meshQuality: .export)
        let original = try await h.runForExport(lattices.outputs)
        for output in lattices.outputs {
            let (a, b) = (try mesh(original, output), try mesh(reopened, output))
            #expect(a.positions == b.positions && a.triangles == b.triangles)
        }
    }

    @Test func noLatticeOrSeedIsWrittenToTheFile() throws {
        var h = Harness()
        _ = graph(&h)
        let text = try #require(String(bytes: try GraphFileIO.encode(GraphFile(graph: h.graph)), encoding: .utf8))
        #expect(text.contains("creator.tpms") && text.contains("creator.strutLattice") && text.contains("creator.voronoiLattice"))
        #expect(!text.contains("positions") && !text.contains("triangles") && !text.contains("starts") && !text.contains("entries"))
    }
}

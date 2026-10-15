import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

/// Inputs the spec implies and a person will meet (plan "Review Focus"): a skin thicker than the region, a cell larger than the region,
/// a region far from the origin, walls under a voxel, a lattice with nothing in the region, and awkward seeds.
struct LatticeEdgeCaseTests {
    /// A box of `side` millimetres wired to `lattice`'s region.
    func region(_ h: inout Harness, _ lattice: Node, side: Double = 20) -> Node {
        let box = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(side, side, side))])
        h.wire(box, "implicit", to: lattice, "region")
        return box
    }

    static let noSurface = "There is no surface to mesh: the shape is empty, or smaller than a voxel."

    /// `lattice` meshed at `resolution` on the CPU for an export; `nil` when the Mesh node refused (see `noSurface`).
    func mesh(_ h: inout Harness, _ lattice: Node, resolution: Double = 1) async throws -> TriangleMesh? {
        let mesh = h.add(MeshNode.self, ["export resolution": .number(resolution)])
        let output = h.add(OutputNode.self, output: true)
        h.wire(lattice, "implicit", to: mesh, "implicit")
        h.wire(mesh, "mesh", to: output, "mesh")
        let report = try await h.runForExport([output])
        return report.value(output, "mesh")?.triangleMeshes?.first
    }

    // MARK: Skin

    @Test func aSkinThickerThanHalfTheRegionLeavesOnlyTheSkin() async throws {
        var h = Harness()
        let tpms = h.add(TPMSNode.self, ["skin": .number(15)])
        _ = region(&h, tpms, side: 20)
        let report = try await h.run([tpms])
        let solid = try #require(report.implicitSolid(tpms))
        #expect(report.isOK(tpms))
        // The inward wall of 15 mm on a 20 mm box reaches past the middle: everything inside the box is wall.
        #expect(solid.distance(0, 0, 0) < 0 && solid.distance(9, 9, 9) < 0 && solid.distance(11, 0, 0) > 0)
        let made = try #require(try await mesh(&h, tpms, resolution: 1))
        #expect(MeshTopology(made).isClosedManifold)
        #expect(abs(made.signedVolume - 8_000) < 8_000 * 0.05, "a solid cube: \(made.signedVolume)")
    }

    // MARK: Cell and region

    @Test(arguments: [100.0, 1_000.0])
    func aCellLargerThanTheRegionStillMeshesWatertight(_ cell: Double) async throws {
        var h = Harness()
        let tpms = h.add(TPMSNode.self, ["cell size": .number(cell), "thickness": .number(3)])
        _ = region(&h, tpms)
        let made = try #require(try await mesh(&h, tpms, resolution: 1))
        #expect(MeshTopology(made).isClosedManifold && made.signedVolume > 0)
    }

    @Test func aRegionFarFromTheOriginKeepsItsLatticeAndRaisesAGradedCellsConstant() async throws {
        func solid(offset: Double) async throws -> ImplicitSolid? {
            var h = Harness()
            let box = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(20, 20, 20))])
            let placed = h.add(PlaceNode.self)
            let plane = h.add(PlaneNode.self, ["offset": .number(offset)])
            h.wire(box, "implicit", to: placed, "implicit")
            h.wire(plane, "plane", to: placed, "placements")
            let tpms = h.add(TPMSNode.self)
            h.wire(placed, "implicits", to: tpms, "region")
            let gradient = h.add(LinearGradientNode.self, ["length": .number(200)])
            let size = h.add(FieldAddNode.self, ["b": .number(8)])
            h.wire(gradient, "field", to: size, "a")
            h.wire(size, "field", to: tpms, "cell size")
            return try await h.run([tpms]).implicitSolid(tpms)
        }
        let near = try #require(try await solid(offset: 0)), far = try #require(try await solid(offset: 5_000))
        #expect(far.signedDistance(at: far.bounds.center).isFinite)
        #expect(far.bounds.center.length > 4_999, "the lattice is where the region is")
        // The size field is 8 + z / 200 mm, so the cell is 33 mm at z = 5,000 and the pattern moves 5,000 / 33 times its slope: 1.76 times
        // the constant of a cell that is still 8 mm at z = 0.
        #expect(far.lipschitz > near.lipschitz * 1.4, "the farther the region, the more the size field moves it")
    }

    // MARK: Thin and empty

    @Test func wallsAndStrutsUnderAVoxelStillMeshWatertightAndWarnFirst() async throws {
        var h = Harness()
        // A 20 mm region previews at 20 / 128 = 0.156 mm.
        let tpms = h.add(TPMSNode.self, ["thickness": .number(0.1)])
        let struts = h.add(StrutLatticeNode.self, ["strut radius": .number(0.04)])
        _ = region(&h, tpms)
        _ = region(&h, struts)
        for node in [tpms, struts] {
            let warning = try #require(try await h.run([node]).warning(node))
            #expect(warning.contains("are thinner than the preview resolution; the preview may show gaps."), "\(warning)")
            let result = try #require(try await mesh(&h, node, resolution: 1))
            #expect(MeshTopology(result).isClosedManifold)
        }
    }

    @Test func strutsThickerThanTheCellsWarnAndFillTheRegion() async throws {
        var h = Harness()
        // The radius range allows 5 mm and the cell size 1 mm: a radius of 2 mm in 2 mm cells is past 0.85 of a cell everywhere.
        let struts = h.add(StrutLatticeNode.self, ["cell size": .number(2), "strut radius": .number(2)])
        _ = region(&h, struts)
        let report = try await h.run([struts])
        #expect(report.warning(struts)?.contains("Struts are thicker than the cells; the lattice is solid.") == true)
        let solid = try #require(report.implicitSolid(struts))
        #expect(solid.distance(1, 1, 1) < 0 && solid.distance(0, 0, 0) < 0 && solid.distance(11, 0, 0) > 0)
        let made = try #require(try await mesh(&h, struts, resolution: 1))
        #expect(MeshTopology(made).isClosedManifold)
        #expect(abs(made.signedVolume - 8_000) < 8_000 * 0.05, "a solid cube: \(made.signedVolume)")
    }

    @Test func aLatticeWithNothingInTheRegionIsTheMeshNodesErrorNotACrash() async throws {
        var h = Harness()
        let struts = h.add(StrutLatticeNode.self, ["cell size": .number(50), "strut radius": .number(0)])
        let box = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(4, 4, 4))])
        h.wire(box, "implicit", to: struts, "region")
        let solid = try #require(try await h.run([struts]).implicitSolid(struts))
        #expect(solid.distance(1, 1, 1) > 0, "a 4 mm box far from every 50 mm strut")
        let mesh = h.add(MeshNode.self, ["export resolution": .number(0.5)])
        h.wire(struts, "implicit", to: mesh, "implicit")
        #expect(try await h.runForExport([mesh]).error(mesh) == Self.noSurface)
    }

    // MARK: Seeds

    @Test func planarSeedsStillMeshWatertight() async throws {
        var h = Harness()
        let voronoi = h.add(VoronoiLatticeNode.self, ["form": .integer(VoronoiForm.foam.rawValue), "thickness": .number(1.5)])
        _ = region(&h, voronoi)
        let grid = h.add(GridPointsNode.self, [
            "countX": .integer(3), "countY": .integer(3), "spacingX": .number(6), "spacingY": .number(6),
        ])
        h.wire(grid, "points", to: voronoi, "seeds")
        let flat = try #require(try await mesh(&h, voronoi, resolution: 1))
        #expect(MeshTopology(flat).isClosedManifold)
    }

    @Test func aSingleSeedHasNoEdgesAndNoWallsSoThereIsNothingToMesh() async throws {
        for form in [VoronoiForm.struts, .foam] {
            var h = Harness()
            let one = h.add(VoronoiLatticeNode.self, ["form": .integer(form.rawValue), "thickness": .number(1.5)])
            _ = region(&h, one)
            let seed = h.add(VectorNode.self)
            h.wire(seed, "vector", to: one, "seeds")
            let mesh = h.add(MeshNode.self, ["export resolution": .number(1)])
            h.wire(one, "implicit", to: mesh, "implicit")
            let report = try await h.runForExport([mesh])
            #expect(report.error(mesh) == Self.noSurface, "\(form.name): \(String(describing: report.state(mesh)))")
        }
    }

    @Test func seedsFarOutsideTheRegionAreHarmless() async throws {
        var h = Harness()
        let voronoi = h.add(VoronoiLatticeNode.self)
        _ = region(&h, voronoi)
        let far = h.add(VectorNode.self, ["x": .number(5_000), "y": .number(0), "z": .number(0)])
        h.wire(far, "vector", to: voronoi, "seeds")
        let report = try await h.run([voronoi])
        let solid = try #require(report.implicitSolid(voronoi))
        #expect(solid.distance(0, 0, 0).isFinite)
        #expect(report.warning(voronoi)?.contains("The seeds leave gaps in the region; the lattice is solid there.") == true)
    }
}

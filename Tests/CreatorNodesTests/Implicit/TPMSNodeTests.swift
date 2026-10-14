import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

/// The TPMS node (implicit spec §3.4): the lattice cut to a region, the skin, the settings and the warnings.
struct TPMSNodeTests {
    /// A 40 mm cube wired to a TPMS node's region.
    func cube(_ h: inout Harness, _ values: [SocketName: ConstantValue] = [:]) -> (cube: Node, tpms: Node) {
        let cube = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(40, 40, 40))])
        let tpms = h.add(TPMSNode.self, values)
        h.wire(cube, "implicit", to: tpms, "region")
        return (cube, tpms)
    }

    @Test func withoutARegionItSaysWhatToConnect() async throws {
        var h = Harness()
        let tpms = h.add(TPMSNode.self)
        #expect(try await h.run([tpms]).error(tpms) == "Connect a region to fill.")
    }

    @Test func theLatticeIsCutToTheRegionAndTheRegionsEdgeIsTheShapesEdge() async throws {
        var h = Harness()
        let (_, tpms) = cube(&h)
        let report = try await h.run([tpms])
        let solid = try #require(report.implicitSolid(tpms))
        #expect(solid.description == "intersect(box(40 × 40 × 40 mm), gyroid(cell 8 mm, sheet, t = 1 mm))")
        #expect(solid.bounds == BoundingBox(min: Vector3(-20, -20, -20), max: Vector3(20, 20, 20)))
        // A point on the gyroid's surface (g = 0 at the origin) is inside the wall; a point past the cube is outside.
        #expect(abs(solid.distance(0, 0, 0) + 0.5) < 1e-12)
        #expect(solid.distance(25, 0, 0) >= 5 - 1e-12)
        #expect(report.isOK(tpms))
    }

    @Test func theTypeFormAndCellAreTheSettings() async throws {
        var h = Harness()
        let (_, tpms) = cube(&h, ["type": .integer(3), "form": .integer(1), "cell size": .number(5), "thickness": .number(0.4)])
        let solid = try #require(try await h.run([tpms]).implicitSolid(tpms))
        #expect(solid.description == "intersect(box(40 × 40 × 40 mm), neovius(cell 5 mm, network, t = 0.4 mm))")
    }

    @Test func aStretchShapesTheCellsWithoutChangingTheirSize() async throws {
        var h = Harness()
        let (_, tpms) = cube(&h, ["cell stretch": .vector(Vector3(1, 1, 8))])
        let solid = try #require(try await h.run([tpms]).implicitSolid(tpms))
        #expect(solid.description.contains("stretch 0.5 : 0.5 : 4"))
        h.set(tpms, "cell stretch", .vector(Vector3(1, 0, 1)))
        #expect(try await h.run([tpms]).error(tpms) == "“cell stretch” must be greater than 0 on every axis.")
    }

    @Test func aSkinKeepsTheRegionsWallAndFillsTheInside() async throws {
        var h = Harness()
        let (_, tpms) = cube(&h, ["skin": .number(1.5), "thickness": .number(0.5)])
        let solid = try #require(try await h.run([tpms]).implicitSolid(tpms))
        #expect(solid.description.hasPrefix("union(shell(box(40 × 40 × 40 mm), inward 1.5 mm), intersect(gyroid("))
        // 0.8 mm inside a face is in the skin; 3 mm inside, where the gyroid has a gap, is not solid.
        #expect(solid.distance(19.2, 3, 3) < 0)
        #expect(solid.distance(17, 0.7, 0.9) > 0, "inside, away from the skin and the lattice")
        let withoutSkin = try #require(try await h.run([tpms]).implicitSolid(tpms))
        #expect(withoutSkin.signedDistance(at: Vector3(19.2, 3, 3)) == solid.signedDistance(at: Vector3(19.2, 3, 3)))
        h.set(tpms, "skin", .number(-1))
        #expect(try await h.run([tpms]).error(tpms) == "“skin” must be 0 or more.")
    }

    @Test func aFieldGradesTheCellSizeAndTheThickness() async throws {
        var h = Harness()
        let (_, tpms) = cube(&h)
        let gradient = h.add(LinearGradientNode.self, ["length": .number(40)])
        let ramp = h.add(FieldAddNode.self)
        h.wire(gradient, "field", to: ramp, "a")
        h.wire(ramp, "field", to: tpms, "cell size")
        h.set(ramp, "b", .number(8))
        let wall = h.add(NoiseFieldNode.self, ["scale": .number(10)])
        h.wire(wall, "field", to: tpms, "thickness")
        let report = try await h.run([tpms])
        let solid = try #require(report.implicitSolid(tpms))
        let plain = try #require(try await { () async throws -> ImplicitSolid? in
            var other = Harness()
            let pair = cube(&other)
            return try await other.run([pair.tpms]).implicitSolid(pair.tpms)
        }())
        #expect(solid.lipschitz > plain.lipschitz, "the pattern moves with the size field")
        #expect(solid.description.contains("t = noise("), "the thickness is the field's recipe: \(solid.description)")
        guard case .intersect(let parts, _) = solid, case .tpms(let lattice) = parts[1] else { Issue.record("not an intersection"); return }
        #expect(lattice.cells.size.constantValue == nil && lattice.thickness.constantValue == nil)
        #expect(report.warning(tpms) == nil || report.warning(tpms)?.contains("“thickness” is below 0") == false)
    }

    @Test func aCellSizeThatReachesZeroIsRefused() async throws {
        var h = Harness()
        let (_, tpms) = cube(&h, ["cell size": .number(0)])
        #expect(try await h.run([tpms]).error(tpms) == "“cell size” must stay above 0 mm; it reaches 0 mm.")
        h.set(tpms, "cell size", .number(-2))
        #expect(try await h.run([tpms]).error(tpms) == "“cell size” must stay above 0 mm; it reaches -2 mm.")
    }

    @Test func aThicknessBelowZeroIsHeldAtZeroWithAWarning() async throws {
        var h = Harness()
        let (_, tpms) = cube(&h)
        let gradient = h.add(LinearGradientNode.self, ["length": .number(20)])
        h.wire(gradient, "field", to: tpms, "thickness")
        let report = try await h.run([tpms])
        #expect(report.warning(tpms)?.contains("“thickness” is below 0 in places; it is held at 0 there.") == true)
    }

    @Test func anUnknownTypeOrFormIsRefused() async throws {
        var h = Harness()
        let (_, tpms) = cube(&h, ["type": .integer(9)])
        #expect(try await h.run([tpms]).error(tpms) == "Choose Gyroid, Schwarz P, Diamond, Neovius, or Lidinoid for “type”.")
        h.set(tpms, "type", .integer(0))
        h.set(tpms, "form", .integer(2))
        #expect(try await h.run([tpms]).error(tpms) == "Choose Sheet or Network for “form”.")
    }

    @Test func cellsAndWallsUnderTheResolutionWarn() async throws {
        var h = Harness()
        // A 40 mm cube previews at 40 / 128 = 0.3125 mm: cells under 0.625 mm and walls under 0.3125 mm are too small.
        let (_, tpms) = cube(&h, ["cell size": .number(0.5), "thickness": .number(0.1)])
        let warning = try #require(try await h.run([tpms]).warning(tpms))
        #expect(warning.contains("Cells are smaller than the preview resolution; the preview may look solid."))
        #expect(warning.contains("Walls are thinner than the preview resolution; the preview may show gaps."))
        h.set(tpms, "form", .integer(1))
        let network = try #require(try await h.run([tpms]).warning(tpms))
        #expect(network.contains("Cells are smaller") && !network.contains("Walls are thinner"), "a network has no wall to be thin")
        h.set(tpms, "cell size", .number(8))
        h.set(tpms, "form", .integer(0))
        let thin = try #require(try await h.run([tpms]).warning(tpms))
        #expect(!thin.contains("Cells are smaller") && thin.contains("Walls are thinner"))
        h.set(tpms, "thickness", .number(1))
        #expect(try await h.run([tpms]).isOK(tpms))
    }

    @Test func anExportJudgesTheResolutionByTheMeshNodesDefault() async throws {
        var h = Harness()
        let (_, tpms) = cube(&h, ["cell size": .number(0.15), "thickness": .number(0.05)])
        let report = try await h.runForExport([tpms])
        let warning = try #require(report.warning(tpms))
        #expect(warning.contains("Cells are smaller than the export resolution; the mesh may look solid."))
        #expect(warning.contains("Walls are thinner than the export resolution; the mesh may show gaps."))
    }

    @Test func aSphereRegionIsCutToItsRoundSurface() async throws {
        var h = Harness()
        let ball = h.add(ImplicitSphereNode.self, ["radius": .number(15)])
        let tpms = h.add(TPMSNode.self, ["type": .integer(1), "form": .integer(1), "thickness": .number(0)])
        h.wire(ball, "implicit", to: tpms, "region")
        let solid = try #require(try await h.run([tpms]).implicitSolid(tpms))
        #expect(solid.distance(14, 8, 0) > 0, "outside the ball, though inside its box")
        #expect(solid.bounds.size.x == 30)
    }
}

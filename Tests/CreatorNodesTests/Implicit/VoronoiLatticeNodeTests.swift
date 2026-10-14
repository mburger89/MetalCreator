import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

/// The Voronoi Lattice node (implicit spec §3.4): built-in and wired seeds, the two forms, the skin and the warnings.
struct VoronoiLatticeNodeTests {
    func cube(_ h: inout Harness, _ values: [SocketName: ConstantValue] = [:]) -> Node {
        let cube = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(40, 40, 40))])
        let voronoi = h.add(VoronoiLatticeNode.self, values)
        h.wire(cube, "implicit", to: voronoi, "region")
        return voronoi
    }

    func lattice(_ solid: ImplicitSolid) -> VoronoiLattice? {
        if case .intersect(let parts, _) = solid, case .voronoi(let lattice) = parts[1] { lattice } else { nil }
    }

    /// The Voronoi lattice `node` makes.
    func made(_ h: Harness, _ node: Node) async throws -> VoronoiLattice {
        let solid = try #require(try await h.run([node]).implicitSolid(node))
        return try #require(lattice(solid))
    }

    @Test func withoutARegionItSaysWhatToConnect() async throws {
        var h = Harness()
        let voronoi = h.add(VoronoiLatticeNode.self)
        #expect(try await h.run([voronoi]).error(voronoi) == "Connect a region to fill.")
    }

    @Test func builtInSeedsMakeAStrutLatticeCutToTheRegion() async throws {
        var h = Harness()
        let voronoi = cube(&h, ["count": .integer(60)])
        let report = try await h.run([voronoi])
        let solid = try #require(report.implicitSolid(voronoi))
        #expect(solid.description == "intersect(box(40 × 40 × 40 mm), voronoi struts(60 seeds, t = 0.8 mm))")
        let made = try #require(lattice(solid))
        #expect(made.seeds.points.count == 60 && made.region == solid.bounds)
        #expect(made.seeds.radius == VoronoiSeeds.searchRadius(count: 60, in: solid.bounds))
        #expect(report.isOK(voronoi))
    }

    @Test func theSeedAndCountAreTheSettingsAndTheSameSettingsGiveTheSameSeeds() async throws {
        var h = Harness()
        let voronoi = cube(&h, ["count": .integer(30), "seed": .integer(5)])
        let first = try await made(h, voronoi)
        let again = try await made(h, voronoi)
        #expect(first.seeds.points == again.seeds.points && first.seeds !== again.seeds)
        h.set(voronoi, "seed", .integer(6))
        let moved = try await made(h, voronoi)
        #expect(moved.seeds.points != first.seeds.points)
    }

    @Test func foamIsTheOtherForm() async throws {
        var h = Harness()
        let voronoi = cube(&h, ["count": .integer(40), "form": .integer(1), "thickness": .number(1)])
        let solid = try #require(try await h.run([voronoi]).implicitSolid(voronoi))
        #expect(solid.description == "intersect(box(40 × 40 × 40 mm), voronoi foam(40 seeds, t = 1 mm))")
        h.set(voronoi, "form", .integer(2))
        #expect(try await h.run([voronoi]).error(voronoi) == "Choose Struts or Foam for “form”.")
    }

    @Test func aDensityFieldPlacesTheBuiltInSeeds() async throws {
        var h = Harness()
        let voronoi = cube(&h, ["count": .integer(80)])
        let ramp = h.add(LinearGradientNode.self, ["length": .number(40)])
        h.wire(ramp, "field", to: voronoi, "density")
        let made = try await made(h, voronoi)
        #expect(made.seeds.points.count == 80 && made.seeds.points.allSatisfy { $0.z >= 0 }, "the gradient's plane is XY: z / 40")
        let empty = cube(&h, ["count": .integer(80), "density": .number(0)])
        #expect(try await h.run([empty]).error(empty) == "The density is 0 everywhere in the region, so there are no seeds.")
    }

    /// Known consequence of graded density (U5): the search radius comes from `count`, so where the density is 0 the seeds are farther
    /// apart than the radius, the lattice reads as solid and the node says so. Nothing sizes the radius from the lowest density, because a
    /// density that reaches 0 has no finite spacing.
    @Test func aDensityRampToZeroLeavesASolidSlabAndWarns() async throws {
        var h = Harness()
        let voronoi = cube(&h, ["count": .integer(80)])
        let ramp = h.add(LinearGradientNode.self, ["length": .number(40)])
        h.wire(ramp, "field", to: voronoi, "density")
        let report = try await h.run([voronoi])
        #expect(report.warning(voronoi)?.contains("The seeds leave gaps in the region; the lattice is solid there.") == true)
        let solid = try #require(report.implicitSolid(voronoi))
        // The ramp is below 0 for z < 0, so every seed has z >= 0 and a point 19 mm below the middle is 19 mm or more from all of them: the
        // radius is 2 x the mean spacing of 80 seeds in 40 mm, 18.6 mm.
        #expect(solid.distance(0, 0, -19) < 0, "the empty end is a solid slab")
        let even = cube(&h, ["count": .integer(80)])
        #expect(try await h.run([even]).isOK(even), "an even density covers the region")
    }

    @Test func wiredPointsAreTheSeeds() async throws {
        var h = Harness()
        let voronoi = cube(&h, ["count": .integer(5)])
        let grid = h.add(GridPointsNode.self, [
            "countX": .integer(4), "countY": .integer(3), "spacingX": .number(12), "spacingY": .number(12),
        ])
        h.wire(grid, "points", to: voronoi, "seeds")
        let made = try await made(h, voronoi)
        #expect(made.seeds.points.count == 12 && made.seeds.points.allSatisfy { $0.z == 0 }, "“count” is ignored once points are wired")
        #expect(Set(made.seeds.points.map(\.x)) == [-18, -6, 6, 18])
    }

    @Test func aPlanesOriginIsASeed() async throws {
        var h = Harness()
        let voronoi = cube(&h)
        let plane = h.add(PlaneNode.self, ["offset": .number(7)])
        h.wire(plane, "plane", to: voronoi, "seeds")
        let made = try await made(h, voronoi)
        #expect(made.seeds.points == [Vector3(0, 0, 7)])
    }

    @Test func tooFewTooManyOrNoSeedsAreRefused() async throws {
        var h = Harness()
        let voronoi = cube(&h, ["count": .integer(0)])
        #expect(try await h.run([voronoi]).error(voronoi) == "“count” must be between 1 and 100,000.")
        h.set(voronoi, "count", .integer(100_001))
        #expect(try await h.run([voronoi]).error(voronoi) == "“count” must be between 1 and 100,000.")
        h.set(voronoi, "count", .integer(10))
        let none = h.add(GridPointsNode.self, ["countX": .integer(0)])
        h.wire(none, "points", to: voronoi, "seeds")
        let refusal = "“seeds” has no points. Wire some in, or disconnect it to use “count” seeds."
        #expect(try await h.run([voronoi]).error(voronoi) == refusal)
    }

    @Test func aSkinKeepsTheRegionsWall() async throws {
        var h = Harness()
        let voronoi = cube(&h, ["count": .integer(40), "skin": .number(2)])
        let solid = try #require(try await h.run([voronoi]).implicitSolid(voronoi))
        #expect(solid.description.hasPrefix("union(shell(box(40 × 40 × 40 mm), inward 2 mm), intersect(voronoi struts(40 seeds"))
        #expect(solid.distance(19, 3, 3) < 0, "inside the skin")
    }

    @Test func seedsThatDoNotReachTheRegionWarnThatItIsSolidThere() async throws {
        var h = Harness()
        let voronoi = cube(&h)
        let grid = h.add(GridPointsNode.self, [
            "countX": .integer(4), "countY": .integer(4), "spacingX": .number(2), "spacingY": .number(2), "centred": .bool(false),
        ])
        h.wire(grid, "points", to: voronoi, "seeds")
        let report = try await h.run([voronoi])
        #expect(report.warning(voronoi)?.contains("The seeds leave gaps in the region; the lattice is solid there.") == true)
        let spread = cube(&h, ["count": .integer(100)])
        #expect(try await h.run([spread]).isOK(spread))
    }

    @Test func cellsAndWallsUnderTheResolutionWarn() async throws {
        var h = Harness()
        // 2,000 seeds in a 40 mm cube are about 3 mm apart: more than 2 voxels of 0.3125 mm, so only the wall is too thin.
        let voronoi = cube(&h, ["count": .integer(2_000), "thickness": .number(0.2)])
        let warning = try #require(try await h.run([voronoi]).warning(voronoi))
        #expect(warning == "Struts are thinner than the preview resolution; the preview may show gaps.")
        h.set(voronoi, "form", .integer(1))
        #expect(try await h.run([voronoi]).warning(voronoi) == "Walls are thinner than the preview resolution; the preview may show gaps.")
        // A slab 200 × 200 × 5 mm previews at 1.5625 mm; 20,000 seeds in it are about 2.15 mm apart, under two voxels.
        let slab = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(200, 200, 5))])
        let fine = h.add(VoronoiLatticeNode.self, ["count": .integer(20_000), "thickness": .number(3)])
        h.wire(slab, "implicit", to: fine, "region")
        #expect(try await h.run([fine]).warning(fine) == "Cells are smaller than the preview resolution; the preview may look solid.")
    }

    @Test func aThicknessFieldIsGradedAndHeldAtZero() async throws {
        var h = Harness()
        let voronoi = cube(&h, ["count": .integer(30)])
        let gradient = h.add(LinearGradientNode.self, ["length": .number(20)])
        h.wire(gradient, "field", to: voronoi, "thickness")
        let report = try await h.run([voronoi])
        let solid = try #require(report.implicitSolid(voronoi))
        let made = try #require(lattice(solid))
        #expect(made.thickness.constantValue == nil)
        #expect(report.warning(voronoi)?.contains("“thickness” is below 0 in places; it is held at 0 there.") == true)
    }
}

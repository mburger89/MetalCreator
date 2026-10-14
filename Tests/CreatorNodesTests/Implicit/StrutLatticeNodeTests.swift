import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

/// The Strut Lattice node (implicit spec §3.4): the six cells, the radius and joint settings, the skin and the warnings.
struct StrutLatticeNodeTests {
    func cube(_ h: inout Harness, _ values: [SocketName: ConstantValue] = [:]) -> Node {
        let cube = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(40, 40, 40))])
        let struts = h.add(StrutLatticeNode.self, values)
        h.wire(cube, "implicit", to: struts, "region")
        return struts
    }

    @Test func withoutARegionItSaysWhatToConnect() async throws {
        var h = Harness()
        let struts = h.add(StrutLatticeNode.self)
        #expect(try await h.run([struts]).error(struts) == "Connect a region to fill.")
    }

    @Test func theDefaultIsACubicLatticeCutToTheRegion() async throws {
        var h = Harness()
        let struts = cube(&h)
        let report = try await h.run([struts])
        let solid = try #require(report.implicitSolid(struts))
        #expect(solid.description == "intersect(box(40 × 40 × 40 mm), cubic(cell 8 mm, r = 0.6 mm))")
        // Struts run along the axes through the points of a grid of 8 mm: (3, 0, 0) is on one, (4, 4, 4) is 4√2 from the nearest.
        #expect(abs(solid.distance(3, 0, 0) + 0.6) < 1e-12)
        #expect(abs(solid.distance(4, 4, 4) - (32.0.squareRoot() - 0.6)) < 1e-12)
        #expect(solid.distance(25, 0, 0) >= 5 - 1e-12)
        #expect(report.isOK(struts))
    }

    @Test(arguments: StrutCell.allCases)
    func eachCellIsASetting(_ cell: StrutCell) async throws {
        var h = Harness()
        let struts = cube(&h, ["cell": .integer(cell.rawValue), "cell size": .number(10), "strut radius": .number(0.5)])
        let solid = try #require(try await h.run([struts]).implicitSolid(struts))
        #expect(solid.description == "intersect(box(40 × 40 × 40 mm), \(cell.name.lowercased())(cell 10 mm, r = 0.5 mm))")
        let middle = (cell.struts[0].start + cell.struts[0].end) * 5
        #expect(abs(solid.signedDistance(at: middle) + 0.5) < 1e-9, "the first strut's midpoint is on a strut")
    }

    @Test func anUnknownCellIsRefused() async throws {
        var h = Harness()
        let struts = cube(&h, ["cell": .integer(6)])
        #expect(try await h.run([struts]).error(struts) == "Choose Cubic, BCC, FCC, Octet, Kelvin, or Diamond for “cell”.")
    }

    @Test func theNodeBlendRoundsJointsUpToAQuarterOfTheCell() async throws {
        var h = Harness()
        let sharp = cube(&h)
        let rounded = cube(&h, ["node blend": .number(1.5)])
        let a = try #require(try await h.run([sharp]).implicitSolid(sharp))
        let b = try #require(try await h.run([rounded]).implicitSolid(rounded))
        #expect(b.distance(0, 0, 0) < a.distance(0, 0, 0) - 0.3, "the joint at the origin")
        #expect(b.description.hasSuffix("r = 0.6 mm, blend 1.5 mm))"))
        h.set(rounded, "node blend", .number(2.5))
        let refusal = "“node blend” must be between 0 and a quarter of the smallest cell (2 mm)."
        #expect(try await h.run([rounded]).error(rounded) == refusal)
        h.set(rounded, "node blend", .number(-0.1))
        #expect(try await h.run([rounded]).error(rounded)?.hasPrefix("“node blend” must be between 0") == true)
    }

    @Test func aSkinKeepsTheRegionsWall() async throws {
        var h = Harness()
        let struts = cube(&h, ["skin": .number(1)])
        let solid = try #require(try await h.run([struts]).implicitSolid(struts))
        #expect(solid.description.hasPrefix("union(shell(box(40 × 40 × 40 mm), inward 1 mm), intersect(cubic("))
        #expect(solid.distance(19.5, 4, 4) < 0, "in the skin, away from any strut")
        #expect(solid.distance(15, 4, 4) > 0, "inside, away from any strut")
    }

    @Test func aStrutRadiusFieldAndACellSizeFieldAreGraded() async throws {
        var h = Harness()
        let struts = cube(&h)
        let size = h.add(LinearGradientNode.self, ["length": .number(80)])
        let sum = h.add(FieldAddNode.self, ["b": .number(8)])
        h.wire(size, "field", to: sum, "a")
        h.wire(sum, "field", to: struts, "cell size")
        let radius = h.add(RadialGradientNode.self, ["radius": .number(40)])
        h.wire(radius, "field", to: struts, "strut radius")
        let solid = try #require(try await h.run([struts]).implicitSolid(struts))
        guard case .intersect(let parts, _) = solid, case .struts(let lattice) = parts[1] else {
            Issue.record("not an intersection")
            return
        }
        #expect(lattice.cells.size.constantValue == nil && lattice.radius.constantValue == nil)
        #expect(lattice.cells.size.range.lowerBound > 0 && solid.lipschitz > 1)
    }

    @Test func aCellSizeThatReachesZeroOrAStretchOfZeroIsRefused() async throws {
        var h = Harness()
        let struts = cube(&h, ["cell size": .number(0)])
        #expect(try await h.run([struts]).error(struts) == "“cell size” must stay above 0 mm; it reaches 0 mm.")
        h.set(struts, "cell size", .number(8))
        h.set(struts, "cell stretch", .vector(Vector3(1, -1, 1)))
        #expect(try await h.run([struts]).error(struts) == "“cell stretch” must be greater than 0 on every axis.")
    }

    @Test func cellsAndStrutsUnderTheResolutionWarn() async throws {
        var h = Harness()
        // A 40 mm cube previews at 0.3125 mm: a strut of radius 0.1 is 0.2 across.
        let struts = cube(&h, ["cell size": .number(0.5), "strut radius": .number(0.1)])
        let warning = try #require(try await h.run([struts]).warning(struts))
        #expect(warning.contains("Cells are smaller than the preview resolution; the preview may look solid."))
        #expect(warning.contains("Struts are thinner than the preview resolution; the preview may show gaps."))
        h.set(struts, "cell size", .number(8))
        h.set(struts, "strut radius", .number(0.2))
        #expect(try await h.run([struts]).isOK(struts), "0.4 mm struts are wider than a voxel")
    }

    @Test func strutsThickerThanTheCellsWarnThatTheLatticeIsSolid() async throws {
        var h = Harness()
        let thick = "Struts are thicker than the cells; the lattice is solid."
        // 0.85 of a 2 mm cell is 1.7 mm: a radius of 2 fills it, and so does one of exactly 1.7; 1.6 does not trip the warning.
        let struts = cube(&h, ["cell size": .number(2), "strut radius": .number(2)])
        let report = try await h.run([struts])
        #expect(report.warning(struts)?.contains(thick) == true)
        let solid = try #require(report.implicitSolid(struts))
        #expect(solid.distance(1, 1, 1) < 0 && solid.distance(0.5, 0.5, 0.5) < 0, "solid between the struts")
        h.set(struts, "strut radius", .number(1.7))
        #expect(try await h.run([struts]).warning(struts)?.contains(thick) == true)
        h.set(struts, "strut radius", .number(1.6))
        #expect(try await h.run([struts]).warning(struts)?.contains(thick) != true)
        // The smallest cell edge counts: a stretch of 4, 1, 1 is normalised to geometric mean 1, so the smallest edge is 0.63 of 2 mm.
        h.set(struts, "cell stretch", .vector(Vector3(4, 1, 1)))
        #expect(try await h.run([struts]).warning(struts)?.contains(thick) == true, "1.6 mm against a 1.26 mm cell edge")
    }
}

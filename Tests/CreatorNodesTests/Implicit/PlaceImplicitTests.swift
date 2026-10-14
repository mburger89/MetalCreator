import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import Testing
@testable import CreatorNodes

/// Place accepting implicit solids (implicit spec §3.3): a rigid move per placement, exact.
struct PlaceImplicitTests {
    /// A cylinder tool (radius 2, height 10, centred on the origin) and Grid Points → Points to Placements → Place.
    struct Fixture {
        var h = Harness()
        let tool: Node, placements: Node, place: Node

        init(columns: Int = 2, rows: Int = 1, direction: Vector3 = .unitZ) {
            tool = h.add(ImplicitCylinderNode.self, ["radius": .number(2), "height": .number(10)])
            let grid = h.add(GridPointsNode.self, ["countX": .integer(columns), "countY": .integer(rows), "spacingX": .number(20),
                                                   "spacingY": .number(20),
            ])
            placements = h.add(PointsToPlacementsNode.self, ["direction": .vector(direction)])
            place = h.add(PlaceNode.self)
            h.wire(grid, "points", to: placements, "points")
            h.wire(placements, "placements", to: place, "placements")
            h.wire(tool, "implicit", to: place, "implicit")
        }
    }

    @Test func aCopyOfTheImplicitSitsAtEachPlacement() async throws {
        let f = Fixture()
        let report = try await f.h.run([f.place])
        let copies = try #require(report.value(f.place, "implicits")?.implicitSolids)
        #expect(copies.count == 2 && report.isOK(f.place))
        // Grid points at x = −10 and 10, facing +Z: the cylinder stands there, 5 mm each way along its axis.
        #expect(copies[0].distance(-10, 0, 0) == -2 && copies[1].distance(10, 0, 0) == -2)
        #expect(copies[0].distance(-10, 0, 5) == 0 && copies[1].distance(10, 0, -5) == 0)
        #expect(copies[0].distance(10, 0, 0) == 18, "the copy at −10 is 20 mm from the other cylinder's axis, less its radius")
        #expect(report.value(f.place, "solids") == nil)
    }

    @Test func aPlacementFacingAwayTurnsTheShapeToFaceIt() async throws {
        let f = Fixture(columns: 1, rows: 1, direction: .unitX)
        let copy = try #require(try await f.h.run([f.place]).value(f.place, "implicits")?.implicitSolids?.first)
        // Standing along +Z becomes lying along +X: the axis runs along X, the cylinder 5 mm each way, so x = 4 is 1 mm inside its end.
        #expect(abs(copy.distance(4, 0, 0) + 1) < 1e-9 && abs(copy.distance(0, 0, 4) - 2) < 1e-9)
    }

    @Test func movingIsExact() async throws {
        let f = Fixture()
        let copies = try #require(try await f.h.run([f.place]).value(f.place, "implicits")?.implicitSolids)
        for copy in copies { #expect(copy.lipschitz == 1) }
        #expect(copies[0].description == "place(cylinder(radius 2 mm, height 10 mm))")
    }

    @Test func aSolidToolStillWorksAndBothCanBePlacedTogether() async throws {
        var f = Fixture()
        let box = f.h.box(10, 10, 10)
        f.h.wire(box, "solid", to: f.place, "tool")
        let report = try await f.h.run([f.place])
        #expect(report.value(f.place, "solids")?.solids?.count == 2)
        #expect(report.value(f.place, "implicits")?.implicitSolids?.count == 2)
    }

    @Test func aPlaceNeedsAToolOrAnImplicit() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self)
        let placements = h.add(PointsToPlacementsNode.self)
        let place = h.add(PlaceNode.self)
        h.wire(grid, "points", to: placements, "points")
        h.wire(placements, "placements", to: place, "placements")
        #expect(try await h.run([place]).error(place) == "Connect or set “tool”.")
    }
}

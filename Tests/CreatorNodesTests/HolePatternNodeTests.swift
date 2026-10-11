import Foundation
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

/// Hole Pattern (patterns spec §5): a hole cut from each placement's origin into the part, against the normal.
struct HolePatternNodeTests {
    /// The 60 × 40 × 6 plate (top on z = 0), a 2 × 2 grid of placements and a Hole Pattern wired to them.
    func holes(_ settings: [SocketName: ConstantValue] = [:], columns: Int = 2, rows: Int = 2)
        -> (plate: PatternPlate, node: Node) {
        var plate = PatternPlate(columns: columns, rows: rows)
        let node = plate.h.add(HolePatternNode.self, settings)
        plate.h.wire(plate.plate, "solid", to: node, "part")
        plate.h.wire(plate.placements, "placements", to: node, "placements")
        return (plate, node)
    }

    func removed(_ report: EvaluationReport, _ node: Node, _ kernel: OCCTKernel) async throws -> Double {
        PatternPlate.plateVolume - (try await volume(try onlySolid(report, node), kernel))
    }

    @Test func aBlindHoleRemovesACylinderOfItsDepth() async throws {
        let kernel = OCCTKernel()
        let (plate, node) = holes(["diameter": .number(5), "depth": .number(3)])
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(report.isOK(node))
        #expect(isClose(try await removed(report, node, kernel), 4 * PatternPlate.cylinderVolume(5, 3)))
    }

    @Test func throughAllReachesPastThePartWhateverTheDepth() async throws {
        let kernel = OCCTKernel()
        let (plate, node) = holes(["diameter": .number(5), "depth": .number(1), "throughAll": .bool(true)])
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(report.isOK(node))
        #expect(isClose(try await removed(report, node, kernel), 4 * PatternPlate.cylinderVolume(5, 6)))
    }

    @Test func aCounterboreAddsAWiderShallowerStep() async throws {
        let kernel = OCCTKernel()
        let (plate, node) = holes(["diameter": .number(5), "depth": .number(6), "style": .integer(1), "counterboreDiameter": .number(9),
                                   "counterboreDepth": .number(2),
        ])
        let report = try await plate.h.run([node], kernel: kernel)
        let each = PatternPlate.cylinderVolume(9, 2) + PatternPlate.cylinderVolume(5, 4)
        #expect(isClose(try await removed(report, node, kernel), 4 * each))
    }

    @Test func aCountersinkOpensTheRimToACone() async throws {
        let kernel = OCCTKernel()
        let (plate, node) = holes(["diameter": .number(5), "depth": .number(6), "style": .integer(2), "countersinkDiameter": .number(10),
                                   "countersinkAngle": .number(90),
        ])
        let report = try await plate.h.run([node], kernel: kernel)
        // A 90° countersink from Ø10 to Ø5 is 2.5 mm deep: a cone frustum on a 3.5 mm bore.
        let frustum = Double.pi * 2.5 / 3 * (25 + 12.5 + 6.25)
        let each = frustum + PatternPlate.cylinderVolume(5, 3.5)
        #expect(isClose(try await removed(report, node, kernel), 4 * each))
    }

    @Test func eachHolesWallIsNamedByItsInstance() async throws {
        let kernel = OCCTKernel()
        let (plate, node) = holes(["diameter": .number(5), "depth": .number(6)])
        let part = try onlySolid(try await plate.h.run([node], kernel: kernel), node)
        let qualifier = NodeID.instanceScoped([node.id, node.id])
        for index in 0..<4 {
            // The bore is segment 1 of the revolved profile: top disc, wall, bottom disc.
            let wall = TopoTag(node: qualifier, item: index, role: .side(segment: 1))
            #expect(part.topology.faces.filter { $0.tags.contains(wall) }.count == 1)
        }
    }

    @Test func eachInstanceTakesItsOwnDiameterFromAListAndTheLastRepeats() async throws {
        let kernel = OCCTKernel()
        var (plate, node) = holes(["depth": .number(6)])
        let sizes = plate.h.add(SeriesNode.self, ["start": .number(3), "step": .number(3), "count": .integer(2)])
        plate.h.wire(sizes, "values", to: node, "diameter")
        let report = try await plate.h.run([node], kernel: kernel)
        let expected = PatternPlate.cylinderVolume(3, 6) + 3 * PatternPlate.cylinderVolume(6, 6)
        #expect(isClose(try await removed(report, node, kernel), expected))
    }

    @Test func aHolePlacedFacingDownCutsUpIntoThePart() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let plate = h.box(60, 40, 6)  // z 0…6: its bottom face is on z = 0.
        let grid = h.add(GridPointsNode.self, ["countX": .integer(1), "countY": .integer(1)])
        let placements = h.add(PointsToPlacementsNode.self, ["direction": .vector(-.unitZ)])
        let node = h.add(HolePatternNode.self, ["diameter": .number(5), "depth": .number(2)])
        h.wire(grid, "points", to: placements, "points")
        h.wire(plate, "solid", to: node, "part")
        h.wire(placements, "placements", to: node, "placements")
        let part = try onlySolid(try await h.run([node], kernel: kernel), node)
        #expect(isClose(try await volume(part, kernel), PatternPlate.plateVolume - PatternPlate.cylinderVolume(5, 2)))
    }

    @Test func aThroughAllHoleCutsAlongASideFacesNormal() async throws {
        let kernel = OCCTKernel()
        var plate = PatternPlate(columns: 1, rows: 1)
        // A point on the plate's +X side (x = 30) at mid-thickness, facing +X: the hole runs back along −X, the plate's whole width.
        let point = plate.h.add(VectorNode.self, ["x": .number(30), "z": .number(-3)])
        let placements = plate.h.add(PointsToPlacementsNode.self, ["direction": .vector(.unitX)])
        let node = plate.h.add(HolePatternNode.self, ["diameter": .number(4), "throughAll": .bool(true)])
        plate.h.wire(point, "vector", to: placements, "points")
        plate.h.wire(plate.plate, "solid", to: node, "part")
        plate.h.wire(placements, "placements", to: node, "placements")
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(report.isOK(node))
        #expect(isClose(try await removed(report, node, kernel), PatternPlate.cylinderVolume(4, 60)))
    }

    @Test func holesInEmptySpaceAreCountedInAWarning() async throws {
        let kernel = OCCTKernel()
        var (plate, node) = holes(["diameter": .number(5), "depth": .number(6)], columns: 5, rows: 1)
        plate.h.set(plate.grid, "spacingX", .number(30))
        let report = try await plate.h.run([node], kernel: kernel)
        // x = −60, −30, 0, 30, 60 on a plate spanning ±30: the holes on the edges cut half, and only ±60 miss.
        #expect(report.warning(node) == "2 of 5 holes miss the part.")
    }

    @Test func twoHolesWhoseWallsMeetCutTheirUnionAndBothCount() async throws {
        let kernel = OCCTKernel()
        var (plate, node) = holes(["diameter": .number(5), "depth": .number(6)], columns: 2, rows: 1)
        plate.h.set(plate.grid, "spacingX", .number(4))
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(report.isOK(node) && report.warning(node) == nil, "both holes still carry a wall: no miss is reported")
        // Two Ø5 circles 4 mm apart overlap in a lens of 2r²·acos(d/2r) − (d/2)·√(4r² − d²).
        let (r, d) = (2.5, 4.0)
        let lens = 2 * r * r * acos(d / (2 * r)) - d / 2 * (4 * r * r - d * d).squareRoot()
        #expect(isClose(try await removed(report, node, kernel), 2 * PatternPlate.cylinderVolume(5, 6) - lens * 6))
    }

    @Test func aHoleThatOnlyTouchesThePartMissesAndOneThatBitesASliverDoesNot() async throws {
        let kernel = OCCTKernel()
        // Two holes at x = ±32.5 on a plate spanning ±30: Ø5 holes just tangent to its sides.
        var (plate, node) = holes(["diameter": .number(5), "depth": .number(6)], columns: 2, rows: 1)
        plate.h.set(plate.grid, "spacingX", .number(65))
        var report = try await plate.h.run([node], kernel: kernel)
        #expect(report.warning(node) == "2 of 2 holes miss the part.")
        #expect(isClose(try await removed(report, node, kernel), 0))
        // 0.05 mm closer, each takes a sliver off the side and counts as a hit.
        plate.h.set(plate.grid, "spacingX", .number(64.9))
        report = try await plate.h.run([node], kernel: kernel)
        #expect(report.isOK(node) && report.warning(node) == nil)
        #expect(try await removed(report, node, kernel) > 0)
    }

    @Test func moreSizesThanPlacementsStackTheLastPlacementsHoleOnItself() async throws {
        let kernel = OCCTKernel()
        var (plate, node) = holes(["depth": .number(6)], columns: 1, rows: 1)
        let sizes = plate.h.add(SeriesNode.self, ["start": .number(5), "step": .number(0), "count": .integer(3)])
        plate.h.wire(sizes, "values", to: node, "diameter")
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(report.isOK(node) && report.warning(node) == nil, "stacked duplicates are no misses")
        #expect(isClose(try await removed(report, node, kernel), PatternPlate.cylinderVolume(5, 6)), "cut once, not three times")
    }

    @Test func aTooWideCounterboreIsRefusedNamingTheInstance() async throws {
        let (plate, node) = holes(["diameter": .number(5), "style": .integer(1), "counterboreDiameter": .number(4)])
        let report = try await plate.h.run([node], kernel: OCCTKernel())
        #expect(report.error(node) == "Hole {0}: the counterbore must be wider than the hole.")
    }

    @Test(arguments: [
        (["diameter": ConstantValue.number(0)], "Hole {0}: the diameter must be greater than 0 mm."),
        (["diameter": .number(.nan)], "Hole {0}: the diameter must be greater than 0 mm."),
        (["depth": .number(.infinity)], "Hole {0}: the depth must be greater than 0 mm."),
        (["depth": .number(-1)], "Hole {0}: the depth must be greater than 0 mm."),
        (["style": .integer(1), "depth": .number(6), "counterboreDepth": .number(7)],
         "Hole {0}: the counterbore must be shallower than the hole."),
        (["style": .integer(2), "countersinkDiameter": .number(5)], "Hole {0}: the countersink must be wider than the hole."),
        (["style": .integer(2), "countersinkAngle": .number(180)], "Hole {0}: the countersink angle must be between 0° and 180°."),
        (["style": .integer(2), "countersinkDiameter": .number(40), "depth": .number(3)],
         "Hole {0}: the countersink must be shallower than the hole."),
        (["style": .integer(3)], "Choose Plain, Counterbore, or Countersink for “style”."),
    ])
    func badSizesAreRefusedPlainly(_ settings: [SocketName: ConstantValue], _ message: String) async throws {
        let (plate, node) = holes(settings)
        #expect(try await plate.h.run([node], kernel: OCCTKernel()).error(node) == message)
    }

    @Test func noPlacementsLeaveThePartAsItIs() async throws {
        var (plate, node) = holes()
        plate.h.set(plate.grid, "total", .integer(0))
        let report = try await plate.h.run([node])
        #expect(try onlySolid(report, node) === (try onlySolid(report, plate.plate)))
    }

    @Test func moreThanTwoThousandInstancesAreRefused() async throws {
        var (plate, node) = holes(columns: 1, rows: 1)
        let sizes = plate.h.add(SeriesNode.self, ["start": .number(1), "step": .number(0.001), "count": .integer(2001)])
        plate.h.wire(sizes, "values", to: node, "diameter")
        #expect(try await plate.h.run([node]).error(node) == "Patterns are limited to 2,000 instances.")
    }

    @Test func fourHolesRemoveFourCylindersFromTheBracket() async throws {
        let kernel = OCCTKernel()
        let (plate, node) = holes(["diameter": .number(5), "depth": .number(6)])
        let part = try onlySolid(try await plate.h.run([node], kernel: kernel), node)
        #expect(isClose(try await volume(part, kernel), PatternPlate.plateVolume - 4 * PatternPlate.cylinderVolume(5, 6)))
        #expect(part.topology.faces.filter { $0.kind == .cylinder }.count == 4)
    }

    @Test func aTreeOfPlacementsIsRefusedAndTheKernelNeverCuts() async throws {
        let kernel = OCCTKernel()
        var plate = PatternPlate(columns: 2, rows: 2)
        let node = plate.h.add(HolePatternNode.self, ["diameter": .number(5), "depth": .number(3)])
        let rows = plate.h.add(PartitionNode.self, ["size": .integer(2)])
        plate.h.wire(plate.plate, "solid", to: node, "part")
        plate.h.wire(plate.placements, "placements", to: rows, "tree")
        plate.h.wire(rows, "tree", to: node, "placements")
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(report.error(node) == "Patterns take flat lists for now: flatten the tree first.")
        #expect(report.value(node, "solid") == nil)
    }
}

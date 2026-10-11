import Foundation
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

/// Boss / Pin Pattern (patterns spec §5): a boss standing on each placement and growing along its normal.
struct BossPatternNodeTests {
    /// The plate (top on z = 0), a 2 × 2 grid of placements facing +Z and a Boss / Pin Pattern wired to them.
    func bosses(_ settings: [SocketName: ConstantValue] = [:], columns: Int = 2, rows: Int = 2)
        -> (plate: PatternPlate, node: Node) {
        var plate = PatternPlate(columns: columns, rows: rows)
        let node = plate.h.add(BossPatternNode.self, settings)
        plate.h.wire(plate.plate, "solid", to: node, "part")
        plate.h.wire(plate.placements, "placements", to: node, "placements")
        return (plate, node)
    }

    func added(_ report: EvaluationReport, _ node: Node, _ kernel: OCCTKernel) async throws -> Double {
        (try await volume(try onlySolid(report, node), kernel)) - PatternPlate.plateVolume
    }

    @Test func aPlainPinAddsACylinderOfItsHeight() async throws {
        let kernel = OCCTKernel()
        let (plate, node) = bosses(["diameter": .number(4), "height": .number(5)])
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(report.isOK(node))
        #expect(isClose(try await added(report, node, kernel), 4 * PatternPlate.cylinderVolume(4, 5)))
        let top = try onlySolid(report, node).bounds.max.z
        #expect(isClose(top, 5))
    }

    @Test func aDraftNarrowsTheTip() async throws {
        let kernel = OCCTKernel()
        let (plate, node) = bosses(["diameter": .number(8), "height": .number(5), "draft": .number(5)])
        let report = try await plate.h.run([node], kernel: kernel)
        let tip = 4 - 5 * tan(5 * Double.pi / 180)
        let frustum = Double.pi * 5 / 3 * (16 + 4 * tip + tip * tip)
        #expect(isClose(try await added(report, node, kernel), 4 * frustum))
    }

    @Test func aTipFilletRoundsTheRimAndNamesItsBlendByInstance() async throws {
        let kernel = OCCTKernel()
        let (plate, node) = bosses(["diameter": .number(8), "height": .number(5), "tipFillet": .number(1)])
        let report = try await plate.h.run([node], kernel: kernel)
        let part = try onlySolid(report, node)
        let sharp = 4 * PatternPlate.cylinderVolume(8, 5)
        let gain = try await added(report, node, kernel)
        // Rounding a rim of radius 4 by 1 takes (1 − π/4)·r² of area swept about the axis: a little over 4 % of a pin here.
        #expect(gain < sharp && gain > sharp * 0.9)
        let qualifier = NodeID.instanceScoped([node.id, node.id])
        for index in 0..<4 {
            let blends = part.topology.faces.filter { face in
                face.tags.contains { $0.node == qualifier && $0.item == index && { if case .blend = $0.role { true } else { false } }($0) }
            }
            #expect(blends.count == 1)
        }
    }

    @Test func eachBossIsNamedByItsInstance() async throws {
        let kernel = OCCTKernel()
        let (plate, node) = bosses(["diameter": .number(4), "height": .number(5)])
        let part = try onlySolid(try await plate.h.run([node], kernel: kernel), node)
        let qualifier = NodeID.instanceScoped([node.id, node.id])
        for index in 0..<4 {
            // The side is segment 1 of the revolved profile: base disc, side, tip disc.
            let side = TopoTag(node: qualifier, item: index, role: .side(segment: 1))
            #expect(part.topology.faces.filter { $0.tags.contains(side) }.count == 1)
        }
    }

    @Test func eachInstanceTakesItsOwnHeightFromAListAndTheLastRepeats() async throws {
        let kernel = OCCTKernel()
        var (plate, node) = bosses(["diameter": .number(4)])
        let heights = plate.h.add(SeriesNode.self, ["start": .number(3), "step": .number(3), "count": .integer(2)])
        plate.h.wire(heights, "values", to: node, "height")
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(isClose(try await added(report, node, kernel),
                        PatternPlate.cylinderVolume(4, 3) + 3 * PatternPlate.cylinderVolume(4, 6)))
    }

    @Test func aBossGrowsAlongItsPlacementsNormal() async throws {
        let kernel = OCCTKernel()
        var plate = PatternPlate(columns: 1, rows: 1)
        // A point on the plate's +X side (x = 30) at mid-thickness, facing +X.
        let point = plate.h.add(VectorNode.self, ["x": .number(30), "z": .number(-3)])
        let placements = plate.h.add(PointsToPlacementsNode.self, ["direction": .vector(.unitX)])
        let node = plate.h.add(BossPatternNode.self, ["diameter": .number(4), "height": .number(5)])
        plate.h.wire(point, "vector", to: placements, "points")
        plate.h.wire(plate.plate, "solid", to: node, "part")
        plate.h.wire(placements, "placements", to: node, "placements")
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(report.isOK(node))
        let part = try onlySolid(report, node)
        #expect(isClose(part.bounds.max.x, 35))
        #expect(isClose(try await volume(part, kernel), PatternPlate.plateVolume + PatternPlate.cylinderVolume(4, 5)))
    }

    @Test func bossesBesideThePartAreCountedInAWarning() async throws {
        let kernel = OCCTKernel()
        var (plate, node) = bosses(["diameter": .number(4)], columns: 5, rows: 1)
        plate.h.set(plate.grid, "spacingX", .number(30))
        let report = try await plate.h.run([node], kernel: kernel)
        // x = −60, −30, 0, 30, 60 on a plate spanning ±30: the two outer bosses stand in empty space.
        let message = try #require(report.warning(node))
        #expect(message.contains("2 of 5 bosses miss the part."))
    }

    @Test(arguments: [
        (["diameter": ConstantValue.number(0)], "Boss {0}: the diameter must be greater than 0 mm."),
        (["diameter": .number(.nan)], "Boss {0}: the diameter must be greater than 0 mm."),
        (["height": .number(.infinity)], "Boss {0}: the height must be greater than 0 mm."),
        (["height": .number(0)], "Boss {0}: the height must be greater than 0 mm."),
        (["draft": .number(90)], "Boss {0}: the draft must be between 0° and 90°."),
        (["draft": .number(-1)], "Boss {0}: the draft must be between 0° and 90°."),
        (["diameter": .number(8), "height": .number(5), "draft": .number(40)],
         "Boss {0}: the draft is too steep: the tip would have no width."),
        (["tipFillet": .number(-1)], "Boss {0}: the tip fillet can't be negative."),
        (["diameter": .number(8), "height": .number(5), "tipFillet": .number(4)],
         "Boss {0}: the tip fillet must be smaller than the tip's radius and the boss's height."),
    ])
    func badSizesAreRefusedPlainly(_ settings: [SocketName: ConstantValue], _ message: String) async throws {
        let (plate, node) = bosses(settings)
        #expect(try await plate.h.run([node], kernel: OCCTKernel()).error(node) == message)
    }

    @Test func moreThanTwoThousandInstancesAreRefused() async throws {
        var (plate, node) = bosses(columns: 1, rows: 1)
        let sizes = plate.h.add(SeriesNode.self, ["start": .number(1), "step": .number(0.001), "count": .integer(2001)])
        plate.h.wire(sizes, "values", to: node, "diameter")
        #expect(try await plate.h.run([node]).error(node) == "Patterns are limited to 2,000 instances.")
    }
}

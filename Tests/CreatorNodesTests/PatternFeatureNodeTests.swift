import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

/// Pattern Feature (patterns spec §5): any tool, unioned or subtracted at every placement, by Place + Boolean.
struct PatternFeatureNodeTests {
    /// The plate and a cylinder tool through it (z −8…1), wired into a Pattern Feature that subtracts. The tool is Ø5,
    /// or one size for each item of a Series when `diameters` (start, step, count) is given.
    func subtracting(columns: Int = 2, rows: Int = 2, spacingX: Double = 40, diameters: (Double, Double, Int)? = nil)
        -> (plate: PatternPlate, tool: Node, feature: Node) {
        var plate = PatternPlate(columns: columns, rows: rows, spacingX: spacingX)
        let tool = plate.cylinder(diameter: 5, from: -8, to: 1)
        if let (start, step, count) = diameters {
            let sizes = plate.h.add(SeriesNode.self, ["start": .number(start), "step": .number(step), "count": .integer(count)])
            plate.h.wire(sizes, "values", to: plate.circle(of: tool), "diameter")
        }
        let feature = plate.h.add(PatternFeatureNode.self, ["operation": .integer(1)])
        plate.h.wire(plate.plate, "solid", to: feature, "part")
        plate.h.wire(tool, "solid", to: feature, "tool")
        plate.h.wire(plate.placements, "placements", to: feature, "placements")
        return (plate, tool, feature)
    }

    @Test func subtractingMakesOnePlaceAndOneBooleanWhateverTheCount() async throws {
        let (plate, _, feature) = subtracting(columns: 6, rows: 4)
        let kernel = FakeKernel()
        await kernel.clearLog()
        let report = try await plate.h.run([feature], kernel: kernel)
        #expect(report.error(feature) == nil && report.value(feature, "solid") != nil)
        let log = await kernel.operationLog
        #expect(log.filter { $0 == "place" }.count == 1)
        #expect(log.filter { $0 == "boolean" }.count == 1)
        #expect(!log.contains("transform"))
    }

    @Test func subtractingCutsEveryInstanceOnOCCT() async throws {
        let kernel = OCCTKernel()
        let (plate, _, feature) = subtracting()
        let report = try await plate.h.run([feature], kernel: kernel)
        #expect(report.isOK(feature))
        let part = try onlySolid(report, feature)
        #expect(isClose(try await volume(part, kernel), PatternPlate.plateVolume - 4 * PatternPlate.cylinderVolume(5, 6)))
    }

    @Test func unioningAddsAnInstanceOfTheToolAtEveryPlacement() async throws {
        let kernel = OCCTKernel()
        var plate = PatternPlate()
        let pin = plate.cylinder(diameter: 4, from: 0, to: 5)
        let feature = plate.h.add(PatternFeatureNode.self, ["operation": .integer(0)])
        plate.h.wire(plate.plate, "solid", to: feature, "part")
        plate.h.wire(pin, "solid", to: feature, "tool")
        plate.h.wire(plate.placements, "placements", to: feature, "placements")
        let report = try await plate.h.run([feature], kernel: kernel)
        #expect(report.isOK(feature))
        #expect(isClose(try await volume(try onlySolid(report, feature), kernel),
                        PatternPlate.plateVolume + 4 * PatternPlate.cylinderVolume(4, 5)))
    }

    @Test func aListOfToolsGivesEachInstanceItsOwnSizeAndTheLastRepeats() async throws {
        let kernel = OCCTKernel()
        // Diameters 3 then 6: instance 0 gets Ø3 and the other three repeat Ø6.
        let (plate, _, feature) = subtracting(diameters: (3, 3, 2))
        let report = try await plate.h.run([feature], kernel: kernel)
        let cut = PatternPlate.cylinderVolume(3, 6) + 3 * PatternPlate.cylinderVolume(6, 6)
        #expect(isClose(try await volume(try onlySolid(report, feature), kernel), PatternPlate.plateVolume - cut))
    }

    @Test func instancesThatMissThePartAreCountedInAWarning() async throws {
        let kernel = OCCTKernel()
        // 8 columns 20 mm apart: x = −70…70, and the plate spans ±30, so columns at ±30 touch the edge and four miss.
        let (plate, _, feature) = subtracting(columns: 8, rows: 1, spacingX: 20)
        let report = try await plate.h.run([feature], kernel: kernel)
        #expect(report.warning(feature) == "4 of 8 features miss the part.")
        // Two holes whole (x = ±10) and two cut in half by the plate's edge (x = ±30): three holes' worth.
        let part = try onlySolid(report, feature)
        #expect(isClose(try await volume(part, kernel), PatternPlate.plateVolume - 3 * PatternPlate.cylinderVolume(5, 6)))
    }

    @Test func aSingleInstanceThatMissesSaysSoInTheSingular() async throws {
        let kernel = OCCTKernel()
        var plate = PatternPlate(columns: 1, rows: 1)
        plate.h.set(plate.grid, "spacingX", .number(0))
        let far = plate.h.add(VectorNode.self, ["x": .number(500)])
        let placements = plate.h.add(PointsToPlacementsNode.self)
        plate.h.wire(far, "vector", to: placements, "points")
        let tool = plate.cylinder(diameter: 5, from: -8, to: 1)
        let feature = plate.h.add(PatternFeatureNode.self, ["operation": .integer(1)])
        plate.h.wire(plate.plate, "solid", to: feature, "part")
        plate.h.wire(tool, "solid", to: feature, "tool")
        plate.h.wire(placements, "placements", to: feature, "placements")
        let report = try await plate.h.run([feature], kernel: kernel)
        #expect(report.warning(feature) == "1 of 1 feature misses the part.")
    }

    @Test func aUnionedToolThatMissesThePartIsCountedToo() async throws {
        let kernel = OCCTKernel()
        var plate = PatternPlate(columns: 5, rows: 1, spacingX: 30)
        let pin = plate.cylinder(diameter: 4, from: 0, to: 5)
        let feature = plate.h.add(PatternFeatureNode.self, ["operation": .integer(0)])
        plate.h.wire(plate.plate, "solid", to: feature, "part")
        plate.h.wire(pin, "solid", to: feature, "tool")
        plate.h.wire(plate.placements, "placements", to: feature, "placements")
        let report = try await plate.h.run([feature], kernel: kernel)
        // x = −60, −30, 0, 30, 60 on a plate spanning ±30: the two outer pins stand in empty space.
        let message = try #require(report.warning(feature))
        #expect(message.contains("2 of 5 features miss the part."))
    }

    @Test func noPlacementsLeavesThePartAsItIs() async throws {
        let (plate, _, feature) = subtracting()
        var empty = plate
        empty.h.set(empty.grid, "total", .integer(0))
        let kernel = FakeKernel()
        await kernel.clearLog()
        let report = try await empty.h.run([feature], kernel: kernel)
        #expect(report.isOK(feature))
        let log = await kernel.operationLog
        #expect(!log.contains("place") && !log.contains("boolean"))
    }

    @Test func moreThanTwoThousandInstancesAreRefused() async throws {
        let (plate, _, feature) = subtracting(columns: 1, rows: 1, diameters: (1, 0.001, 2001))
        let report = try await plate.h.run([feature])
        #expect(report.error(feature) == "Patterns are limited to 2,000 instances.")
    }

    @Test func aPartThatTheCutSplitsStillWarnsAboutPieces() async throws {
        let kernel = OCCTKernel()
        var plate = PatternPlate(columns: 1, rows: 1)
        // One slot-like tool wider than the plate's depth, so the cut leaves two pieces.
        let rectangle = plate.h.add(RectangleNode.self, ["width": .number(4), "height": .number(60),
                                                         "plane": .plane(Plane.xy.offset(by: -8)),
        ])
        let tool = plate.h.add(ExtrudeNode.self, ["distance": .number(9)])
        plate.h.wire(rectangle, "profile", to: tool, "profile")
        let feature = plate.h.add(PatternFeatureNode.self, ["operation": .integer(1)])
        plate.h.wire(plate.plate, "solid", to: feature, "part")
        plate.h.wire(tool, "solid", to: feature, "tool")
        plate.h.wire(plate.placements, "placements", to: feature, "placements")
        let report = try await plate.h.run([feature], kernel: kernel)
        #expect(report.warning(feature) == "The result is 2 separate pieces. They stay together as one solid, "
                + "because parts with several bodies aren't supported yet.")
    }

    @Test func twoToolsAtOnePlacementCutOnce() async throws {
        let kernel = OCCTKernel()
        // Two equal tools meet one placement, so both copies stand in the same place.
        let (plate, _, feature) = subtracting(columns: 1, rows: 1, diameters: (5, 0, 2))
        let report = try await plate.h.run([feature], kernel: kernel)
        #expect(report.isOK(feature) && report.warning(feature) == nil, "the stacked copy is no miss")
        let part = try onlySolid(report, feature)
        #expect(isClose(try await volume(part, kernel), PatternPlate.plateVolume - PatternPlate.cylinderVolume(5, 6)))
    }

    @Test func aToolThatSwallowsThePartIsAPlainError() async throws {
        let (plate, _, feature) = subtracting(columns: 1, rows: 1, diameters: (500, 0, 1))
        let report = try await plate.h.run([feature], kernel: OCCTKernel())
        #expect(report.error(feature) == "Subtract failed: the result is empty.")
    }
}

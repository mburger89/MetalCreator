import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

/// Slot Pattern (patterns spec §5): a slot with rounded ends cut along each placement's X axis.
struct SlotPatternNodeTests {
    /// The plate (top on z = 0), a 2 × 2 grid of placements facing +Z and a Slot Pattern wired to them.
    func slots(_ settings: [SocketName: ConstantValue] = [:], columns: Int = 2, rows: Int = 2)
        -> (plate: PatternPlate, node: Node) {
        var plate = PatternPlate(columns: columns, rows: rows)
        let node = plate.h.add(SlotPatternNode.self, settings)
        plate.h.wire(plate.plate, "solid", to: node, "part")
        plate.h.wire(plate.placements, "placements", to: node, "placements")
        return (plate, node)
    }

    /// A slot's floor area: a rectangle between two half circles.
    static func area(length: Double, width: Double) -> Double {
        (length - width) * width + Double.pi * width * width / 4
    }

    func removed(_ report: EvaluationReport, _ node: Node, _ kernel: OCCTKernel) async throws -> Double {
        PatternPlate.plateVolume - (try await volume(try onlySolid(report, node), kernel))
    }

    @Test func aBlindSlotRemovesItsFloorAreaTimesItsDepth() async throws {
        let kernel = OCCTKernel()
        let (plate, node) = slots(["length": .number(16), "width": .number(6), "depth": .number(3)])
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(report.isOK(node))
        #expect(isClose(try await removed(report, node, kernel), 4 * Self.area(length: 16, width: 6) * 3))
    }

    @Test func throughAllCutsRightThroughThePlate() async throws {
        let kernel = OCCTKernel()
        let (plate, node) = slots(["length": .number(16), "width": .number(6), "depth": .number(1), "throughAll": .bool(true)])
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(isClose(try await removed(report, node, kernel), 4 * Self.area(length: 16, width: 6) * 6))
    }

    @Test func aSlotRunsAlongItsPlacementsXAxis() async throws {
        let kernel = OCCTKernel()
        var plate = PatternPlate(columns: 1, rows: 1)
        // Facing +Z, Points to Placements gives an x axis of world X. A slot 50 long fits along X (±25 in a plate spanning
        // ±30) and would run off the plate along Y (±20), so its whole floor area comes out only if it runs along X.
        let node = plate.h.add(SlotPatternNode.self, ["length": .number(50), "width": .number(6), "depth": .number(6)])
        plate.h.wire(plate.plate, "solid", to: node, "part")
        plate.h.wire(plate.placements, "placements", to: node, "placements")
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(report.isOK(node))
        let part = try onlySolid(report, node)
        #expect(isClose(try await volume(part, kernel), PatternPlate.plateVolume - Self.area(length: 50, width: 6) * 6))
    }

    @Test func aSlotRunsAlongAPlacementsOwnXAxis() async throws {
        let kernel = OCCTKernel()
        var plate = PatternPlate(columns: 1, rows: 1)
        // The YZ plane moved to the plate's +X side (x = 30): its normal is +X and its x axis is world Y. A slot 30 long
        // runs ±15 along Y, centred on the top edge so half of its 6 mm width cuts the plate, 6 mm deep into −X.
        let side = plate.h.add(PlaneNode.self, ["orientation": .integer(2), "offset": .number(30)])
        let node = plate.h.add(SlotPatternNode.self, ["length": .number(30), "width": .number(6), "depth": .number(6)])
        plate.h.wire(plate.plate, "solid", to: node, "part")
        plate.h.wire(side, "plane", to: node, "placements")
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(report.isOK(node))
        #expect(isClose(try await removed(report, node, kernel), Self.area(length: 30, width: 6) / 2 * 6))
    }

    @Test func eachSlotsWallsAreNamedByItsInstance() async throws {
        let kernel = OCCTKernel()
        let (plate, node) = slots(["length": .number(16), "width": .number(6), "depth": .number(6)])
        let part = try onlySolid(try await plate.h.run([node], kernel: kernel), node)
        let qualifier = NodeID.instanceScoped([node.id, node.id])
        for index in 0..<4 {
            for segment in 0..<4 {
                let wall = TopoTag(node: qualifier, item: index, role: .side(segment: segment))
                #expect(part.topology.faces.filter { $0.tags.contains(wall) }.count == 1)
            }
        }
    }

    @Test func eachInstanceTakesItsOwnLengthFromAListAndTheLastRepeats() async throws {
        let kernel = OCCTKernel()
        var (plate, node) = slots(["width": .number(6), "depth": .number(3)])
        let lengths = plate.h.add(SeriesNode.self, ["start": .number(10), "step": .number(6), "count": .integer(2)])
        plate.h.wire(lengths, "values", to: node, "length")
        let report = try await plate.h.run([node], kernel: kernel)
        let expected = (Self.area(length: 10, width: 6) + 3 * Self.area(length: 16, width: 6)) * 3
        #expect(isClose(try await removed(report, node, kernel), expected))
    }

    @Test func slotsInEmptySpaceAreCountedInAWarning() async throws {
        let kernel = OCCTKernel()
        var (plate, node) = slots(["length": .number(10), "width": .number(4), "depth": .number(6)], columns: 5, rows: 1)
        plate.h.set(plate.grid, "spacingX", .number(30))
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(report.warning(node) == "2 of 5 slots miss the part.")
    }

    @Test(arguments: [
        (["width": ConstantValue.number(0)], "Slot {0}: the width must be greater than 0 mm."),
        (["width": .number(.nan)], "Slot {0}: the width must be greater than 0 mm."),
        (["length": .number(.infinity)], "Slot {0}: the length must be greater than the width."),
        (["length": .number(6), "width": .number(6)], "Slot {0}: the length must be greater than the width."),
        (["depth": .number(0)], "Slot {0}: the depth must be greater than 0 mm."),
    ])
    func badSizesAreRefusedPlainly(_ settings: [SocketName: ConstantValue], _ message: String) async throws {
        let (plate, node) = slots(settings)
        #expect(try await plate.h.run([node], kernel: OCCTKernel()).error(node) == message)
    }

    @Test func moreThanTwoThousandInstancesAreRefused() async throws {
        var (plate, node) = slots(columns: 1, rows: 1)
        let widths = plate.h.add(SeriesNode.self, ["start": .number(1), "step": .number(0.001), "count": .integer(2001)])
        plate.h.wire(widths, "values", to: node, "width")
        #expect(try await plate.h.run([node]).error(node) == "Patterns are limited to 2,000 instances.")
    }
}

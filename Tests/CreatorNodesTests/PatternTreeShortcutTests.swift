import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Testing

/// The shortcut nodes over trees (patterns spec §5 and §6, 7a-3): placements in rows, sizes per instance or per row, still one
/// Place and one Boolean for the whole tree, and every instance named by its path.
struct PatternTreeShortcutTests {
    /// The plate and a 2 × 2 grid of placements cut into rows of 2 (Partition), wired into `node`'s `placements`.
    func rowed(_ node: any NodeDefinition.Type, _ settings: [SocketName: ConstantValue] = [:], rowLength: Int = 2,
               columns: Int = 2, rows: Int = 2) -> (plate: PatternPlate, node: Node) {
        var plate = PatternPlate(columns: columns, rows: rows)
        let shortcut = plate.h.add(node, settings)
        let partition = plate.h.add(PartitionNode.self, ["size": .integer(rowLength)])
        plate.h.wire(plate.plate, "solid", to: shortcut, "part")
        plate.h.wire(plate.placements, "placements", to: partition, "tree")
        plate.h.wire(partition, "tree", to: shortcut, "placements")
        return (plate, shortcut)
    }

    func pathsNamed(in solid: Solid, by node: Node) -> Set<[Int]> {
        let qualifier = NodeID.instanceScoped([node.id, node.id])
        let items = Set(solid.topology.faces.flatMap(\.tags).filter { $0.node == qualifier }.map(\.item))
        return Set(items.compactMap { InstancePath.indices(ofItem: $0) })
    }

    @Test func aTreeOfPlacementsIsOnePlaceAndOneBooleanAndNamesEverySlotByItsPath() async throws {
        let (plate, node) = rowed(SlotPatternNode.self, ["depth": .number(3)])
        let kernel = FakeKernel()
        await kernel.clearLog()
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(report.error(node) == nil, "\(String(describing: report.state(node)))")
        let part = try onlySolid(report, node)
        #expect(await kernel.operationLog.filter { $0 == "place" }.count == 1)
        #expect(await kernel.operationLog.filter { $0 == "boolean" }.count == 1)
        #expect(pathsNamed(in: part, by: node) == [[0, 0], [0, 1], [1, 0], [1, 1]])
    }

    #if canImport(CreatorOCCT)
    @Test func aTreeOfPlacementsNamesEveryHoleByItsPath() async throws {
        let (plate, node) = rowed(HolePatternNode.self, ["diameter": .number(5), "depth": .number(3)])
        let part = try onlySolid(try await plate.h.run([node], kernel: OCCTKernel()), node)
        #expect(pathsNamed(in: part, by: node) == [[0, 0], [0, 1], [1, 0], [1, 1]])
    }

    @Test func aFlatListIsStillNamedByIndexSoSavedPicksStillResolve() async throws {
        var plate = PatternPlate(columns: 2, rows: 2)
        let node = plate.h.add(HolePatternNode.self, ["diameter": .number(5), "depth": .number(3)])
        plate.h.wire(plate.plate, "solid", to: node, "part")
        plate.h.wire(plate.placements, "placements", to: node, "placements")
        let part = try onlySolid(try await plate.h.run([node], kernel: OCCTKernel()), node)
        #expect(pathsNamed(in: part, by: node) == [[0], [1], [2], [3]])
    }

    @Test func aSizePerRowFromAGraftCutsTheRowsToTheirOwnDiameters() async throws {
        let kernel = OCCTKernel()
        let made = rowed(HolePatternNode.self, ["depth": .number(6)])
        var plate = made.plate
        let node = made.node
        let diameters = plate.h.add(SeriesNode.self, ["start": .number(8), "step": .number(-3), "count": .integer(2)])
        let perRow = plate.h.add(GraftNode.self)
        plate.h.wire(diameters, "values", to: perRow, "tree")
        plate.h.wire(perRow, "tree", to: node, "diameter")
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        let removed = PatternPlate.plateVolume - (try await volume(try onlySolid(report, node), kernel))
        #expect(isClose(removed, 2 * PatternPlate.cylinderVolume(8, 6) + 2 * PatternPlate.cylinderVolume(5, 6)))
    }

    @Test func aFlatListOfSizesAppliesToEveryRowItemByItem() async throws {
        let kernel = OCCTKernel()
        let made = rowed(HolePatternNode.self, ["depth": .number(6)])
        var plate = made.plate
        let node = made.node
        let diameters = plate.h.add(SeriesNode.self, ["start": .number(4), "step": .number(2), "count": .integer(2)])
        plate.h.wire(diameters, "values", to: node, "diameter")
        let report = try await plate.h.run([node], kernel: kernel)
        let removed = PatternPlate.plateVolume - (try await volume(try onlySolid(report, node), kernel))
        #expect(isClose(removed, 2 * PatternPlate.cylinderVolume(4, 6) + 2 * PatternPlate.cylinderVolume(6, 6)))
    }

    @Test func holesThatMissThePartAreCountedAcrossTheTree() async throws {
        let kernel = OCCTKernel()
        var plate = PatternPlate(columns: 3, rows: 2, spacingX: 100)  // x = −100, 0 and 100: four of six holes are off the 60 mm plate.
        let node = plate.h.add(HolePatternNode.self, ["diameter": .number(5), "depth": .number(3)])
        let partition = plate.h.add(PartitionNode.self, ["size": .integer(3)])
        plate.h.wire(plate.plate, "solid", to: node, "part")
        plate.h.wire(plate.placements, "placements", to: partition, "tree")
        plate.h.wire(partition, "tree", to: node, "placements")
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(report.warning(node) == "4 of 6 holes miss the part.")
    }

    @Test func bossesAndPatternFeaturesTakeTreesToo() async throws {
        let (bosses, boss) = rowed(BossPatternNode.self)
        let report = try await bosses.h.run([boss], kernel: OCCTKernel())
        #expect(report.isOK(boss), "\(String(describing: report.state(boss)))")
        #expect(pathsNamed(in: try onlySolid(report, boss), by: boss).count == 4)

        let made = rowed(PatternFeatureNode.self)
        var plate = made.plate
        let feature = made.node
        let tool = plate.cylinder(diameter: 4, from: 0, to: 3)
        plate.h.wire(tool, "solid", to: feature, "tool")
        let kernel = FakeKernel()
        await kernel.clearLog()
        let featured = try await plate.h.run([feature], kernel: kernel)
        #expect(featured.error(feature) == nil, "\(String(describing: featured.state(feature)))")
        #expect(await kernel.operationLog.filter { $0 == "place" }.count == 1)
        let qualifier = NodeID.instanceScoped([feature.id, tool.id])
        let items = Set(try onlySolid(featured, feature).topology.faces.flatMap(\.tags).filter { $0.node == qualifier }.map(\.item))
        #expect(Set(items.compactMap { InstancePath.indices(ofItem: $0) }) == [[0, 0], [0, 1], [1, 0], [1, 1]])
    }
    #endif

    @Test func aTreeOnThePartIsRefusedAndNothingIsPlaced() async throws {
        var plate = PatternPlate(columns: 2, rows: 2)
        let node = plate.h.add(SlotPatternNode.self)
        let parts = plate.h.add(GraftNode.self)
        plate.h.wire(plate.plate, "solid", to: parts, "tree")
        plate.h.wire(parts, "tree", to: node, "part")
        plate.h.wire(plate.placements, "placements", to: node, "placements")
        let kernel = FakeKernel()
        await kernel.clearLog()
        let report = try await plate.h.run([node], kernel: kernel)
        #expect(report.error(node) == "Only placements and sizes can be trees: flatten the tree wired into the part "
            + "or the operation first.")
        #expect(await kernel.operationLog.contains("place") == false)
    }

    @Test func aSizeNestedDifferentlyFromThePlacementsNamesBothShapes() async throws {
        let made = rowed(HolePatternNode.self)
        var plate = made.plate
        let node = made.node
        let counts = plate.h.add(SeriesNode.self, ["start": .number(3), "step": .number(1), "count": .integer(8)])
        let halves = plate.h.add(PartitionNode.self, ["size": .integer(4)])
        let quarters = plate.h.add(PartitionNode.self, ["size": .integer(2)])
        plate.h.wire(counts, "values", to: halves, "tree")
        plate.h.wire(halves, "tree", to: quarters, "tree")
        plate.h.wire(quarters, "tree", to: node, "diameter")
        let report = try await plate.h.run([node])
        #expect(report.error(node) == "“placements” (2 × 2) and “diameter” (2 × 2 × 2) are nested differently. "
            + "Use a flat list, or trees of the same depth.")
    }

    @Test func aBadSizeNamesTheInstanceByItsTreePath() async throws {
        let made = rowed(HolePatternNode.self, ["depth": .number(3)])
        var plate = made.plate
        let node = made.node
        let diameters = plate.h.add(SeriesNode.self, ["start": .number(5), "step": .number(-5), "count": .integer(2)])
        let perRow = plate.h.add(GraftNode.self)
        plate.h.wire(diameters, "values", to: perRow, "tree")
        plate.h.wire(perRow, "tree", to: node, "diameter")
        let report = try await plate.h.run([node])
        #expect(report.error(node) == "Hole {1;0}: the diameter must be greater than 0 mm.")
    }
}

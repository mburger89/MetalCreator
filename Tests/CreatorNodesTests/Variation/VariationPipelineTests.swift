import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Foundation
import Testing

/// The variation nodes working together on a real plate (patterns spec §4): 4 × 3 placements, those within 12 mm of the middle
/// culled by region, three more dropped at random, the rest jittered, and a Hole Pattern whose diameters are random numbers in
/// the shape of what is left. Every number comes from the seed, so the same graph gives the same part.
struct VariationPipelineTests {
    struct Pipeline {
        var plate = PatternPlate(columns: 4, rows: 3, spacingX: 15, spacingY: 15)
        let region: Node, reduce: Node, jitter: Node, diameters: Node, holes: Node

        /// `inRows`: the placements are a Grid Pattern's tree of rows (`{row;column}`) instead of one flat list from Grid Points.
        init(seed: Int, inRows: Bool = false) {
            let origin = plate.h.add(VectorNode.self)
            let placements: Node
            if inRows {
                placements = plate.h.add(GridPatternNode.self, ["countX": .integer(4), "countY": .integer(3),
                                                                "spacingX": .number(15), "spacingY": .number(15),
                ])
            } else {
                placements = plate.placements
            }
            region = plate.h.add(CullByRegionNode.self, ["reference": .integer(1), "keep": .integer(1), "distance": .number(12)])
            reduce = plate.h.add(RandomReduceNode.self, ["count": .integer(3), "scope": .integer(1), "seed": .integer(seed)])
            jitter = plate.h.add(JitterNode.self, ["distance": .number(1), "turn": .number(30), "seed": .integer(seed)])
            diameters = plate.h.add(RandomValuesNode.self, ["min": .number(4), "max": .number(6), "seed": .integer(seed)])
            holes = plate.h.add(HolePatternNode.self, ["depth": .number(6)])
            plate.h.wire(origin, "vector", to: region, "point")
            plate.h.wire(placements, "placements", to: region, "placements")
            plate.h.wire(region, "placements", to: reduce, "tree")
            plate.h.wire(reduce, "tree", to: jitter, "placements")
            plate.h.wire(jitter, "placements", to: diameters, "shape")
            plate.h.wire(plate.plate, "solid", to: holes, "part")
            plate.h.wire(jitter, "placements", to: holes, "placements")
            plate.h.wire(diameters, "values", to: holes, "diameter")
        }
    }

    #if canImport(CreatorOCCT)
    @Test func theGraphMakesTheHolesItsRandomChoicesSay() async throws {
        let kernel = OCCTKernel()
        let p = Pipeline(seed: 5)
        let report = try await p.plate.h.run([p.holes], kernel: kernel)
        for node in [p.region, p.reduce, p.jitter, p.diameters, p.holes] {
            #expect(report.isOK(node), "\(node.name): \(String(describing: report.state(node)))")
        }
        let survivors = try #require(report.positions(p.jitter, "placements")?.first)
        #expect(survivors.count == 7, "12 placements, 2 culled by region, 3 dropped at random")
        #expect(Set(survivors).isDisjoint(with: [5, 6]), "the two beside the middle (x = ±7.5, y = 0) are gone first")
        let solid = try onlySolid(report, p.holes)
        let items = Set(solid.topology.faces.flatMap(\.tags).filter(\.node.isInstanceQualified).map(\.item))
        #expect(items == Set(survivors), "each hole is named by the index its placement had")
        let widths = try #require(report.value(p.diameters, "values")?.numbers)
        let removed = widths.reduce(0) { $0 + Double.pi * $1 * $1 / 4 * 6 }
        #expect(isClose(try await volume(solid, kernel), PatternPlate.plateVolume - removed, relative: 1e-4))
    }

    /// The same graph over a tree of placements: every hole is named by its tree path, and the survivors keep the path they had.
    @Test func theGraphOnATreeOfPlacementsNamesEveryHoleByItsOwnTreePath() async throws {
        let kernel = OCCTKernel()
        let p = Pipeline(seed: 5, inRows: true)
        let report = try await p.plate.h.run([p.holes], kernel: kernel)
        for node in [p.region, p.reduce, p.jitter, p.diameters, p.holes] {
            #expect(report.isOK(node), "\(node.name): \(String(describing: report.state(node)))")
        }
        let tree = try #require(report.tree(p.jitter, "placements"))
        let survivors = Set(tree.leaves.flatMap { leaf in leaf.positions.map { leaf.path.indices + [$0] } })
        #expect(survivors.count == 7, "12 placements, 2 culled by region, 3 dropped at random")
        #expect(survivors.isDisjoint(with: [[1, 1], [1, 2]]), "the two beside the middle are gone first")
        let solid = try onlySolid(report, p.holes)
        let items = solid.topology.faces.flatMap(\.tags).filter(\.node.isInstanceQualified).map(\.item)
        let paths = Set(items.compactMap { InstancePath.indices(ofItem: $0) })
        #expect(paths == survivors, "each hole is named by the tree path its placement had")
        let widths = try #require(report.value(p.diameters, "values")?.numbers)
        let removed = widths.reduce(0) { $0 + Double.pi * $1 * $1 / 4 * 6 }
        #expect(isClose(try await volume(solid, kernel), PatternPlate.plateVolume - removed, relative: 1e-4))
    }

    @Test func theSameSeedMakesTheSamePartAndAnotherSeedAnotherOneWithoutAWarning() async throws {
        let kernel = OCCTKernel()
        let first = Pipeline(seed: 5), again = Pipeline(seed: 5), other = Pipeline(seed: 6)
        let a = try onlySolid(try await first.plate.h.run([first.holes], kernel: kernel), first.holes)
        let b = try onlySolid(try await again.plate.h.run([again.holes], kernel: kernel), again.holes)
        let otherReport = try await other.plate.h.run([other.holes], kernel: kernel)
        let c = try onlySolid(otherReport, other.holes)
        #expect(isClose(try await volume(a, kernel), try await volume(b, kernel), relative: 1e-12))
        #expect(!isClose(try await volume(a, kernel), try await volume(c, kernel), relative: 1e-9))
        #expect(otherReport.isOK(other.holes) && otherReport.isOK(other.reduce) && otherReport.isOK(other.jitter))
    }
    #endif

    /// With every random node on the default seed 0, Random Reduce and Random Values must not draw the same numbers at the same place
    /// (User decision U7): unsalted, the three items dropped here would be exactly the three smallest random values.
    @Test func withTheSameSeedTheItemsRandomReduceDropsAreNotTheSmallestRandomValues() async throws {
        var h = Harness()
        let source = h.source(count: 12)
        let reduce = h.add(RandomReduceNode.self, ["count": .integer(3), "seed": .integer(0)])
        let values = h.add(RandomValuesNode.self, ["count": .integer(12), "seed": .integer(0)])
        h.wire(source, to: reduce, "tree")
        let report = try await h.run([reduce, values])
        let dropped = Set(0..<12).subtracting(try #require(report.positions(reduce)?.first))
        let numbers = try #require(report.value(values, "values")?.numbers)
        let smallest = Set(numbers.indices.sorted { numbers[$0] < numbers[$1] }.prefix(3))
        #expect(dropped == [0, 4, 8] && smallest == [5, 8, 11], "pinned; unsalted both were {2, 4, 6}")
        #expect(dropped != smallest)
    }
}

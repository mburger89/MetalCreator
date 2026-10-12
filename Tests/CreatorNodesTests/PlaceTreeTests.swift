import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// Place over a tree of placements (patterns spec §3 and §6, 7a-3): the copies come out in the tree's shape, made by one
/// kernel call, and each is named by its path.
struct PlaceTreeTests {
    /// Grid Points (3 × 2, 20 mm) → Points to Placements → Partition (rows of 3) → Place, with a 10 mm box tool.
    struct Fixture {
        var h = Harness()
        let tool: Node, grid: Node, placements: Node, rows: Node, place: Node

        init(rowLength: Int = 3, flat: Bool = false) {
            tool = h.box(10, 10, 10)
            grid = h.add(GridPointsNode.self, ["countX": .integer(3), "countY": .integer(2), "spacingX": .number(20),
                                               "spacingY": .number(20),
            ])
            placements = h.add(PointsToPlacementsNode.self)
            rows = h.add(PartitionNode.self, ["size": .integer(rowLength)])
            place = h.add(PlaceNode.self)
            h.wire(grid, "points", to: placements, "points")
            h.wire(placements, "placements", to: rows, "tree")
            if flat {
                h.wire(placements, "placements", to: place, "placements")
            } else {
                h.wire(rows, "tree", to: place, "placements")
            }
            h.wire(tool, "solid", to: place, "tool")
        }

        func tree(_ report: EvaluationReport) throws -> DataTree {
            try #require(report.value(place, "solids")?.asTree)
        }
    }

    @Test func aTreeOfPlacementsComesOutAsATreeOfCopiesInOneKernelCall() async throws {
        let f = Fixture()
        let kernel = FakeKernel()
        await kernel.clearLog()
        let report = try await f.h.run([f.place], kernel: kernel)
        #expect(report.isOK(f.place), "\(String(describing: report.state(f.place)))")
        let copies = try f.tree(report)
        #expect(copies.depth == 2)
        #expect(copies.leaves.map(\.path.indices) == [[0], [1]])
        #expect(copies.leaves.map { $0.items.count } == [3, 3])
        #expect(await kernel.operationLog.filter { $0 == "place" }.count == 1)
        #expect(await kernel.operationLog.contains("transform") == false)
    }

    @Test func copiesSitAtTheirPlacementsRowByRow() async throws {
        let f = Fixture()
        let copies = try f.tree(try await f.h.run([f.place])).leaves.map { leaf in leaf.items.compactMap(\.solidValue) }
        let centres = copies.map { row in row.map { ($0.bounds.min + $0.bounds.max) * 0.5 } }
        #expect(centres.map { $0.map(\.x) } == [[-20, 0, 20], [-20, 0, 20]])
        #expect(centres.map { $0.map(\.y) } == [[-10, -10, -10], [10, 10, 10]])
    }

    @Test func eachCopyIsNamedByItsPathInTheTree() async throws {
        let f = Fixture()
        let tree = try f.tree(try await f.h.run([f.place]))
        let qualifier = NodeID.instanceScoped([f.place.id, f.tool.id])
        for leaf in tree.leaves {
            for (column, scalar) in leaf.items.enumerated() {
                let copy = try #require(scalar.solidValue)
                let path = leaf.path.indices + [column]
                let item = try #require(InstancePath.item(for: path))
                let tags = Set(copy.topology.faces.flatMap(\.tags))
                #expect(tags.contains(TopoTag(node: qualifier, item: item, role: .endCap)), "\(path)")
                #expect(tags.allSatisfy { $0.node == qualifier && $0.item == item })
                #expect(InstancePath.text(item) == "{\(path.map(String.init).joined(separator: ";"))}")
            }
        }
    }

    @Test func aFlatListOfPlacementsIsStillNamedByIndex() async throws {
        let f = Fixture(flat: true)
        let report = try await f.h.run([f.place])
        let copies = try #require(report.value(f.place, "solids"))
        #expect(copies.isList)
        let qualifier = NodeID.instanceScoped([f.place.id, f.tool.id])
        for (index, copy) in (copies.solids ?? []).enumerated() {
            #expect(Set(copy.topology.faces.flatMap(\.tags)).allSatisfy { $0.node == qualifier && $0.item == index })
        }
    }

    @Test func aTreeOfToolsGivesEachBranchItsOwnTool() async throws {
        var f = Fixture()
        let heights = f.h.add(SeriesNode.self, ["start": .number(5), "step": .number(5), "count": .integer(2)])
        let perRow = f.h.add(GraftNode.self)
        f.h.wire(heights, "values", to: perRow, "tree")
        f.h.wire(perRow, "tree", to: f.tool, "distance")
        let report = try await f.h.run([f.place])
        let copies = try f.tree(report).leaves.map { leaf in leaf.items.compactMap(\.solidValue) }
        #expect(copies.map { $0.map(\.bounds.max.z) } == [[5, 5, 5], [10, 10, 10]])
    }

    @Test func treesOfDifferentDepthsAreRefusedNamingBothShapesAndNothingIsPlaced() async throws {
        var f = Fixture()
        let counts = f.h.add(SeriesNode.self, ["start": .number(1), "step": .number(1), "count": .integer(8)])
        let halves = f.h.add(PartitionNode.self, ["size": .integer(4)])
        let quarters = f.h.add(PartitionNode.self, ["size": .integer(2)])
        f.h.wire(counts, "values", to: halves, "tree")
        f.h.wire(halves, "tree", to: quarters, "tree")
        f.h.wire(quarters, "tree", to: f.tool, "distance")
        let kernel = FakeKernel()
        await kernel.clearLog()
        let report = try await f.h.run([f.place], kernel: kernel)
        #expect(report.error(f.place) == "“placements” (2 × 3) and “tool” (2 × 2 × 2) are nested differently. "
            + "Use a flat list, or trees of the same depth.")
        #expect(await kernel.operationLog.contains("place") == false)
    }

    @Test func rowsOfDifferentLengthsAreAllPlacedAndKeepTheirLengths() async throws {
        let f = Fixture(rowLength: 4)  // 6 placements in rows of 4: [4, 2].
        let tree = try f.tree(try await f.h.run([f.place]))
        #expect(tree.leaves.map { $0.items.count } == [4, 2])
    }
}

private extension Scalar {
    var solidValue: Solid? { if case .solid(let solid) = self { solid } else { nil } }
}

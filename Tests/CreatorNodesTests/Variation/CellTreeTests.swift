import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// The variation nodes on a tree three deep, `{row;column;0}`: one item in every branch, which is the shape Face Pattern gives
/// Place (one placement per cell). It is built here by hand (a Series, Partition and Graft), not by Face Pattern, so these
/// tests hold whatever the layouts do. Bare indices and the mask count places within a branch, so what they do to this shape
/// is pinned: it is deliberate (User decisions U10 and U16), and the paths, Cull Pattern's Overall scope and Cull by Region
/// are how a designer reaches cells.
struct CellTreeTests {
    /// 2 rows of 3 cells numbered 0…5: `{0;0;0}` … `{1;2;0}`.
    static let all = "[[[0],[1],[2]],[[3],[4],[5]]]"

    /// A Series of 6 in rows of 3, every item then grafted into a branch of its own.
    func cells(_ h: inout Harness) -> TreeSource {
        let rows = h.source(count: 6, rows: 3)
        let graft = h.add(GraftNode.self)
        h.wire(rows, to: graft, "tree")
        return TreeSource(node: graft, socket: "tree")
    }

    /// `type` run on the cells with `settings`.
    func run(_ type: any NodeDefinition.Type,
             _ settings: [SocketName: ConstantValue]) async throws -> (report: EvaluationReport, node: Node) {
        var h = Harness()
        let source = cells(&h)
        let node = h.add(type, settings)
        h.wire(source, to: node, "tree")
        return (try await h.run([node]), node)
    }

    func cull(_ text: String) async throws -> (report: EvaluationReport, node: Node) {
        try await run(CullIndexNode.self, [NodeSetting.cullIndices: .text(text)])
    }

    @Test func theCellsAreThreeDeepWithOneItemInEveryBranch() async throws {
        var h = Harness()
        let source = cells(&h)
        let report = try await h.run([source.node])
        let tree = try #require(report.tree(source.node))
        #expect(tree.depth == 3 && tree.shapeText == "2 × 3 × 1")
        #expect(tree.outline == Self.all)
        #expect(tree.leaves.map(\.path) == [[0, 0], [0, 1], [0, 2], [1, 0], [1, 1], [1, 2]].map { TreePath($0) })
    }

    // MARK: Cull Index

    @Test(arguments: ["{0;1;0}", "{0;1}"])
    func aPathOfThreeIndicesOrTwoCullsOneCell(_ text: String) async throws {
        let (report, node) = try await cull(text)
        #expect(report.value(node, "tree")?.outline == "[[[0],[],[2]],[[3],[4],[5]]]", "\(text)")
        #expect(report.tree(node)?.leaves.count == 6, "the other five cells are still at their own paths")
        #expect(report.isOK(node))
    }

    @Test func aRowPathCullsTheWholeRowAndLeavesItsBranchesEmpty() async throws {
        let (report, node) = try await cull("{1}")
        #expect(report.value(node, "tree")?.outline == "[[[0],[1],[2]],[[],[],[]]]")
    }

    @Test func severalPathsAtDifferentLevelsApplyTogether() async throws {
        let (report, node) = try await cull("{0;0;0}, {1;1}, {0;2}")
        #expect(report.value(node, "tree")?.outline == "[[[],[1],[]],[[3],[],[5]]]")
    }

    @Test func aBareIndexIsAPlaceInTheLastLevelSoOnCellsOnlyZeroIsThere() async throws {
        let (one, oneNode) = try await cull("1")
        #expect(one.value(oneNode, "tree")?.outline == Self.all, "no cell has an item 1: nothing is culled, and nothing warns")
        #expect(one.isOK(oneNode))
        let (zero, zeroNode) = try await cull("0")
        #expect(zero.value(zeroNode, "tree")?.outline == "[[[],[],[]],[[],[],[]]]", "every cell's only item is item 0: all of them go")
    }

    @Test func aPathWithFourIndicesIsRefusedNamingTheShape() async throws {
        let (report, node) = try await cull("{0;1;0;0}")
        #expect(report.error(node) == "{0;1;0;0} has 4 indices, but an item of this tree (2 × 3 × 1) needs 3. Write it like {0;0;0}.")
    }

    @Test func aPathThatNamesNoCellWarns() async throws {
        let (report, node) = try await cull("{0;5}, {0;1;0}")
        #expect(report.warning(node) == "{0;5} names nothing in this tree.")
        #expect(report.value(node, "tree")?.outline == "[[[0],[],[2]],[[3],[4],[5]]]")
    }

    // MARK: Cull Pattern

    @Test func perBranchTheMaskRestartsInEveryCellSoOneOneZeroKeepsEveryCell() async throws {
        let (report, node) = try await run(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])
        #expect(report.value(node, "tree")?.outline == Self.all, "each branch has one item, the mask's first")
        #expect(report.tree(node)?.isCulled == false)
        let (second, secondNode) = try await run(CullPatternNode.self, [NodeSetting.cullPattern: .text("0 1")])
        #expect(second.value(secondNode, "tree")?.outline == "[[[],[],[]],[[],[],[]]]", "and 0 1 culls every cell")
    }

    @Test func overallTheMaskRunsAlongTheCellsInOrder() async throws {
        let (report, node) = try await run(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0"), "scope": .integer(1)])
        #expect(report.value(node, "tree")?.outline == "[[[0],[],[2]],[[],[4],[]]]", "cells 0, 2 and 4 stay, at their own paths")
        let (thirds, thirdsNode) = try await run(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 1 0"), "scope": .integer(1)])
        #expect(thirds.value(thirdsNode, "tree")?.outline == "[[[0],[1],[]],[[3],[4],[]]]")
    }

    // MARK: Random Reduce

    @Test func randomReduceDropsOneCellByDefaultAndNeverEmptiesTheTree() async throws {
        let (report, node) = try await run(RandomReduceNode.self, [:])
        #expect(report.tree(node)?.itemCount == 5)
        let (three, threeNode) = try await run(RandomReduceNode.self, ["count": .integer(3), "seed": .integer(7)])
        #expect(three.tree(threeNode)?.itemCount == 3)
    }

    @Test func randomReducePerBranchOnCellsDropsEveryCellAsItSays() async throws {
        let (report, node) = try await run(RandomReduceNode.self, ["scope": .integer(0)])
        #expect(report.tree(node)?.itemCount == 0)
        #expect(report.isOK(node))
    }

    @Test func randomReduceOverallKeepsTheSurvivorsAtTheirCellPaths() async throws {
        let (report, node) = try await run(RandomReduceNode.self, ["count": .integer(2), "seed": .integer(3)])
        let tree = try #require(report.tree(node))
        #expect(tree.leaves.count == 6 && tree.itemCount == 4)
        for leaf in tree.leaves {
            let cell = String(leaf.path.indices[0] * 3 + leaf.path.indices[1])
            #expect(leaf.items.isEmpty || leaf.items.map(\.outlineText) == [cell], "a survivor keeps its own number at its own path")
        }
    }

    // MARK: Random Values and Jitter

    @Test func aCulledCellKeepsTheOtherCellsRandomValues() async throws {
        func values(culling text: String) async throws -> [[String]] {
            var h = Harness()
            let source = cells(&h)
            let cullNode = h.add(CullIndexNode.self, [NodeSetting.cullIndices: .text(text)])
            let random = h.add(RandomValuesNode.self, ["seed": .integer(42)])
            h.wire(source, to: cullNode, "tree")
            h.wire(cullNode, "tree", to: random, "shape")
            let report = try await h.run([random])
            return try #require(report.tree(random, "values")).leaves.map { $0.items.map(\.outlineText) }
        }
        let whole = try await values(culling: "")
        let culled = try await values(culling: "{0;1}")
        #expect(whole.count == 6 && culled.count == 6)
        #expect(Set(whole.joined()).count == 6, "each cell draws from its own branch's stream")
        #expect(culled[1].isEmpty)
        for cell in [0, 2, 3, 4, 5] { #expect(culled[cell] == whole[cell], "cell \(cell)") }
    }

    @Test func aCulledCellKeepsTheOtherCellsJitter() async throws {
        func jittered(culling text: String) async throws -> [[Plane]] {
            var h = Harness()
            let layout = h.add(GridPatternNode.self, ["countX": .integer(3), "countY": .integer(2)])
            let graft = h.add(GraftNode.self)
            let cullNode = h.add(CullIndexNode.self, [NodeSetting.cullIndices: .text(text)])
            let jitter = h.add(JitterNode.self, ["distance": .number(2), "turn": .number(10), "seed": .integer(5)])
            h.wire(layout, "placements", to: graft, "tree")
            h.wire(graft, "tree", to: cullNode, "tree")
            h.wire(cullNode, "tree", to: jitter, "placements")
            let report = try await h.run([jitter])
            return try #require(report.tree(jitter, "placements")).leaves.map { leaf in
                leaf.items.compactMap { if case .plane(let plane) = $0 { plane } else { nil } }
            }
        }
        let whole = try await jittered(culling: "")
        let culled = try await jittered(culling: "{1;0}")
        #expect(whole.count == 6 && culled.count == 6 && culled[3].isEmpty)
        for cell in [0, 1, 2, 4, 5] { #expect(culled[cell] == whole[cell], "cell \(cell)") }
        #expect(whole[0] != whole[1], "the cells do not all move alike")
    }
}

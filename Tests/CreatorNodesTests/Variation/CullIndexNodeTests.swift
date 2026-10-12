import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// Cull Index (patterns spec §4): listed indices or paths such as {0;3} come out, and everything else keeps its path.
struct CullIndexNodeTests {
    func run(_ text: String, count: Int = 8, rows: Int? = nil) async throws -> (report: EvaluationReport, cull: Node) {
        var h = Harness()
        let source = h.source(count: count, rows: rows)
        let cull = h.add(CullIndexNode.self, [NodeSetting.cullIndices: .text(text)])
        h.wire(source, to: cull, "tree")
        return (try await h.run([cull]), cull)
    }

    @Test func anIndexComesOutOfEveryBranch() async throws {
        let (report, cull) = try await run("1", count: 8, rows: 4)
        #expect(report.value(cull, "tree")?.outline == "[[0,2,3],[4,6,7]]")
        #expect(report.positions(cull) == [[0, 2, 3], [0, 2, 3]])
        #expect(report.isOK(cull))
    }

    @Test func severalIndicesInAnyOrderWithSpaces() async throws {
        let (report, cull) = try await run(" 3 ,0, 5", count: 6)
        #expect(report.value(cull, "tree")?.outline == "[1,2,4]")
        #expect(report.positions(cull) == [[1, 2, 4]])
    }

    @Test func aPathDropsOneItem() async throws {
        let (report, cull) = try await run("{1;2}", count: 8, rows: 4)
        #expect(report.value(cull, "tree")?.outline == "[[0,1,2,3],[4,5,7]]")
        #expect(report.positions(cull) == [[0, 1, 2, 3], [0, 1, 3]])
    }

    @Test func aShortPathDropsTheWholeBranchAndLeavesItsPlaceEmpty() async throws {
        let (report, cull) = try await run("{0}", count: 6, rows: 2)
        #expect(report.value(cull, "tree")?.outline == "[[],[2,3],[4,5]]")
        #expect(report.positions(cull) == [[], [0, 1], [0, 1]])
        #expect(report.tree(cull)?.branches.count == 3, "{1} and {2} are still {1} and {2}")
    }

    @Test func aPathOnAFlatListIsAnIndex() async throws {
        let (report, cull) = try await run("{2}", count: 4)
        #expect(report.positions(cull) == [[0, 1, 3]])
    }

    @Test func indicesAndPathsTogether() async throws {
        let (report, cull) = try await run("0, {1;3}", count: 8, rows: 4)
        #expect(report.positions(cull) == [[1, 2, 3], [1, 2]])
    }

    @Test func aPathWithTooManyIndicesIsRefusedNamingTheShape() async throws {
        let (report, cull) = try await run("{0;1;2}", count: 8, rows: 4)
        #expect(report.error(cull) == "{0;1;2} has 3 indices, but an item of this tree (2 × 4) needs 2. Write it like {0;0}.")
    }

    @Test func aPathThatNamesNothingWarnsOnceAndTheOthersStillApply() async throws {
        let (report, cull) = try await run("{0;1}, {0;9}, {5;0}", count: 8, rows: 4)
        #expect(report.warning(cull) == "{0;9} and {5;0} name nothing in this tree.")
        #expect(report.positions(cull) == [[0, 2, 3], [0, 1, 2, 3]])
        let (single, singleCull) = try await run("{0;9}", count: 8, rows: 4)
        #expect(single.warning(singleCull) == "{0;9} names nothing in this tree.")
    }

    @Test func anIndexPastTheEndIsNotAProblem() async throws {
        let (report, cull) = try await run("99", count: 3)
        #expect(report.isOK(cull))
        #expect(report.value(cull, "tree")?.outline == "[0,1,2]")
    }

    @Test func nothingToCullChangesNothingAndAPlainListStaysPlain() async throws {
        let (report, cull) = try await run("", count: 3)
        #expect(report.isOK(cull))
        #expect(report.value(cull, "tree")?.isList == true)
    }

    @Test func indicesNameThePlacesTheItemsHadBeforeAnyCull() async throws {
        var h = Harness()
        let source = h.source(count: 6)
        let pattern = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])  // keeps {0}, {2}, {4}
        let index = h.add(CullIndexNode.self, [NodeSetting.cullIndices: .text("2, 1")])
        h.wire(source, to: pattern, "tree")
        h.wire(pattern, "tree", to: index, "tree")
        let report = try await h.run([index])
        #expect(report.positions(index) == [[0, 4]], "{2} is gone, and {1} was gone already")
        #expect(report.value(index, "tree")?.outline == "[0,4]")
        #expect(report.isOK(index), "an index never warns")
    }

    @Test func aPathOnAnItemAlreadyCulledWarns() async throws {
        var h = Harness()
        let source = h.source(count: 6)
        let pattern = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])
        let index = h.add(CullIndexNode.self, [NodeSetting.cullIndices: .text("{1}")])
        h.wire(source, to: pattern, "tree")
        h.wire(pattern, "tree", to: index, "tree")
        let report = try await h.run([index])
        #expect(report.warning(index) == "{1} names nothing in this tree.")
    }

    @Test func wiredNumbersAreIndices() async throws {
        var h = Harness()
        let source = h.source(count: 6)
        let which = h.add(SeriesNode.self, ["start": .number(1), "step": .number(2), "count": .integer(2)])  // 1, 3
        let cull = h.add(CullIndexNode.self)
        h.wire(source, to: cull, "tree")
        h.wire(which, "values", to: cull, "indices")
        let report = try await h.run([cull])
        #expect(report.positions(cull) == [[0, 2, 4, 5]])
    }

    @Test func wiredNumbersMustBeWholeAndNotNegative() async throws {
        for bad in [1.5, -1.0] {
            var h = Harness()
            let source = h.source(count: 4)
            let which = h.add(SeriesNode.self, ["start": .number(bad), "count": .integer(1)])
            let cull = h.add(CullIndexNode.self)
            h.wire(source, to: cull, "tree")
            h.wire(which, "values", to: cull, "indices")
            let report = try await h.run([cull])
            #expect(report.error(cull)?.hasPrefix("“indices” must be whole numbers from 0 up") == true, "\(bad)")
        }
    }

    @Test func anEmptyPathIsRefusedBecauseItWouldCullTheWholeTree() async throws {
        for text in ["{}", "1, { }"] {
            let (report, cull) = try await run(text, count: 4)
            #expect(report.error(cull) == "“{}” names the whole tree. To cull everything, use Cull Pattern with 0.", "\(text)")
        }
    }

    @Test func textThatIsNotAnIndexOrAPathNamesItself() async throws {
        let (report, cull) = try await run("1, x, 3")
        #expect(report.error(cull) == "“x” isn't an index or a path. Write indices like 3 and paths like {0;3}, separated by commas.")
        let (negative, negativeCull) = try await run("-2")
        #expect(negative.error(negativeCull)?.hasPrefix("“-2” isn't an index or a path.") == true)
        let (open, openCull) = try await run("{0;3")
        #expect(open.error(openCull)?.hasPrefix("“{0;3” isn't an index or a path.") == true)
    }

    @Test func itCullsAnyKindOfItem() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self, ["countX": .integer(3), "countY": .integer(1)])
        let cull = h.add(CullIndexNode.self, [NodeSetting.cullIndices: .text("0")])
        h.wire(grid, "points", to: cull, "tree")
        let report = try await h.run([cull])
        #expect(report.value(cull, "tree")?.vectors?.count == 2)
        #expect(report.positions(cull) == [[1, 2]])
    }

    @Test func theNodeStartsWithNothingToCull() {
        let node = BuiltInNodes.registry.makeNode(CullIndexNode.typeID)
        #expect(node.inputValues[NodeSetting.cullIndices] == .text(""))
    }
}

import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import Testing

/// Points to Placements takes its points whole and gives back placements with the same paths (patterns spec §4, User decision
/// U15), so a cull anywhere before it, on the Grid Points say, numbers the instances as a cull of the placements would.
struct PointsToPlacementsCullTests {
    let kernel = FakeKernel()

    /// The inputs the evaluator would hand the node: every socket's default unless `given` sets it.
    func inputs(_ given: [SocketName: Value]) -> NodeInputs {
        var values: [SocketName: Value] = given
        for spec in PointsToPlacementsNode.inputs where values[spec.name] == nil {
            if let constant = spec.defaultValue, let scalar = Scalar(constant) { values[spec.name] = .one(scalar) }
        }
        return BroadcastPlan.make(inputs: values, specs: PointsToPlacementsNode.inputs).inputs(at: 0)
    }

    func context() -> EvalContext {
        EvalContext(node: BuiltInNodes.registry.makeNode(PointsToPlacementsNode.typeID), item: 0, parameters: [:])
    }

    func point(_ index: Int) -> Scalar { .vector(Vector3(Double(index) * 20, 0, 0)) }

    /// Points at x = 0, 20, 40, 60 with the ones in `kept` left, as a Cull node leaves them.
    func culledPoints(_ kept: [Int]) throws -> Value {
        Value(try #require(DataTree.culledList(kept.map(point), at: kept)))
    }

    @Test func pointsToPlacementsKeepsACulledListsIndices() async throws {
        let outputs = try await PointsToPlacementsNode.evaluate(inputs(["points": try culledPoints([1, 2, 3])]), kernel: kernel,
                                                                context: context())
        let tree = try #require(outputs.trees["placements"])
        #expect(tree.itemPositions == [1, 2, 3], "the first survivor is still {1}, not {0}")
        #expect(Value(tree).planes?.map(\.origin.x) == [20, 40, 60])
        #expect(outputs.warnings.isEmpty)
    }

    @Test func aCulledDirectionListIsReadByTheInstancesIndexAndSetsNoNumberOfPlacements() async throws {
        let directions = try #require(DataTree.culledList([.vector(.unitX), .vector(.unitY)], at: [0, 2]))
        let points = Value.list((0..<3).map(point))
        let outputs = try await PointsToPlacementsNode.evaluate(inputs(["points": points, "direction": Value(directions)]),
                                                                kernel: kernel, context: context())
        let tree = try #require(outputs.trees["placements"])
        let planes = try #require(Value(tree).planes)
        #expect(planes.count == 3, "three points, three placements")
        #expect(zip(planes.map(\.normal), [Vector3.unitX, .unitX, .unitY]).allSatisfy { isClose($0, $1) }, "{1} takes {0}'s direction")
    }

    @Test func aCullThatRemovesEveryPointMakesAnEmptyCulledListOfPlacements() async throws {
        let outputs = try await PointsToPlacementsNode.evaluate(inputs(["points": try culledPoints([])]), kernel: kernel,
                                                                context: context())
        let tree = try #require(outputs.trees["placements"])
        #expect(tree.isCulled && tree.itemCount == 0)
    }

    @Test func aTreeOfPointsIsATreeOfPlacementsAtTheSamePaths() async throws {
        let rows = try #require(DataTree(depth: 2, branches: [.list((0..<3).map(point)), .list((3..<5).map(point))]))
        let culled = rows.keepingItems { leaf, _, k in !(leaf.path == TreePath([0]) && k == 1) }
        let outputs = try await PointsToPlacementsNode.evaluate(inputs(["points": Value(culled)]), kernel: kernel, context: context())
        let tree = try #require(outputs.trees["placements"])
        #expect(tree.depth == 2)
        #expect(tree.leaves.map(\.positions) == [[0, 2], [0, 1]], "{0;2} is still {0;2}")
        #expect(Value(tree).planes?.map(\.origin.x) == [0, 40, 60, 80])
    }

    @Test func aDirectionPerRowIsMatchedToTheRowsOfPoints() async throws {
        let rows = try #require(DataTree(depth: 2, branches: [.list((0..<2).map(point)), .list((2..<4).map(point))]))
        let facing = try #require(DataTree(depth: 2, branches: [.list([.vector(.unitX)]), .list([.vector(.unitY)])]))
        let outputs = try await PointsToPlacementsNode.evaluate(inputs(["points": .tree(rows), "direction": .tree(facing)]),
                                                                kernel: kernel, context: context())
        let tree = try #require(outputs.trees["placements"])
        let planes = try #require(Value(tree).planes)
        #expect(zip(planes.map(\.normal), [Vector3.unitX, .unitX, .unitY, .unitY]).allSatisfy { isClose($0, $1) })
    }

    @Test func aZeroDirectionOnACulledPointNamesItsPath() async throws {
        let directions = try #require(DataTree.culledList([.vector(.unitZ), .vector(.zero)], at: [0, 5]))
        let given = inputs(["points": .list((0..<6).map(point)), "direction": Value(directions)])
        await #expect(throws: NodeError.invalidValue("The direction of placement {5} can't be zero.")) {
            _ = try await PointsToPlacementsNode.evaluate(given, kernel: kernel, context: context())
        }
    }

    @Test func aPlainListOfPointsStillMakesAPlainListOfPlacements() async throws {
        let outputs = try await PointsToPlacementsNode.evaluate(inputs(["points": .list((0..<3).map(point))]), kernel: kernel,
                                                                context: context())
        let tree = try #require(outputs.trees["placements"])
        #expect(!tree.isCulled && tree.depth == 1 && tree.itemCount == 3)
    }
}

import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Testing

/// Culling keeps paths (patterns spec §4, §6): an instance whose placement survived a cull keeps its path in its tags,
/// its messages and its tool, so a pick on it follows it. Place and the shortcuts read culled placements here; the
/// Cull nodes that make them have their own tests.
struct CulledInstancesTests {
    #if canImport(CreatorOCCT)
    let kernel = OCCTKernel()
    #endif

    func plane(_ x: Double) -> Plane { .through(Vector3(x, 0, 0)) }

    /// Placements at x = 0, 20, 40, 60 with the instances in `kept` left, as a Cull node leaves them.
    func culled(_ kept: [Int]) throws -> Value {
        let tree = try #require(DataTree.culledList(kept.map { .plane(plane(Double($0) * 20)) }, at: kept))
        return Value(tree)
    }

    func plain(_ count: Int) -> Value { .list((0..<count).map { .plane(plane(Double($0) * 20)) }) }

    #if canImport(CreatorOCCT)
    func block(height: Double = 10) async throws -> Solid {
        try await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: height, mode: .oneSided,
                                 tag: NodeTag(node: NodeID(), item: 0))
    }
    #endif

    /// The inputs the evaluator would hand a node: every socket's default unless `given` sets it.
    func inputs(_ definition: any NodeDefinition.Type, _ given: [SocketName: Value]) -> NodeInputs {
        var values: [SocketName: Value] = given
        for spec in definition.inputs where values[spec.name] == nil {
            if let constant = spec.defaultValue, let scalar = Scalar(constant) { values[spec.name] = .one(scalar) }
        }
        return BroadcastPlan.make(inputs: values, specs: definition.inputs).inputs(at: 0)
    }

    func context(_ definition: any NodeDefinition.Type) -> EvalContext {
        EvalContext(node: BuiltInNodes.registry.makeNode(definition.typeID), item: 0, parameters: [:])
    }

    /// The solid a shortcut node made.
    func resultSolid(_ outputs: NodeOutputs) throws -> Solid {
        guard case .solid(let solid)? = outputs.values["solid"] else { throw NodeError.invalidValue("The node made no solid.") }
        return solid
    }

    /// The copies of a Place that left its copies as a culled tree.
    func copies(_ outputs: NodeOutputs) throws -> [Solid] {
        let tree = try #require(outputs.trees["solids"])
        return try #require(Value(tree).solids)
    }

    func items(of solid: Solid) -> Set<Int> {
        Set(solid.topology.faces.flatMap(\.tags).filter(\.node.isInstanceQualified).map(\.item))
    }

    #if canImport(CreatorOCCT)
    // MARK: Place

    @Test func placeTagsEachCopyWithItsOriginalIndex() async throws {
        let tool = try await block()
        let given = inputs(PlaceNode.self, ["tool": .one(.solid(tool)), "placements": try culled([0, 2, 3])])
        let outputs = try await PlaceNode.evaluate(given, kernel: kernel, context: context(PlaceNode.self))
        let copies = try copies(outputs)
        #expect(copies.map { items(of: $0) } == [[0], [2], [3]])
        #expect(zip(copies.map(\.bounds.min.x), [-5, 35, 55]).allSatisfy { isClose($0, $1) }, "each copy stands on its own placement")
    }

    @Test func placeOutputsCulledCopiesAtTheirPaths() async throws {
        let outputs = try await PlaceNode.evaluate(
            inputs(PlaceNode.self, ["tool": .one(.solid(try await block())), "placements": try culled([1, 3])]),
            kernel: kernel, context: context(PlaceNode.self))
        let tree = try #require(outputs.trees["solids"])
        #expect(tree.itemPositions == [1, 3])
        #expect(tree.isCulled)
    }

    @Test func placeWithPlainPlacementsIsUnchanged() async throws {
        let outputs = try await PlaceNode.evaluate(
            inputs(PlaceNode.self, ["tool": .one(.solid(try await block())), "placements": plain(3)]),
            kernel: kernel, context: context(PlaceNode.self))
        let tree = try #require(outputs.trees["solids"])
        #expect(!tree.isCulled, "nothing was culled, so nothing is marked")
        #expect(try copies(outputs).map { items(of: $0) } == [[0], [1], [2]])
    }

    @Test func aSurvivingInstanceKeepsItsOwnTool() async throws {
        let tools = try await [block(height: 5), block(height: 6), block(height: 7), block(height: 8)]
        let outputs = try await PlaceNode.evaluate(
            inputs(PlaceNode.self, ["tool": .list(tools.map(Scalar.solid)), "placements": try culled([1, 3])]),
            kernel: kernel, context: context(PlaceNode.self))
        let copies = try copies(outputs)
        #expect(zip(copies.map(\.bounds.max.z), [6, 8]).allSatisfy { isClose($0, $1) }, "{1} has the second tool, {3} the fourth")
    }

    @Test func aLongerToolListAddsNoInstancesToCulledPlacements() async throws {
        let tools = try await [block(), block(), block(), block(), block()]
        let outputs = try await PlaceNode.evaluate(
            inputs(PlaceNode.self, ["tool": .list(tools.map(Scalar.solid)), "placements": try culled([0, 1])]),
            kernel: kernel, context: context(PlaceNode.self))
        #expect(try #require(outputs.trees["solids"]).itemCount == 2, "what was culled off the end stays gone")
    }

    @Test func aBadCulledPlacementNamesItsOwnPath() async throws {
        let bad = Plane(origin: .zero, normal: .zero, xAxis: .unitX)
        let tree = try #require(DataTree.culledList([.plane(plane(0)), .plane(bad)], at: [0, 5]))
        let given = inputs(PlaceNode.self, ["tool": .one(.solid(try await block())), "placements": Value(tree)])
        var message: String?
        do {
            _ = try await PlaceNode.evaluate(given, kernel: kernel, context: context(PlaceNode.self))
        } catch let error as NodeError {
            message = error.message
        }
        #expect(message?.hasPrefix("Placement {5} has no usable direction") == true, "got \(String(describing: message))")
    }

    @Test func aCulledSizeListLongerThanThePlacementsMakesNoExtraHoles() async throws {
        let sizes = try #require(DataTree.culledList(Array(repeating: Scalar.number(5), count: 10), at: Array(10..<20)))
        let given = inputs(HolePatternNode.self, [
            "part": .one(.solid(try await plate())), "placements": plain(4), "diameter": Value(sizes),
        ])
        let outputs = try await HolePatternNode.evaluate(given, kernel: kernel, context: context(HolePatternNode.self))
        #expect(items(of: try resultSolid(outputs)) == [0, 1, 2, 3], "four placements, four holes, all of {10}'s size")
    }

    @Test func aCulledSizeListWithNothingLeftMakesNoHoles() async throws {
        let part = try await plate()
        let none = try #require(DataTree.culledList([], at: []))
        let given = inputs(HolePatternNode.self, ["part": .one(.solid(part)), "placements": plain(3), "diameter": Value(none)])
        let outputs = try await HolePatternNode.evaluate(given, kernel: kernel, context: context(HolePatternNode.self))
        #expect(try resultSolid(outputs) === part)
        #expect(outputs.warnings.isEmpty)
    }

    @Test func aCulledToolListGivesEachSurvivorItsOwnTool() async throws {
        let tools = try await [block(height: 5), block(height: 6), block(height: 7)]
        let toolTree = try #require(DataTree.culledList(tools.map(Scalar.solid), at: [1, 2, 3]))
        let outputs = try await PlaceNode.evaluate(
            inputs(PlaceNode.self, ["tool": Value(toolTree), "placements": plain(4)]),
            kernel: kernel, context: context(PlaceNode.self))
        let placed = try copies(outputs)
        #expect(zip(placed.map(\.bounds.max.z), [5, 5, 6, 7]).allSatisfy { isClose($0, $1) }, "{0} has no tool of its own: the first")
        #expect(placed.count == 4, "a culled tool list sets no number of instances")
    }

    @Test func aCulledSizeListIsReadByTheInstancesIndex() async throws {
        let sizes = try #require(DataTree.culledList([.number(5), .number(-1)], at: [0, 3]))
        let given = inputs(HolePatternNode.self, [
            "part": .one(.solid(try await plate())), "placements": plain(4), "diameter": Value(sizes),
        ])
        var message: String?
        do {
            _ = try await HolePatternNode.evaluate(given, kernel: kernel, context: context(HolePatternNode.self))
        } catch let error as NodeError {
            message = error.message
        }
        #expect(message == "Hole {3}: the diameter must be greater than 0 mm.", "{1} and {2} took {0}'s 5 mm; {3} its own")
    }

    // MARK: the shortcuts

    /// A 160 × 40 × 6 plate standing on z = −6…0, so placements on z = 0 lie on its top face.
    func plate() async throws -> Solid {
        try await kernel.extrude(.rectangle(width: 160, height: 40, plane: .through(Vector3(0, 0, -6))), distance: 6, mode: .oneSided,
                                 tag: NodeTag(node: NodeID(), item: 0))
    }

    @Test func aHolePatternKeepsEachSurvivorsIndexAndDoesntCountTheCulledAsMissing() async throws {
        let part = try await plate()
        let outputs = try await HolePatternNode.evaluate(
            inputs(HolePatternNode.self, ["part": .one(.solid(part)), "placements": try culled([0, 2, 3])]),
            kernel: kernel, context: context(HolePatternNode.self))
        let solid = try resultSolid(outputs)
        #expect(items(of: solid) == [0, 2, 3], "got \(items(of: solid).sorted())")
        #expect(outputs.warnings.isEmpty, "no hole on {1} to miss the part: \(outputs.warnings)")
    }

    /// Hole sizes where only {1} is unusable.
    func holes(keeping kept: [Int]) async throws -> NodeInputs {
        let diameters = Value.list([5, -1, 5, 5].map { .number($0) })
        return inputs(HolePatternNode.self, [
            "part": .one(.solid(try await plate())), "placements": try culled(kept), "diameter": diameters,
        ])
    }

    @Test func aHolePatternReadsASizeByTheInstancesIndexAndNamesItsPath() async throws {
        var message: String?
        do {
            _ = try await HolePatternNode.evaluate(try await holes(keeping: [1, 3]), kernel: kernel,
                                                   context: context(HolePatternNode.self))
        } catch let error as NodeError {
            message = error.message
        }
        #expect(message == "Hole {1}: the diameter must be greater than 0 mm.")
    }

    @Test func aCulledInstancesSizeIsNeverRead() async throws {
        let outputs = try await HolePatternNode.evaluate(try await holes(keeping: [0, 2, 3]), kernel: kernel,
                                                         context: context(HolePatternNode.self))
        let solid = try resultSolid(outputs)
        #expect(items(of: solid) == [0, 2, 3], "got \(items(of: solid).sorted())")
    }

    @Test func aBossAndASlotAndAFeatureKeepIndicesToo() async throws {
        let part = try await plate()
        let placements = try culled([2, 3])
        for definition in [BossPatternNode.self, SlotPatternNode.self] as [any NodeDefinition.Type] {
            let outputs = try await definition.evaluate(inputs(definition, ["part": .one(.solid(part)), "placements": placements]),
                                                        kernel: kernel, context: context(definition))
            let solid = try resultSolid(outputs)
            #expect(items(of: solid) == [2, 3], "\(definition.typeID)")
        }
        let tool = try await block()
        let featureInputs = inputs(PatternFeatureNode.self, [
            "part": .one(.solid(part)), "tool": .one(.solid(tool)), "placements": placements,
        ])
        let feature = try await PatternFeatureNode.evaluate(featureInputs, kernel: kernel, context: context(PatternFeatureNode.self))
        let solid = try resultSolid(feature)
        #expect(items(of: solid) == [2, 3], "got \(items(of: solid).sorted())")
    }

    @Test func aCullThatRemovesEveryPlacementLeavesThePartAloneAndMakesNoCopies() async throws {
        let part = try await plate()
        let holes = try await HolePatternNode.evaluate(
            inputs(HolePatternNode.self, ["part": .one(.solid(part)), "placements": try culled([])]),
            kernel: kernel, context: context(HolePatternNode.self))
        #expect(try resultSolid(holes) === part)
        #expect(holes.warnings.isEmpty)
        let placed = try await PlaceNode.evaluate(
            inputs(PlaceNode.self, ["tool": .one(.solid(try await block())), "placements": try culled([])]),
            kernel: kernel, context: context(PlaceNode.self))
        #expect(try #require(placed.trees["solids"]).itemCount == 0)
    }

    @Test func aPlainPatternStillNumbersFromZero() async throws {
        let outputs = try await HolePatternNode.evaluate(
            inputs(HolePatternNode.self, ["part": .one(.solid(try await plate())), "placements": plain(3)]),
            kernel: kernel, context: context(HolePatternNode.self))
        let solid = try resultSolid(outputs)
        #expect(items(of: solid) == [0, 1, 2], "got \(items(of: solid).sorted())")
    }
    #endif

    // MARK: trees

    /// Two rows of three placements, 20 mm apart along x and 20 mm along y, with `culling` taken out as a Cull node would.
    func rows(culling drop: (DataTree.Leaf, Int) -> Bool = { _, _ in false }) throws -> Value {
        let branches = (0..<2).map { row in
            DataTree.list((0..<3).map { .plane(.through(Vector3(Double($0) * 20, Double(row) * 20, 0))) })
        }
        let tree = try #require(DataTree(depth: 2, branches: branches))
        return Value(tree.keepingItems { leaf, _, k in !drop(leaf, k) })
    }

    func paths(of solid: Solid) -> Set<[Int]> {
        Set(items(of: solid).compactMap { InstancePath.indices(ofItem: $0) })
    }

    #if canImport(CreatorOCCT)
    @Test func aCulledTreeOfPlacementsKeepsEveryTreePath() async throws {
        let placements = try rows { leaf, k in leaf.path == TreePath([0]) && k == 1 }
        let outputs = try await HolePatternNode.evaluate(
            inputs(HolePatternNode.self, ["part": .one(.solid(try await plate())), "placements": placements]),
            kernel: kernel, context: context(HolePatternNode.self))
        let solid = try resultSolid(outputs)
        #expect(paths(of: solid) == [[0, 0], [0, 2], [1, 0], [1, 1], [1, 2]], "{0;2} is still {0;2}, and {0;1} is gone")
        #expect(outputs.warnings.isEmpty, "\(outputs.warnings)")
    }

    @Test func aWholeBranchCulledLeavesTheOtherBranchesNumbersAlone() async throws {
        let placements = try rows { leaf, _ in leaf.path == TreePath([0]) }
        let outputs = try await HolePatternNode.evaluate(
            inputs(HolePatternNode.self, ["part": .one(.solid(try await plate())), "placements": placements]),
            kernel: kernel, context: context(HolePatternNode.self))
        #expect(paths(of: try resultSolid(outputs)) == [[1, 0], [1, 1], [1, 2]])
    }

    @Test func placeOnACulledTreeGivesCopiesBackInTheSameGaps() async throws {
        let placements = try rows { leaf, k in leaf.path == TreePath([1]) && k == 0 }
        let outputs = try await PlaceNode.evaluate(
            inputs(PlaceNode.self, ["tool": .one(.solid(try await block())), "placements": placements]),
            kernel: kernel, context: context(PlaceNode.self))
        let tree = try #require(outputs.trees["solids"])
        #expect(tree.leaves.map(\.positions) == [[0, 1, 2], [1, 2]])
        #expect(try copies(outputs).map { paths(of: $0) } == [[[0, 0]], [[0, 1]], [[0, 2]], [[1, 1]], [[1, 2]]])
    }

    @Test func aSizePerRowAndACullTogetherReadTheRowsSizeAtTheInstancesPlace() async throws {
        let placements = try rows { _, k in k == 0 }
        let diameters = try #require(DataTree(depth: 2, branches: [.list([.number(4)]), .list([.number(-1)])]))
        let given = inputs(HolePatternNode.self, [
            "part": .one(.solid(try await plate())), "placements": placements, "diameter": Value(diameters),
        ])
        var message: String?
        do {
            _ = try await HolePatternNode.evaluate(given, kernel: kernel, context: context(HolePatternNode.self))
        } catch let error as NodeError {
            message = error.message
        }
        #expect(message == "Hole {1;1}: the diameter must be greater than 0 mm.", "got \(String(describing: message))")
    }
    #endif
}

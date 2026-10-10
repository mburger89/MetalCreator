import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// A group node evaluates its definition's graph (groups spec §5).
struct GroupEvaluationTests {
    let doubler = Doubler()

    func evaluate(_ g: Graph, _ definitions: [GroupDefinition], demand: [Node],
                  evaluator: Evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())) async throws -> EvaluationReport {
        try await evaluator.evaluate(g, definitions: table(definitions), demand: Set(demand.map(\.id)))
    }

    /// "Quadrupler": two Doublers in a row.
    func quadrupler() -> (definition: GroupDefinition, first: Node, second: Node) {
        let first = instance(of: doubler.definition), second = instance(of: doubler.definition)
        let definition = define("Quadrupler", inputs: [SocketSpec("value", .number)], outputs: [SocketSpec("result", .number)],
                                nodes: [first, second]) { input, output in
            [link(input, "value", first, "value"), link(first, "result", second, "value"), link(second, "result", output, "result")]
        }
        return (definition, first, second)
    }

    @Test func aGroupNodeRunsItsDefinition() async throws {
        let constant = makeNode(ConstantNode.self, ["value": .number(3)])
        let wired = instance(of: doubler.definition), typed = instance(of: doubler.definition, ["value": .number(4)])
        let defaulted = instance(of: doubler.definition)
        let report = try await evaluate(graph([constant, wired, typed, defaulted], [link(constant, "value", wired, "value")]),
                                        [doubler.definition], demand: [wired, typed, defaulted])
        #expect(report.results[wired.id]?.outputs?["result"]?.numbers == [6])
        #expect(report.results[typed.id]?.outputs?["result"]?.numbers == [8])
        #expect(report.results[defaulted.id]?.outputs?["result"]?.numbers == [2], "the socket's default, 1")
        #expect(report.innerResults[[wired.id, doubler.add.id]]?.outputs?["sum"]?.numbers == [6])
    }

    @Test func listsPassThroughAndBroadcastInside() async throws {
        let list = makeNode(ListSourceNode.self, ["count": .integer(3)])
        let sum = makeNode(SumListNode.self)
        let summer = define("Summer", inputs: [SocketSpec("values", .number)], outputs: [SocketSpec("sum", .number)],
                            nodes: [sum]) { input, output in
            [link(input, "values", sum, "values"), link(sum, "sum", output, "sum")]
        }
        let summed = instance(of: summer), doubled = instance(of: doubler.definition)
        let report = try await evaluate(graph([list, summed, doubled], [
            link(list, "values", summed, "values"), link(list, "values", doubled, "value"),
        ]), [summer, doubler.definition], demand: [summed, doubled])
        #expect(report.results[summed.id]?.outputs?["sum"]?.numbers == [3], "the list reached Sum List whole")
        #expect(report.results[doubled.id]?.outputs?["result"]?.numbers == [0, 2, 4], "Add broadcast over it inside")
        #expect(report.results[doubled.id]?.outputs?["result"]?.isList == true)
    }

    @Test func groupsNest() async throws {
        let (quadrupler, first, second) = quadrupler()
        let node = instance(of: quadrupler, ["value": .number(5)])
        let report = try await evaluate(graph([node]), [doubler.definition, quadrupler], demand: [node])
        #expect(report.results[node.id]?.outputs?["result"]?.numbers == [20])
        #expect(report.innerResults[[node.id, first.id, doubler.add.id]]?.outputs?["sum"]?.numbers == [10])
        #expect(report.innerResults[[node.id, second.id, doubler.add.id]]?.outputs?["sum"]?.numbers == [20])
    }

    @Test func scopedIDsAreNameBasedAndDistinct() {
        let a = NodeID(), b = NodeID()
        #expect(NodeID.scoped([a, b]) == NodeID.scoped([a, b]))
        #expect(NodeID.scoped([a, b]) != NodeID.scoped([b, a]))
        #expect(NodeID.scoped([a]) != a)
        #expect(NodeID.scoped([a, b]) != NodeID.scoped([a]))
        #expect(NodeID.scoped([a, b]).rawValue.uuidString.dropFirst(14).first == "5", "a version-5 UUID")
    }

    @Test func eachInstanceTagsItsFacesWithItsOwnScopedID() async throws {
        let box = makeNode(BoxNode.self)
        let boxer = define("Boxer", outputs: [SocketSpec("solid", .solid)], nodes: [box]) { _, output in
            [link(box, "solid", output, "solid")]
        }
        let first = instance(of: boxer), second = instance(of: boxer)
        let report = try await evaluate(graph([first, second]), [boxer], demand: [first, second])
        for node in [first, second] {
            guard case .solid(let solid)? = report.results[node.id]?.outputs?["solid"]?.items.first else {
                Issue.record("expected a solid")
                return
            }
            let tags = solid.topology.faces.flatMap(\.tags)
            #expect(!tags.isEmpty)
            #expect(tags.allSatisfy { $0.node == NodeID.scoped([node.id, box.id]) })
        }
    }

    @Test func aPickInsideADefinitionNamesEachInstancesFaces() async throws {
        let box = pickRegistry.makeNode(BoxNode.typeID)
        var counter = pickRegistry.makeNode(FacePickCountNode.typeID)
        counter.inputValues[NodeSetting.face] = endCapPick(of: box.id)
        let counted = define("Counted", outputs: [SocketSpec("count", .number), SocketSpec("solid", .solid)],
                             nodes: [box, counter]) { _, output in
            [link(box, "solid", counter, "solid"), link(counter, "count", output, "count"), link(box, "solid", output, "solid")]
        }
        // Nested: a pick in "Outer" names the box inside its group node `inner` as Outer's own level reaches it.
        let inner = instance(of: counted)
        var outerCounter = pickRegistry.makeNode(FacePickCountNode.typeID)
        outerCounter.inputValues[NodeSetting.face] = endCapPick(of: NodeID.scoped([inner.id, box.id]))
        let outer = define("Outer", outputs: [SocketSpec("count", .number)], nodes: [inner, outerCounter]) { _, output in
            [link(inner, "solid", outerCounter, "solid"), link(outerCounter, "count", output, "count")]
        }

        let first = instance(of: counted), second = instance(of: counted), nested = instance(of: outer)
        let report = try await evaluate(graph([first, second, nested]), [counted, outer], demand: [first, second, nested],
                                        evaluator: Evaluator(registry: pickRegistry, kernel: FakeKernel()))
        #expect(report.results[first.id]?.outputs?["count"]?.numbers == [1], "the pick names this instance's end cap")
        #expect(report.results[second.id]?.outputs?["count"]?.numbers == [1], "and this one's")
        #expect(report.innerResults[[nested.id, inner.id, counter.id]]?.outputs?["count"]?.numbers == [1], "a nested one's")
        #expect(report.results[nested.id]?.outputs?["count"]?.numbers == [1], "a pick through a nested group")
    }

    @Test func renamingTagsReachesBlendSourceEdges() {
        let a = NodeID(), b = NodeID(), c = NodeID()
        let edge = EdgeKey([TopoTag(node: a, item: 0, role: .endCap)], [TopoTag(node: c, item: 0, role: .side(segment: 1))])
        let blend = TopoTag(node: c, item: 0, role: .blend(sourceEdge: edge))
        let pick = EdgePick(key: EdgeKey([blend], [TopoTag(node: a, item: 1, role: .startCap)]), matchCount: 2, ordinals: [1])
        let renamedEdge = EdgeKey([TopoTag(node: b, item: 0, role: .endCap)], [TopoTag(node: c, item: 0, role: .side(segment: 1))])
        let renamedBlend = TopoTag(node: c, item: 0, role: .blend(sourceEdge: renamedEdge))
        let renamedPick = EdgePick(key: EdgeKey([renamedBlend], [TopoTag(node: b, item: 1, role: .startCap)]), matchCount: 2,
                                   ordinals: [1])
        let picks = ConstantValue.edgePicks([pick]), renamed = ConstantValue.edgePicks([renamedPick])
        #expect(picks.renamingTags([a: b]) == renamed)
        #expect(endCapPick(of: a).renamingTags([a: b]) == endCapPick(of: b))
        #expect(ConstantValue.number(1).renamingTags([a: b]) == .number(1))
    }

    @Test func renamingTagsKeepsAFacePicksPosition() {
        let a = NodeID(), b = NodeID()
        let normal = Vector3(0, 0, 1), centroid = Vector3(1, 2, 3)
        let pick = FacePick(tags: [TopoTag(node: a, item: 0, role: .endCap)], normal: normal, centroid: centroid)
        let renamed = FacePick(tags: [TopoTag(node: b, item: 0, role: .endCap)], normal: normal, centroid: centroid)
        #expect(ConstantValue.facePick(pick).renamingTags([a: b]) == .facePick(renamed))
    }

    @Test func eachInstanceIsCachedOnItsOwnAndADefinitionEditRerunsThemAll() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        let first = instance(of: doubler.definition, ["value": .number(2)])
        let second = instance(of: doubler.definition, ["value": .number(3)])
        let g = graph([first, second])
        let opening = try await evaluate(g, [doubler.definition], demand: [first, second], evaluator: evaluator)
        #expect(Set(opening.evaluatedInnerNodes) == [[first.id, doubler.add.id], [second.id, doubler.add.id]])
        #expect(await evaluator.cachedEntryCount == 2)
        let again = try await evaluate(g, [doubler.definition], demand: [first, second], evaluator: evaluator)
        #expect(again.evaluatedNodes.isEmpty && again.evaluatedInnerNodes.isEmpty)
        #expect(again.results[second.id]?.outputs?["result"]?.numbers == [6])

        // Inside, Add's `b` is now 10 instead of a second copy of the input.
        var edited = doubler.definition
        edited.graph.links.removeAll { $0.to == Endpoint(node: doubler.add.id, socket: "b") }
        edited.graph.nodes[doubler.add.id]?.inputValues["b"] = .number(10)
        let after = try await evaluate(g, [edited], demand: [first, second], evaluator: evaluator)
        #expect(Set(after.evaluatedNodes) == [first.id, second.id])
        #expect(after.results[first.id]?.outputs?["result"]?.numbers == [12])
        #expect(after.results[second.id]?.outputs?["result"]?.numbers == [13])
        // Each instance's Add has an entry from before the edit (kept, so undo hits the cache) and one from after.
        #expect(await evaluator.cachedEntryCount == 4)

        // A group node that's gone takes its inner entries out of the cache.
        _ = try await evaluate(graph([first]), [edited], demand: [first], evaluator: evaluator)
        #expect(await evaluator.cachedEntryCount == 2)
    }

    @Test func cancellationIsHonouredBetweenNodesInsideAGroup() async throws {
        let kernel = FakeKernel()
        let canceller = makeNode(CancelsTaskNode.self), box = makeNode(BoxNode.self)
        let definition = define("Cancels", outputs: [SocketSpec("solid", .solid)], nodes: [canceller, box]) { _, output in
            [link(canceller, "value", box, "width"), link(box, "solid", output, "solid")]
        }
        let node = instance(of: definition)
        let evaluator = Evaluator(registry: testRegistry, kernel: kernel)
        let task = Task { try await evaluator.evaluate(graph([node]), definitions: table([definition]), demand: [node.id]) }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await kernel.operationLog.isEmpty)
    }

    @Test func innerFailuresAndWarningsCarryTheirPath() async throws {
        let fail = makeNode(FailNode.self), warn = makeNode(WarnNode.self)
        let failing = define("Rib", outputs: [SocketSpec("value", .number)], nodes: [fail]) { _, output in
            [link(fail, "value", output, "value")]
        }
        let warning = define("Careful rib", outputs: [SocketSpec("value", .number)], nodes: [warn]) { _, output in
            [link(warn, "value", output, "value")]
        }
        let inner = instance(of: failing)
        let outer = define("Bracket", outputs: [SocketSpec("value", .number)], nodes: [inner]) { _, output in
            [link(inner, "value", output, "value")]
        }
        let failed = instance(of: failing), warned = instance(of: warning), nested = instance(of: outer)
        let report = try await evaluate(graph([failed, warned, nested]), [failing, warning, outer],
                                        demand: [failed, warned, nested])
        #expect(report.results[failed.id]?.state == .error("Rib › Fail: Boom"))
        #expect(report.results[nested.id]?.state == .error("Bracket › Rib › Fail: Boom"))
        #expect(report.results[warned.id]?.state == .warning("Careful rib › Warn: Careful"))
        #expect(report.results[warned.id]?.outputs?["value"]?.numbers == [0])
    }

    @Test func aWaitingInnerNodeLeavesTheGroupWaiting() async throws {
        let required = makeNode(RequiredNode.self)
        let definition = define("Needy", outputs: [SocketSpec("value", .number)], nodes: [required]) { _, output in
            [link(required, "value", output, "value")]
        }
        let node = instance(of: definition)
        let report = try await evaluate(graph([node]), [definition], demand: [node])
        #expect(report.results[node.id]?.state == .idle("Needy › Required: Connect or set “value”."))
    }

    @Test func handEditedFilesFailPlainly() async throws {
        let orphan = instance(of: Doubler(name: "Gone").definition)
        var loop = GroupDefinition.make(name: "Loop", outputs: [SocketSpec("value", .number)], registry: testRegistry)
        let inside = testRegistry.withGroups(table([loop])).makeGroupNode(GroupNodes.groupTypeID, for: loop.id)
        loop.graph.nodes[inside.id] = inside
        if let output = loop.outputNode { loop.graph.links = [link(inside, "value", output, "value")] }
        let looping = instance(of: loop)
        let strayInput = testRegistry.makeGroupNode(GroupNodes.inputTypeID, for: loop.id)
        let report = try await evaluate(graph([orphan, looping, strayInput]), [loop], demand: [orphan, looping, strayInput])
        #expect(report.results[orphan.id]?.state == .error("This group's definition is missing."))
        #expect(report.results[looping.id]?.state == .error("Loop › “Loop” contains itself, so it can't be evaluated."))
        #expect(report.results[strayInput.id]?.state == .error("Group Input works only inside a group."))
    }
}

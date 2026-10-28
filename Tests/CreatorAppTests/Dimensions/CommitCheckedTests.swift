import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
@testable import CreatorViewport
import Testing
@testable import CreatorApp

/// A feature node that declares one dimension and waits at a gate while evaluating (DIM-3 Task 13).
enum GatedFeatureNode: NodeDefinition {
    static let typeID = "test.gatedFeature"
    static let displayName = "Gated Feature"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("size", .number, defaultValue: .number(10))]
    static let outputs = [SocketSpec("size", .number)]
    static let gate = AppGate()

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        try await gate.waitUntilOpen()
        let size = try inputs.number("size")
        var outputs = NodeOutputs(["size": .number(size)])
        let line = DimensionGeometry.linear(from: .zero, to: Vector3(size, 0, 0), direction: .unitX, side: .unitY,
                                            placement: .standoff)
        outputs.dimensions = [DimensionSpec(.input("size"), line, .length, value: size)]
        return outputs
    }
}

/// A feature node that evaluates with a warning.
enum WarningFeatureNode: NodeDefinition {
    static let typeID = "test.warningFeature"
    static let displayName = "Warning Feature"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("size", .number, defaultValue: .number(10))]
    static let outputs = [SocketSpec("size", .number)]

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["size": .number(try inputs.number("size"))], warnings: ["Careful"])
    }
}

/// An actor-isolated gate for `GatedFeatureNode`, opened and closed by the test.
actor AppGate {
    private var isOpen = false
    func open() { isOpen = true }
    func close() { isOpen = false }
    func waitUntilOpen() async throws {
        while !isOpen { try await Task.sleep(for: .milliseconds(5)) }
    }
}

/// `commitChecked`: one step, taken back with no redo when it makes a new error, never shown meanwhile (spec §7).
@MainActor
struct CommitCheckedTests {
    let radius: SocketName = "corner radius"

    func boxApp() async -> (app: AppModel, box: Node) {
        var builder = GraphBuilder()
        let box = builder.add(ImplicitBoxNode.self, ["size": .vector(Vector3(20, 20, 20))])
        builder.graph.nodes[box.id]?.isOutput = true
        let app = await makeApp(builder.graph)
        return (app, box)
    }

    func setRadius(_ box: Node, _ value: Double) -> GraphCommand { .setInput(box.id, radius, .number(value)) }

    @Test func anAcceptedValueIsOneChangeDimensionStep() async throws {
        let (app, box) = await boxApp()
        let pose = app.viewport.pose
        let outcome = await app.commitChecked(setRadius(box, 3), at: .root, name: UndoName.changeDimension)
        #expect(outcome == .accepted)
        await app.settle()
        #expect(app.document.undoName == UndoName.changeDimension)
        #expect(app.document.graph.nodes[box.id]?.inputValues[radius] == .number(3))
        #expect(app.viewport.pose == pose)
        #expect(!app.document.isHoldingResults)
    }

    @Test func aFailingValueIsTakenBackWithNoRedo() async throws {
        let (app, box) = await boxApp()
        try app.editor.edit(setRadius(box, 2), name: UndoName.changeDimension)
        await app.settle()
        let before = app.document.content
        let undoName = app.document.undoName
        let canRedo = app.document.canRedo
        let outcome = await app.commitChecked(setRadius(box, 30), at: .root, name: UndoName.changeDimension)
        #expect(outcome == .refused("Box: “corner radius” can't be more than half the smallest side."))
        await app.settle()
        #expect(app.document.content == before)
        #expect(app.document.canRedo == canRedo)
        #expect(app.document.undoName == undoName)
        #expect(!app.document.isHoldingResults)
        #expect(app.document.results[box.id]?.state.isSuccess == true)
    }

    @Test func aCommitThatMadeNoStepNeverJudgesAnOlderOne() async throws {
        let (app, box) = await boxApp()
        // An earlier step, accepted by the user, that has an error of its own.
        try app.document.perform(setRadius(box, 30), name: UndoName.changeDimension)
        await app.settle()
        let before = app.document.content
        let undoName = app.document.undoName
        app.sketchCheckBaseline = app.document.performCount  // a sketch commit begins, and performs no graph step
        let refusal = await app.checkLastStep()
        #expect(refusal == nil)
        #expect(app.document.content == before)
        #expect(app.document.undoName == undoName)
    }

    @Test func aRefusedValueNeverReachesTheViewport() async throws {
        let (app, box) = await boxApp()
        let generation = app.viewport.renderKey.sceneGeneration
        let items = app.viewport.items
        let outcome = await app.commitChecked(setRadius(box, 30), at: .root, name: UndoName.changeDimension)
        #expect(outcome != .accepted)
        await app.settle()
        #expect(app.viewport.renderKey.sceneGeneration == generation)
        #expect(ViewportItem.sameScene(app.viewport.items, items))
    }

    @Test func aWarningIsAccepted() async throws {
        let node = Node(typeID: WarningFeatureNode.typeID, name: "Warning Feature", isOutput: true)
        var graph = Graph()
        graph.nodes[node.id] = node
        let registry = NodeRegistry(BuiltInNodes.all + [WarningFeatureNode.self])
        let app = AppModel(kernel: FakeKernel(), registry: registry, file: GraphFile(graph: graph))
        await app.settle()
        let outcome = await app.commitChecked(.setInput(node.id, "size", .number(30)), at: .root, name: UndoName.changeDimension)
        #expect(outcome == .accepted)
        await app.settle()
        #expect(app.document.graph.nodes[node.id]?.inputValues["size"] == .number(30))
        #expect(app.document.undoName == UndoName.changeDimension)
        #expect(app.document.results[node.id]?.state == .warning("Careful"))
    }

    @Test func anEditInsideAGroupIsCheckedThroughItsGroupNode() async throws {
        var builder = GraphBuilder()
        let box = builder.add(ImplicitBoxNode.self, ["size": .vector(Vector3(20, 20, 20))])
        let offset = builder.add(ImplicitOffsetNode.self, at: Vector2(240, 0))
        builder.graph.nodes[offset.id]?.isOutput = true
        builder.wire(box, "implicit", to: offset, "implicit")
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.id]
        app.editor.groupSelection()
        await app.settle()
        let group = try #require(app.editor.selection.first)
        #expect(group != box.id)
        app.editor.enterGroup(group)
        await app.settle()
        let path = app.editor.graphPath
        #expect(path != .root)
        let before = app.document.content
        let outcome = await app.commitChecked(setRadius(box, 30), at: path, name: UndoName.changeDimension)
        let label = try #require(app.document.graph.nodes[group]).name
        guard case .refused(let message) = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
        #expect(message.hasPrefix("\(label): "), "the check names the top level's group node")
        await app.settle()
        #expect(app.document.content == before)
        #expect(app.document.undoName == UndoName.group)
        let good = await app.commitChecked(setRadius(box, 4), at: path, name: UndoName.changeDimension)
        #expect(good == .accepted)
        #expect(app.document.undoName == UndoName.changeDimension)
    }

    @Test func deletingTheNodeWhileCheckingClosesTheBox() async throws {
        await GatedFeatureNode.gate.open()
        var builder = GraphBuilder()
        let node = Node(typeID: GatedFeatureNode.typeID, name: "Gated Feature", isOutput: true)
        builder.graph.nodes[node.id] = node
        let registry = NodeRegistry(BuiltInNodes.all + [GatedFeatureNode.self])
        let app = AppModel(kernel: FakeKernel(), registry: registry, file: GraphFile(graph: builder.graph))
        await app.settle()
        await GatedFeatureNode.gate.close()
        let check = Task { await app.commitChecked(.setInput(node.id, "size", .number(30)), at: .root, name: UndoName.changeDimension) }
        while app.document.lastStep() == nil { await Task.yield() }
        try app.editor.edit(.removeNode(node.id), name: UndoName.delete)
        await GatedFeatureNode.gate.open()
        let outcome = await check.value
        #expect(outcome == .accepted)
        #expect(app.document.graph.nodes[node.id] == nil)
        #expect(!app.document.isHoldingResults)
        #expect(app.document.undoName == UndoName.delete)
    }
}

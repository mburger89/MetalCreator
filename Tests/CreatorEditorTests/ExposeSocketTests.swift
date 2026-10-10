import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Dropping a wire on Group Output's "+" and dragging from Group Input's "+" expose sockets, one undo step each
/// (groups spec §6).
@MainActor
struct ExposeSocketTests {
    /// The level inside the group at zoom 1, so sockets are a full row apart and a drop lands on the socket aimed at.
    func inside() throws -> (GroupedEditor, EditorModel, input: Node, output: Node) {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.transform = CanvasTransform()
        return (grouped, editor, try #require(grouped.definition.inputNode), try #require(grouped.definition.outputNode))
    }

    @Test func droppingAnOutputOnGroupOutputsPlusExposesANewOutput() throws {
        let (grouped, editor, _, output) = try inside()
        let from = editor.screenPoint(of: grouped.rectangle.id, "profile", input: false)
        editor.drag(from, editor.screenPoint(of: output.id, "+", input: true))
        let definition = try #require(grouped.current)
        #expect(definition.outputs.map(\.name) == ["solid", "profile"])
        #expect(definition.outputs.last?.type == .profile)
        #expect(definition.graph.links.contains(wire(grouped.rectangle, "profile", output, "profile")))
        let node = try #require(editor.rootGraph.nodes[grouped.group])
        #expect(editor.registry.outputs(for: node).map(\.name) == ["solid", "profile"], "the group node has it too")
        editor.perform(.undo)
        #expect(grouped.current == grouped.definition, "one undo step")
    }

    @Test func draggingFromGroupInputsPlusOntoAnInputExposesANewInput() throws {
        let (grouped, editor, input, _) = try inside()
        let from = editor.screenPoint(of: input.id, "+", input: false)
        editor.drag(from, editor.screenPoint(of: grouped.extrude.id, "distance", input: true))
        let definition = try #require(grouped.current)
        #expect(definition.inputs.map(\.name) == ["width", "distance"])
        #expect(definition.graph.links.contains(wire(input, "distance", grouped.extrude, "distance")))
        #expect(definition.inputs.last?.defaultValue == .number(10), "it keeps the target's default")
        editor.perform(.undo)
        #expect(grouped.current == grouped.definition)
    }

    @Test func theWireCanBeDraggedEitherWayRound() throws {
        let (grouped, editor, input, output) = try inside()
        editor.drag(editor.screenPoint(of: output.id, "+", input: true),
                    editor.screenPoint(of: grouped.rectangle.id, "profile", input: false))
        editor.drag(editor.screenPoint(of: grouped.extrude.id, "distance", input: true),
                    editor.screenPoint(of: input.id, "+", input: false))
        #expect(grouped.current?.outputs.map(\.name) == ["solid", "profile"])
        #expect(grouped.current?.inputs.map(\.name) == ["width", "distance"])
    }

    @Test func aDropThatMakesNoSenseIsRefusedAndChangesNothing() throws {
        let (grouped, editor, input, output) = try inside()
        // An output onto Group Input's + (both are outputs), and an input onto Group Output's + (both are inputs).
        editor.drag(editor.screenPoint(of: grouped.rectangle.id, "profile", input: false),
                    editor.screenPoint(of: input.id, "+", input: false))
        #expect(editor.refusal?.message == EditorModel.exposeHint)
        editor.clearRefusal()
        editor.drag(editor.screenPoint(of: grouped.extrude.id, "distance", input: true),
                    editor.screenPoint(of: output.id, "+", input: true))
        #expect(editor.refusal?.message == EditorModel.exposeHint)
        editor.clearRefusal()
        editor.drag(editor.screenPoint(of: input.id, "+", input: false), editor.screenPoint(of: output.id, "+", input: true))
        #expect(editor.refusal?.message == EditorModel.exposeHint, "plus to plus")
        #expect(grouped.current == grouped.definition)
    }

    @Test func aNewSocketGetsAUniqueNameAndTheDropIsRepeatable() throws {
        let (grouped, editor, _, output) = try inside()
        let from = editor.screenPoint(of: grouped.rectangle.id, "profile", input: false)
        editor.drag(from, editor.screenPoint(of: output.id, "+", input: true))
        editor.drag(from, editor.screenPoint(of: output.id, "+", input: true))
        #expect(grouped.current?.outputs.map(\.name) == ["solid", "profile", "profile2"])
    }

    /// Only Group Input's and Group Output's "+" is the expose socket; a node whose type is missing keeps whatever sockets
    /// its wires name, one of them possibly called "+", and a wire dragged from that is refused as any wire from such a node.
    @Test func aMissingNodesPlusSocketIsNotTheExposeSocket() {
        let first = testNode(NumberTestNode.self, id: 1, at: Vector2(300, 0))
        let second = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 200))
        var gone = Node(id: nodeID(3), typeID: "plugin.gone", name: "Gone")
        gone.position = .zero
        let editor = makeEditor([first, second, gone], [wire(gone, "+", first, "value")])
        editor.transform = CanvasTransform()
        editor.drag(editor.screenPoint(of: gone.id, "+", input: false), editor.screenPoint(of: second.id, "value", input: true))
        #expect(editor.refusal?.message == "That node's type isn't available, so it can't be wired.")
        #expect(editor.refusal?.node == second.id)
        #expect(editor.graph.links == [wire(gone, "+", first, "value")])
    }

    @Test func plusIsOnlyGroupInputsOrOutputsSocket() throws {
        let (grouped, editor, input, output) = try inside()
        #expect(editor.isPlus(SocketRef(Endpoint(node: input.id, socket: "+"), isInput: false)))
        #expect(editor.isPlus(SocketRef(Endpoint(node: output.id, socket: "+"), isInput: true)))
        #expect(!editor.isPlus(SocketRef(Endpoint(node: grouped.rectangle.id, socket: "+"), isInput: true)))
        #expect(!editor.isPlus(SocketRef(Endpoint(node: nodeID(99), socket: "+"), isInput: true)))
    }
}

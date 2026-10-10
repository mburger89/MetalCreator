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
}

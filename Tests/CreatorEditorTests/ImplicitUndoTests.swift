import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorEditor

/// The new inputs of 7c-1 are edited like any other: one undo step each, named by the input's fixed label.
@MainActor
struct ImplicitUndoTests {
    let mesh = testNode(MeshNode.self, id: 1, at: .zero, registry: BuiltInNodes.registry)
    let sphere = testNode(ImplicitSphereNode.self, id: 2, at: .zero, registry: BuiltInNodes.registry)
    let place = testNode(PlaceNode.self, id: 3, at: .zero, registry: BuiltInNodes.registry)

    private func field(_ editor: EditorModel, socket: SocketName) throws -> InputField {
        let rows = editor.inspectorPage.sections.flatMap(\.rows)
        for row in rows {
            switch row {
            case .slider(let field, _), .number(let field), .integer(let field):
                if field.socket == socket { return field }
            default:
                continue
            }
        }
        throw UndoFixtureError.noField(socket)
    }

    @Test func aPreviewResolutionEditIsOneNamedUndoStep() throws {
        let editor = makeEditor([mesh], registry: BuiltInNodes.registry)
        editor.selection = [mesh.id]
        let field = try field(editor, socket: "preview resolution")
        for value in [0.2, 0.3, 0.4] { editor.setInput(field, to: .number(value), continuous: true) }
        #expect(editor.graph.nodes[mesh.id]?.inputValues["preview resolution"] == .number(0.4))
        #expect(editor.document.undoName == "Change \(field.label)")
        editor.document.undo()
        #expect(editor.graph.nodes[mesh.id]?.inputValues["preview resolution"] == nil, "the drag was one step")
        #expect(!editor.document.canUndo)
    }

    @Test func anExportResolutionEditIsItsOwnStep() throws {
        let editor = makeEditor([mesh], registry: BuiltInNodes.registry)
        editor.selection = [mesh.id]
        let field = try field(editor, socket: "export resolution")
        editor.setInput(field, to: .number(0.2))
        editor.setInput(field, to: .number(0.3))
        editor.document.undo()
        #expect(editor.graph.nodes[mesh.id]?.inputValues["export resolution"] == .number(0.2))
        editor.document.undo()
        #expect(!editor.document.canUndo)
    }

    @Test func wiringAnImplicitIntoPlaceIsOneStepAndUndoesCleanly() {
        let editor = makeEditor([sphere, place], registry: BuiltInNodes.registry)
        editor.connect(wire(sphere, "implicit", place, "implicit"))
        #expect(editor.document.undoName == "Connect")
        #expect(editor.graph.links.count == 1)
        editor.document.undo()
        #expect(editor.graph.links.isEmpty && !editor.document.canUndo)
        editor.document.redo()
        #expect(editor.graph.links.count == 1)
    }
}

private enum UndoFixtureError: Error {
    case noField(SocketName)
}

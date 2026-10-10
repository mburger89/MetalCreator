import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Every edit the graph editor makes names its undo step (named undo steps; groups-and-comments spec §7): the name
/// Undo and Redo show in the Edit menu and the top bar.
@MainActor
struct EditorUndoNameTests {
    let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
    let extrude = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
    let output = testNode(OutputTestNode.self, id: 3, at: Vector2(600, 0))
    let sticky = note(1, at: Vector2(300, 300))
    let frame = box(2, at: Vector2(50, 400), size: Vector2(200, 150))

    func chain() -> EditorModel {
        makeEditor([rect, extrude, output], [wire(rect, "profile", extrude, "profile"), wire(extrude, "solid", output, "solid")],
                   stickies: [sticky], frames: [frame])
    }

    func widthField(_ editor: EditorModel) throws -> InputField {
        editor.selection = [rect.id]
        guard case .slider(let field, _)? = editor.inspectorPage.sections.first?.rows.first else {
            throw UndoNameFixtureError.noSlider
        }
        return field
    }

    // MARK: Nodes and wires

    @Test func addingANodeNamesItAfterItsType() {
        let editor = makeEditor([])
        editor.addFromLibrary(NumberTestNode.typeID)
        #expect(editor.document.undoName == "Add \(NumberTestNode.displayName)")
        _ = editor.addNode(RectangleTestNode.typeID, atScreen: Vector2(50, 50))
        #expect(editor.document.undoName == "Add \(RectangleTestNode.displayName)")
    }

    @Test func connectingAndDisconnecting() {
        let editor = makeEditor([rect, extrude])
        editor.connect(wire(rect, "profile", extrude, "profile"))
        #expect(editor.document.undoName == "Connect")
        editor.drag(editor.screenPoint(of: extrude.id, "profile", input: true), Vector2(900, 900))
        #expect(editor.document.undoName == "Disconnect")
        editor.document.undo()
        #expect(editor.document.undoName == "Connect" && editor.document.redoName == "Disconnect")
    }

    @Test func deleteCutPasteAndDuplicate() {
        let editor = chain()
        editor.selection = [extrude.id]
        editor.deleteSelection()
        #expect(editor.document.undoName == "Delete")
        editor.selection = [rect.id]
        editor.cutSelection()
        #expect(editor.document.undoName == "Cut")
        editor.paste()
        #expect(editor.document.undoName == "Paste")
        editor.duplicateSelection()
        #expect(editor.document.undoName == "Duplicate")
    }

    @Test func anOptionDragIsADuplicate() {
        let editor = chain()
        editor.selection = [rect.id]
        let start = editor.screenPoint(in: rect.id)
        editor.pointerDragged(from: start, to: start, modifiers: .option)
        editor.pointerDragged(from: start, to: start + Vector2(0, 60), modifiers: .option)
        editor.pointerReleased(from: start, at: start + Vector2(0, 60), modifiers: .option)
        #expect(editor.document.undoName == "Duplicate")
    }

    @Test func aMoveDragIsOneStepCalledMove() {
        let editor = chain()
        let start = editor.screenPoint(in: rect.id)
        editor.drag(start, start + Vector2(40, 30))
        #expect(editor.document.undoName == "Move")
        editor.document.undo()
        #expect(editor.document.undoName == nil, "every step of the drag was one step")
    }

    @Test func aHeldArrowIsOneStepCalledMove() {
        let editor = chain()
        editor.selection = [rect.id]
        editor.nudgeSelection(by: Vector2(1, 0), isRepeat: false)
        editor.nudgeSelection(by: Vector2(1, 0), isRepeat: true)
        #expect(editor.document.undoName == "Move")
        editor.document.undo()
        #expect(editor.document.undoName == nil)
    }

    // MARK: Inputs and parameters

    @Test func anInputIsChangedByItsLabelAndASliderDragKeepsTheFirstName() throws {
        let editor = chain()
        let field = try widthField(editor)
        editor.setInput(field, to: .number(11))
        #expect(editor.document.undoName == "Change \(field.label)")
        editor.document.endCoalescing()
        for value in [12.0, 13, 14] { editor.setInput(field, to: .number(value), continuous: true) }
        #expect(editor.document.undoName == "Change \(field.label)")
        editor.document.undo()
        #expect(editor.document.undoName == "Change \(field.label)", "the drag was one step; the typed value is the one before")
        editor.document.undo()
        #expect(editor.document.undoName == nil)
    }

    @Test func clearingAnOptionalInputSaysSo() throws {
        let grid = testNode(GridPointsTestNode.self, id: 8, at: .zero)
        let editor = makeEditor([grid], registry: inspectorTestRegistry)
        editor.selection = [grid.id]
        guard case .integer(let field)? = editor.inspectorPage.sections.first?.rows.last else { throw UndoNameFixtureError.noSlider }
        editor.setNumber(field, to: 6)
        guard case .integer(let set)? = editor.inspectorPage.sections.first?.rows.last else { throw UndoNameFixtureError.noSlider }
        editor.clearInput(set)
        #expect(editor.document.undoName == "Clear \(field.label)")
        #expect(editor.document.redoName == nil)
        editor.document.undo()
        #expect(editor.document.undoName == "Change \(field.label)")
    }

    @Test func aParameterIsChangedWithoutItsTypedName() {
        let width = GraphParameter(name: "Plate width", type: .number, value: .number(60))
        let editor = makeEditor([], parameters: [width])
        for value in [61.0, 70, 90] { editor.setParameter(width.id, to: .number(value), continuous: true) }
        #expect(editor.document.undoName == "Change Parameter", "text the person typed is never part of a name")
    }

    // MARK: Comments

    @Test func addingNotesAndFrames() {
        let editor = chain()
        editor.addNote(atScreen: Vector2(30, 40))
        #expect(editor.document.undoName == "Add Note")
        editor.canvasSelection = CanvasSelection(nodes: [rect.id])
        editor.addFrameAroundSelection()
        #expect(editor.document.undoName == "Add Frame")
    }

    @Test func editingNotesAndFrames() {
        let editor = chain()
        editor.setNoteText(sticky.id, to: "Changed")
        #expect(editor.document.undoName == "Edit Note")
        editor.setFrameTitle(frame.id, to: "Front plate")
        #expect(editor.document.undoName == "Edit Frame")
        editor.setCommentAccent(sticky.id, to: .purple)
        #expect(editor.document.undoName == "Edit Note")
        editor.setCommentAccent(frame.id, to: .orange)
        #expect(editor.document.undoName == "Edit Frame")
    }

    @Test func movingResizingAndDeletingComments() {
        let editor = chain()
        editor.canvasSelection = CanvasSelection(comments: [sticky.id])
        let rectangle = editor.frame(ofComment: sticky.id) ?? CanvasRect(origin: .zero, size: .zero)
        let handle = editor.transform.toScreen(CommentLayout.handle(of: rectangle).centre)
        editor.drag(handle, handle + Vector2(40, 25))
        #expect(editor.document.undoName == "Resize")
        let inside = editor.screenPoint(inComment: sticky.id, inset: Vector2(20, 20))
        editor.drag(inside, inside + Vector2(30, 30))
        #expect(editor.document.undoName == "Move")
        editor.deleteSelection()
        #expect(editor.document.undoName == "Delete")
    }

    // MARK: Groups

    @Test func groupUngroupAndMakeUnique() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        #expect(editor.document.undoName == "Group")
        editor.makeUnique(grouped.group)
        #expect(editor.document.undoName == "Make Unique")
        editor.selection = [try #require(editor.selection.first)]
        editor.ungroupSelection()
        #expect(editor.document.undoName == "Ungroup")
    }

    @Test func groupDefinitionEditsEachHaveTheirOwnName() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let id = grouped.definition.id
        editor.renameGroup(id, to: "Rib")
        #expect(editor.document.undoName == "Rename Group", "the typed name is not in the step's")
        editor.setGroupAccent(id, to: .orange)
        #expect(editor.document.undoName == "Change Group Accent")
        editor.renameGroupSocket(id, side: .input, from: "width", to: "w")
        #expect(editor.document.undoName == "Rename Socket")
    }

    @Test func groupSocketsAreExposedMovedAndRemoved() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.transform = CanvasTransform()
        let output = try #require(grouped.definition.outputNode)
        let input = try #require(grouped.definition.inputNode)
        editor.drag(editor.screenPoint(of: grouped.rectangle.id, "profile", input: false),
                    editor.screenPoint(of: output.id, "+", input: true))
        #expect(editor.document.undoName == "Add Output Socket")
        editor.moveGroupSocket(grouped.definition.id, side: .output, named: "profile", by: -1)
        #expect(editor.document.undoName == "Move Socket")
        editor.removeGroupSocket(grouped.definition.id, side: .output, named: "profile")
        #expect(editor.document.undoName == "Remove Socket")
        editor.drag(editor.screenPoint(of: input.id, "+", input: false),
                    editor.screenPoint(of: grouped.extrude.id, "distance", input: true))
        #expect(editor.document.undoName == "Add Input Socket")
    }

    @Test func deletingAnUnusedGroup() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.deleteSelection()
        editor.deleteGroup(grouped.definition.id)
        #expect(editor.document.undoName == "Delete Group")
        editor.document.undo()
        #expect(editor.document.undoName == "Delete" && editor.document.redoName == "Delete Group")
    }
}

/// A fixture that did not have the row the test needs.
enum UndoNameFixtureError: Error {
    case noSlider
}

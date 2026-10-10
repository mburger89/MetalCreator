import CreatorGeometry
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// Every undo step carries a short name (named undo steps; groups-and-comments spec §7): the caller's, else one from
/// the command; a coalesced run keeps its first record's.
@MainActor
struct UndoNameTests {
    let a = makeNode(ConstantNode.self, ["value": .number(1)])
    let b = makeNode(AddNode.self)

    func model() -> DocumentModel {
        DocumentModel(file: GraphFile(graph: graph([a, b])), registry: testRegistry, kernel: FakeKernel())
    }

    @Test func aFreshDocumentHasNoNames() {
        let document = model()
        #expect(document.undoName == nil && document.redoName == nil)
    }

    @Test func aCallersNameIsTheStepsName() throws {
        let document = model()
        try document.perform(.move(a.id, to: Vector2(5, 5)), name: UndoName.resize)
        #expect(document.undoName == "Resize")
        try document.perform(.move(a.id, to: Vector2(9, 9)), at: .root, name: "Nudge it")
        #expect(document.undoName == "Nudge it", "the at: overload takes a name too")
    }

    @Test func withoutANameTheStepIsCalledEdit() throws {
        let document = model()
        try document.perform(.setInput(a.id, "value", .number(2)))
        #expect(document.undoName == "Edit", "no name, no guess from the command: a caller that forgets shows up as Edit")
        try document.perform(.connect(link(a, "value", b, "a")), at: .root)
        #expect(document.undoName == "Edit")
        document.undo()
        #expect(document.redoName == "Edit" && document.undoName == "Edit")
    }

    @Test func aBlankNameFallsBackToEdit() throws {
        let document = model()
        try document.perform(.move(a.id, to: Vector2(1, 1)), name: "  \n")
        #expect(document.undoName == "Edit")
        try document.perform(.move(a.id, to: Vector2(2, 2)), name: "")
        #expect(document.undoName == "Edit")
        try document.perform(.move(a.id, to: Vector2(3, 3)), name: "  Slide  ")
        #expect(document.undoName == "Slide", "a name is trimmed")
    }

    @Test func undoAndRedoWalkTheNames() throws {
        let document = model()
        try document.perform(.move(a.id, to: Vector2(1, 1)), name: "First")
        try document.perform(.move(a.id, to: Vector2(2, 2)), name: "Second")
        #expect(document.undoName == "Second" && document.redoName == nil)
        document.undo()
        #expect(document.undoName == "First" && document.redoName == "Second", "Redo names the step Undo took back")
        document.undo()
        #expect(document.undoName == nil && document.redoName == "First")
        document.redo()
        #expect(document.undoName == "First" && document.redoName == "Second")
        try document.perform(.move(a.id, to: Vector2(3, 3)), name: "Third")
        #expect(document.redoName == nil, "a new edit clears Redo")
    }

    @Test func aCoalescedRunKeepsItsFirstRecordsName() throws {
        let document = model()
        try document.perform(.setInput(a.id, "value", .number(2)), coalescingKey: "drag", name: "Change Value")
        try document.perform(.setInput(a.id, "value", .number(3)), coalescingKey: "drag", name: "Something Else")
        try document.perform(.setInput(a.id, "value", .number(4)), coalescingKey: "drag")
        #expect(document.undoName == "Change Value")
        document.undo()
        #expect(document.undoName == nil, "one step")
        #expect(document.redoName == "Change Value")
    }

    @Test func endingTheRunStartsAStepWithItsOwnName() throws {
        let document = model()
        try document.perform(.move(a.id, to: Vector2(1, 1)), coalescingKey: "drag", name: "Move")
        document.endCoalescing()
        try document.perform(.move(a.id, to: Vector2(2, 2)), coalescingKey: "drag", name: "Resize")
        #expect(document.undoName == "Resize")
        document.undo()
        #expect(document.undoName == "Move")
    }

    @Test func aRefusedEditRecordsNoName() {
        let document = model()
        #expect(throws: GraphError.self) { try document.perform(.removeNode(NodeID()), name: "Delete") }
        #expect(document.undoName == nil)
    }

    @Test func theStackKeepsOneNamePerEntryAndFirstWinsInARun() {
        var stack = UndoStack()
        let id = NodeID()
        stack.record(forward: .setInput(id, "v", .number(1)), inverse: .setInput(id, "v", nil), coalescingKey: "k", name: "One")
        stack.record(forward: .setInput(id, "v", .number(2)), inverse: .setInput(id, "v", .number(1)), coalescingKey: "k", name: "Two")
        #expect(stack.undoEntries.map(\.name) == ["One"] && stack.undoName == "One")
        stack.record(forward: .move(id, to: .zero), inverse: .move(id, to: .zero), coalescingKey: nil)
        #expect(stack.undoEntries.map(\.name) == ["One", "Edit"], "a record with no name is the generic \"Edit\"")
        _ = stack.takeUndo()
        #expect(stack.redoName == "Edit" && stack.undoName == "One")
    }

    @Test func inputNamesUseTheLabelWhenThereIsOne() {
        #expect(UndoName.changeInput("Width") == "Change Width" && UndoName.changeInput("") == "Change Input")
        #expect(UndoName.clearInput("Width") == "Clear Width" && UndoName.clearInput("") == "Clear Input")
        var node = makeNode(ConstantNode.self)
        node.name = "Box"
        #expect(UndoName.addNode(node) == "Add Box")
        node.name = "  "
        #expect(UndoName.addNode(node) == "Add Node", "a node with no title")
        let doubler = Doubler()
        var instance = instance(of: doubler.definition)
        instance.name = "My own name"
        #expect(UndoName.addNode(instance) == "Add Group", "a group node's name is the person's, so it is not used")
    }
}

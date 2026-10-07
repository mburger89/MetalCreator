import Testing
@testable import CreatorGeometry
@testable import CreatorGraph

struct CommandTests {
    /// Applies `command`, then its inverse, and checks the graph is back where it started.
    func expectRoundTrip(_ command: GraphCommand, on start: Graph) throws {
        var g = start
        let inverse = try g.apply(command, registry: testRegistry)
        #expect(g != start)
        _ = try g.apply(inverse, registry: testRegistry)
        #expect(g == start)
    }

    @Test func everyCommandIsReversible() throws {
        let a = makeNode(ConstantNode.self), b = makeNode(AddNode.self)
        let base = graph([a, b], [link(a, "value", b, "a")])
        let parameter = GraphParameter(name: "Wall", type: .number, value: .number(6))
        try expectRoundTrip(.addNode(makeNode(ConstantNode.self)), on: base)
        try expectRoundTrip(.removeNode(a.id), on: base)
        try expectRoundTrip(.disconnect(link(a, "value", b, "a")), on: base)
        try expectRoundTrip(.connect(link(a, "value", b, "b")), on: base)
        try expectRoundTrip(.setInput(b.id, "b", .number(4)), on: base)
        try expectRoundTrip(.move(a.id, to: Vector2(5, 5)), on: base)
        try expectRoundTrip(.rename(a.id, "Width"), on: base)
        try expectRoundTrip(.setOutput(b.id, true), on: base)
        try expectRoundTrip(.addParameter(parameter), on: base)
        try expectRoundTrip(.batch([.setInput(b.id, "b", .number(1)), .move(b.id, to: Vector2(1, 1))]), on: base)
    }

    @Test func removingANodeRemovesItsLinksAndUndoRestoresThem() throws {
        let a = makeNode(ConstantNode.self), b = makeNode(AddNode.self)
        var g = graph([a, b], [link(a, "value", b, "a")])
        let inverse = try g.apply(.removeNode(a.id), registry: testRegistry)
        #expect(g.links.isEmpty)
        _ = try g.apply(inverse, registry: testRegistry)
        #expect(g.links == [link(a, "value", b, "a")])
    }

    @Test func connectingAnOccupiedInputReplacesItsWire() throws {
        let a = makeNode(ConstantNode.self), c = makeNode(ConstantNode.self), b = makeNode(AddNode.self)
        var g = graph([a, b, c], [link(a, "value", b, "a")])
        let inverse = try g.apply(.connect(link(c, "value", b, "a")), registry: testRegistry)
        #expect(g.links == [link(c, "value", b, "a")])
        _ = try g.apply(inverse, registry: testRegistry)
        #expect(g.links == [link(a, "value", b, "a")])
    }

    @Test func invalidConnectionIsRefused() {
        let box = makeNode(BoxNode.self), add = makeNode(AddNode.self)
        var g = graph([box, add])
        #expect(throws: GraphError.invalidConnection(.typeMismatch(from: .solid, to: .number))) {
            try g.apply(.connect(link(box, "solid", add, "a")), registry: testRegistry)
        }
    }

    @Test(arguments: [ConstantValue.number(.nan), .number(.infinity), .vector(Vector3(0, .nan, 0))])
    func nonFiniteInputIsRejected(_ value: ConstantValue) {
        let a = makeNode(ConstantNode.self)
        var g = graph([a])
        #expect(throws: GraphError.invalidValue("Enter a finite number.")) {
            try g.apply(.setInput(a.id, "value", value), registry: testRegistry)
        }
    }

    @Test func nonFiniteParameterIsRejected() throws {
        let parameter = GraphParameter(name: "Wall", type: .number, value: .number(6))
        var g = graph([], parameters: [parameter])
        #expect(throws: GraphError.invalidValue("Enter a finite number.")) {
            try g.apply(.setParameter(parameter.id, .number(.nan)), registry: testRegistry)
        }
    }

    @Test func commandsOnMissingNodesThrow() {
        var g = Graph()
        let ghost = makeNode(ConstantNode.self)
        #expect(throws: GraphError.nodeNotFound(ghost.id)) { try g.apply(.move(ghost.id, to: .zero), registry: testRegistry) }
    }

    @Test func coalescedDragUndoesInOneStep() {
        let id = makeNode(ConstantNode.self).id
        var stack = UndoStack()
        stack.record(forward: .setInput(id, "value", .number(2)), inverse: .setInput(id, "value", .number(1)), coalescingKey: "drag")
        stack.record(forward: .setInput(id, "value", .number(3)), inverse: .setInput(id, "value", .number(2)), coalescingKey: "drag")
        stack.endCoalescing()
        #expect(stack.undoEntries.count == 1)
        let entry = stack.takeUndo()
        #expect(entry?.inverse == .setInput(id, "value", .number(1)))
        #expect(entry?.forward == .setInput(id, "value", .number(3)))
    }

    @Test func newEditAfterUndoClearsRedo() {
        let id = makeNode(ConstantNode.self).id
        var stack = UndoStack()
        stack.record(forward: .rename(id, "A"), inverse: .rename(id, "Constant"), coalescingKey: nil)
        _ = stack.takeUndo()
        #expect(stack.canRedo)
        stack.record(forward: .rename(id, "B"), inverse: .rename(id, "Constant"), coalescingKey: nil)
        #expect(!stack.canRedo)
    }

    @Test func sameKeyAfterEndCoalescingStartsANewStep() {
        let id = makeNode(ConstantNode.self).id
        var stack = UndoStack()
        stack.record(forward: .setInput(id, "value", .number(2)), inverse: .setInput(id, "value", .number(1)), coalescingKey: "drag")
        stack.endCoalescing()
        stack.record(forward: .setInput(id, "value", .number(3)), inverse: .setInput(id, "value", .number(2)), coalescingKey: "drag")
        #expect(stack.undoEntries.count == 2)
    }
}

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

    /// Builds a graph through `connect` commands, so its links are in canonical order.
    func canonical(_ nodes: [Node], _ links: [Link], parameters: [GraphParameter] = []) throws -> Graph {
        var g = graph(nodes, parameters: parameters)
        for l in links { try g.apply(.connect(l), registry: testRegistry) }
        return g
    }

    @Test func removingANodeWithSeveralLinksRoundTripsExactly() throws {
        let a = makeNode(ConstantNode.self), b = makeNode(AddNode.self), c = makeNode(AddNode.self)
        let start = try canonical([a, b, c], [link(a, "value", b, "a"), link(a, "value", c, "a"), link(a, "value", c, "b")])
        try expectRoundTrip(.removeNode(a.id), on: start)
    }

    @Test func replacingConnectRoundTripsAmongOtherLinks() throws {
        let a = makeNode(ConstantNode.self), d = makeNode(ConstantNode.self)
        let b = makeNode(AddNode.self), c = makeNode(AddNode.self)
        let start = try canonical([a, b, c, d], [link(a, "value", b, "a"), link(a, "value", c, "a"), link(a, "value", c, "b")])
        try expectRoundTrip(.connect(link(d, "value", c, "a")), on: start)
        try expectRoundTrip(.connect(link(d, "value", b, "a")), on: start)
    }

    @Test func batchIsAtomic() throws {
        let box = makeNode(BoxNode.self), add = makeNode(AddNode.self)
        let start = graph([box, add])
        var g = start
        #expect(throws: GraphError.self) {
            try g.apply(.batch([.setInput(add.id, "b", .number(1)), .connect(link(box, "solid", add, "a"))]), registry: testRegistry)
        }
        #expect(g == start)
    }

    @Test func rejectedCommandsLeaveTheGraphUnchanged() {
        let a = makeNode(ConstantNode.self)
        let parameter = GraphParameter(name: "Wall", type: .number, value: .number(6))
        let start = graph([a], parameters: [parameter])
        var g = start
        _ = try? g.apply(.setInput(a.id, "value", .number(.nan)), registry: testRegistry)
        _ = try? g.apply(.setParameter(parameter.id, .number(.infinity)), registry: testRegistry)
        #expect(g == start)
    }

    @Test func parameterCommandsRoundTrip() throws {
        let parameter = GraphParameter(name: "Wall", type: .number, value: .number(6))
        let start = graph([], parameters: [parameter])
        try expectRoundTrip(.setParameter(parameter.id, .number(8)), on: start)
        try expectRoundTrip(.setParameter(parameter.id, .integer(8)), on: start)
        try expectRoundTrip(.removeParameter(parameter.id), on: start)
    }

    @Test func parameterValidation() {
        let parameter = GraphParameter(name: "Wall", type: .number, value: .number(6))
        var g = graph([], parameters: [parameter])
        #expect(throws: GraphError.invalidValue("Enter a finite number.")) {
            try g.apply(.addParameter(GraphParameter(name: "X", type: .number, value: .number(.nan))), registry: testRegistry)
        }
        #expect(throws: GraphError.invalidValue("A parameter with this ID already exists.")) {
            try g.apply(.addParameter(parameter), registry: testRegistry)
        }
        #expect(throws: GraphError.invalidValue("“Wall” needs a number.")) {
            try g.apply(.setParameter(parameter.id, .text("hi")), registry: testRegistry)
        }
        #expect(throws: GraphError.invalidValue("“Wall” needs a number.")) {
            try g.apply(.setParameter(parameter.id, .bool(true)), registry: testRegistry)
        }
    }

    @Test func redoReturnsTheSameEntry() {
        let id = makeNode(ConstantNode.self).id
        var stack = UndoStack()
        stack.record(forward: .rename(id, "A"), inverse: .rename(id, "Constant"), coalescingKey: nil)
        let undone = stack.takeUndo()
        #expect(!stack.canUndo)
        let redone = stack.takeRedo()
        #expect(redone == undone)
        #expect(stack.canUndo)
        #expect(!stack.canRedo)
    }

    @Test func nilKeyNeverCoalescesAndDifferentKeysDoNotMerge() {
        let id = makeNode(ConstantNode.self).id
        var stack = UndoStack()
        stack.record(forward: .rename(id, "A"), inverse: .rename(id, "Constant"), coalescingKey: nil)
        stack.record(forward: .rename(id, "B"), inverse: .rename(id, "A"), coalescingKey: nil)
        #expect(stack.undoEntries.count == 2)
        stack.record(forward: .setInput(id, "value", .number(1)), inverse: .setInput(id, "value", nil), coalescingKey: "x")
        stack.record(forward: .setInput(id, "value", .number(2)), inverse: .setInput(id, "value", .number(1)), coalescingKey: "y")
        #expect(stack.undoEntries.count == 4)
    }

    @Test func restoreNodeTouchesLinkTargets() {
        let a = makeNode(ConstantNode.self), b = makeNode(AddNode.self)
        let command = GraphCommand.restoreNode(a, links: [link(a, "value", b, "a")])
        #expect(command.touchedNodes == [a.id, b.id])
    }

    /// A node whose type isn't registered, standing in for one saved by a newer app.
    func futureNode() -> Node {
        var node = makeNode(AddNode.self)
        node.typeID = "future.node"
        return node
    }

    @Test func undoingDisconnectRestoresAWireWhoseEndIsUnregistered() throws {
        let a = makeNode(ConstantNode.self), future = futureNode()
        let start = graph([a, future], [link(a, "value", future, "a")])
        try expectRoundTrip(.disconnect(link(a, "value", future, "a")), on: start)
    }

    @Test func undoingDisconnectRestoresAWireInAHandBuiltCycle() throws {
        let a = makeNode(AddNode.self), b = makeNode(AddNode.self), c = makeNode(AddNode.self)
        var start = graph([a, b, c], [link(a, "sum", b, "a"), link(b, "sum", c, "a"), link(c, "sum", a, "a")])
        start.sortLinks()
        try expectRoundTrip(.disconnect(link(b, "sum", c, "a")), on: start)
    }

    @Test func undoingAReplacingConnectRestoresAnUnregisteredSource() throws {
        let future = futureNode(), c = makeNode(ConstantNode.self), b = makeNode(AddNode.self)
        let start = graph([future, c, b], [link(future, "sum", b, "a")])
        try expectRoundTrip(.connect(link(c, "value", b, "a")), on: start)
    }

    @Test func restoreLinksRefusesAWireThatIsAlreadyThere() {
        let a = makeNode(ConstantNode.self), b = makeNode(AddNode.self)
        var g = graph([a, b], [link(a, "value", b, "a")])
        #expect(throws: GraphError.invalidValue("This wire already exists.")) {
            try g.apply(.restoreLinks([link(a, "value", b, "a")]), registry: testRegistry)
        }
    }

    @Test func nonFinitePositionsAreRejected() throws {
        let a = makeNode(ConstantNode.self)
        var g = graph([a])
        #expect(throws: GraphError.invalidValue("Enter a finite number.")) {
            try g.apply(.move(a.id, to: Vector2(.nan, 0)), registry: testRegistry)
        }
        var bad = makeNode(ConstantNode.self)
        bad.position = Vector2(0, .infinity)
        #expect(throws: GraphError.invalidValue("Enter a finite number.")) {
            try g.apply(.addNode(bad), registry: testRegistry)
        }
        var badInput = makeNode(ConstantNode.self)
        badInput.inputValues = ["value": .number(.nan)]
        #expect(throws: GraphError.invalidValue("Enter a finite number.")) {
            try g.apply(.restoreNode(badInput, links: []), registry: testRegistry)
        }
        #expect(g == graph([a]))
    }
}

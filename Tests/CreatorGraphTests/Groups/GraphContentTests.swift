import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Group commands on the whole document (groups spec §4, §5): every one undoable, and the group rules refused with a
/// plain message.
struct GraphContentTests {
    let doubler = Doubler()

    func content(_ nodes: [Node], _ definitions: [GroupDefinition]) -> GraphContent {
        GraphContent(graph: graph(nodes), definitions: table(definitions))
    }

    /// "Outer": a definition whose inside places one Doubler.
    func outer() -> GroupDefinition {
        var outer = GroupDefinition.make(name: "Outer", registry: testRegistry)
        let inner = instance(of: doubler.definition)
        outer.graph.nodes[inner.id] = inner
        return outer
    }

    /// Applies `command`, then its inverse: the content changed, then is back where it started.
    func expectRoundTrip(_ command: GraphCommand, on start: GraphContent,
                         sourceLocation: SourceLocation = #_sourceLocation) throws {
        var content = start
        let inverse = try content.apply(command, registry: testRegistry)
        #expect(content != start, sourceLocation: sourceLocation)
        try content.apply(inverse, registry: testRegistry)
        #expect(content == start, sourceLocation: sourceLocation)
    }

    func expectRefused(_ command: GraphCommand, on start: GraphContent, _ message: String,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        var content = start
        #expect(throws: GraphError.invalidValue(message), sourceLocation: sourceLocation) {
            try content.apply(command, registry: testRegistry)
        }
        #expect(content == start, sourceLocation: sourceLocation)
    }

    @Test func everyGroupCommandIsReversible() throws {
        let start = content([instance(of: doubler.definition)], [doubler.definition])
        let other = Doubler(name: "Other").definition
        var renamed = doubler.definition.interface
        renamed.name = "Twice"
        try expectRoundTrip(.inDefinition(doubler.id, .addNode(makeNode(ConstantNode.self))), on: start)
        try expectRoundTrip(.inDefinition(doubler.id, .move(doubler.add.id, to: Vector2(5, 5))), on: start)
        try expectRoundTrip(.addDefinition(other), on: start)
        try expectRoundTrip(.setInterface(doubler.id, renamed), on: start)
        try expectRoundTrip(.batch([.addDefinition(other), .addNode(instance(of: other))]), on: start)
        try expectRoundTrip(.removeDefinition(other.id), on: content([], [doubler.definition, other]))
    }

    @Test func anEditInsideADefinitionChangesOnlyItsGraph() throws {
        let top = makeNode(ConstantNode.self)
        var content = content([top], [doubler.definition])
        try content.apply(.inDefinition(doubler.id, .setInput(doubler.add.id, "b", .number(3))), registry: testRegistry)
        #expect(content.definitions[doubler.id]?.graph.nodes[doubler.add.id]?.inputValues["b"] == .number(3))
        #expect(content.graph == graph([top]))
        #expect(content.graph(at: .definition(doubler.id)) == content.definitions[doubler.id]?.graph)
        #expect(content.graph(at: .definition(GroupID())) == nil)
    }

    @Test func aGraphCommandIsAddressedToAPath() {
        let command = GraphCommand.move(doubler.add.id, to: Vector2(1, 2))
        #expect(command.at(.root) == command)
        #expect(command.at(.definition(doubler.id)) == .inDefinition(doubler.id, command))
    }

    @Test func aGroupCantContainItself() {
        let outer = outer()
        let start = content([], [doubler.definition, outer])
        let message = "A group can't contain itself."
        expectRefused(.inDefinition(doubler.id, .addNode(instance(of: doubler.definition))), on: start, message)
        expectRefused(.inDefinition(doubler.id, .addNode(instance(of: outer))), on: start, message)
        let placed = outer.graph.nodes.values.first { $0.typeID == GroupNodes.groupTypeID }
        expectRefused(.inDefinition(outer.id, .setInput(placed?.id ?? NodeID(), NodeSetting.group, .group(outer.id))),
                      on: start, message)
        var selfish = GroupDefinition.make(name: "Selfish", registry: testRegistry)
        let inside = testRegistry.withGroups(table([selfish])).makeGroupNode(GroupNodes.groupTypeID, for: selfish.id)
        selfish.graph.nodes[inside.id] = inside
        expectRefused(.addDefinition(selfish), on: start, message)
    }

    @Test func anOutputNodeCantGoInAGroup() throws {
        let start = content([], [doubler.definition])
        let message = "An Output node can't go in a group."
        expectRefused(.inDefinition(doubler.id, .addNode(makeNode(SinkNode.self))), on: start, message)
        expectRefused(.inDefinition(doubler.id, .setOutput(doubler.add.id, true)), on: start, message)
        var withSink = Doubler(name: "With sink").definition
        let sink = makeNode(SinkNode.self)
        withSink.graph.nodes[sink.id] = sink
        expectRefused(.addDefinition(withSink), on: start, message)
        try expectRoundTrip(.addNode(makeNode(SinkNode.self)), on: start)
    }

    @Test func groupInputAndOutputStayInTheirGroup() {
        let start = content([], [doubler.definition])
        expectRefused(.inDefinition(doubler.id, .removeNode(doubler.input.id)), on: start,
                      "A group's Group Input and Group Output can't be deleted.")
        expectRefused(.addNode(testRegistry.makeGroupNode(GroupNodes.inputTypeID, for: doubler.id)), on: start,
                      "Group Input and Group Output only go inside a group.")
        expectRefused(.inDefinition(doubler.id, .addNode(testRegistry.makeGroupNode(GroupNodes.outputTypeID, for: doubler.id))),
                      on: start, "A group has exactly one Group Input and one Group Output.")
        expectRefused(.inDefinition(doubler.id, .setInput(doubler.output.id, NodeSetting.group, .group(GroupID()))),
                      on: start, "Group Input and Group Output belong to their group.")
        expectRefused(.addDefinition(GroupDefinition(name: "Bare")), on: start,
                      "A group has exactly one Group Input and one Group Output.")
    }

    @Test func aDefinitionInUseCantBeRemoved() {
        let start = content([], [doubler.definition, outer()])
        expectRefused(.removeDefinition(doubler.id), on: start, "“Doubler” is still in use. Delete its group nodes first.")
        expectRefused(.addNode(instance(of: Doubler(name: "Elsewhere").definition)), on: start, "That group no longer exists.")
    }

    @Test func namesAndSocketsAreChecked() {
        let start = content([], [doubler.definition])
        expectRefused(.addDefinition(Doubler().definition), on: start, "A group named “Doubler” already exists.")
        var interface = doubler.definition.interface
        interface.name = "  "
        expectRefused(.setInterface(doubler.id, interface), on: start, "A group needs a name.")
        interface = doubler.definition.interface
        interface.inputs.append(SocketSpec("value", .integer))
        expectRefused(.setInterface(doubler.id, interface), on: start, "Two sockets can't both be named “value”.")
        interface = doubler.definition.interface
        interface.outputs.append(SocketSpec(NodeSetting.group, .number))
        expectRefused(.setInterface(doubler.id, interface), on: start, "“groupID” is reserved. Choose another name.")
        interface = doubler.definition.interface
        interface.outputs.append(SocketSpec("value", .number))  // An input's name is free on the output side.
        #expect(throws: Never.self) {
            var content = start
            try content.apply(.setInterface(doubler.id, interface), registry: testRegistry)
        }
    }

    @Test func aRefusedBatchChangesNothing() {
        let start = content([instance(of: doubler.definition)], [doubler.definition])
        expectRefused(.batch([.inDefinition(doubler.id, .addNode(makeNode(ConstantNode.self))), .removeDefinition(doubler.id)]),
                      on: start, "“Doubler” is still in use. Delete its group nodes first.")
        expectRefused(.inDefinition(doubler.id, .batch([.removeDefinition(doubler.id)])), on: start,
                      "A group edit can't go inside another edit.")
    }

    @Test func anEditInsideADefinitionTouchesEveryGroupNodeThatReachesIt() {
        let outer = outer()
        let direct = instance(of: doubler.definition), nested = instance(of: outer), plain = makeNode(ConstantNode.self)
        let content = content([direct, nested, plain], [doubler.definition, outer])
        #expect(content.touchedTopLevelNodes(.inDefinition(doubler.id, .move(doubler.add.id, to: .zero))) == [direct.id, nested.id])
        #expect(content.touchedTopLevelNodes(.setInterface(outer.id, outer.interface)) == [nested.id])
        #expect(content.touchedTopLevelNodes(.addDefinition(Doubler(name: "New").definition)).isEmpty)
        #expect(content.touchedTopLevelNodes(.batch([.setInput(plain.id, "value", .number(1))])) == [plain.id])
    }

    @Test func instancesAreListedTopLevelFirst() {
        let outer = outer()
        let direct = instance(of: doubler.definition)
        let instances = GroupDependencies.instances(of: doubler.id, in: content([direct], [doubler.definition, outer]))
        #expect(instances.map(\.path) == [.root, .definition(outer.id)])
        #expect(instances.first?.node == direct)
        #expect(GroupDependencies.transitive(outer.id, in: table([doubler.definition, outer])) == [doubler.id])
    }

    @Test func oneGraphRefusesGroupCommands() {
        var g = Graph()
        #expect(throws: GraphError.self) { try g.apply(.removeDefinition(GroupID()), registry: testRegistry) }
        #expect(GraphCommand.inDefinition(doubler.id, .move(doubler.add.id, to: .zero)).affectsResults == false)
        #expect(GraphCommand.inDefinition(doubler.id, .setInput(doubler.add.id, "b", nil)).affectsResults)
        #expect(GraphCommand.addDefinition(doubler.definition).affectsResults == false)
    }

    @Test func aWiredSocketCantBeRemovedOrRetypedByANewInterface() throws {
        let constant = makeNode(ConstantNode.self)
        let node = instance(of: doubler.definition)
        var start = GraphContent(graph: graph([constant, node], [link(constant, "value", node, "value")]),
                                 definitions: table([doubler.definition]))
        var interface = doubler.definition.interface
        interface.inputs = []
        #expect(throws: GraphError.invalidValue("“value” is wired on “Doubler”. Unwire it first.")) {
            try start.apply(.setInterface(doubler.id, interface), registry: testRegistry)
        }
        #expect(start.definitions == table([doubler.definition]), "a refused command changes nothing")

        // Inside: Group Output takes `result` from Add, so it can't become a vector.
        start.graph.links = []
        var retyped = doubler.definition.interface
        retyped.outputs = [SocketSpec("result", .vector)]
        #expect(throws: GraphError.invalidValue("“result” is wired on “Group Output”. Unwire it first.")) {
            try start.apply(.setInterface(doubler.id, retyped), registry: testRegistry)
        }
        // Renaming a socket in one batch that also moves its wires is fine; so is a new name or accent.
        var renamed = doubler.definition.interface
        renamed.name = "Twice"
        renamed.accent = .green
        try expectRoundTrip(.setInterface(doubler.id, renamed), on: start)
    }

    @Test func aNewNameOrAccentChangesNoResultButANameChangesMessages() {
        let start = content([instance(of: doubler.definition)], [doubler.definition])
        var named = doubler.definition.interface
        named.name = "Twice"
        var accented = doubler.definition.interface
        accented.accent = .green
        var socketed = doubler.definition.interface
        socketed.inputs[0].defaultValue = .number(2)
        #expect(!start.affectsResults(.setInterface(doubler.id, named)) && start.affectsMessages(.setInterface(doubler.id, named)))
        #expect(!start.affectsResults(.setInterface(doubler.id, accented)) && !start.affectsMessages(.setInterface(doubler.id, accented)))
        #expect(start.affectsResults(.batch([.setInterface(doubler.id, socketed)])))
        let rename = GraphCommand.inDefinition(doubler.id, .rename(doubler.add.id, "Plus"))
        #expect(!start.affectsResults(rename) && start.affectsMessages(rename))
        #expect(start.affectsResults(.inDefinition(doubler.id, .setInput(doubler.add.id, "b", nil))))
        #expect(!start.affectsMessages(.rename(doubler.add.id, "Plus")), "top-level names aren't in any message")
    }
}

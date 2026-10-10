import CreatorKernel
import Testing
@testable import CreatorGraph

/// The levels the graph panel shows (groups spec §6): entering group nodes, falling back when one is gone, and
/// picks written relative to the level shown.
struct GroupLevelTests {
    let doubler = Doubler()

    /// "Outer" holds one instance (`inner`) of the doubler; `top` is an instance of "Outer" on the top level.
    func nested() -> (content: GraphContent, outer: GroupDefinition, top: Node, inner: Node) {
        let inner = instance(of: doubler.definition)
        let outer = define("Outer", outputs: [SocketSpec("result", .number)], nodes: [inner]) { _, output in
            [link(inner, "result", output, "result")]
        }
        let top = instance(of: outer)
        return (GraphContent(graph: graph([top]), definitions: table([doubler.definition, outer])), outer, top, inner)
    }

    func pick(naming node: NodeID) -> ConstantValue {
        let key = EdgeKey([TopoTag(node: node, item: 0, role: .endCap)], [TopoTag(node: node, item: 0, role: .startCap)])
        return .edgePicks([EdgePick(key: key, matchCount: 1, ordinals: [0])])
    }

    @Test func enteringGroupNodesWalksDownThroughTheirDefinitions() {
        let (content, outer, top, inner) = nested()
        #expect(content.path(entering: []) == .root)
        #expect(content.path(entering: [top.id]) == .definition(outer.id))
        #expect(content.path(entering: [top.id, inner.id]) == .definition(doubler.id))
        #expect(content.path(entering: [inner.id]) == nil, "inner is not on the top level")
        #expect(content.path(entering: [top.id, NodeID()]) == nil, "no such node")
        let plain = GraphContent(graph: graph([makeNode(AddNode.self)]))
        #expect(plain.path(entering: plain.graph.nodes.keys.sorted()) == nil, "an Add node isn't a group node")
    }

    @Test func aLevelThatNoLongerExistsFallsBackToTheDeepestOneThatDoes() {
        var (content, _, top, inner) = nested()
        #expect(content.existingLevels([top.id, inner.id]) == [top.id, inner.id])
        content.definitions[doubler.id] = nil
        #expect(content.existingLevels([top.id, inner.id]) == [top.id], "the doubler is gone, Outer remains")
        content.graph.nodes[top.id] = nil
        #expect(content.existingLevels([top.id, inner.id]) == [])
    }

    @Test func aPickIsWrittenRelativeToTheLevelShown() {
        let (content, _, top, inner) = nested()
        let add = doubler.add.id
        // Shown inside the doubler (via top, inner): its Add makes faces under the doubler instance's identity.
        let made = pick(naming: NodeID.scoped([top.id, inner.id, add]))
        #expect(content.relativeToLevel(made, levels: [top.id, inner.id]) == pick(naming: add))
        // Shown inside Outer, the same faces are the doubler instance's: named by the path from Outer.
        #expect(content.relativeToLevel(made, levels: [top.id]) == pick(naming: NodeID.scoped([inner.id, add])))
        // A face made by a node of the level itself.
        #expect(content.relativeToLevel(pick(naming: NodeID.scoped([top.id, inner.id])), levels: [top.id])
                == pick(naming: inner.id))
    }

    @Test func tagsOutsideTheLevelAndOtherValuesAreLeftAlone() {
        let (content, _, top, inner) = nested()
        let outside = NodeID()
        #expect(content.relativeToLevel(pick(naming: outside), levels: [top.id, inner.id]) == pick(naming: outside),
                "a face made outside the level keeps its name")
        #expect(content.relativeToLevel(.number(3), levels: [top.id]) == .number(3))
        let made = pick(naming: NodeID.scoped([top.id, inner.id, doubler.add.id]))
        #expect(content.relativeToLevel(made, levels: []) == made, "the top level names faces as they are made")
        #expect(content.relativeToLevel(made, levels: [inner.id]) == made, "a level that doesn't exist changes nothing")
    }

    @Test func thePlusSocketsNameIsReserved() throws {
        #expect(GroupNaming.isReserved(GroupNaming.plusSocket))
        var content = GraphContent(graph: Graph(), definitions: table([doubler.definition]))
        let rename = try GroupCommands.renameSocket(doubler.id, side: .input, from: "value", to: GroupNaming.plusSocket,
                                                    in: content)
        #expect(throws: GraphError.invalidValue("“+” is reserved. Choose another name.")) {
            try content.apply(rename, registry: testRegistry)
        }
    }

    @Test func aGroupNodesInspectorOffersEditMakeUniqueAndUngroup() {
        let buttons = GroupNode.inspector.flatMap(\.controls)
        #expect(buttons == [.button(title: "Edit Group", action: .editGroup),
                            .button(title: "Make Unique", action: .makeUnique),
                            .button(title: "Ungroup", action: .ungroup),
        ])
    }
}

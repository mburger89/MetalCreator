import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// The two tie commands (cable ties spec 2026-10-26 §3.2): each is reversible, a refused one changes nothing, and neither
/// re-evaluates (ties are editor furniture).
@MainActor
struct TieCommandTests {
    let scene = TieGraph()

    @Test func settingAddsAndItsInverseRemoves() throws {
        var g = scene.make()
        let added = tie(1, [scene.s1a, scene.s1b])
        let inverse = try g.apply(.setTie(added), registry: testRegistry)
        #expect(g.ties == [added.id: added])
        #expect(inverse == .removeTie(added.id))
        try g.apply(inverse, registry: testRegistry)
        #expect(g == scene.make())
    }

    @Test func settingAgainReplacesWholeAndItsInverseRestoresTheOld() throws {
        let old = tie(1, [scene.s1a, scene.s1b])
        var g = scene.make(ties: [old])
        var changed = old
        changed.position = Vector2(260, 180)
        changed.wires.insert(scene.s2a)
        let inverse = try g.apply(.setTie(changed), registry: testRegistry)
        #expect(g.ties == [old.id: changed])
        #expect(inverse == .setTie(old))
        try g.apply(inverse, registry: testRegistry)
        #expect(g == scene.make(ties: [old]))
    }

    @Test func removingReturnsTheTieAndUndoPutsItBack() throws {
        let start = scene.make(ties: [tie(1, [scene.s1a, scene.s1b]), tie(2, [scene.s2a, scene.s2b])])
        var g = start
        let inverse = try g.apply(.removeTie(tieID(1)), registry: testRegistry)
        #expect(Set(g.ties.keys) == [tieID(2)])
        #expect(inverse == .setTie(tie(1, [scene.s1a, scene.s1b])))
        try g.apply(inverse, registry: testRegistry)
        #expect(g == start)
    }

    /// (I1) and (I2) are refused, not repaired: a command carries what the editor meant, and a wrong one is a bug to see.
    @Test func aBadTieIsRefusedAndChangesNothing() {
        let start = scene.make(ties: [tie(1, [scene.s1a, scene.s1b])])
        let unwired = Endpoint(node: scene.c1.id, socket: "value")  // the constant's own input: no wire
        let refused: [GraphCommand] = [
            .setTie(tie(2, [scene.s1a])),
            .setTie(tie(2, [])),
            .setTie(tie(2, [scene.s1a, unwired])),
            .setTie(tie(2, [scene.s1a, scene.s1b], at: Vector2(.nan, 0))),
            .setTie(tie(2, [scene.s1a, scene.s1b], at: Vector2(0, .infinity))),
            .removeTie(tieID(9)),
            .batch([.setTie(tie(3, [scene.s2a, scene.s2b])), .removeTie(tieID(8))]),
        ]
        for command in refused {
            var g = start
            #expect(throws: GraphError.self) { try g.apply(command, registry: testRegistry) }
            #expect(g == start, "\(command)")
        }
    }

    @Test func tiesTouchNoNodeAndAffectNoResult() {
        let commands: [GraphCommand] = [.setTie(tie(1, [scene.s1a, scene.s1b])), .removeTie(tieID(1))]
        for command in commands {
            #expect(command.touchedNodes.isEmpty)
            #expect(!command.affectsResults)
        }
        #expect(!GraphCommand.batch(commands).affectsResults)
        #expect(GraphContent().affectsResults(.batch(commands)) == false)
    }

    @Test func aTieInsideADefinitionIsEditedThere() throws {
        let doubler = Doubler()
        let inside = tie(1, [Endpoint(node: doubler.add.id, socket: "a"), Endpoint(node: doubler.add.id, socket: "b")])
        var content = GraphContent(definitions: table([doubler.definition]))
        let inverse = try content.apply(GraphCommand.setTie(inside).at(.definition(doubler.id)), registry: testRegistry)
        #expect(content.definitions[doubler.id]?.graph.ties == [inside.id: inside])
        #expect(content.graph.ties.isEmpty)
        #expect(inverse == .inDefinition(doubler.id, .removeTie(inside.id)))
        try content.apply(inverse, registry: testRegistry)
        #expect(content.definitions[doubler.id]?.graph.ties.isEmpty == true)
    }

    @Test func theUndoNamesAreTheSpecs() {
        #expect([UndoName.tieWires, UndoName.addToTie, UndoName.moveTie, UndoName.removeTie, UndoName.untieWire]
                == ["Tie Wires", "Add to Tie", "Move Tie", "Remove Tie", "Untie Wire"])
    }

    @Test func endpointsAreOrderedByNodeThenSocket() {
        #expect([scene.s2b, scene.s1b, scene.s2a, scene.s1a].sorted()
                == [scene.s1a, scene.s1b, scene.s2a, scene.s2b].sorted { ($0.node, $0.socket) < ($1.node, $1.socket) })
        #expect(Endpoint(node: scene.s1.id, socket: "a") < Endpoint(node: scene.s1.id, socket: "b"))
    }
}

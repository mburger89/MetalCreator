// Test fixture file: cable tie fixtures shared by the tie tests.
import CreatorGeometry
import CreatorKernel
import Foundation
@testable import CreatorGraph

/// A tie ID whose sort order is `n`, so tests control the order ties are written in.
func tieID(_ n: Int) -> TieID {
    let digits = String(n)
    let suffix = String(repeating: "0", count: max(0, 12 - digits.count)) + digits
    return TieID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-" + suffix) ?? UUID())
}

/// Tie `n` holding `wires` at `position` (stored coordinates).
func tie(_ n: Int, _ wires: [Endpoint], at position: Vector2 = Vector2(250, 150)) -> CableTie {
    CableTie(id: tieID(n), position: position, wires: Set(wires))
}

/// A test node of `definition` placed at `position`.
func tieNode(_ definition: any NodeDefinition.Type, at position: Vector2) -> Node {
    var node = makeNode(definition)
    node.position = position
    return node
}

/// Four constants feeding two adders, each wire into an adder's input: `s1a` (c1 → s1.a), `s1b` (c2 → s1.b), `s2a`
/// (c3 → s2.a) and `s2b` (c4 → s2.b). The nodes sit apart, so grouping any of c1, c2 and s1 puts the group's top-left at c1's
/// place, (100, 100).
struct TieGraph {
    let c1 = tieNode(ConstantNode.self, at: Vector2(100, 100))
    let c2 = tieNode(ConstantNode.self, at: Vector2(100, 200))
    let c3 = tieNode(ConstantNode.self, at: Vector2(100, 300))
    let c4 = tieNode(ConstantNode.self, at: Vector2(100, 400))
    let s1 = tieNode(AddNode.self, at: Vector2(400, 100))
    let s2 = tieNode(AddNode.self, at: Vector2(400, 300))

    var nodes: [Node] { [c1, c2, c3, c4, s1, s2] }
    var links: [Link] {
        [link(c1, "value", s1, "a"), link(c2, "value", s1, "b"), link(c3, "value", s2, "a"), link(c4, "value", s2, "b")]
    }
    var s1a: Endpoint { Endpoint(node: s1.id, socket: "a") }
    var s1b: Endpoint { Endpoint(node: s1.id, socket: "b") }
    var s2a: Endpoint { Endpoint(node: s2.id, socket: "a") }
    var s2b: Endpoint { Endpoint(node: s2.id, socket: "b") }

    /// The graph with `ties`, its links in canonical order (as commands and decoding keep them, so undo compares equal).
    func make(ties: [CableTie] = []) -> Graph {
        var made = Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }), links: links,
                         ties: Dictionary(uniqueKeysWithValues: ties.map { ($0.id, $0) }))
        made.sortLinks()
        return made
    }

    @MainActor
    func document(ties: [CableTie] = []) -> DocumentModel {
        DocumentModel(file: GraphFile(graph: make(ties: ties)), registry: testRegistry, kernel: FakeKernel())
    }
}

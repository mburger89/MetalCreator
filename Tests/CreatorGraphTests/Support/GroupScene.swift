// Test fixture file: the graph the Group and Ungroup tests group.
import CreatorGeometry
import CreatorKernel
@testable import CreatorGraph

/// c1 (2) feeds both of a1's inputs, a1 and c2 (3) feed a2; a2 feeds the Sink and a1 feeds `other`.
struct GroupScene {
    let c1 = position(makeNode(ConstantNode.self, ["value": .number(2)]), 0, 0)
    let c2 = position(makeNode(ConstantNode.self, ["value": .number(3)]), 0, 100)
    let a1 = position(makeNode(AddNode.self), 200, 0)
    let a2 = position(makeNode(AddNode.self), 200, 100)
    let sink = position(makeNode(SinkNode.self, output: true), 400, 50)
    let other = position(makeNode(AddNode.self), 400, 200)

    var nodes: [Node] { [c1, c2, a1, a2, sink, other] }
    var links: [Link] {
        [link(c1, "value", a1, "a"), link(c1, "value", a1, "b"), link(a1, "sum", a2, "a"), link(c2, "value", a2, "b"),
         link(a2, "sum", sink, "value"), link(a1, "sum", other, "a"), ]
    }

    static func position(_ node: Node, _ x: Double, _ y: Double) -> Node {
        var placed = node
        placed.position = Vector2(x, y)
        return placed
    }
}

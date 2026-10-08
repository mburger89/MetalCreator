// Test fixture file: helpers shared by the editor tests.
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
@testable import CreatorEditor

/// A node ID whose sort order is `n`, so tests control the draw order.
func nodeID(_ n: Int) -> NodeID {
    let digits = String(n)
    let suffix = String(repeating: "0", count: max(0, 12 - digits.count)) + digits
    return NodeID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-" + suffix) ?? UUID())
}

func testNode(_ definition: any NodeDefinition.Type, id: Int, at position: Vector2,
              values: [SocketName: ConstantValue] = [:], registry: NodeRegistry = inspectorTestRegistry) -> Node {
    // Created as the app creates nodes: seeded `defaultSettings`, and `isOutput` for `.output` nodes (M3).
    var node = registry.makeNode(definition.typeID, at: position)
    node.id = nodeID(id)
    node.inputValues.merge(values) { _, given in given }
    return node
}

func wire(_ from: Node, _ fromSocket: SocketName, _ to: Node, _ toSocket: SocketName) -> Link {
    Link(from: Endpoint(node: from.id, socket: fromSocket), to: Endpoint(node: to.id, socket: toSocket))
}

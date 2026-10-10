import CreatorKernel
import Testing
@testable import CreatorGraph

/// Which top-level node made a face, when faces made inside groups carry scoped IDs (groups spec §5).
struct ProducingNodeTests {
    @Test func aScopedIDLeadsToItsTopLevelGroupNode() {
        let doubler = Doubler()
        let inner = instance(of: doubler.definition)
        let outer = define("Outer", outputs: [SocketSpec("result", .number)], nodes: [inner]) { _, output in
            [link(inner, "result", output, "result")]
        }
        let top = instance(of: outer), plain = makeNode(ConstantNode.self)
        let content = GraphContent(graph: graph([top, plain]), definitions: table([doubler.definition, outer]))
        #expect(content.topLevelNode(producing: plain.id) == plain.id)
        #expect(content.topLevelNode(producing: NodeID.scoped([top.id, inner.id, doubler.add.id])) == top.id)
        #expect(content.topLevelNode(producing: NodeID.scoped([top.id, inner.id])) == top.id)
        #expect(content.topLevelNode(producing: doubler.add.id) == nil)
    }
}

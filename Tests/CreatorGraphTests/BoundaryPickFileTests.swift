import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// NS-1 Task 3: a pick that names a sheet's boundary edge (`TopoRole.boundary`, covered by file format 14) survives a save.
struct BoundaryPickFileTests {
    let sheet = NodeID()

    @Test func aBoundaryRolePickRoundTripsThroughAFile() throws {
        let face = TopoTag(node: sheet, item: 0, role: .startCap)
        let picks = [
            EdgePick(key: EdgeKey([face], [TopoTag(node: sheet, item: 0, role: .boundary(.piece(loop: 1, segment: 2)))]), matchCount: 1),
            EdgePick(key: EdgeKey([face], [TopoTag(node: sheet, item: 0, role: .boundary(.rail(1)))]), matchCount: 1),
            EdgePick(key: EdgeKey([face], [TopoTag(node: sheet, item: 0, role: .boundary(.imported(edge: 7)))]), matchCount: 1),
        ]
        let rule = makeNode(ConstantNode.self, ["picks": .edgePicks(picks)])
        let data = try GraphFileIO.encode(GraphFile(graph: graph([rule])))
        let text = try #require(String(bytes: data, encoding: .utf8))
        #expect(text.contains(#""role" : "boundary""#))
        #expect(text.contains(#""formatVersion" : \#(GraphFile.currentFormatVersion)"#))
        let decoded = try GraphFileIO.decode(data, registry: testRegistry)
        #expect(decoded.graph.nodes[rule.id]?.inputValues["picks"] == .edgePicks(picks))
    }
}

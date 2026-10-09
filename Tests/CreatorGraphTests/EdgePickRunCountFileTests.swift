import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// `EdgePick.runCount` (roadmap "Naming: picks on merged faces") is an optional key: files keep format
/// version 4, picks without it are written exactly as before, and a reader that doesn't know it still decodes.
struct EdgePickRunCountFileTests {
    let plate = NodeID()

    /// An `EdgePick` as builds before runCount decode it (synthesized `Codable`, unknown keys ignored).
    struct EarlierEdgePick: Decodable, Equatable {
        var key: EdgeKey
        var matchCount: Int
        var ordinals: [Int]?
    }

    var split: EdgePick {
        let top = TopoTag(node: plate, item: 0, role: .endCap)
        let side = TopoTag(node: plate, item: 0, role: .side(segment: 6))
        return EdgePick(key: EdgeKey([top], [side]), matchCount: 2, runCount: 1)
    }

    @Test func aRunCountRoundTripsThroughAVersionFourFile() throws {
        let rule = makeNode(ConstantNode.self, ["picks": .edgePicks([split])])
        let data = try GraphFileIO.encode(GraphFile(graph: graph([rule])))
        let text = try #require(String(bytes: data, encoding: .utf8))
        #expect(text.contains(#""runCount" : 1"#))
        #expect(text.contains(#""formatVersion" : 4"#))
        let decoded = try GraphFileIO.decode(data, registry: testRegistry)
        #expect(decoded.graph.nodes[rule.id]?.inputValues["picks"] == .edgePicks([split]))
    }

    @Test func anEarlierReaderDecodesAPickWithARunCount() throws {
        let earlier = try JSONDecoder().decode(EarlierEdgePick.self, from: try JSONEncoder().encode(split))
        #expect(earlier == EarlierEdgePick(key: split.key, matchCount: 2, ordinals: nil))
    }
}

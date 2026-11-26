import CreatorGeometry
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// NS-4 Task 3: Trim Surface's keep picks (`ConstantValue.regionPicks`), file format 16 and group renaming of nested tags.
struct RegionPicksFileTests {
    let trim = NodeID()
    let source = NodeID()

    private var nestedRole: TopoRole { .cutSide(.face([TopoTag(node: source, item: 0, role: .endCap)]), .front) }

    private var picks: [RegionPick] {
        [
            RegionPick(pick: FacePick(tags: [TopoTag(node: source, item: 0, role: .startCap),
                                             TopoTag(node: trim, item: 0, role: .cutSide(.curve(index: 0, piece: 0), .outside)),
                                             ],
                                      normal: Vector3(0, 0, 1), centroid: Vector3(1, 0, 0)), sharedBy: 1),
            RegionPick(pick: FacePick(tags: [TopoTag(node: trim, item: 0, role: nestedRole)]), sharedBy: 2),
        ]
    }

    @Test func regionPicksRoundTrip() throws {
        let value = ConstantValue.regionPicks(picks)
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(ConstantValue.self, from: data) == value)
        let text = try #require(String(bytes: data, encoding: .utf8))
        #expect(text.contains("regionPicks"))
        #expect(value.isFinite)
        let rule = makeNode(ConstantNode.self, [NodeSetting.keepRegions: value])
        let file = try GraphFileIO.encode(GraphFile(graph: Graph(nodes: [rule.id: rule])))
        let decoded = try GraphFileIO.decode(file, registry: testRegistry)
        #expect(decoded.graph.nodes[rule.id]?.inputValues[NodeSetting.keepRegions] == value)
    }

    @Test func aFormat15FileOpens() throws {
        let json = #"{"formatVersion": 15, "graph": {"nodes": []}}"#
        let file = try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
        #expect(file.graph == Graph())
    }

    @Test func theFormatIs16() {
        #expect(GraphFile.currentFormatVersion == 18)
    }

    @Test func keepRegionsIsNotReserved() {
        #expect(NodeSetting.all.contains(NodeSetting.keepRegions))
        #expect(!NodeSetting.reservedForSockets.contains(NodeSetting.keepRegions))
        #expect(NodeSetting.keepRegions == "keepRegions")
    }

    @Test func groupRenamingReachesNestedTagsAndKeepsSharedBy() {
        let renamed = NodeID()
        let value = ConstantValue.regionPicks(picks)
        guard case .regionPicks(let out) = value.renamingTags([source: renamed, trim: renamed]) else { Issue.record("kind"); return }
        #expect(out.map(\.sharedBy) == [1, 2])
        #expect(out[0].pick.tags.allSatisfy { $0.node == renamed })
        #expect(out[0].pick.normal == Vector3(0, 0, 1) && out[0].pick.centroid == Vector3(1, 0, 0))
        guard case .cutSide(.face(let nested), _)? = out[1].pick.tags.first?.role else { Issue.record("shape"); return }
        #expect(nested.allSatisfy { $0.node == renamed })
    }
}

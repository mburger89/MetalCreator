import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Task 2e of G-b: the G2 fillet's history is renumbered against the final solid (a corner replaced by a patch is gone
/// from the middle of its face map and the patch is last), so every record names the face the circular fillet's
/// record of the same source names.
struct G2FilletHistoryTests {
    let base = G2FilletTests()
    let coverage = G2FilletCoverageTests()

    struct Key: Hashable { var kind: OCCTHistoryRecord.Kind; var operand: Int; var index: Int }

    /// Every record of the G2 result lies within `radius` of a same-source record of the circular result, and the
    /// circular result has no source the G2 one lacks. Returns the worst distance. The tags a face carries match too.
    @discardableResult
    func expectSameHistory(_ shape: OCCTShape, midpoints: [[Double]], radius: Double,
                           sourceLocation: SourceLocation = #_sourceLocation) throws -> Double {
        let edges = try OCCTKernel.serialized { try base.helper.topology(of: shape) }
        let ids = try midpoints.map { try base.helper.edge(edges, near: $0) }
        return try OCCTKernel.serialized {
            let circular = try shape.blended(edges: ids, size: radius, chamfer: false)
            let g2 = try shape.blendedCurvatureContinuous(edges: ids, size: radius, weight: 1)
            let circularRaw = try OCCTRawTopology.read(circular.0)
            let g2Raw = try OCCTRawTopology.read(g2.shape)
            func centroid(_ raw: OCCTRawTopology, _ face: Int) -> Vector3 { raw.faces[face].centroid }
            var worst = 0.0
            var circularSources = Set<Key>(), g2Sources = Set<Key>()
            for record in circular.1 { circularSources.insert(Key(kind: record.kind, operand: record.operand, index: record.index)) }
            for record in g2.history {
                let key = Key(kind: record.kind, operand: record.operand, index: record.index)
                g2Sources.insert(key)
                #expect(g2Raw.faces.indices.contains(record.outFace), sourceLocation: sourceLocation)
                let nearest = circular.1.filter { Key(kind: $0.kind, operand: $0.operand, index: $0.index) == key }
                    .map { (centroid(circularRaw, $0.outFace) - centroid(g2Raw, record.outFace)).length }.min()
                #expect(nearest != nil, "no circular record for \(key)", sourceLocation: sourceLocation)
                #expect((nearest ?? 1e9) <= radius, "\(key) is \(nearest ?? -1) mm from the circular fillet's face",
                        sourceLocation: sourceLocation)
                worst = max(worst, nearest ?? 1e9)
            }
            #expect(g2Sources == circularSources, sourceLocation: sourceLocation)
            // Roles: the tags the tagger gives each face, from the same inputs.
            let tag = NodeTag(node: NodeID(), item: 0)
            let source = NodeTag(node: NodeID(), item: 9)
            let input = OCCTTagger.topology(raw: try OCCTRawTopology.read(shape), history: [], inputs: [], tag: source)
            let circularTopology = OCCTTagger.topology(raw: circularRaw, history: circular.1, inputs: [input], tag: tag)
            let g2Topology = OCCTTagger.topology(raw: g2Raw, history: g2.history, inputs: [input], tag: tag)
            for record in g2.history {
                let tags = g2Topology.faces[record.outFace].tags
                let match = circularTopology.faces.contains { face in
                    face.tags == tags && (face.centroid - g2Topology.faces[record.outFace].centroid).length <= radius
                }
                #expect(match, "record \(record) has tags the circular fillet's neighbour lacks", sourceLocation: sourceLocation)
            }
            return worst
        }
    }

    @Test func historyNamesTheSameFacesAsTheCircularFilletOnABoxCorner() throws {
        let box = try OCCTKernel.serialized { try OCCTShape.box(20, 20, 10) }
        let worst = try expectSameHistory(box, midpoints: [[10, 0, 10], [0, 10, 10], [0, 0, 5]], radius: 2)
        print("G2HIST box corner worst \(worst)")
    }

    @Test func historyNamesTheSameFacesAsTheCircularFilletOnAMitre() throws {
        let box = try OCCTKernel.serialized { try OCCTShape.box(20, 20, 10) }
        let worst = try expectSameHistory(box, midpoints: [[10, 0, 10], [20, 10, 10], [10, 20, 10], [0, 10, 10]], radius: 2)
        print("G2HIST mitre outline worst \(worst)")
    }

    @Test func historyNamesTheSameFacesAsTheCircularFilletOnTheBracket() throws {
        let plate = try coverage.bracketPlate()
        let worst = try expectSameHistory(plate, midpoints: [[30, -2, 6]], radius: 1)
        print("G2HIST bracket worst \(worst)")
    }
}

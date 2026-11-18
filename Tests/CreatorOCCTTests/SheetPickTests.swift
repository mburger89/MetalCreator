#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-1 Task 3 (ruling R-A: at the kernel, since the Planar Surface node comes in Task 6): a boundary edge picked on a
/// sheet is found again after the sheet is rebuilt, moved or placed.
struct SheetPickTests {
    let node = NodeID()
    let place = NodeID()
    var tag: NodeTag { NodeTag(node: node, item: 0) }

    /// What `NodeID.instanceScoped([place, node])` does in the app, without CreatorGraph.
    func qualify(_ node: NodeID) -> NodeID {
        var bytes = node.rawValue.uuid
        bytes.6 = (bytes.6 & 0x0F) | 0x80
        bytes.0 ^= place.rawValue.uuid.0
        return NodeID(rawValue: UUID(uuid: bytes))
    }

    func sheet(_ kernel: OCCTKernel, width: Double) async throws -> Solid {
        let corners = [Vector3(0, 0, 0), Vector3(width, 0, 0), Vector3(width, 20, 0), Vector3(0, 20, 0)]
        let curve = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: tag)
        return try await kernel.planarSurface([curve], tag: tag)
    }

    /// The right-hand edge (piece 1: x = width).
    func rightEdge(_ solid: Solid) throws -> EdgeInfo {
        try #require(solid.topology.edges.first { $0.tags.contains { $0.role == .boundary(.piece(loop: 0, segment: 1)) } })
    }

    func resolve(_ picks: [EdgePick], in solid: Solid) -> [EdgeInfo] {
        picks.flatMap { solid.topology.edges(resolving: $0.key) }
    }

    @Test func aPickedBoundaryEdgeSurvivesAChangeOfWidth() async throws {
        let kernel = OCCTKernel()
        let narrow = try await sheet(kernel, width: 10)
        let picks = narrow.topology.picks(for: [try rightEdge(narrow).id])
        #expect(picks.count == 1)
        let wide = try await sheet(kernel, width: 14)
        let found = resolve(picks, in: wide)
        #expect(found.count == 1)
        #expect(abs(try #require(found.first).midpoint.x - 14) < 1e-6)
        #expect(found.first?.id == (try rightEdge(wide)).id)
    }

    @Test func aPickedBoundaryEdgeSurvivesATransform() async throws {
        let kernel = OCCTKernel()
        let move = Transform(translation: Vector3(5, 7, 3))
        let first = try await kernel.transform(try await sheet(kernel, width: 10), by: move, tag: newTag())
        // The moved sheet keeps its edges' names, in the same order, and the edges are where the move put them.
        let edge = try rightEdge(first)
        #expect(first.topology.edges.allSatisfy { $0.isBoundary && $0.tags.count == 1 })
        #expect((edge.midpoint - Vector3(15, 17, 3)).length < 1e-6)
        let picks = first.topology.picks(for: [edge.id])
        let second = try await kernel.transform(try await sheet(kernel, width: 14), by: move, tag: newTag())
        let found = resolve(picks, in: second)
        #expect(found.count == 1)
        #expect((try #require(found.first).midpoint - Vector3(19, 17, 3)).length < 1e-6)
        #expect(first.topology.faces[0].isOnOpenShell && !first.isClosed)
    }

    @Test func aPickOnPlacedCopyOneFindsThatCopysEdgeAfterARebuild() async throws {
        let kernel = OCCTKernel()
        let moves = (0..<3).map { Transform(translation: Vector3(Double($0) * 30, 0, 0)) }
        func placed(width: Double) async throws -> [Solid] {
            let tool = try await sheet(kernel, width: width)
            return try await kernel.place(Array(repeating: tool, count: 3), at: moves, qualifying: { qualify($0) }, tag: newTag())
        }
        let before = try await placed(width: 10)
        for (index, copy) in before.enumerated() {
            let tags = Set(copy.topology.faces.flatMap(\.tags) + copy.topology.edges.flatMap(\.tags))
            #expect(tags.allSatisfy { $0.node.isInstanceQualified && $0.item == index })
        }
        let picks = before[1].topology.picks(for: [try rightEdge(before[1]).id])
        let after = try await placed(width: 14)
        let found = resolve(picks, in: after[1])
        #expect(found.count == 1)
        #expect((try #require(found.first).midpoint - Vector3(44, 10, 0)).length < 1e-6)
        // The other copies' edges carry other items, so the same pick finds nothing on them.
        #expect(resolve(picks, in: after[0]).isEmpty && resolve(picks, in: after[2]).isEmpty)
    }

    @Test func aBoundaryPickRoundTripsThroughTheFileFormat() async throws {
        let kernel = OCCTKernel()
        let solid = try await sheet(kernel, width: 10)
        let picks = solid.topology.picks(for: try solid.topology.edges.map(\.id))
        let data = try JSONEncoder().encode(picks)
        let decoded = try JSONDecoder().decode([EdgePick].self, from: data)
        #expect(decoded == picks)
        #expect(resolve(decoded, in: solid).count == 4)
    }
}
#endif

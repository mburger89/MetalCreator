#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorOCCT

/// NS-5 Task 10: the names NS-5 gives hold (R3 to R6, R12, R13): each test builds, records a pick or key, changes one
/// input and finds exactly one match, narrowed or ambiguous never.
struct BackToSolidsNamingTests {
    let kernel = OCCTKernel()
    /// One node tag per node, as in a graph, so the same node builds the same names again.
    let node = NodeTag(node: NodeID(), item: 0)
    let source = NodeTag(node: NodeID(), item: 0)

    /// The sheet's rectangle, clockwise from +z so its normal is +z.
    func square(x: ClosedRange<Double> = 0...10, y: ClosedRange<Double> = 0...10, tag: NodeTag? = nil) async throws -> Solid {
        let tag = tag ?? source
        let corners = [Vector3(x.lowerBound, y.lowerBound, 0), Vector3(x.lowerBound, y.upperBound, 0),
                       Vector3(x.upperBound, y.upperBound, 0), Vector3(x.upperBound, y.lowerBound, 0),
        ]
        let loop = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: tag)
        return try await kernel.planarSurface([loop], tag: tag)
    }

    /// The one face `pick` names in `solid`, with nothing narrowed or ambiguous.
    func onlyFace(_ pick: FacePick, in solid: Solid, sourceLocation: SourceLocation = #_sourceLocation) throws -> FaceInfo {
        let resolution = solid.topology.resolution(of: pick)
        #expect(resolution.faces.count == 1 && !resolution.isNarrowed && !resolution.isAmbiguous, sourceLocation: sourceLocation)
        return try #require(resolution.faces.first, sourceLocation: sourceLocation)
    }

    func onlyEdge(_ key: EdgeKey, in solid: Solid, sourceLocation: SourceLocation = #_sourceLocation) throws -> EdgeInfo {
        let resolution = solid.topology.resolution(of: key)
        #expect(resolution.edges.count == 1 && !resolution.isAmbiguous && !resolution.isSplit, sourceLocation: sourceLocation)
        return try #require(resolution.edges.first, sourceLocation: sourceLocation)
    }

    func cylinderTube(topRadius: Double) async throws -> Solid {
        func circle(_ radius: Double, z: Double) async throws -> Curve {
            let piece = CurvePiece.arc(center: Vector3(0, 0, z), normal: Vector3(0, 0, 1), radius: radius,
                                       start: Vector3(radius, 0, z), sweep: 2 * .pi)
            return try await kernel.makeCurve([piece], tag: source)
        }
        return try await kernel.loftSurface([circle(10, z: 0), circle(topRadius, z: 20)], ruled: false, closed: false, tag: source)
    }

    /// A Planar Surface `z` up, its names fixed by `source` so moving it keeps them.
    func plane(z: Double) async throws -> Solid {
        let corners = [Vector3(-15, -15, z), Vector3(-15, 15, z), Vector3(15, 15, z), Vector3(15, -15, z)]
        let loop = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: source)
        return try await kernel.planarSurface([loop], tag: source)
    }

    @Test func aWallSurvivesTheDistance() async throws {
        let sheet = try await square(x: 0...20, y: 0...30)
        let thin = try await kernel.thickened(sheet, distance: 2, side: .front, tag: node)
        let wall = try #require(thin.topology.faces.first { abs(($0.normal?.x ?? 0) - 1) < 1e-9 })
        let pick = try #require(thin.topology.facePick(for: wall.id))
        let wallEdges = thin.topology.edges.filter { $0.faces.contains(wall.id) }
        let key = try #require(wallEdges.compactMap { thin.topology.key(of: $0) }.first)
        let thick = try await kernel.thickened(sheet, distance: 3, side: .front, tag: node)
        let found = try onlyFace(pick, in: thick)
        #expect(abs((found.normal?.x ?? 0) - 1) < 1e-9 && abs(found.centroid.x - 20) < 1e-9)
        #expect(abs(found.centroid.z - 1.5) < 1e-6, "the same wall, now 3 mm tall")
        _ = try onlyEdge(key, in: thick)
    }

    @Test func theEndFaceSurvivesFrontToBoth() async throws {
        let sheet = try await square(x: 0...20, y: 0...30)
        let front = try await kernel.thickened(sheet, distance: 2, side: .front, tag: node)
        let end = try #require(front.topology.faces.first { $0.tags.contains(TopoTag(node, .endCap)) })
        #expect(abs(end.centroid.z - 2) < 1e-6)
        let pick = try #require(front.topology.facePick(for: end.id))
        let both = try await kernel.thickened(sheet, distance: 2, side: .both, tag: node)
        let found = try onlyFace(pick, in: both)
        #expect(abs(found.centroid.z - 1) < 1e-6, "the face that looks +z, now half the distance up")
        #expect((found.normal?.z ?? 0) > 0.99)
    }

    @Test func aSewnFaceSurvivesTheTolerance() async throws {
        let data = try OCCTKernel.looseBoxFaces(size: 10, movingTopBy: 0.03, doublingTop: false)
        let read = try await kernel.readShapes(data, format: .step, tag: source)
        let sheet = try #require(read.sheets.first)
        let tight = try await kernel.sewn([sheet], tolerance: 0.01, tag: node)
        #expect(tight.solids == 0 && tight.sheets == 2)
        let loose = try await kernel.sewn([sheet], tolerance: 0.05, tag: node)
        #expect(loose.solids == 1 && loose.sheets == 0)
        for face in tight.body.topology.faces {
            let pick = try #require(tight.body.topology.facePick(for: face.id))
            let found = try onlyFace(pick, in: loose.body)
            #expect(Set(found.tags.map(\.sortKey)) == Set(face.tags.map(\.sortKey)))
        }
    }

    @Test func aPreSewBoundaryKeyNamesTheSewnEdge() async throws {
        let left = try await square(x: 0...10, y: 0...10)
        // Two nodes, two tags, as in a graph.
        let right = try await square(x: 10...20, y: 0...10, tag: NodeTag(node: NodeID(), item: 0))
        let shared = try #require(left.topology.edges.first { $0.isBoundary && abs($0.midpoint.x - 10) < 1e-9 })
        let key = try #require(left.topology.key(of: shared))
        let sewn = try await kernel.sewn([left, right], tolerance: 0.01, tag: node)
        let edge = try onlyEdge(key, in: sewn.body)
        #expect(abs(edge.midpoint.x - 10) < 1e-6 && !edge.isBoundary)
    }

    @Test func aCapSurvivesTheSectionGrowing() async throws {
        let small = try await kernel.cappingPlanarHoles(cylinderTube(topRadius: 6), tag: node)
        let top = try #require(small.body.topology.faces.first { $0.kind == .plane && abs($0.centroid.z - 20) < 1e-6 })
        let pick = try #require(small.body.topology.facePick(for: top.id))
        let grown = try await kernel.cappingPlanarHoles(cylinderTube(topRadius: 7), tag: node)
        let found = try onlyFace(pick, in: grown.body)
        #expect(abs(found.centroid.z - 20) < 1e-6 && abs(found.area - Double.pi * 49) / (Double.pi * 49) < 1e-4)
    }

    @Test func aCutFaceSurvivesThePlaneMoving() async throws {
        let part = try await box(kernel, 10, 10, 10)
        let low = try await kernel.splitSolid(part, by: [plane(z: 5)], tag: node)
        let lower = try #require(low.pieces.first { $0.bounds.max.z < 6 })
        let cut = try #require(lower.topology.faces.first { abs($0.centroid.z - 5) < 1e-6 })
        let pick = try #require(lower.topology.facePick(for: cut.id))
        let high = try await kernel.splitSolid(part, by: [plane(z: 6)], tag: node)
        let moved = try #require(high.pieces.first { $0.bounds.max.z < 7 })
        let found = try onlyFace(pick, in: moved)
        #expect(abs(found.centroid.z - 6) < 1e-6)
    }

    @Test func anOffsetFaceSurvivesTheDistance() async throws {
        let sheet = try await square()
        let near = try await kernel.offsetSurface(sheet, distance: 2, tag: node)
        let pick = try #require(near.topology.facePick(for: near.topology.faces[0].id))
        let key = try #require(near.topology.edges.first.flatMap { near.topology.key(of: $0) })
        let far = try await kernel.offsetSurface(sheet, distance: 3, tag: node)
        let found = try onlyFace(pick, in: far)
        #expect(abs(found.centroid.z - 3) < 1e-6)
        _ = try onlyEdge(key, in: far)
    }
}
#endif

import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing

@testable import CreatorApp

@MainActor
struct MeasureResolverTests {
    private let kernel = FakeKernel()
    private let node = NodeID()

    private func extrusion(_ profile: Profile2D = .rectangle(width: 10, height: 10, plane: .xy), distance: Double) async throws -> Solid {
        try await kernel.extrude(profile, distance: distance, mode: .oneSided, tag: NodeTag(node: node, item: 0))
    }

    private func scene(_ solids: [Solid], pickable: [Bool]? = nil, parts: [SectionedPart] = [], plane: Plane? = nil) -> MeasureScene {
        MeasureScene(solids: solids, pickable: pickable ?? solids.map { _ in true }, parts: parts, plane: plane)
    }

    private func topFace(_ solid: Solid) throws -> FaceInfo {
        let top = solid.topology.faces.filter { ($0.normal?.z ?? 0) > 0.5 }
        return try #require(top.first)
    }

    private func mesh(resolution: Double? = nil) -> Solid {
        Solid(displaying: DisplayMesh(positions: [.zero, .unitX, .unitY], normals: [.unitZ, .unitZ, .unitZ], indices: [0, 1, 2],
                                      triangleFaces: [FaceID(0)], edgePolylines: [:]), resolution: resolution)
    }

    private func line(_ points: [Vector3], face: FaceID? = nil) -> SectionPiece {
        SectionPiece(curve: nil, polyline: points, sourceFace: face)
    }

    private func part(_ solid: Solid, _ pieces: [SectionPiece]) -> SectionedPart {
        SectionedPart(solid: solid, section: PlaneSection(regions: [SectionRegion(positions: [], triangles: [], boundary: pieces)]))
    }

    @Test func aFacePickFollowsAnEditedBox() async throws {
        let old = try await extrusion(distance: 10)
        let pick = MeasurePick.face(solid: 0, try topFace(old).id)
        let anchor = try #require(MeasureResolver.anchor(for: pick, in: scene([old])))
        let edited = try await extrusion(distance: 20)
        let resolved = try #require(MeasureResolver.resolve(anchor, in: scene([edited])))
        guard case let .face(solid, id) = resolved else { Issue.record("not a face"); return }
        // FakeKernel's faces have no centroid, so the top face is told by its normal.
        let top = try topFace(edited)
        #expect(solid == 0 && id == top.id)
    }

    @Test func anEdgeAndItsCornerFollowTheEdit() async throws {
        let old = try await extrusion(distance: 10)
        let edge = try #require(old.topology.edges.first { ($0.direction?.z ?? 0).magnitude > 0.5 })
        let scene0 = scene([old])
        let corner = MeasurePick.corner(solid: 0, edge.id, .end, at: edge.curve?.ends.last ?? .zero)
        let anchor = try #require(MeasureResolver.anchor(for: corner, in: scene0))
        let edited = try await extrusion(distance: 20)
        guard case let .corner(_, id, end, point)? = MeasureResolver.resolve(anchor, in: scene([edited])) else {
            Issue.record("not a corner"); return
        }
        #expect(end == .end && point == edited.topology.edge(id)?.curve?.ends.last)
        #expect(point.z == 20)
        let plain = try #require(MeasureResolver.anchor(for: .edge(solid: 0, edge.id), in: scene0))
        #expect(MeasureResolver.resolve(plain, in: scene([edited])) != nil)
    }

    @Test func aCircleCentreResolves() async throws {
        let solid = try await extrusion(.circle(radius: 3, center: Vector2(1, 2), plane: .xy), distance: 5)
        let edge = try #require(solid.topology.edges.first { if case .circle? = $0.curve { true } else { false } })
        guard case let .circle(centre, _, _, _, _)? = edge.curve else { return }
        let anchor = try #require(MeasureResolver.anchor(for: .corner(solid: 0, edge.id, .centre, at: centre), in: scene([solid])))
        guard case let .corner(_, _, end, at)? = MeasureResolver.resolve(anchor, in: scene([solid])) else {
            Issue.record("did not resolve"); return
        }
        #expect(end == .centre && at == centre)
    }

    @Test func anAnchorMatchingTwoEdgesDoesNotResolve() async throws {
        let solid = try await extrusion(distance: 10)
        let edge = try #require(solid.topology.edges.first)
        let pick = try #require(solid.topology.picks(for: [edge.id]).first)
        // A key with one side empty matches every edge along the first face: several, and no ordinals to choose between them.
        let loose = EdgePick(key: EdgeKey(pick.key.first, []), matchCount: 1)
        #expect(solid.topology.resolution(of: loose.key).edges.count > 1)
        #expect(MeasureResolver.resolve(.edge(loose), in: scene([solid])) == nil)
    }

    @Test func aSectionEdgeResolvesByIndexWhenTheCountHolds() async throws {
        let solid = try await extrusion(distance: 10)
        let face = try topFace(solid)
        let a = line([Vector3(0, 0, 0), Vector3(1, 0, 0)], face: face.id)
        let b = line([Vector3(0, 5, 0), Vector3(1, 5, 0)], face: face.id)
        let plane = Plane.xy
        let before = scene([solid], parts: [part(solid, [a, b])], plane: plane)
        let anchor = try #require(MeasureResolver.anchor(for: .sectionEdge(solid: 0, piece: b, at: Vector3(0.5, 5, 0)), in: before))
        guard case let .sectionEdge(index) = anchor else { Issue.record("not a section edge"); return }
        #expect(index.index == 1 && index.count == 2)
        // The cut moved: both pieces are elsewhere, the count holds.
        let a2 = line([Vector3(0, 1, 0), Vector3(1, 1, 0)], face: face.id)
        let b2 = line([Vector3(0, 9, 0), Vector3(1, 9, 0)], face: face.id)
        let after = scene([solid], parts: [part(solid, [a2, b2])], plane: plane)
        guard case let .sectionEdge(_, piece, _)? = MeasureResolver.resolve(anchor, in: after) else {
            Issue.record("did not resolve"); return
        }
        #expect(piece == b2)
    }

    @Test func aSectionEdgeResolvesByMidpointWhenTheCountChanged() async throws {
        let solid = try await extrusion(distance: 10)
        let face = try topFace(solid)
        let a = line([Vector3(0, 0, 0), Vector3(1, 0, 0)], face: face.id)
        let b = line([Vector3(0, 5, 0), Vector3(1, 5, 0)], face: face.id)
        let anchor = try #require(MeasureResolver.anchor(for: .sectionEdge(solid: 0, piece: b, at: Vector3(0.5, 5, 0)),
                                                         in: scene([solid], parts: [part(solid, [a, b])], plane: .xy)))
        let c = line([Vector3(0, 20, 0), Vector3(1, 20, 0)], face: face.id)
        let after = scene([solid], parts: [part(solid, [c, a, b])], plane: .xy)
        guard case let .sectionEdge(_, piece, _)? = MeasureResolver.resolve(anchor, in: after) else {
            Issue.record("did not resolve"); return
        }
        #expect(piece == b)
    }

    @Test func aSectionEdgeWithoutASectionDoesNotResolve() async throws {
        let solid = try await extrusion(distance: 10)
        let face = try topFace(solid)
        let a = line([Vector3(0, 0, 0), Vector3(1, 0, 0)], face: face.id)
        let anchor = try #require(MeasureResolver.anchor(for: .sectionEdge(solid: 0, piece: a, at: .zero),
                                                         in: scene([solid], parts: [part(solid, [a])], plane: .xy)))
        #expect(MeasureResolver.resolve(anchor, in: scene([solid], parts: [], plane: nil)) == nil)
        #expect(MeasureResolver.resolve(anchor, in: scene([solid], parts: [], plane: .xy)) == nil)
        #expect(MeasureResolver.resolve(anchor, in: scene([solid], parts: [part(solid, [a])], plane: nil)) == nil)
    }

    private var square: [Vector3] { [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 10, 0), Vector3(0, 10, 0), Vector3(0, 0, 0)] }

    @Test func aMeshSectionEdgeResolvesWithin1mm() {
        let solid = mesh()
        let piece = line(square)
        let anchor = MeasureAnchor.meshSectionEdge(Vector3(5, 0.5, 0))
        let resolved = MeasureResolver.resolve(anchor, in: scene([solid], parts: [part(solid, [piece])], plane: .xy))
        guard case let .sectionEdge(index, found, at)? = resolved else { Issue.record("did not resolve"); return }
        #expect(index == 0 && found == piece && at == Vector3(5, 0, 0))
    }

    @Test func aMeshSectionEdgeFollowsAMovedPlane() {
        let solid = mesh()
        // The cut moved 5 mm along its normal, so its outline lies there; the stored point lay on the old plane.
        let piece = line(square.map { $0 + Vector3(0, 0, 5) })
        let anchor = MeasureAnchor.meshSectionEdge(Vector3(5, 0.5, 0))
        let moved = Plane(origin: Vector3(0, 0, 5), normal: .unitZ, xAxis: .unitX)
        let resolved = MeasureResolver.resolve(anchor, in: scene([solid], parts: [part(solid, [piece])], plane: moved))
        guard case let .sectionEdge(_, found, _)? = resolved else { Issue.record("did not resolve"); return }
        #expect(found == piece)
    }

    @Test func aSharedTagResolvesOnThePreferredPart() async throws {
        let first = try await extrusion(distance: 10)
        let second = try await extrusion(distance: 10)
        let both = scene([first, second])
        let anchor = try #require(MeasureResolver.anchor(for: .face(solid: 0, try topFace(first).id), in: both))
        #expect(MeasureResolver.resolve(anchor, in: both)?.solidIndex == 0)
        #expect(MeasureResolver.resolve(anchor, in: both, preferring: 1)?.solidIndex == 1)
        #expect(MeasureResolver.resolve(anchor, in: scene([first, second], pickable: [true, false]), preferring: 1)?.solidIndex == 0)
    }

    @Test func aMeshSectionEdgeDoesNotResolveBeyond1mm() {
        let solid = mesh()
        let anchor = MeasureAnchor.meshSectionEdge(Vector3(5, 2, 0))
        #expect(MeasureResolver.resolve(anchor, in: scene([solid], parts: [part(solid, [line(square)])], plane: .xy)) == nil)
    }

    @Test func aMeshPointAlwaysResolves() {
        let solid = mesh(resolution: 0.5)
        let current = scene([solid])
        let anchor = MeasureResolver.anchor(for: .meshPoint(solid: 0, at: Vector3(1, 2, 3)), in: current)
        #expect(anchor == .meshPoint(Vector3(1, 2, 3)))
        let pick = MeasureResolver.resolve(.meshPoint(Vector3(7, 8, 9)), in: current)
        #expect(pick == .meshPoint(solid: 0, at: Vector3(7, 8, 9)))
        #expect(pick?.isApproximate == true)
        #expect(pick.flatMap { MeasureResolver.meshResolution(of: $0, in: current) } == 0.5)
    }

    @Test func aGhostOrGuideIsNeverResolvedOn() async throws {
        let solid = try await extrusion(distance: 10)
        let face = MeasurePick.face(solid: 0, try topFace(solid).id)
        let anchor = try #require(MeasureResolver.anchor(for: face, in: scene([solid])))
        #expect(MeasureResolver.resolve(anchor, in: scene([solid], pickable: [false])) == nil)
        #expect(MeasureResolver.resolve(.meshPoint(.zero), in: scene([mesh()], pickable: [false])) == nil)
        let second = try await extrusion(distance: 10)
        let hit = MeasureResolver.resolve(anchor, in: scene([solid, second], pickable: [false, true]))
        #expect(hit?.solidIndex == 1)
    }
}

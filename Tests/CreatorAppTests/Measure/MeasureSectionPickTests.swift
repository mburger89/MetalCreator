import CreatorGeometry
import CreatorKernel
import CreatorViewport
import Testing
@testable import CreatorApp

struct MeasureSectionPickTests {
    private func square(_ x0: Double, _ y0: Double, size: Double = 10) -> SectionPiece {
        let corners = [(0.0, 0.0), (1, 0), (1, 1), (0, 1), (0, 0)]
        return SectionPiece(curve: nil, polyline: corners.map { Vector3(x0 + $0.0 * size, y0 + $0.1 * size, 0) },
                            sourceFace: nil)
    }

    private func parts(_ pieces: [SectionPiece]) async throws -> [SectionedPart] {
        let region = SectionRegion(positions: [], triangles: [], boundary: pieces)
        let solid = try await FakeKernel().extrude(.rectangle(width: 1, height: 1, plane: .xy), distance: 1, mode: .oneSided,
                                                   tag: NodeTag(node: NodeID(), item: 0))
        return [SectionedPart(solid: solid, section: PlaneSection(regions: [region]))]
    }

    private let project: (Vector3) -> ScreenPoint? = { ScreenPoint($0.x, $0.y) }

    @Test func aPointNearAnOutlinePicksIt() async throws {
        let parts = try await parts([square(0, 0), square(20, 0)])
        let hit = MeasureSectionPick.nearest(to: ScreenPoint(16, 5), in: parts, screenPoint: project)
        #expect(hit?.part == 0 && hit?.piece == 1)
    }

    @Test func aPointFarFromEveryOutlineIsNil() async throws {
        let parts = try await parts([square(0, 0), square(24, 0)])
        #expect(MeasureSectionPick.nearest(to: ScreenPoint(17, 5), in: parts, screenPoint: project) == nil)
    }

    @Test func theNearerOfTwoPiecesWins() async throws {
        let parts = try await parts([square(0, 0), square(14, 0)])
        let hit = MeasureSectionPick.nearest(to: ScreenPoint(11, 5), in: parts, screenPoint: project)
        #expect(hit?.piece == 0)
        let other = MeasureSectionPick.nearest(to: ScreenPoint(12.5, 5), in: parts, screenPoint: project)
        #expect(other?.piece == 1)
    }

    @Test func aFarPieceIsNotProjected() async throws {
        let parts = try await parts([square(0, 0), square(1000, 0)])
        var projected = 0
        let counting: (Vector3) -> ScreenPoint? = { projected += 1; return ScreenPoint($0.x, $0.y) }
        let hit = MeasureSectionPick.nearest(to: ScreenPoint(5, 5), in: parts, screenPoint: counting)
        #expect(hit?.piece == 0)
        // 8 corners each, plus the 5 points of the near piece only (the far one is skipped after its corners).
        #expect(projected == 8 + 5 + 8)
    }

    @Test func aPieceBehindTheCameraIsStillTested() async throws {
        let parts = try await parts([square(0, 0)])
        let behind: (Vector3) -> ScreenPoint? = { $0.y == 10 ? nil : ScreenPoint($0.x, $0.y) }
        // The top edge's points have no screen position, so the bottom edge answers; the piece is tested in full.
        let hit = MeasureSectionPick.nearest(to: ScreenPoint(5, 1), in: parts, screenPoint: behind)
        #expect(hit?.piece == 0)
    }
}

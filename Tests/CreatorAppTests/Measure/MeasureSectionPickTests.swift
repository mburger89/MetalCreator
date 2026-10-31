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
}

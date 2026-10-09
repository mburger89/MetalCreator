import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// S4: FakeKernel's cap edges carry exact curves like OCCT's, so Sketch-node projection is testable
/// without OCCT.
struct FakeKernelCurveTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    @Test func capEdgesCarryTheirLinesAtTheCapHeights() async throws {
        let solid = try await FakeKernel().extrude(.rectangle(width: 10, height: 20, plane: .xy), distance: 5,
                                                   mode: .oneSided, tag: tag)
        // Edge 0 is segment 0 on the start cap, edge 1 the same segment on the end cap.
        #expect(solid.topology.edges[0].curve == .line(start: Vector3(-5, -10, 0), end: Vector3(5, -10, 0)))
        #expect(solid.topology.edges[1].curve == .line(start: Vector3(-5, -10, 5), end: Vector3(5, -10, 5)))
    }

    @Test func wallEdgesRiseFromTheCornerWhereTheirSegmentEnds() async throws {
        let solid = try await FakeKernel().extrude(.rectangle(width: 10, height: 20, plane: .xy), distance: 5,
                                                   mode: .oneSided, tag: tag)
        // Edges 0–7 are the caps' (two per segment); edge 8 is between sides 0 and 1, at segment 0's end.
        #expect(solid.topology.edges[8].curve == .line(start: Vector3(5, -10, 0), end: Vector3(5, -10, 5)))
        #expect(solid.topology.edges.allSatisfy { $0.curve != nil })
    }

    @Test func aClockwiseArcIsReportedCounterClockwiseFromItsEnd() async throws {
        let notch = Segment2D.arc(center: Vector2(10, 10), radius: 4, start: .degrees(0), end: .degrees(-180))
        let loop: [Segment2D] = [
            .line(Vector2(0, 0), Vector2(20, 0)), .line(Vector2(20, 0), Vector2(20, 10)),
            .line(Vector2(20, 10), Vector2(14, 10)), notch,
            .line(Vector2(6, 10), Vector2(0, 10)), .line(Vector2(0, 10), Vector2(0, 0)),
        ]
        let solid = try await FakeKernel().extrude(Profile2D(plane: .xy, segments: loop), distance: 2, mode: .oneSided, tag: tag)
        // Segment 3's start-cap edge is edge 6.
        guard case .circle(let center, let axis, let radius, let start, let sweep)? = solid.topology.edges[6].curve else {
            Issue.record("expected a circle")
            return
        }
        #expect(center == Vector3(10, 10, 0) && axis == .unitZ && radius == 4)
        #expect((start - Vector3(6, 10, 0)).length < 1e-9)
        #expect(abs(sweep - .pi) < 1e-12)
    }
}

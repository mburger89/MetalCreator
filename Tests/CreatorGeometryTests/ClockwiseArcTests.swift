import Foundation
import Testing
@testable import CreatorGeometry

/// S4: an arc with `end < start` runs clockwise, the way a counter-clockwise loop runs along a
/// notch cut into an outline (sketcher spec §5 step 5).
struct ClockwiseArcTests {
    /// The semicircular notch in the top edge of the 20 × 10 plate, run clockwise from (14, 10) to (6, 10).
    let notch = Segment2D.arc(center: Vector2(10, 10), radius: 4, start: .degrees(0), end: .degrees(-180))

    @Test func aClockwiseArcHasAPositiveLength() {
        #expect(isClose(notch.length, 4 * .pi))
    }

    @Test func aClockwiseArcRunsFromStartToEnd() {
        #expect(isClose(Vector3(notch.startPoint.x, notch.startPoint.y, 0), Vector3(14, 10, 0)))
        #expect(isClose(Vector3(notch.endPoint.x, notch.endPoint.y, 0), Vector3(6, 10, 0)))
    }

    @Test func aLoopThroughAClockwiseArcIsClosed() {
        let loop: [Segment2D] = [
            .line(Vector2(0, 0), Vector2(20, 0)), .line(Vector2(20, 0), Vector2(20, 10)),
            .line(Vector2(20, 10), Vector2(14, 10)), notch,
            .line(Vector2(6, 10), Vector2(0, 10)), .line(Vector2(0, 10), Vector2(0, 0)),
        ]
        #expect(Profile2D(plane: .xy, segments: loop).isClosed)
    }
}

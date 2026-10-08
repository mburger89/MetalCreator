import Testing
@testable import CreatorGeometry

struct ProfileHoleTests {
    let square = Profile2D.rectangle(width: 10, height: 10, plane: .xy).segments
    let hole: [Segment2D] = Profile2D.circle(radius: 2, center: Vector2(1, 1), plane: .xy).segments

    @Test func theSegmentsInitialiserMakesAProfileWithoutHoles() {
        let plain = Profile2D(plane: .xy, segments: square)
        #expect(plain.outer == square)
        #expect(plain.holes.isEmpty)
        #expect(plain.segments == square)
        #expect(plain == Profile2D(plane: .xy, outer: square))
    }

    @Test func loopsListTheOuterLoopFirst() {
        let profile = Profile2D(plane: .xy, outer: square, holes: [hole])
        #expect(profile.loops == [square, hole])
        #expect(profile.segments == square)
        #expect(profile.segmentCount == 5)
        #expect(profile != Profile2D(plane: .xy, segments: square))
    }

    @Test func settingSegmentsKeepsTheHoles() {
        var profile = Profile2D(plane: .xy, outer: square, holes: [hole])
        profile.segments = Profile2D.rectangle(width: 20, height: 20, plane: .xy).segments
        #expect(profile.holes == [hole])
    }

    @Test func isClosedChecksEveryLoop() {
        #expect(Profile2D(plane: .xy, outer: square, holes: [hole]).isClosed)
        let openHole: [Segment2D] = [.line(Vector2(0, 0), Vector2(1, 0)), .line(Vector2(1, 0), Vector2(1, 1))]
        #expect(!Profile2D(plane: .xy, outer: square, holes: [openHole]).isClosed)
        #expect(!Profile2D(plane: .xy, outer: square, holes: [[]]).isClosed)
        #expect(!Profile2D(plane: .xy, outer: [], holes: [hole]).isClosed)
    }

    @Test func translatingMovesTheHolesToo() {
        let moved = Profile2D(plane: .xy, outer: square, holes: [hole]).translated(by: Vector2(3, 4))
        guard case .arc(let center, _, _, _)? = moved.holes.first?.first else { Issue.record("expected an arc"); return }
        #expect(center == Vector2(4, 5))
        #expect(moved.outer[0].startPoint == Vector2(-2, -1))
    }

    @Test func boundsCoverEveryLoop() throws {
        // A hole that sticks out past the outline, so outer-only bounds would stop at x = 5.
        let stray = Profile2D.circle(radius: 1, center: Vector2(20, 0), plane: .xy).segments
        let bounds = try #require(Profile2D(plane: .xy, outer: square, holes: [hole, stray]).bounds)
        #expect(bounds.min == Vector3(-5, -5, 0))
        #expect(bounds.max == Vector3(21, 5, 0))
        #expect(Profile2D(plane: .xy, outer: [], holes: [hole]).bounds != nil)
    }
}

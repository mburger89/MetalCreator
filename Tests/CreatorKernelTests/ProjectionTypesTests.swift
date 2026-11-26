import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

struct ProjectionTypesTests {
    @Test func frontPlacesXAndZ() {
        let frame = ProjectionFrame(direction: Vector3(0, 1, 0), up: Vector3(0, 0, 1))
        #expect(frame.place(Vector3(3, 7, 5)) == Vector2(3, 5))
        #expect(frame.right == Vector3(1, 0, 0))
    }

    @Test func makeOrthonormalises() throws {
        let frame = try #require(ProjectionFrame.make(direction: Vector3(0, 2, 0), up: Vector3(0, 1, 1)))
        #expect(frame.direction == Vector3(0, 1, 0))
        #expect((frame.up - Vector3(0, 0, 1)).length < 1e-12)
    }

    @Test func parallelUpIsNil() {
        #expect(ProjectionFrame.make(direction: Vector3(0, 1, 0), up: Vector3(0, 3, 0)) == nil)
        #expect(ProjectionFrame.make(direction: .zero, up: Vector3(0, 0, 1)) == nil)
    }

    @Test func hugeNearParallelUpIsNil() {
        let direction = Vector3(0, 1, 0)
        let up = (direction + Vector3(1e-12, 0, 0)) * 1e9
        #expect(ProjectionFrame.make(direction: direction, up: up) == nil)
    }

    @Test func validateRefuses() {
        let sentence = "The view direction and its up direction must be perpendicular unit vectors."
        for frame in [ProjectionFrame(direction: Vector3(0, 2, 0), up: Vector3(0, 0, 1)),
                      ProjectionFrame(direction: Vector3(0, 1, 0), up: Vector3(0, 1, 0)),
        ] {
            do {
                try frame.validate()
                Issue.record("expected a refusal")
            } catch {
                #expect(error.userMessage.contains(sentence))
            }
        }
        #expect(throws: Never.self) { try ProjectionFrame(direction: Vector3(0, 1, 0), up: Vector3(0, 0, 1)).validate() }
    }

    @Test func arcBoundsUseExtremes() {
        let box = ProjectedCurve.arc(center: Vector2(0, 0), radius: 2, start: 0, sweep: .pi).bounds
        #expect(abs(box.min.x + 2) < 1e-12 && abs(box.min.y) < 1e-12)
        #expect(abs(box.max.x - 2) < 1e-12 && abs(box.max.y - 2) < 1e-12)
    }

    @Test func ellipseBoundsAreExact() {
        let flat = ProjectedCurve.ellipse(center: .zero, majorAxis: Vector2(1, 0), majorRadius: 5, minorRadius: 3, start: 0,
                                          sweep: 2 * .pi).bounds
        #expect(abs(flat.max.x - 5) < 1e-9 && abs(flat.min.x + 5) < 1e-9 && abs(flat.max.y - 3) < 1e-9 && abs(flat.min.y + 3) < 1e-9)
        let tall = ProjectedCurve.ellipse(center: .zero, majorAxis: Vector2(0, 1), majorRadius: 5, minorRadius: 3, start: 0,
                                          sweep: 2 * .pi).bounds
        #expect(abs(tall.max.x - 3) < 1e-9 && abs(tall.min.x + 3) < 1e-9 && abs(tall.max.y - 5) < 1e-9 && abs(tall.min.y + 5) < 1e-9)
    }

    @Test func projectionBoundsCoverHiddenLines() {
        let projection = Projection2D(lines: [
            ProjectedLine(visibility: .visible, lineClass: .sharp, curve: .line(Vector2(0, 0), Vector2(1, 1)), source: nil),
            ProjectedLine(visibility: .hidden, lineClass: .sharp, curve: .polyline([Vector2(-3, 0), Vector2(0, 7)]), source: nil),
        ])
        #expect(projection.bounds == Rect2D(min: Vector2(-3, 0), max: Vector2(1, 7)))
        #expect(projection.estimatedBytes == 64 + 64 + 32)
        #expect(Projection2D().bounds == nil)
    }
}

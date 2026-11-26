import CreatorGeometry
import Foundation
import Testing

@testable import CreatorKernel

struct SectionCutterTests {
    private let frame = ProjectionFrame(direction: Vector3(0, 0, -1), up: Vector3(0, 1, 0))

    private func cutter(_ points: [(Double, Double)], viewing: Vector2 = Vector2(0, 1)) -> SectionCutter {
        SectionCutter(frame: frame, points: points.map { Vector2($0.0, $0.1) }, viewing: viewing)
    }

    private func refusal(_ cutter: SectionCutter) -> String? {
        do {
            try cutter.validate()
            return nil
        } catch {
            if case .invalidInput(let message) = error { return message }
            return "other"
        }
    }

    private let alternate = "A stepped cutting line alternates cuts and steps at right angles, starting and ending with a cut."

    @Test func aStraightLineIsValid() {
        #expect(refusal(cutter([(0, 0), (10, 0)])) == nil)
    }

    @Test func underTwoPointsIsRefused() {
        #expect(refusal(cutter([(0, 0)])) == "A cutting line needs at least two points.")
    }

    @Test func oneSegmentAfterAnotherMustAlternate() {
        #expect(refusal(cutter([(0, 0), (10, 0), (20, 0)])) == alternate)
        #expect(refusal(cutter([(0, 0), (10, 0), (10, 5), (20, 5)])) == nil)
    }

    @Test func anEvenCountIsRefused() {
        #expect(refusal(cutter([(0, 0), (10, 0), (10, 5)])) == alternate)
    }

    @Test func aCutAgainstTheFirstIsRefused() {
        #expect(
            refusal(cutter([(0, 0), (10, 0), (10, 5), (0, 5)]))
                == "Every cut of a stepped cutting line runs the same way as the first.")
    }

    @Test func aSlantedStepIsRefused() {
        #expect(refusal(cutter([(0, 0), (10, 0), (12, 5), (20, 5)])) == alternate)
    }

    @Test func pointsMustBeApart() {
        #expect(refusal(cutter([(0, 0), (0, 0)])) == "A cutting line's points must be apart.")
    }

    @Test func viewingMustBeSquare() {
        let message = "The cutting line's view direction must be square to it."
        #expect(refusal(cutter([(0, 0), (10, 0)], viewing: Vector2(1, 0))) == message)
        #expect(refusal(cutter([(0, 0), (10, 0)], viewing: Vector2(0, 2))) == message)
    }

    @Test func thePolygonFollowsTheLine() {
        let line = cutter([(0, 0), (10, 0), (10, 5), (20, 5)])
        #expect(line.removedPolygon(reach: 100) == [
            Vector2(-100, 0), Vector2(10, 0), Vector2(10, 5), Vector2(120, 5), Vector2(120, -95), Vector2(-100, -100),
        ])
        #expect(line.cutIndices == [0, 2])
        #expect(line.direction == Vector2(1, 0))
    }

    @Test func codableRoundTrip() throws {
        let line = cutter([(0, 0), (10, 0), (10, 5), (20, 5)])
        let back = try JSONDecoder().decode(SectionCutter.self, from: JSONEncoder().encode(line))
        #expect(back == line)
    }

    @Test func theToolNodeIsFixed() {
        #expect(SectionCutter.toolNode.rawValue.uuidString == "5EC7C0DE-0D30-4000-8000-000000000001")
    }
}

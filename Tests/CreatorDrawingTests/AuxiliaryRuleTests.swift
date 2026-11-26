import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Auxiliary rule")
struct AuxiliaryRuleTests {
    private let frame = StandardOrientation.top.frame
    private let mapping = ViewMapping(scale: 1, offset: .zero)
    private let click = Vector2.zero

    private var topology: Topology {
        TopologyFixtures.plate(edges: [
            TopologyFixtures.line(1, Vector3(0, 0, 0), Vector3(10, 4, 0), between: 0, 2),
            TopologyFixtures.line(2, Vector3(0, 0, 0), Vector3(0, 0, 10), between: 2, 3),
            TopologyFixtures.circle(3, center: Vector3(5, 5, 0), axis: Vector3(0, 0, 1), radius: 2, between: 0, 1),
            TopologyFixtures.line(4, Vector3(2, 2, 0), Vector3(2, 2.5, 0), between: 1, 2),
        ])
    }

    private func arrow(_ candidate: PickCandidate) -> Result<(at: Vector2, along: Vector2), DrawingRefusal> {
        AuxiliaryRule.arrow(for: candidate, click: click, topology: topology, frame: frame, mapping: mapping)
    }

    @Test func aSquareLineGivesItsMidpointAndDirection() throws {
        let result = try arrow(.edge(EdgeID(1), stroke: 0)).get()
        let start = frame.place(Vector3(0, 0, 0)), end = frame.place(Vector3(10, 4, 0))
        #expect((result.at - (start + end) * 0.5).length < 1e-12)
        let d = end - start
        #expect((result.along - d * (1 / d.length)).length < 1e-12)
    }

    @Test func aCornerPicksItsLine() throws {
        let result = try arrow(.corner(EdgeID(4), at: Vector2(2, 2))).get()
        let a = frame.place(Vector3(2, 2, 0)), b = frame.place(Vector3(2, 2.5, 0))
        #expect((result.at - (a + b) * 0.5).length < 1e-12)
        #expect((result.along - Vector2(frame.place(Vector3(0, 0.5, 0)).x, frame.place(Vector3(0, 0.5, 0)).y) * 2).length < 1e-12)
    }

    @Test func aCentreIsRefused() {
        #expect(refusal(arrow(.centre(EdgeID(3), at: Vector2(5, 5)))) == AuxiliaryRule.lineSentence)
    }

    @Test func aCircleIsRefused() {
        #expect(refusal(arrow(.edge(EdgeID(3), stroke: 0))) == "An auxiliary view looks square to a straight edge; pick a line.")
    }

    @Test func aTiltedLineIsRefused() {
        #expect(
            refusal(arrow(.edge(EdgeID(2), stroke: 0)))
                == "This edge isn't square to the view, so a view square to it wouldn't show its true size.")
    }

    @Test func anOutlineIsRefused() {
        #expect(refusal(arrow(.outline(FaceID(0), stroke: 0))) == AuxiliaryRule.lineSentence)
    }

    private func refusal(_ result: Result<(at: Vector2, along: Vector2), DrawingRefusal>) -> String? {
        if case .failure(let refused) = result { return refused.sentence }
        return nil
    }
}

import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Lost annotation labels")
struct AnnotationLostLabelTests {
    private typealias Fixtures = AnnotationFixtures
    private let topology = Fixtures.topology()
    private let figure = AnnotationFigure.linear(points: [Vector2(0, 0), Vector2(40, 0)], direction: Vector2(1, 0))

    private func remembered(_ id: AnnotationID) -> [AnnotationID: LastGood] {
        [id: LastGood(values: [40], lines: ["40"], figure: figure)]
    }

    private func dimension(_ view: DrawingView, tolerance: DimensionTolerance) -> DrawingAnnotation {
        DrawingAnnotation(
            view: view.id,
            kind: .dimension(
                DrawingDimension(
                    kind: .linear(.horizontal), anchors: [Fixtures.pick(topology, 102)],
                    placement: DimensionPlacement(offset: 10, angle: 0), tolerance: tolerance)))
    }

    @Test func aLostBasicDimensionStaysBoxed() {
        let view = Fixtures.makeView()
        let boxed = dimension(view, tolerance: .basic)
        let picture = Fixtures.compose(
            view, [boxed], content: Fixtures.content(Fixtures.topology(removing: [102])), remembered: remembered(boxed.id))
        #expect(Fixtures.texts(picture, of: boxed.id).map(\.original) == ["40?"])
        let boxes = Fixtures.strokes(picture, of: boxed.id).filter { stroke in
            if stroke.segments.count == 1, case .polyline(let points) = stroke.segments[0] { points.count == 5 } else { false }
        }
        #expect(boxes.count == 1 && boxes.allSatisfy(\.isLost))
    }

    @Test func aLostDeviationKeepsItsStack() {
        let view = Fixtures.makeView()
        let toleranced = dimension(view, tolerance: .deviation(upper: 0.1, lower: -0.2))
        let picture = Fixtures.compose(
            view, [toleranced], content: Fixtures.content(Fixtures.topology(removing: [102])),
            remembered: remembered(toleranced.id))
        let texts = Fixtures.texts(picture, of: toleranced.id).map(\.original)
        #expect(texts.contains("40?") && texts.count >= 3)
    }

    @Test func aNonFiniteMeasureIsLost() throws {
        let view = Fixtures.makeView()
        // A circle whose diameter overflows: finite geometry, an infinite value.
        let huge = Fixtures.dimension(view.id, .diameter, [Fixtures.pick(topology, 0)])
        let broken = Topology(
            faces: topology.faces,
            edges: topology.edges.map {
                $0.id.rawValue == 0
                    ? TopologyFixtures.circle(0, center: Vector3(20, 10, 0), axis: Vector3(0, 0, 1), radius: 1e308, between: 2, 0)
                    : $0
            })
        let picture = Fixtures.compose(view, [huge], content: Fixtures.content(broken))
        let report = try #require(picture.annotationReports[huge.id])
        #expect(report.status == .lost(.refused("What it measures has no finite size here.")), "\(report.status)")
    }
}

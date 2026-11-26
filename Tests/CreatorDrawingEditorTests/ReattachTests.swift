import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// A click on a line of the view re-attaches the one lost annotation that is selected, or says why it can't (plan R15).
@MainActor
@Suite("Re-attaching")
struct ReattachTests {
    typealias Fixtures = AnnotationEditorFixtures

    private struct Opened {
        let h: EditorHarness
        let view: DrawingView
        let mapping: ViewMapping
        let id: AnnotationID
    }

    /// A horizontal dimension between the edges `anchors` of the full part, shown against `content`.
    private func open(
        _ content: ViewContent, orientation: StandardOrientation = .top, anchors: [Int], kind: DrawingDimensionKind = .linear(.horizontal)
    ) -> Opened {
        let full = Fixtures.topology()
        let annotation = DrawingAnnotation(
            view: nil,
            kind: .dimension(
                DrawingDimension(
                    kind: kind, anchors: anchors.map { Fixtures.pick(full, $0) },
                    placement: DimensionPlacement(offset: 10, angle: 0))))
        let view = EditorDocuments.view(at: Fixtures.centre, orientation: orientation)
        var placed = annotation
        placed.view = view.id
        let sheet = DrawingSheet(name: "Sheet 1", views: [view], annotations: [placed])
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id, contents: [view.id: content])
        h.model.transform = SheetTransform(offset: Vector2(0, 297 * 4), zoom: 4)
        h.model.selectedAnnotations = [placed.id]
        return Opened(h: h, view: view, mapping: Fixtures.mapping(content), id: placed.id)
    }

    private func click(_ o: Opened, _ x: Double, _ y: Double) {
        let point = o.mapping.sheet(Vector2(x, y))
        o.h.click(point.x, point.y)
    }

    private func dimension(_ o: Opened) throws -> DrawingDimension {
        guard case .dimension(let dimension)? = o.h.model.document.sheets[0].annotation(o.id)?.kind else {
            throw CancellationError()
        }
        return dimension
    }

    @Test func aClickReplacesTheFirstLostAnchor() throws {
        let full = Fixtures.topology()
        let o = open(Fixtures.top(Fixtures.topology(removing: [103])), anchors: [100, 103])
        let report = try #require(o.h.model.picture?.annotationReports[o.id])
        #expect(report.anchors == [.held, .lost(.missing)], "\(report.anchors)")
        let before = try dimension(o)
        click(o, 30, 15)
        #expect(o.h.log.commits.map(\.name) == ["Reattach Dimension"], "\(o.h.model.refusal ?? "")")
        let after = try dimension(o)
        #expect(after.anchors[0] == before.anchors[0], "the held anchor stays")
        #expect(after.anchors[1] == Fixtures.pick(full, 106))
        #expect(o.h.model.picture?.annotationReports[o.id]?.status == .held, "the dimension is held again")
        #expect(o.h.model.selectedAnnotations == [o.id])
    }

    @Test func theSameCaseIsRequired() throws {
        let o = open(Fixtures.top(Fixtures.topology(removing: [103])), anchors: [100, 103])
        // The end of the bottom line is a corner; the lost anchor was an edge.
        click(o, 0.2, 0.2)
        #expect(
            o.h.model.refusal == "Pick the same kind of thing the annotation lost: a line, a circle, a corner or a centre.",
            "\(o.h.model.refusal ?? "")")
        #expect(o.h.log.commits.isEmpty)
    }

    @Test func aPickTheAnnotationCannotMeasureIsRefused() throws {
        // A radius whose circle is gone, pointed at a straight edge: same case, but it would stay lost "not a line or circle".
        let o = open(Fixtures.top(Fixtures.topology(removing: [0])), anchors: [0], kind: .radius)
        #expect(o.h.model.picture?.annotationReports[o.id]?.firstLostAnchor == 0)
        click(o, 10, 0)
        #expect(o.h.model.refusal != nil && o.h.model.refusal != DrawingEditorModel.sameKindSentence, "\(o.h.model.refusal ?? "")")
        #expect(o.h.log.commits.isEmpty, "nothing is stored that would stay lost")
    }

    @Test func onlyWithOneLostSelected() throws {
        let o = open(Fixtures.top(), anchors: [100, 103])
        #expect(o.h.model.picture?.annotationReports[o.id]?.status == .held)
        click(o, 30, 15)
        #expect(o.h.model.selection == [o.view.id], "a held selection: the click selects the view as before")
        #expect(o.h.log.commits.isEmpty)
    }

    @Test func aMeasureLevelLossIsNotReattached() throws {
        // The diagonal runs along the front view's direction: its dimension is foreshortened, and every anchor is still held.
        let o = open(Fixtures.front(), orientation: .front, anchors: [105])
        let report = try #require(o.h.model.picture?.annotationReports[o.id])
        #expect(report.isLost && report.firstLostAnchor == nil, "\(report)")
        click(o, 20, 10)
        #expect(
            o.h.model.refusal == """
                What it was attached to is still there; it is lost because of what that measures now. Delete it or change the model.
                """)
        #expect(o.h.log.commits.isEmpty)
        #expect(o.h.model.selectedAnnotations == [o.id])
    }

    @Test func aViewWithNoPartIsNotReattached() throws {
        var content = Fixtures.top()
        content.problem = "The view failed."
        let o = open(content, anchors: [100, 103])
        let report = try #require(o.h.model.picture?.annotationReports[o.id])
        #expect(report.isLost && report.anchors.isEmpty, "\(report)")
        click(o, 30, 15)
        #expect(o.h.model.refusal == "Its view has no part to attach it to.")
        #expect(o.h.log.commits.isEmpty)
        #expect(o.h.model.selectedAnnotations == [o.id])
    }
}

import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The Auxiliary tool: pick a straight edge square to the view, then click where the view goes (plan R9, R11, R13).
@MainActor
@Suite("Auxiliary tool")
struct AuxiliaryToolTests {
    typealias Fixtures = AnnotationEditorFixtures

    private func open(
        _ content: ViewContent = Fixtures.top(), orientation: StandardOrientation = .top
    ) -> OpenedView {
        OpenedView.make(content, orientation: orientation)
    }

    private func auxiliary(_ o: OpenedView) -> DrawingView? { o.h.model.document.sheets[0].views.first { $0.kind == .auxiliary } }

    @Test func aLineThenAClickPlacesIt() throws {
        let o = open()
        o.h.model.press(.auxiliaryView)
        // The diagonal from (0, 0) to (15, 15), clicked in its middle (7.5, 7.5).
        o.click(o.at(7.5, 7.5))
        let draft = try #require(o.h.model.auxiliaryDraft)
        #expect(draft.parent == o.view.id)
        #expect((draft.at - Vector2(7.5, 7.5)).length < 1e-9)
        #expect(abs(draft.along.x - 0.5.squareRoot()) < 1e-9 && abs(draft.along.y - 0.5.squareRoot()) < 1e-9)
        #expect(o.h.log.commits.isEmpty)
        o.click(o.at(40, 30))
        #expect(o.h.log.commits.map(\.name) == ["Add View"])
        let made = try #require(auxiliary(o))
        #expect(made.kind == .auxiliary)
        #expect(made.alignment == nil)
        #expect(made.showsLabel)
        #expect(made.letter == "A")
        guard case .auxiliary(let arrow)? = made.derivation else {
            Issue.record("no derivation")
            return
        }
        #expect(arrow.parent == o.view.id)
        #expect(arrow.parentFrame == StandardOrientation.top.frame)
        #expect((arrow.at - Vector2(7.5, 7.5)).length < 1e-9)
        // Square to the edge, toward the drop at (40, 30), which is below the diagonal.
        #expect(abs(arrow.viewing.x - 0.5.squareRoot()) < 1e-9 && abs(arrow.viewing.y + 0.5.squareRoot()) < 1e-9)
        let frame = try #require({ () -> ProjectionFrame? in
            if case .custom(let frame) = made.orientation { frame } else { nil }
        }())
        #expect(abs(frame.direction.dot(Vector3(0.5.squareRoot(), 0.5.squareRoot(), 0))) < 1e-9)
        #expect(o.h.model.selection == [made.id])
        #expect(o.h.model.auxiliaryDraft == nil)
    }

    @Test func aClickNearALinesEndPicksIt() throws {
        let o = open()
        o.h.model.press(.auxiliaryView)
        // Near the diagonal's far end (15, 15), which is a corner candidate.
        o.click(o.at(14.5, 14.6))
        let draft = try #require(o.h.model.auxiliaryDraft)
        #expect((draft.at - Vector2(7.5, 7.5)).length < 1e-9)
    }

    @Test func aCircleIsRefused() throws {
        let o = open()
        o.h.model.press(.auxiliaryView)
        o.click(o.at(23, 10))
        #expect(o.h.model.refusal == "An auxiliary view looks square to a straight edge; pick a line.")
        #expect(o.h.model.auxiliaryDraft == nil)
    }

    @Test func aTiltedEdgeIsRefused() throws {
        // Seen from the front, the diagonal's depth runs across the view direction: it isn't square to it.
        let o = open(Fixtures.front(), orientation: .front)
        o.h.model.press(.auxiliaryView)
        o.click(o.at(7.5, 0))
        #expect(
            o.h.model.refusal == "This edge isn't square to the view, so a view square to it wouldn't show its true size.")
        #expect(o.h.model.auxiliaryDraft == nil)
    }

    @Test func aDetailParentIsRefused() throws {
        let base = EditorDocuments.view(at: Vector2(150, 150))
        let detail = DrawingView(
            kind: .detail, source: base.source, orientation: base.orientation, center: Vector2(150, 150),
            derivation: .detail(DetailCircle(parent: base.id, center: Vector2(10, 10), radius: 5)), letter: "A")
        let sheet = DrawingSheet(name: "Sheet 1", views: [detail])
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        h.model.press(.auxiliaryView)
        h.click(150, 150)
        #expect(h.model.refusal == "Pick the edge for an auxiliary view on the view the detail enlarges.")
        #expect(h.model.auxiliaryDraft == nil)
    }

    private func placedAuxiliary() throws -> (OpenedView, DrawingView) {
        let o = open()
        o.h.model.press(.auxiliaryView)
        o.click(o.at(7.5, 7.5))
        o.click(o.at(40, 30))
        o.h.log.commits.removeAll()
        o.h.model.press(.select)
        o.h.model.selection = []
        return (o, try #require(auxiliary(o)))
    }

    @Test func anAuxiliaryViewTakesDimensions() throws {
        let (o, made) = try placedAuxiliary()
        // The auxiliary view shows the diagonal at true length: one straight line, dimensioned by the tool.
        let content = ViewContent(
            projection: Projection2D(lines: [
                ProjectedLine(
                    visibility: .visible, lineClass: .sharp, curve: .line(Vector2(0, 0), Vector2(21.2, 0)),
                    source: .edge(EdgeID(105))),
                ProjectedLine(
                    visibility: .visible, lineClass: .sharp, curve: .line(Vector2(0, -5), Vector2(0, 5)),
                    source: .edge(EdgeID(102))),
            ]),
            topology: Fixtures.topology())
        o.h.model.contents[made.id] = content
        let mapping = try #require(
            ViewMapping.of(content: content, center: made.center, scale: o.h.model.document.sheets[0].scale.value))
        o.h.model.press(.dimension)
        o.h.click(mapping.sheet(Vector2(10, 0)).x, mapping.sheet(Vector2(10, 0)).y)
        #expect(o.h.model.refusal == nil, "\(o.h.model.refusal ?? "")")
        #expect(o.h.model.picks.count == 1)
        let side = mapping.sheet(Vector2(10, 0)) + Vector2(0, 8)
        o.h.click(side.x, side.y)
        #expect(o.h.log.commits.map(\.name) == ["Add Dimension"])
    }

    @Test func aDetailOfAnAuxiliaryViewTakesDimensions() throws {
        let (o, made) = try placedAuxiliary()
        let frame = made.orientation
        let detail = DrawingView(
            kind: .detail, source: made.source, orientation: frame, center: Vector2(100, 100),
            derivation: .detail(DetailCircle(parent: made.id, center: Vector2(0, 10), radius: 5)), letter: "B")
        var document = o.h.model.document
        var sheet = document.sheets[0]
        sheet.setView(detail)
        document.sheets[0] = sheet
        o.h.model.replaceDocument(document)
        #expect(!sheet.isPictorial(detail))
        let content = ViewContent(
            projection: Projection2D(lines: [
                ProjectedLine(
                    visibility: .visible, lineClass: .sharp, curve: .line(Vector2(-10, 0), Vector2(10, 0)),
                    source: .edge(EdgeID(105))),
            ]),
            topology: Fixtures.topology(), framing: Rect2D(min: Vector2(-12, -12), max: Vector2(12, 12)))
        o.h.model.contents[detail.id] = content
        let mapping = try #require(
            ViewMapping.of(content: content, center: detail.center, scale: sheet.scale.value))
        o.h.model.press(.dimension)
        let on = mapping.sheet(Vector2(0, 0))
        o.h.click(on.x, on.y)
        #expect(o.h.model.refusal != DrawingPick.isometricSentence)
        #expect(o.h.model.refusal == nil, "\(o.h.model.refusal ?? "")")
        #expect(o.h.model.picks.count == 1)
    }

    @Test func theUKeyChoosesTheTool() throws {
        #expect(SheetCanvasInput.key("u", modifiers: []) == .tool(.auxiliaryView))
    }
}

import CreatorGeometry
import Foundation
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The Section tool: the cutting line drawn on a parent view, finished, and the click that places the view (plan R3, R13).
@MainActor
@Suite("Section tool")
struct SectionToolTests {
    typealias Fixtures = AnnotationEditorFixtures

    func open(
        _ content: ViewContent = Fixtures.top(), orientation: StandardOrientation = .top, settings: DrawingSettings = DrawingSettings()
    ) -> OpenedView {
        let o = OpenedView.make(content, orientation: orientation)
        guard settings != DrawingSettings() else { return o }
        let sheet = o.h.model.document.sheets[0]
        let h = EditorHarness(
            document: EditorDocuments.document([sheet], settings: settings), sheet: sheet.id, contents: [o.view.id: content])
        return OpenedView(h: h, view: o.view, mapping: o.mapping, content: content)
    }

    /// A straight horizontal line across the plate, finished.
    func finishedLine(_ o: OpenedView) {
        o.h.model.press(.section)
        o.click(o.at(5, 10))
        o.click(o.at(35, 10))
        o.h.model.keyPressed(.finish)
    }

    func section(_ o: OpenedView) -> DrawingView? { o.h.model.document.sheets[0].views.first { $0.kind == .section } }

    @Test func twoClicksAndReturnMakeAStraightLine() throws {
        let o = open()
        o.h.model.press(.section)
        o.click(o.at(5, 10))
        #expect(o.h.model.sectionDraft?.points.count == 1)
        o.click(o.at(35, 10))
        #expect(o.h.model.sectionDraft?.points.count == 2)
        #expect(o.h.model.sectionDraft?.isFinished == false)
        #expect(o.h.model.keyPressed(.finish))
        let draft = try #require(o.h.model.sectionDraft)
        #expect(draft.isFinished)
        #expect(draft.parent == o.view.id)
        #expect(o.h.log.commits.isEmpty)
        #expect(o.h.model.draftPicture != nil)
    }

    @Test func theFirstSegmentSnapsWithinFiveDegrees() throws {
        let o = open()
        o.h.model.press(.section)
        o.click(o.at(5, 10))
        // 4 degrees off the horizontal.
        let end = Vector2(35, 10 + 30 * tan(4 * .pi / 180))
        o.click(o.at(end.x, end.y))
        let points = try #require(o.h.model.sectionDraft?.points)
        #expect(abs(points[1].y - points[0].y) < 1e-9)
    }

    @Test func shiftKeepsTheSlant() throws {
        let o = open()
        o.h.model.press(.section)
        o.click(o.at(5, 10))
        let end = Vector2(35, 10 + 30 * tan(4 * .pi / 180))
        o.click(o.at(end.x, end.y), .shift)
        let points = try #require(o.h.model.sectionDraft?.points)
        #expect(abs(points[1].y - end.y) < 1e-6)
    }

    /// The end of the previewed chain that lies furthest right.
    private func previewEnd(_ o: OpenedView) throws -> Vector2 {
        let picture = try #require(o.h.model.draftPicture)
        let chain = picture.strokes.filter { $0.mark == o.h.model.draftViewID && $0.layer == .center }
        let ends = chain.flatMap { stroke in
            stroke.segments.flatMap { segment -> [Vector2] in
                switch segment {
                case let .line(a, b): [a, b]
                case let .polyline(points): points
                default: []
                }
            }
        }
        return try #require(ends.max { $0.x < $1.x })
    }

    @Test func thePreviewSnapsLikeTheClick() throws {
        let o = open()
        o.h.model.press(.section)
        o.click(o.at(5, 10))
        // 4 degrees off the horizontal: the click snaps it, so does the preview, which moves the pointer without pressing.
        let end = Vector2(35, 10 + 30 * tan(4 * .pi / 180))
        o.h.model.pointerMoved(to: o.h.canvas(o.at(end.x, end.y).x, o.at(end.x, end.y).y))
        let previewed = try previewEnd(o)
        #expect(abs(previewed.y - o.at(5, 10).y) < 1e-6, "the first segment snaps to the horizontal within 5 degrees")
        o.h.model.modifiersChanged(.shift)
        #expect(abs(try previewEnd(o).y - o.at(end.x, end.y).y) < 1e-6, "Shift keeps the slant in the preview too")
        o.h.model.modifiersChanged([])
        // The plate's corner at (40, 0) is within the snap reach: the preview ends on it, as a click would.
        let near = o.at(40, 0) + Vector2(0.3, 0.2)
        o.h.model.pointerMoved(to: o.h.canvas(near.x, near.y))
        let cornered = try previewEnd(o)
        #expect((cornered - o.at(40, 0)).length < 1e-6, "the preview ends on the corner: \(cornered) against \(o.at(40, 0))")
    }

    @Test func leavingTheCanvasClearsAHeldShift() {
        let o = open()
        o.h.model.modifiersChanged(.shift)
        #expect(o.h.model.heldModifiers == .shift)
        o.h.model.pointerLeft()
        #expect(o.h.model.heldModifiers.isEmpty)
    }

    @Test func laterPointsAreConstrained() throws {
        let o = open()
        o.h.model.press(.section)
        o.click(o.at(5, 10))
        o.click(o.at(20, 10))
        // A step moves only across: the click's x is ignored.
        o.click(o.at(23, 16))
        var points = try #require(o.h.model.sectionDraft?.points)
        #expect(points.count == 3)
        #expect(abs(points[2].x - 20) < 1e-9 && abs(points[2].y - 16) < 1e-9)
        // A cut moves only along: the click's y is ignored.
        o.click(o.at(35, 14))
        points = try #require(o.h.model.sectionDraft?.points)
        #expect(points.count == 4)
        #expect(abs(points[3].x - 35) < 1e-9 && abs(points[3].y - 16) < 1e-9)
    }

    @Test func clickingTheLastPointFinishes() throws {
        let o = open()
        o.h.model.press(.section)
        o.click(o.at(5, 10))
        o.click(o.at(35, 10))
        o.click(o.at(35, 10))
        #expect(o.h.model.sectionDraft?.isFinished == true)
        #expect(o.h.model.sectionDraft?.points.count == 2)
    }

    @Test func anEvenCountIsRefusedAtFinish() throws {
        let o = open()
        o.h.model.press(.section)
        o.click(o.at(5, 10))
        o.click(o.at(20, 10))
        o.click(o.at(20, 16))
        #expect(o.h.model.keyPressed(.finish))
        #expect(o.h.model.refusal == "A stepped cutting line ends with a cut, not a step.")
        let draft = try #require(o.h.model.sectionDraft)
        #expect(!draft.isFinished)
        #expect(draft.points.count == 3)
    }

    @Test func aCutAgainstTheFirstIsRefused() throws {
        let o = open()
        o.h.model.press(.section)
        o.click(o.at(5, 10))
        o.click(o.at(20, 10))
        o.click(o.at(20, 16))
        o.click(o.at(8, 16))
        #expect(o.h.model.refusal == "Every cut of a stepped cutting line runs the same way as the first.")
        #expect(o.h.model.sectionDraft?.points.count == 3)
    }

    @Test func pointsSnapToCentres() throws {
        let o = open()
        o.h.model.press(.section)
        // The hole's centre is (20, 10); click near it.
        o.click(o.at(20.5, 10.4))
        let points = try #require(o.h.model.sectionDraft?.points)
        #expect(abs(points[0].x - 20) < 1e-9 && abs(points[0].y - 10) < 1e-9)
    }

    @Test func placingMakesAnAlignedSection() throws {
        let o = open()
        finishedLine(o)
        o.click(o.at(20, -15))
        #expect(o.h.log.commits.map(\.name) == ["Add View"])
        let made = try #require(section(o))
        #expect(made.kind == .section)
        #expect(made.alignment == ViewAlignment(parent: o.view.id, axis: .vertical))
        #expect(made.letter == "A")
        #expect(made.showsLabel)
        #expect(made.source == o.view.source)
        #expect(made.scale == o.view.scale)
        #expect(o.h.model.selection == [made.id])
        #expect(o.h.model.sectionDraft == nil)
        guard case .section(let line)? = made.derivation else {
            Issue.record("no derivation")
            return
        }
        #expect(line.parent == o.view.id)
        #expect(line.cutter.points.count == 2)
        #expect((line.cutter.points[0] - Vector2(5, 10)).length < 1e-9 && (line.cutter.points[1] - Vector2(35, 10)).length < 1e-9)
        // First angle: the section looks toward the drop.
        #expect(abs(line.cutter.viewing.x) < 1e-9 && abs(line.cutter.viewing.y + 1) < 1e-9)
        #expect(made.orientation == .custom(SectionFrame.frame(for: line.cutter)))
        #expect(abs(made.center.x - 150) < 1e-9)
        #expect(abs(made.center.y - o.at(20, -15).y) < 1e-9)
    }

    @Test func placingInASMELooksAway() throws {
        let o = open(settings: DrawingSettings(standard: .asme))
        finishedLine(o)
        o.click(o.at(20, -15))
        let made = try #require(section(o))
        guard case .section(let line)? = made.derivation else {
            Issue.record("no derivation")
            return
        }
        #expect(abs(line.cutter.viewing.y - 1) < 1e-9)
    }

    @Test func aSlantedLineMakesAFreeSection() throws {
        let o = open()
        o.h.model.press(.section)
        o.click(o.at(5, 3))
        o.click(o.at(35, 17), .shift)
        o.h.model.keyPressed(.finish)
        o.click(o.at(45, -10))
        let made = try #require(section(o))
        #expect(made.alignment == nil)
        #expect(abs(made.center.x - o.at(45, -10).x) < 1e-9)
    }

    @Test func aPictorialParentIsRefused() throws {
        let o = open(orientation: .isometricFrontRight)
        o.h.model.press(.section)
        o.click(o.at(5, 10))
        #expect(
            o.h.model.refusal
                == "A section or auxiliary view is taken from a front, side, top, bottom, section or auxiliary view, not an isometric one.")
        #expect(o.h.model.sectionDraft == nil)
    }

    @Test func aDetailParentIsRefused() throws {
        let parent = EditorDocuments.view(at: Vector2(150, 150))
        let detail = DrawingView(
            kind: .detail, source: parent.source, orientation: parent.orientation, center: Vector2(150, 150),
            derivation: .detail(DetailCircle(parent: parent.id, center: Vector2(10, 10), radius: 5)), letter: "A")
        let sheet = DrawingSheet(name: "Sheet 1", views: [detail])
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        h.model.press(.section)
        h.click(150, 150)
        #expect(h.model.refusal == "Draw the cutting line on the view the detail enlarges.")
        #expect(h.model.sectionDraft == nil)
    }

    @Test func aParentWithNothingDrawnIsRefused() throws {
        let view = EditorDocuments.view(at: Vector2(150, 150))
        let sheet = DrawingSheet(name: "Sheet 1", views: [view])
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id, contents: [view.id: ViewContent()])
        h.model.press(.section)
        h.click(150, 150)
        #expect(h.model.refusal == "This view has nothing drawn to cut yet.")
        #expect(h.model.sectionDraft == nil)
    }

    @Test func escapeDropsTheDraftThenTheTool() throws {
        let o = open()
        o.h.model.press(.section)
        o.click(o.at(5, 10))
        #expect(o.h.model.keyPressed(.escape))
        #expect(o.h.model.sectionDraft == nil)
        #expect(o.h.model.tool == .section)
        #expect(o.h.model.keyPressed(.escape))
        #expect(o.h.model.tool == .select)
    }

    @Test func theSKeyChoosesTheTool() throws {
        #expect(SheetCanvasInput.key("s", modifiers: []) == .tool(.section))
        #expect(SheetCanvasInput.key(.return, modifiers: []) == .finish)
        let o = open()
        o.h.model.keyPressed(.tool(.section))
        #expect(o.h.model.tool == .section)
    }
}

@MainActor
extension SectionToolTests {
    private func placed(_ o: OpenedView) throws -> DrawingView {
        finishedLine(o)
        o.click(o.at(20, -15))
        o.h.log.commits.removeAll()
        o.h.model.press(.select)
        o.h.model.selection = []
        return try #require(section(o))
    }

    @Test func draggingTheCuttingLineMovesIt() throws {
        let o = open()
        let made = try placed(o)
        let start = o.at(15, 10)
        o.h.model.pointerDown(at: o.h.canvas(start.x, start.y), modifiers: [])
        #expect(o.h.model.selection == [made.id])
        o.h.model.pointerDragged(to: o.h.canvas(start.x + 2, start.y + 1))
        o.h.model.pointerDragged(to: o.h.canvas(start.x + 4, start.y + 3))
        o.h.model.pointerUp(at: o.h.canvas(start.x + 4, start.y + 3))
        #expect(!o.h.log.commits.isEmpty)
        #expect(Set(o.h.log.commits.map(\.name)) == ["Move Cutting Line"])
        #expect(Set(o.h.log.commits.compactMap(\.coalescingKey)).count == 1)
        guard case .section(let line)? = o.h.model.document.sheets[0].view(made.id)?.derivation else {
            Issue.record("no derivation")
            return
        }
        #expect(abs(line.cutter.points[0].x - 9) < 1e-6 && abs(line.cutter.points[0].y - 13) < 1e-6)
        #expect(abs(line.cutter.points[1].x - 39) < 1e-6 && abs(line.cutter.points[1].y - 13) < 1e-6)
    }

    @Test func draggingTheCuttingLineDividesByTheParentsScale() throws {
        let content = Fixtures.top()
        let view = EditorDocuments.view(at: Fixtures.centre, orientation: .top)
        var sheet = DrawingSheet(name: "Sheet 1", views: [view])
        sheet.scale = DrawingScale(numerator: 2, denominator: 1)
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id, contents: [view.id: content])
        h.model.transform = SheetTransform(offset: Vector2(0, 297), zoom: 1)
        let mapping = ViewMapping.of(content: content, center: Fixtures.centre, scale: 2)!
        let o = OpenedView(h: h, view: view, mapping: mapping, content: content)
        let made = try placed(o)
        let start = o.at(15, 10)
        h.model.pointerDown(at: h.canvas(start.x, start.y), modifiers: [])
        h.model.pointerDragged(to: h.canvas(start.x + 2, start.y + 1))
        h.model.pointerDragged(to: h.canvas(start.x + 4, start.y + 3))
        h.model.pointerUp(at: h.canvas(start.x + 4, start.y + 3))
        guard case .section(let line)? = h.model.document.sheets[0].view(made.id)?.derivation else {
            Issue.record("no derivation")
            return
        }
        #expect(abs(line.cutter.points[0].x - 7) < 1e-6 && abs(line.cutter.points[0].y - 11.5) < 1e-6)
        #expect(abs(line.cutter.points[1].x - 37) < 1e-6 && abs(line.cutter.points[1].y - 11.5) < 1e-6)
    }

    @Test func pressingAMarkSelectsItsView() throws {
        let o = open()
        let made = try placed(o)
        let start = o.at(15, 10)
        o.h.click(start.x, start.y)
        #expect(o.h.model.selection == [made.id])
    }

    @Test func deletingAParentKeepsItsSections() throws {
        let o = open()
        let made = try placed(o)
        o.h.model.selection = [o.view.id]
        o.h.model.deleteSelection()
        #expect(o.h.log.commits.map(\.name) == ["Delete View"])
        let sheet = o.h.model.document.sheets[0]
        #expect(sheet.view(o.view.id) == nil)
        let kept = try #require(sheet.view(made.id))
        #expect(kept.alignment == nil)
        #expect(kept.derivation != nil)
    }

    @Test func undoPrunesTheDraft() throws {
        let o = open()
        o.h.model.press(.section)
        o.click(o.at(5, 10))
        #expect(o.h.model.sectionDraft != nil)
        var document = o.h.model.document
        document.sheets[0].removeView(o.view.id)
        o.h.model.replaceDocument(document)
        #expect(o.h.model.sectionDraft == nil)
    }
}

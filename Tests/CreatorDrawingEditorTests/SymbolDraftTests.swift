import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// What the symbol tools refuse, how Esc backs out of them and the draft that follows the pointer (plan R15, R17).
@MainActor
@Suite("Symbol tool drafts")
struct SymbolDraftTests {
    private typealias Scene = SelectionScene

    private func open(_ pieces: [Scene.Piece] = []) -> Scene { Scene.make(pieces) }

    private func at(_ s: Scene, _ x: Double, _ y: Double) -> Vector2 { s.mapping.sheet(Vector2(x, y)) }

    private func click(_ s: Scene, _ point: Vector2) { s.h.click(point.x, point.y) }

    // MARK: Refusals, Esc and the draft

    @Test func aSymbolRefusesANote() throws {
        let s = open([.note])
        for tool in [DrawingTool.datum, .featureControlFrame, .surfaceFinish] {
            s.h.model.press(tool)
            click(s, s.centre(of: Scene.note))
            #expect(s.h.model.symbolDraft == nil)
            #expect(s.h.model.refusal == "Attach the symbol to a line of a view or to a dimension.", "\(tool)")
        }
    }

    @Test func isometricViewsRefuseSymbols() throws {
        let view = EditorDocuments.view(at: Scene.Fixtures.centre, orientation: .isometricFrontRight)
        let sheet = DrawingSheet(name: "Sheet 1", views: [view])
        let content = Scene.Fixtures.front()
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id, contents: [view.id: content])
        h.model.transform = SheetTransform(offset: Vector2(0, 297 * 4), zoom: 4)
        let mapping = Scene.Fixtures.mapping(content)
        h.model.press(.datum)
        let point = mapping.sheet(Vector2(0, 10))
        h.click(point.x, point.y)
        #expect(h.model.symbolDraft == nil)
        #expect(h.model.refusal == DrawingPick.symbolIsometricSentence, "\(h.model.refusal ?? "")")
    }

    @Test func escapeDropsTheTargetThenTheTool() throws {
        let s = open()
        s.h.model.press(.datum)
        click(s, at(s, 8, 0))
        #expect(s.h.model.symbolDraft != nil)
        #expect(s.h.model.keyPressed(.escape))
        #expect(s.h.model.symbolDraft == nil)
        #expect(s.h.model.tool == .datum)
        #expect(s.h.model.keyPressed(.escape))
        #expect(s.h.model.tool == .select)
    }

    @Test func theDraftFollowsThePointer() throws {
        let s = open()
        s.h.model.press(.datum)
        click(s, at(s, 8, 0))
        let near = at(s, 8, -6)
        s.h.model.pointerMoved(to: s.h.canvas(near.x, near.y))
        let first = try #require(s.h.model.draftPicture)
        #expect(first.annotationReports[s.h.model.draftAnnotationID] != nil, "the draft symbol is composed in")
        let far = at(s, 20, -12)
        s.h.model.pointerMoved(to: s.h.canvas(far.x, far.y))
        let second = try #require(s.h.model.draftPicture)
        #expect(first.annotationReports[s.h.model.draftAnnotationID]?.frame != second.annotationReports[s.h.model.draftAnnotationID]?.frame)
        #expect(s.h.log.commits.isEmpty, "a draft is never committed")
        #expect(s.h.model.document.sheets[0].annotations.isEmpty)
    }

    @Test func undoPrunesTheTarget() throws {
        let s = open([.horizontal])
        s.h.model.press(.datum)
        click(s, s.label(of: Scene.horizontal))
        #expect(s.h.model.symbolDraft != nil)
        var without = s.h.model.document
        without.sheets[0].removeAnnotation(Scene.horizontal)
        s.h.model.replaceDocument(without)
        #expect(s.h.model.symbolDraft == nil)
    }

    @Test func aLineTargetSurvivesUndoOfSomethingElse() throws {
        let s = open()
        s.h.model.press(.datum)
        click(s, at(s, 8, 0))
        s.h.model.replaceDocument(s.h.model.document)
        #expect(s.h.model.symbolDraft != nil)
    }
}

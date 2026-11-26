import CreatorGeometry
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The draft under construction follows the document, not only the pointer.
@MainActor
@Suite("Annotation draft")
struct AnnotationDraftTests {
    typealias Fixtures = AnnotationEditorFixtures

    @Test func theDraftFollowsUndoAndUnits() async throws {
        let plate = try await Fixtures.plate(.front)
        let o = OpenedView.make(plate, orientation: .front, zoom: 1, annotations: { _ in [] }, units: .millimetres)
        let bounds = try #require(o.content.projection?.bounds)
        let before = o.h.model.document
        o.h.model.press(.dimension)
        let bottom = o.at( bounds.center.x, bounds.min.y)
        o.click(bottom, [])
        o.click(bottom - Vector2(0, 8), [])
        #expect(o.h.model.document.sheets[0].annotations.count == 1)
        o.h.model.press(.dimension)
        let top = o.at( bounds.center.x, bounds.max.y)
        o.click(top, [])
        o.h.model.pointerMoved(to: o.h.canvas(top.x, top.y + 12))
        let withBoth = try #require(o.h.model.draftPicture)
        #expect(withBoth.annotationReports.count == 2)
        o.h.model.replaceDocument(before)
        let afterUndo = try #require(o.h.model.draftPicture)
        #expect(afterUndo.annotationReports.count == 1, "the undone dimension is gone from the draft")
        o.h.model.units = DocumentUnits(length: .inches)
        let inInches = try #require(o.h.model.draftPicture)
        #expect(inInches != afterUndo, "a units change recomposes the draft")
    }
}

import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// A pick on a second view is refused with the tool's own words and leaves the first pick armed (plan R7 wording).
@MainActor
@Suite("Picks from one view")
struct OneViewPickTests {
    typealias Fixtures = AnnotationEditorFixtures

    /// Two Top views of the plate side by side, the hole at (20, 10) in each.
    private func twoViews() -> (h: EditorHarness, first: ViewMapping, second: ViewMapping) {
        let content = Fixtures.top()
        let a = EditorDocuments.view(at: Vector2(100, 150), orientation: .top)
        let b = EditorDocuments.view(at: Vector2(300, 150), orientation: .top)
        let sheet = DrawingSheet(name: "Sheet 1", views: [a, b])
        let h = EditorHarness(
            document: EditorDocuments.document([sheet]), sheet: sheet.id, contents: [a.id: content, b.id: content])
        h.model.transform = SheetTransform(offset: Vector2(0, 297), zoom: 1)
        return (h, Fixtures.mapping(content, at: a.center), Fixtures.mapping(content, at: b.center))
    }

    @Test func aHoleCalloutTakesItsPickFromOneView() {
        let (h, first, second) = twoViews()
        h.model.press(.holeCallout)
        let one = first.sheet(Vector2(23, 10))
        h.click(one.x, one.y)
        #expect(h.model.picks.count == 1, "\(h.model.refusal ?? "")")
        let other = second.sheet(Vector2(23, 10))
        h.click(other.x, other.y)
        #expect(h.model.refusal == "A hole callout takes its pick from one view.")
        #expect(h.model.picks.count == 1, "the first pick stays and the tool stays armed")
        #expect(h.log.commits.isEmpty)
    }

    @Test func aDimensionTakesItsPicksFromOneView() {
        let (h, first, second) = twoViews()
        h.model.press(.dimension)
        let one = first.sheet(Vector2(10, 0))
        h.click(one.x, one.y)
        #expect(h.model.picks.count == 1, "\(h.model.refusal ?? "")")
        let other = second.sheet(Vector2(10, 0))
        h.click(other.x, other.y)
        #expect(h.model.refusal == "A dimension takes its picks from one view.")
        #expect(h.log.commits.isEmpty)
    }
}

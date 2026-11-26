import CreatorGeometry
import CreatorKernel
import MetalUI
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The dimension draft is the dimension the click would commit, Shift's aligned one included (drawings minors, task 6).
@MainActor
@Suite("Annotation draft and Shift")
struct AnnotationDraftShiftTests {
    typealias Fixtures = AnnotationEditorFixtures

    @Test func theDraftComposesWhatAShiftClickCommits() async throws {
        let content = try await Fixtures.plate(.front)
        let o = OpenedView.make(content, orientation: .front, zoom: 1, annotations: { _ in [] }, units: .millimetres)
        let bounds = try #require(o.content.projection?.bounds)
        o.h.model.press(.dimension)
        o.click(o.at(bounds.min.x, bounds.min.y) + Vector2(0.3, 0.2))
        o.click(o.at(bounds.max.x, bounds.max.y) + Vector2(-0.3, -0.2))
        let placing = o.at(bounds.center.x, bounds.max.y + 8)
        o.h.model.pointerMoved(to: o.h.canvas(placing.x, placing.y))
        let plain = try #require(o.h.model.draftPicture)
        o.h.model.modifiersChanged([.shift])
        let shifted = try #require(o.h.model.draftPicture)
        #expect(plain != shifted, "Shift's aligned dimension is what the draft shows")
        o.click(placing, [.shift])
        let placed = try #require(o.h.model.document.sheets[0].annotations.first)
        guard case .dimension(let made) = placed.kind else {
            Issue.record("not a dimension")
            return
        }
        #expect(made.kind == .linear(.aligned))
        o.h.model.selectedAnnotations = []
        let committed = try #require(o.h.model.picture)
        func geometry(_ picture: SheetPicture) -> [[SheetSegment]] {
            picture.strokes.filter { $0.layer == .dimension }.map(\.segments)
        }
        #expect(!geometry(shifted).isEmpty)
        #expect(geometry(shifted) == geometry(committed), "the draft is the committed dimension, drawn")
    }
}

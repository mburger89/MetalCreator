import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

@MainActor
@Suite("Selection and moving")
struct SelectionAndMoveTests {
    private let a = EditorDocuments.view(at: Vector2(100, 150))
    private let b = EditorDocuments.view(at: Vector2(250, 150))

    private func harness(
        _ views: [DrawingView], scale: DrawingScale = DrawingScale(numerator: 1, denominator: 1)
    ) -> EditorHarness {
        var sheet = DrawingSheet(name: "Sheet 1", views: views)
        sheet.scale = scale
        return EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
    }

    private func center(_ h: EditorHarness, _ id: ViewID) -> Vector2 {
        let sheet = h.model.document.sheets[0]
        return ViewPlacement.centers(in: sheet)[id] ?? .zero
    }

    @Test func clickSelectsAndShiftAdds() throws {
        let h = harness([a, b])
        h.click(100, 150)
        #expect(h.model.selection == [a.id])
        h.click(250, 150, .shift)
        #expect(h.model.selection == [a.id, b.id])
        h.click(20, 20)
        #expect(h.model.selection.isEmpty)
        #expect(h.log.commits.isEmpty)
    }

    @Test func aDragIsOneCoalescedStep() throws {
        let h = harness([a, b])
        h.model.pointerDown(at: h.canvas(100, 150), modifiers: [])
        h.model.pointerDragged(to: h.canvas(110, 150))
        h.model.pointerDragged(to: h.canvas(120, 150))
        h.model.pointerDragged(to: h.canvas(130, 155))
        h.model.pointerUp(at: h.canvas(130, 155))
        #expect(h.log.commits.count == 3)
        #expect(Set(h.log.commits.map(\.name)) == ["Move View"])
        let keys = Set(h.log.commits.map(\.coalescingKey))
        #expect(keys.count == 1)
        #expect(try #require(keys.first.flatMap { $0 }).hasPrefix("drawing-move-"))
        let moved = center(h, a.id)
        #expect(abs(moved.x - 130) < 1e-9 && abs(moved.y - 155) < 1e-9)
        h.model.pointerDown(at: h.canvas(130, 155), modifiers: [])
        h.model.pointerDragged(to: h.canvas(140, 155))
        h.model.pointerUp(at: h.canvas(140, 155))
        #expect(h.log.commits.last?.coalescingKey != h.log.commits.first?.coalescingKey)
    }

    @Test func aProjectedViewSlides() throws {
        let child = EditorDocuments.child(of: a, axis: .horizontal, at: Vector2(200, 150))
        let h = harness([a, child])
        h.model.pointerDown(at: h.canvas(200, 150), modifiers: [])
        h.model.pointerDragged(to: h.canvas(220, 180))
        h.model.pointerUp(at: h.canvas(220, 180))
        let moved = center(h, child.id)
        #expect(abs(moved.x - 220) < 1e-9 && abs(moved.y - 150) < 1e-9)
    }

    @Test func movingAParentCarriesChildren() throws {
        let child = EditorDocuments.child(of: a, axis: .horizontal, at: Vector2(200, 150))
        let h = harness([a, child])
        h.model.pointerDown(at: h.canvas(100, 150), modifiers: [])
        h.model.pointerDragged(to: h.canvas(110, 160))
        h.model.pointerUp(at: h.canvas(110, 160))
        let carried = center(h, child.id)
        #expect(abs(carried.x - 210) < 1e-9 && abs(carried.y - 160) < 1e-9)
    }

    @Test func deleteFreesChildren() throws {
        let child = EditorDocuments.child(of: a, axis: .horizontal, at: Vector2(200, 150))
        let h = harness([a, child])
        h.click(100, 150)
        #expect(h.model.keyPressed(.delete))
        #expect(h.log.commits.map(\.name) == ["Delete View"])
        let sheet = h.model.document.sheets[0]
        #expect(sheet.views.map(\.id) == [child.id])
        #expect(sheet.views[0].alignment == nil)
        #expect(sheet.views[0].center == Vector2(200, 150))
        #expect(h.model.selection.isEmpty)
    }

    @Test func nudgeMovesOneMillimetreAndShiftTen() throws {
        let h = harness([a])
        h.click(100, 150)
        #expect(h.model.keyPressed(.nudge(Vector2(1, 0), isRepeat: false)))
        #expect(center(h, a.id) == Vector2(101, 150))
        #expect(h.model.keyPressed(.nudge(Vector2(0, -10), isRepeat: true)))
        #expect(center(h, a.id) == Vector2(101, 140))
        #expect(h.log.commits.map(\.name) == ["Move View", "Move View"])
        #expect(Set(h.log.commits.map(\.coalescingKey)).count == 1, "a held key's repeat joins the run's step")
    }

    @Test func separateKeyDownRunsAreSeparateSteps() throws {
        let h = harness([a])
        h.click(100, 150)
        #expect(h.model.keyPressed(.nudge(Vector2(1, 0), isRepeat: false)))
        #expect(h.model.keyPressed(.nudge(Vector2(1, 0), isRepeat: true)))
        #expect(h.model.keyPressed(.nudge(Vector2(1, 0), isRepeat: false)))
        let keys = h.log.commits.map(\.coalescingKey)
        #expect(keys.count == 3)
        #expect(keys[0] == keys[1] && keys[1] != keys[2])
    }

    @Test func nudgeWithNothingSelectedDoesNothing() throws {
        let h = harness([a])
        #expect(!h.model.keyPressed(.nudge(Vector2(1, 0), isRepeat: false)))
        #expect(h.log.commits.isEmpty)
    }

    @Test func hoverFindsTheNearestLine() throws {
        let h = harness([a])
        h.model.transform = SheetTransform(offset: h.model.transform.offset, zoom: 2)
        // The left edge of the 50 x 30 rectangle is at x = 75.
        h.model.pointerMoved(to: h.canvas(76, 150))
        let index = try #require(h.model.hoveredStroke)
        #expect(h.model.picture?.strokes[index].view == a.id)
        h.model.pointerMoved(to: h.canvas(79, 150))
        #expect(h.model.hoveredStroke == nil)
    }

    @Test func changeScaleIsOneStep() throws {
        let h = harness([a])
        h.model.setScale(DrawingScale(numerator: 1, denominator: 2), of: a.id)
        #expect(h.log.commits.map(\.name) == ["Change Scale"])
        #expect(h.model.document.sheets[0].view(a.id)?.scale == DrawingScale(numerator: 1, denominator: 2))
    }

    @Test func theSheetScaleScalesViewsWithoutAnOverride() throws {
        var override = b
        override.scale = DrawingScale(numerator: 2, denominator: 1)
        override.showsLabel = true
        let h = harness([a, override], scale: DrawingScale(numerator: 2, denominator: 1))
        let before = try #require(h.model.picture)
        #expect(abs((before.viewFrames[a.id]?.width ?? 0) - 100) < 1e-9)
        #expect(!before.texts.contains { $0.original == "Front (2 : 1)" })
        h.model.setSheetScale(DrawingScale(numerator: 1, denominator: 2))
        #expect(h.log.commits.map(\.name) == ["Change Scale"])
        let after = try #require(h.model.picture)
        #expect(abs((after.viewFrames[a.id]?.width ?? 0) - 25) < 1e-9)
        #expect(abs((after.viewFrames[b.id]?.width ?? 0) - 100) < 1e-9)
        #expect(after.texts.contains { $0.original == "Front (2 : 1)" })
    }

    @Test func anInvalidSheetScaleIsRefused() throws {
        let h = harness([a])
        h.model.setSheetScale(DrawingScale(numerator: 1, denominator: 1001))
        #expect(h.model.refusal == "A scale is two whole numbers from 1 to 1000.")
        #expect(h.log.commits.isEmpty)
    }

    @Test func toggleHiddenIsChangeView() throws {
        let h = harness([a])
        h.model.setShowsHidden(true, of: a.id)
        #expect(h.log.commits.map(\.name) == ["Change View"])
        #expect(h.model.document.sheets[0].view(a.id)?.showsHidden == true)
    }

    @Test func replaceDocumentKeepsWhatStillExists() throws {
        let one = DrawingSheet(name: "one", views: [a, b])
        let two = DrawingSheet(name: "two")
        let h = EditorHarness(document: EditorDocuments.document([one, two]), sheet: one.id)
        h.model.selection = [a.id, b.id]
        var fewer = one
        fewer.removeView(b.id)
        h.model.replaceDocument(EditorDocuments.document([fewer, two]))
        #expect(h.model.currentSheet == one.id)
        #expect(h.model.selection == [a.id])
        h.model.replaceDocument(EditorDocuments.document([two]))
        #expect(h.model.currentSheet == two.id)
        #expect(h.model.selection.isEmpty)
        #expect(h.log.commits.isEmpty)
    }
}

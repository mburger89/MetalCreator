import CreatorGeometry
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

@MainActor
@Suite("Canvas transform")
struct CanvasTransformTests {
    private func harness() -> EditorHarness {
        let sheet = DrawingSheet(name: "Sheet 1")
        return EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
    }

    @Test func fitCentresTheSheetInTheVisibleRect() throws {
        let h = harness()
        h.model.visibleRect = Rect2D(min: .zero, max: Vector2(1000, 600))
        h.model.fit()
        #expect(abs(h.model.transform.zoom - 600 * 0.9 / 297) < 1e-9)
        let centre = h.model.transform.screenPoint(Vector2(210, 148.5))
        #expect(abs(centre.x - 500) < 1e-9 && abs(centre.y - 300) < 1e-9)
        #expect(h.model.keyPressed(.fit))
    }

    @Test func transformInvertsAndFlipsY() throws {
        let t = SheetTransform(offset: Vector2(10, 500), zoom: 2)
        #expect(t.screenPoint(Vector2(5, 7)) == Vector2(20, 486))
        let back = t.sheetPoint(Vector2(20, 486))
        #expect(abs(back.x - 5) < 1e-12 && abs(back.y - 7) < 1e-12)
    }

    @Test func scrollPans() throws {
        let h = harness()
        let before = h.model.transform.offset
        h.model.scrolled(by: Vector2(12, -7), at: Vector2(300, 200), zooming: false)
        #expect(h.model.transform.offset == before + Vector2(12, -7))
    }

    @Test func zoomScrollKeepsThePointUnderThePointer() throws {
        let h = harness()
        let pointer = Vector2(300, 200)
        let was = h.model.transform.sheetPoint(pointer)
        let zoom = h.model.transform.zoom
        h.model.scrolled(by: Vector2(0, 50), at: pointer, zooming: true)
        #expect(h.model.transform.zoom > zoom)
        let now = h.model.transform.screenPoint(was)
        #expect(abs(now.x - pointer.x) < 1e-9 && abs(now.y - pointer.y) < 1e-9)
    }

    @Test func pinchZoomsAboutItsCentre() throws {
        let h = harness()
        let pointer = Vector2(400, 250)
        let was = h.model.transform.sheetPoint(pointer)
        let zoom = h.model.transform.zoom
        h.model.pinchChanged(2, at: pointer)
        h.model.pinchChanged(3, at: pointer)
        #expect(abs(h.model.transform.zoom - zoom * 3) < 1e-9)
        let now = h.model.transform.screenPoint(was)
        #expect(abs(now.x - pointer.x) < 1e-9 && abs(now.y - pointer.y) < 1e-9)
        h.model.pinchEnded()
        h.model.pinchChanged(2, at: pointer)
        #expect(abs(h.model.transform.zoom - zoom * 3 * 2) < 1e-9)
    }

    @Test func zoomIsClamped() throws {
        let h = harness()
        h.model.scrolled(by: Vector2(0, 100_000), at: .zero, zooming: true)
        #expect(h.model.transform.zoom == 40)
        h.model.scrolled(by: Vector2(0, -100_000), at: .zero, zooming: true)
        #expect(h.model.transform.zoom == 0.25)
    }

    @Test func middleDragPans() throws {
        let h = harness()
        let before = h.model.transform.offset
        h.model.middleDragged(by: Vector2(-5, 9))
        #expect(h.model.transform.offset == before + Vector2(-5, 9))
    }
}

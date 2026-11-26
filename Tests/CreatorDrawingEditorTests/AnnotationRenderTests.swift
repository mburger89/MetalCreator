#if canImport(MetalUITestingSnapshot)
import CreatorGeometry
import CreatorStyle
import MetalUI
import MetalUITesting
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// Annotations on the canvas, read back as pixels (plan R16, R17): filled arrowheads, the warning colour of a lost dimension, the
/// centre pattern's gaps, the selection and the draft in the highlight colour, and notes that belong to no view.
@MainActor
@Suite("Annotation pixels")
struct AnnotationRenderTests {
    private let colors = DrawingColors(nil)

    private func open(_ scene: SelectionScene) async throws -> DrawingWindow {
        let window = try await DrawingWindow.open { SheetCanvas(model: scene.h.model) }
        scene.h.model.transform = SheetTransform(offset: Vector2(0, 297 * 4), zoom: 4)
        window.redraw()
        try await window.window.runUntilIdle()
        return window
    }

    private func screen(_ scene: SelectionScene, _ point: Vector2) -> Vector2 { scene.h.model.transform.screenPoint(point) }

    private func centroid(_ fill: SheetFill) -> Vector2 {
        fill.points.reduce(Vector2.zero) { $0 + $1 } * (1 / Double(fill.points.count))
    }

    private func isNear(_ p: (r: Int, g: Int, b: Int), _ color: HexColor, tolerance: Int = 40) -> Bool {
        let r = Int((color.rgb >> 16) & 0xff), g = Int((color.rgb >> 8) & 0xff), b = Int(color.rgb & 0xff)
        return abs(p.r - r) <= tolerance && abs(p.g - g) <= tolerance && abs(p.b - b) <= tolerance
    }

    @Test func anArrowheadIsFilledInk() async throws {
        let scene = SelectionScene.make([.horizontal])
        let window = try await open(scene)
        let picture = try #require(scene.h.model.picture)
        let fill = try #require(picture.fills.first { $0.annotation == SelectionScene.horizontal })
        let image = try PixelImage(window: window.window)
        let at = screen(scene, centroid(fill))
        let pixel = image.rgb(atPoint: at.x, at.y)
        #expect(pixel.r < 40 && pixel.g < 40 && pixel.b < 40, "the arrowhead's middle is ink: \(pixel)")
    }

    @Test func aLostDimensionIsWarningColoured() async throws {
        // Held first, so the editor remembers the figure a lost dimension is drawn from; then the edge goes.
        let scene = SelectionScene.make([.horizontal])
        scene.h.model.contents[scene.view.id] = AnnotationEditorFixtures.top(AnnotationEditorFixtures.topology(removing: [100]))
        let window = try await open(scene)
        let picture = try #require(scene.h.model.picture)
        #expect(picture.lostAnnotations == [SelectionScene.horizontal])
        let image = try PixelImage(window: window.window)
        var warm = 0, black = 0
        for fill in picture.fills where fill.isLost {
            let at = screen(scene, centroid(fill))
            let pixel = image.rgb(atPoint: at.x, at.y)
            if isNear(pixel, colors.warning) { warm += 1 }
            if pixel.r < 60 && pixel.g < 60 && pixel.b < 60 { black += 1 }
        }
        #expect(!picture.fills.filter(\.isLost).isEmpty, "a lost dimension still draws its arrowheads")
        #expect(warm > 0 && black == 0, "\(warm) warning-coloured, \(black) black")
    }

    @Test func centreDashesShowGaps() async throws {
        let scene = SelectionScene.make([])
        let window = try await open(scene)
        let picture = try #require(scene.h.model.picture)
        let stroke = try #require(
            picture.strokes.first { stroke in
                guard stroke.pattern == .centre, case let .line(a, b)? = stroke.segments.first else { return false }
                return abs(a.y - b.y) < 1e-9
            })
        guard case let .line(a, b)? = stroke.segments.first else { return }
        let image = try PixelImage(window: window.window)
        let from = screen(scene, a), to = screen(scene, b)
        let x0 = Swift.min(from.x, to.x) + 1, x1 = Swift.max(from.x, to.x) - 1
        let runs = Swift.max(
            image.darkRuns(row: from.y, from: x0, to: x1), image.darkRuns(row: from.y - 0.5, from: x0, to: x1),
            image.darkRuns(row: from.y + 0.5, from: x0, to: x1))
        #expect(runs >= 2, "a chain line is dashes with gaps, not one run: \(runs)")
    }

    @Test func aSelectedAnnotationIsHighlighted() async throws {
        let scene = SelectionScene.make([.horizontal])
        let window = try await open(scene)
        let picture = try #require(scene.h.model.picture)
        let fill = try #require(picture.fills.first { $0.annotation == SelectionScene.horizontal })
        let at = screen(scene, centroid(fill))
        let before = try PixelImage(window: window.window).rgb(atPoint: at.x, at.y)
        #expect(!isNear(before, colors.highlight))
        scene.h.model.selectedAnnotations = [SelectionScene.horizontal]
        window.redraw()
        let after = try PixelImage(window: window.window).rgb(atPoint: at.x, at.y)
        #expect(isNear(after, colors.highlight), "the arrowhead is drawn in the highlight colour: \(after)")
    }

    @Test func theDraftIsDrawnWhilePicking() async throws {
        let scene = SelectionScene.make([])
        let window = try await open(scene)
        let model = scene.h.model
        model.press(.dimension)
        let ring = scene.mapping.sheet(Vector2(23, 10))
        model.pointerMoved(to: scene.h.canvas(ring.x, ring.y))
        model.pointerDown(at: scene.h.canvas(ring.x, ring.y), modifiers: [])
        model.pointerUp(at: scene.h.canvas(ring.x, ring.y))
        let away = ring + Vector2(12, 12)
        model.pointerMoved(to: scene.h.canvas(away.x, away.y))
        let draft = try #require(model.draftPicture)
        let fill = try #require(draft.fills.first { $0.annotation == model.draftID })
        window.redraw()
        let at = screen(scene, centroid(fill))
        let pixel = try PixelImage(window: window.window).rgb(atPoint: at.x, at.y)
        #expect(isNear(pixel, colors.highlight), "the draft's arrowhead shows before the click that places it: \(pixel)")
        #expect(model.document.sheets[0].annotations.isEmpty)
    }

    @Test func freeNotesDrawOnTheFrameLayer() async throws {
        let scene = SelectionScene.make([])
        var document = scene.h.model.document
        let note = DrawingAnnotation(
            id: AnnotationID(), view: nil, kind: .note(DrawingNote(text: "HHHH", position: Vector2(100, 200))))
        document.sheets[0].setAnnotation(note)
        scene.h.model.replaceDocument(document)
        let window = try await open(scene)
        let picture = try #require(scene.h.model.picture)
        let text = try #require(picture.texts.first { $0.annotation == note.id })
        #expect(text.view == nil)
        let image = try PixelImage(window: window.window)
        let origin = screen(scene, text.origin)
        let width = text.run.width * 4
        var dark = 0
        for step in 0..<Int(width) {
            dark += image.darkLength(column: origin.x + Double(step), from: origin.y - text.height * 4, to: origin.y)  > 0 ? 1 : 0
        }
        #expect(dark > 5, "the note's lettering is on the paper: \(dark) dark columns")
    }
}
#endif

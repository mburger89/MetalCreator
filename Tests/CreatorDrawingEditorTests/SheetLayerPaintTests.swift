#if canImport(MetalUITestingSnapshot)
import CreatorGeometry
import MetalUI
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// What the split layers put on screen: the z order inside a view, and a changed bucket redrawing (drawings speed R3, R4).
@MainActor
@Suite("Sheet layer painting")
struct SheetLayerPaintTests {
    private func dark(_ image: PixelImage, around text: SheetText, model: DrawingEditorModel) -> Int {
        let low = model.transform.screenPoint(text.origin)
        let high = model.transform.screenPoint(text.origin + Vector2(text.run.width, text.height))
        var count = 0
        for x in stride(from: min(low.x, high.x), through: max(low.x, high.x), by: 0.5) {
            for y in stride(from: min(low.y, high.y), through: max(low.y, high.y), by: 0.5) {
                let p = image.rgb(atPoint: x, y)
                if p.r < 60 && p.g < 60 && p.b < 60 { count += 1 }
            }
        }
        return count
    }

    @Test func aViewsLettersDrawOverItsAnnotationLines() async throws {
        // A wide warning-coloured (lost) annotation stroke across the label: where the glyphs are, ink shows through only if the
        // lettering draws on top, as it did when one layer drew a view's strokes, then its texts.
        let colors = DrawingColors(nil)
        let id = ViewID()
        let label = SheetText(
            run: DrawingText.layout("HHHH", height: 6), original: "HHHH", origin: Vector2(10, 40), height: 6, view: id)
        let band = SheetStroke(
            segments: [.line(Vector2(0, 43), Vector2(60, 43))], width: 8, layer: .dimension, view: id,
            annotation: AnnotationID(), isLost: true)
        let bucket = SheetLayers.Bucket(strokes: [band], texts: [label], revision: 1)
        let window = try await DrawingWindow.open(scaleFactor: 2) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(colors.paper.color).frame(width: 400.px, height: 400.px)
                SheetAnnotationLayer(
                    id: id, bucket: bucket, frame: Rect2D(min: .zero, max: .zero), zoom: 4, paperHeight: 100, isPending: false,
                    isSelected: false, hovered: nil, colors: colors, style: .iso)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        let image = try PixelImage(window: window.window)
        let low = (x: 10.0 * 4, y: (100 - 46) * 4.0), high = (x: 10.0 * 4 + label.run.width * 4, y: (100 - 40) * 4.0)
        var inked = 0, warm = 0
        for x in stride(from: low.x, through: high.x, by: 0.5) {
            for y in stride(from: low.y, through: high.y, by: 0.5) {
                let p = image.rgb(atPoint: x, y)
                if p.r < 60 && p.g < 60 && p.b < 60 { inked += 1 }
                if p.r > 200 && p.b < 190 { warm += 1 }
            }
        }
        #expect(warm > 0, "the lost line is drawn")
        #expect(inked > 0, "the glyphs show in ink over the line")
    }

    @Test func aMovedNoteIsRedrawnAndAnotherViewIsNotEvaluated() async throws {
        let a = EditorDocuments.view(at: Vector2(100, 100))
        let b = EditorDocuments.view(at: Vector2(300, 100))
        let note = AnnotationID()
        let annotation = DrawingAnnotation(
            id: note, view: a.id, kind: .note(DrawingNote(text: "WWWW", position: Vector2(80, 60))))
        let sheet = DrawingSheet(name: "Sheet 1", size: .a0, orientation: .landscape, views: [a, b], annotations: [annotation])
        let harness = EditorHarness(
            document: EditorDocuments.document([sheet]), sheet: sheet.id,
            contents: [a.id: EditorHarness.rectangle(40, 20), b.id: EditorHarness.rectangle(40, 20)])
        let model = harness.model
        let window = try await DrawingWindow.open(scaleFactor: 2) { SheetCanvas(model: model) }
        model.transform = SheetTransform(offset: Vector2(10, 300 + 100), zoom: 1)
        window.redraw()
        try await window.window.runUntilIdle()
        window.redraw()
        let oldText = try #require(model.picture?.texts.first { $0.annotation == note })
        let before = try PixelImage(window: window.window)
        #expect(dark(before, around: oldText, model: model) > 0, "the note is drawn at its first place")

        var document = model.document
        var moved = try #require(document.sheets[0].annotation(note))
        moved.kind = .note(DrawingNote(text: "WWWW", position: Vector2(80, 140)))
        document.sheets[0].setAnnotation(moved)
        model.document = document
        window.window.resetFrameWork()
        window.redraw()
        try await window.window.runUntilIdle()
        let newText = try #require(model.picture?.texts.first { $0.annotation == note })
        let after = try PixelImage(window: window.window)
        #expect(dark(after, around: oldText, model: model) == 0, "nothing is left at the old place")
        #expect(dark(after, around: newText, model: model) > 0, "the note is drawn at its new place")
        let evaluations = window.window.frameWork.reduce(0) { $0 + $1.contentEvaluations }
        #expect(evaluations == 2, "only the note's own view's annotation layer and its upright-text group, not the other view's layers")
    }
}
#endif

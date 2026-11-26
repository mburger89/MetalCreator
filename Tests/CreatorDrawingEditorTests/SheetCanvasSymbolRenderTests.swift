#if canImport(MetalUITestingSnapshot)
import CreatorGeometry
import CreatorKernel
import CreatorStyle
import MetalUI
import MetalUITesting
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// Symbols and fills on the sheet canvas, read back as pixels (DR-4 R9, R11).
@MainActor
extension SheetCanvasRenderTests {
    private static let frameID = AnnotationID()

    private func symbolScene() -> SelectionScene {
        let s = SelectionScene.make([])
        let edge = LeaderEnd(target: AnnotationEditorFixtures.pick(AnnotationEditorFixtures.topology(), 102), hint: Vector2(8, 0))
        let frame = FeatureControlFrame(
            characteristic: .flatness, rows: [ToleranceRow(value: 0.05)], attachment: .feature(edge), offset: Vector2(0, -12))
        let annotation = DrawingAnnotation(id: Self.frameID, view: s.view.id, kind: .featureControl(frame))
        s.h.model.commitSheet("Setup") { $0.setAnnotation(annotation) }
        return s
    }

    private func openScene(_ scene: SelectionScene) async throws -> DrawingWindow {
        let window = try await DrawingWindow.open { SheetCanvas(model: scene.h.model) }
        scene.h.model.transform = SheetTransform(offset: Vector2(0, 297 * 4), zoom: 4)
        window.redraw()
        try await window.window.runUntilIdle()
        return window
    }

    /// The midpoint of the frame's longest line, in screen points.
    private func midpoint(of scene: SelectionScene, lost: Bool) throws -> Vector2 {
        let picture = try #require(scene.h.model.picture)
        let strokes = picture.strokes.filter { $0.annotation == Self.frameID && $0.isLost == lost }
        var best: (length: Double, mid: Vector2)?
        for stroke in strokes {
            for case .line(let a, let b) in stroke.segments where best == nil || (b - a).length > best!.length {
                best = ((b - a).length, (a + b) * 0.5)
            }
        }
        let mid = try #require(best?.mid, "the frame drew a line (lost: \(lost))")
        return scene.h.model.transform.screenPoint(mid)
    }

    @Test func aFrameIsDrawnInInk() async throws {
        let scene = symbolScene()
        let window = try await openScene(scene)
        let at = try midpoint(of: scene, lost: false)
        let pixel = try PixelImage(window: window.window).rgb(atPoint: at.x, at.y)
        #expect(pixel.r < 60 && pixel.g < 60 && pixel.b < 60, "the frame's line is ink: \(pixel)")
    }

    @Test func aLostSymbolIsWarningColoured() async throws {
        let scene = symbolScene()
        scene.h.model.contents[scene.view.id] = AnnotationEditorFixtures.top(AnnotationEditorFixtures.topology(removing: [102]))
        let window = try await openScene(scene)
        let picture = try #require(scene.h.model.picture)
        #expect(picture.lostAnnotations.contains(Self.frameID))
        let at = try midpoint(of: scene, lost: true)
        let pixel = try PixelImage(window: window.window).rgb(atPoint: at.x, at.y)
        let warning = DrawingColors(nil).warning
        let r = Int((warning.rgb >> 16) & 0xff), g = Int((warning.rgb >> 8) & 0xff), b = Int(warning.rgb & 0xff)
        #expect(abs(pixel.r - r) < 60 && abs(pixel.g - g) < 60 && abs(pixel.b - b) < 60, "warning colour \(warning): \(pixel)")
    }

    @Test func overlappingFillsDoNotCancel() async throws {
        // Two triangles over the same ground, one wound each way: where they overlap the paper must be inked, not left blank.
        let counter = SheetFill(points: [Vector2(0, 0), Vector2(20, 0), Vector2(10, 20)])
        let clockwise = SheetFill(points: [Vector2(0, 0), Vector2(10, 20), Vector2(20, 0)])
        let colors = DrawingColors(nil)
        let window = try await DrawingWindow.open(scaleFactor: 1) {
            SheetFrameLayer(
                strokes: [], texts: [], fills: [counter, clockwise], zoom: 4, paperHeight: 100, colors: colors, style: .iso)
        }
        let image = try PixelImage(window: window.window)
        // The overlap's middle, (10, 6) mm: x 40 points, y (100 - 6) * 4.
        let pixel = image.rgb(atPoint: 40, 376)
        #expect(pixel.r < 60 && pixel.g < 60 && pixel.b < 60, "the overlap is inked: \(pixel)")
    }
}
#endif

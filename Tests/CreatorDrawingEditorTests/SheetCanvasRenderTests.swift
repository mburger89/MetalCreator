#if canImport(MetalUITestingSnapshot)
import CreatorGeometry
import CreatorKernel
import CreatorStyle
import MetalUI
import MetalUITesting
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The sheet canvas drawn through MetalUI's real renderer and read back as pixels: paper and ink, line weights, dashes, the pending
/// fade and the selection outline (plan R12, R19, R27).
@MainActor
@Suite("Sheet canvas pixels")
struct SheetCanvasRenderTests {
    struct Fixture {
        var harness: EditorHarness
        var window: DrawingWindow
        var view: DrawingView
    }

    /// An A4 landscape sheet with one view holding `lines`, centred at (148, 105), shown at `zoom` with its top left at (20, 20).
    private func open(
        lines: [ProjectedLine], hidden: Bool = false, pending: Bool = false, zoom: Double = 4
    ) async throws -> Fixture {
        var view = DrawingView(
            kind: .base, source: NodeID(), orientation: .standard(.front), center: Vector2(148, 105), showsHidden: hidden)
        view.showsTangent = true
        let sheet = DrawingSheet(name: "Sheet 1", size: .a4, orientation: .landscape, views: [view])
        let content = ViewContent(projection: Projection2D(lines: lines), isPending: pending)
        let harness = EditorHarness(
            document: EditorDocuments.document([sheet]), sheet: sheet.id, contents: [view.id: content])
        let window = try await DrawingWindow.open { SheetCanvas(model: harness.model) }
        harness.model.transform = SheetTransform(offset: Vector2(20, 20 + 210 * zoom), zoom: zoom)
        window.redraw()
        try await window.window.runUntilIdle()
        return Fixture(harness: harness, window: window, view: view)
    }

    private func line(
        _ a: Vector2, _ b: Vector2, _ lineClass: LineClass = .sharp, _ visibility: LineVisibility = .visible
    ) -> ProjectedLine {
        ProjectedLine(visibility: visibility, lineClass: lineClass, curve: .line(a, b), source: nil)
    }

    @Test func thePaperIsWhiteAndInkBlack() async throws {
        let f = try await open(lines: [line(Vector2(-40, 0), Vector2(40, 0))])
        let image = try PixelImage(window: f.window.window)
        // Inside the paper, away from anything drawn; outside it, the surround.
        let inside = image.rgb(atPoint: 60, 60)
        #expect(inside.r == 255 && inside.g == 255 && inside.b == 255)
        let outside = image.rgb(atPoint: 10, 10)
        #expect(outside.r < 100 && outside.g < 100, "the surround isn't paper-coloured: \(outside)")
        // The sharp line crosses the view's centre, (148, 105) mm, at 4 points a millimetre.
        let y = 20 + (210 - 105) * 4.0
        let x = 20 + 148 * 4.0
        let ink = image.rgb(atPoint: x, y)
        #expect(ink.r < 20 && ink.g < 20 && ink.b < 20, "the sharp line is black: \(ink)")
    }

    @Test func aThickLineIsThickerThanAThin() async throws {
        // A sharp line (thick, 0.5 mm) above a tangent edge (thin, 0.25 mm); at zoom 4 they are 2 and 1 points wide.
        let f = try await open(lines: [
            line(Vector2(-40, 10), Vector2(40, 10)),
            line(Vector2(-40, -10), Vector2(40, -10), .smooth),
        ])
        let image = try PixelImage(window: f.window.window)
        let x = 20 + 148 * 4.0
        let thickY = 20 + (210 - 115) * 4.0, thinY = 20 + (210 - 95) * 4.0
        let thick = image.darkLength(column: x, from: thickY - 6, to: thickY + 6)
        let thin = image.darkLength(column: x, from: thinY - 6, to: thinY + 6)
        #expect(abs(thick - 2) <= 0.5, "thick: \(thick) points")
        #expect(abs(thin - 1) <= 0.5, "thin: \(thin) points")
        #expect(thick > thin)
    }

    @Test func aHiddenLineIsDashed() async throws {
        let f = try await open(
            lines: [
                line(Vector2(-40, 10), Vector2(40, 10)),
                line(Vector2(-40, -10), Vector2(40, -10), .sharp, .hidden),
            ], hidden: true)
        let image = try PixelImage(window: f.window.window)
        let x0 = 20 + 108 * 4.0, x1 = 20 + 188 * 4.0
        let solidY = 20 + (210 - 115) * 4.0, dashedY = 20 + (210 - 95) * 4.0
        #expect(image.darkRuns(row: solidY, from: x0 + 4, to: x1 - 4) == 1)
        // 80 mm in 4.5 mm periods: 17 or 18 dashes, each 12 points long.
        let runs = image.darkRuns(row: dashedY, from: x0 + 4, to: x1 - 4)
        #expect((16...19).contains(runs), "\(runs) dashes")
    }

    @Test func aPendingViewIsFaded() async throws {
        let f = try await open(lines: [line(Vector2(-40, 0), Vector2(40, 0))], pending: true)
        let image = try PixelImage(window: f.window.window)
        let ink = image.rgb(atPoint: 20 + 148 * 4.0, 20 + 105 * 4.0)
        // Black at 40 % over white is about 153.
        #expect((130...180).contains(ink.r), "faded ink: \(ink)")
    }

    @Test func theSelectionIsHighlighted() async throws {
        let f = try await open(lines: [line(Vector2(-40, -20), Vector2(40, -20)), line(Vector2(-40, 20), Vector2(40, 20))])
        let before = try PixelImage(window: f.window.window)
        f.harness.model.selection = [f.view.id]
        f.window.redraw()
        let image = try PixelImage(window: f.window.window)
        let frame = try #require(f.harness.model.picture?.viewFrames[f.view.id])
        let leftX = 20 + (frame.min.x - 1) * 4.0
        let midY = 20 + (210 - frame.center.y) * 4.0
        func isBlue(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.b > 180 && p.r < 90 && p.g > 70 && p.g < 160 }
        var found = false
        for dx in -2...2 where isBlue(image.rgb(atPoint: leftX + Double(dx) * 0.5, midY)) { found = true }
        #expect(found, "the outline is drawn in drawingHighlight")
        var wasBlue = false
        for dx in -2...2 where isBlue(before.rgb(atPoint: leftX + Double(dx) * 0.5, midY)) { wasBlue = true }
        #expect(!wasBlue)
    }
}
#endif

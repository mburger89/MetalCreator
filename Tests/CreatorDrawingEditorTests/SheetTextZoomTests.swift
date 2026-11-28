import CreatorGeometry
import CreatorStyle
import Foundation
import MetalUI
import MetalUITesting
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// Upright sheet lettering at an octave-band reference zoom (drawings zoom-text plan R1, R2, R5).
@MainActor
@Suite("Sheet text zoom")
struct SheetTextZoomTests {
    @Test func referenceIsTheNearestPowerOfTwo() {
        #expect(SheetTextZoom.reference(for: 1) == 1)
        #expect(SheetTextZoom.reference(for: 1.4) == 1)
        #expect(SheetTextZoom.reference(for: 1.42) == 2)
        #expect(SheetTextZoom.reference(for: 3) == 4)
        #expect(SheetTextZoom.reference(for: 0.3) == 0.25)
        #expect(SheetTextZoom.reference(for: 40) == 32)
        for zoom in [0.05, 0.1, 0.7, 1.5, 6, 40] {
            let ratio = zoom / SheetTextZoom.reference(for: zoom)
            #expect(ratio >= pow(2, -0.5) && ratio <= pow(2, 0.5), "zoom \(zoom): scale \(ratio)")
        }
    }

    @Test func uprightMeansAngleZeroModuloATurn() {
        func text(_ angle: Double) -> SheetText {
            SheetText(run: DrawingText.layout("A", height: 3.5), original: "A", origin: .zero, height: 3.5, angle: angle)
        }
        for angle in [0, -0.0, 2 * Double.pi, -2 * Double.pi] { #expect(SheetTextZoom.isUpright(text(angle)), "angle \(angle)") }
        for angle in [Double.pi / 2, .pi, 1e-3] { #expect(!SheetTextZoom.isUpright(text(angle)), "angle \(angle)") }
    }

    #if canImport(MetalUITestingSnapshot)
    /// The ink's left edge and lowest row (the baseline of "H1") in points, over a white sheet.
    private func inkEdges(of content: some ElementGroup, scaleFactor: Double = 2) async throws -> (left: Double, baseline: Double) {
        let window = try await DrawingWindow.open(size: Size(width: Pixels(700), height: Pixels(300))) { content }
        let image = try PixelImage(window: window.window)
        var left: Int?, bottom: Int?
        for y in 0..<image.height {
            for x in 0..<image.width where image.luminance(x, y) < 200 {
                left = min(left ?? x, x)
                bottom = max(bottom ?? y, y)
            }
        }
        return (Double(try #require(left)) / scaleFactor, Double(try #require(bottom) + 1) / scaleFactor)
    }

    @Test(arguments: [0.3, 1.7, 12.0, 22.0])
    func uprightTextLandsWhereItDidBefore(zoom: Double) async throws {
        let text = SheetText(
            run: DrawingText.layout("H1", height: 3.5), original: "H1", origin: Vector2(20, 30), height: 3.5)
        let colors = ColorTheme.dracula.colors
        let ink = colors.drawingInk
        let scaled = try await inkEdges(of: Color.white.overlay(alignment: .topLeading) {
            SheetTexts(texts: [text], zoom: zoom, paperHeight: 40, ink: ink, warning: ink)
        })
        let direct = try await inkEdges(of: Color.white.overlay(alignment: .topLeading) {
            SheetTextView(text: text, zoom: zoom, paperHeight: 40, color: ink)
        })
        // The sheet's baseline is 10 mm down. Text sits within a point of it on both paths: MetalUI aligns `firstTextBaseline` on
        // `round(ascent)` in points but draws glyphs at the device-pixel ascent, so each text is up to ~0.5 pt off its line, and
        // the scaled path pays that error of its reference zoom times the scale (the 2^(1/8) ladder draws ink at the exact scale).
        #expect(abs(scaled.baseline - 10 * zoom) <= 1, "scaled baseline \(scaled.baseline) against \(10 * zoom) at zoom \(zoom)")
        #expect(abs(direct.baseline - 10 * zoom) <= 1, "direct baseline \(direct.baseline) against \(10 * zoom) at zoom \(zoom)")
        #expect(abs(scaled.left - direct.left) <= 0.5, "left edge \(scaled.left) against \(direct.left) at zoom \(zoom)")
    }

    private func text(height: Double, angle: Double = 0) -> SheetText {
        SheetText(run: DrawingText.layout("H1", height: height), original: "H1", origin: Vector2(5, 30), height: height, angle: angle)
    }

    @Test func aTextIsScaledOnlyWhileItsEmFitsMetalUIsRekeyCap() {
        #expect(SheetTextZoom.isScaled(text(height: 3.5), zoom: 20))
        #expect(!SheetTextZoom.isScaled(text(height: 3.5), zoom: 40), "em 390 px at 2x")
        #expect(!SheetTextZoom.isScaled(text(height: 7), zoom: 20), "em 390 px at 2x")
        #expect(SheetTextZoom.isScaled(text(height: 7), zoom: 10))
        #expect(!SheetTextZoom.isScaled(text(height: 3.5, angle: .pi / 2), zoom: 1), "rotated text is never scaled")
        #expect(SheetTextZoom.isScaled(text(height: 3.5, angle: 2 * .pi), zoom: 1))
    }

    /// A text past the cap is drawn on the true-zoom path, so it renders exactly as `SheetTextView` does (sharp).
    @Test(arguments: [(3.5, 40.0), (7.0, 20.0)])
    func textPastTheCapRendersAtTheTrueZoom(height: Double, zoom: Double) async throws {
        let sheetText = text(height: height)
        let ink = ColorTheme.dracula.colors.drawingInk
        func render(_ content: some ElementGroup) async throws -> PixelImage {
            let window = try await DrawingWindow.open(size: Size(width: Pixels(900), height: Pixels(500)), scaleFactor: 2) { content }
            return try PixelImage(window: window.window)
        }
        let viaSheet = try await render(Color.white.overlay(alignment: .topLeading) {
            SheetTexts(texts: [sheetText], zoom: zoom, paperHeight: 40, ink: ink, warning: ink)
        })
        let direct = try await render(Color.white.overlay(alignment: .topLeading) {
            SheetTextView(text: sheetText, zoom: zoom, paperHeight: 40, color: ink)
        })
        #expect(viaSheet.width == direct.width && viaSheet.height == direct.height)
        var differing = 0, inked = 0
        for y in 0..<direct.height {
            for x in 0..<direct.width {
                if direct.luminance(x, y) < 200 { inked += 1 }
                if viaSheet.luminance(x, y) != direct.luminance(x, y) { differing += 1 }
            }
        }
        #expect(inked > 0)
        #expect(differing == 0, "\(differing) pixels differ at zoom \(zoom), height \(height)")
    }

    @Test func warningTextKeepsItsColourInBothGroups() async throws {
        let warning = HexColor(0xFF0000)
        let ink = HexColor(0x000000)
        func lost(_ angle: Double, at origin: Vector2) -> SheetText {
            SheetText(
                run: DrawingText.layout("HHHH", height: 6), original: "HHHH", origin: origin, height: 6, angle: angle, isLost: true)
        }
        let upright = lost(0, at: Vector2(10, 80)), turned = lost(.pi / 2, at: Vector2(70, 30))
        let window = try await DrawingWindow.open(scaleFactor: 2) {
            ZStack(alignment: .topLeading) {
                Color.white.frame(width: 400.px, height: 400.px)
                SheetTexts(texts: [upright, turned], zoom: 3, paperHeight: 100, ink: ink, warning: warning)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        let image = try PixelImage(window: window.window)
        func red(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double) -> Int {
            var n = 0
            for x in stride(from: x0, through: x1, by: 0.5) {
                for y in stride(from: y0, through: y1, by: 0.5) {
                    let p = image.rgb(atPoint: x, y)
                    if p.r > 180 && p.g < 90 && p.b < 90 { n += 1 }
                }
            }
            return n
        }
        #expect(red(30, 100, 40, 66) > 0, "the upright lost text is in the warning colour")
        #expect(red(185, 215, 100, 210) > 0, "the rotated lost text is in the warning colour")
    }
    #endif
}

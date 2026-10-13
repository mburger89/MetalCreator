import CreatorStyle
import MetalUI
import Testing

/// `glassBackground(_:in:)`: the material blurs what is beneath, the theme's tint is drawn over it, and a style that
/// reduces transparency draws the tint alone. What it looks like is human check C21-1.
@MainActor
struct GlassBackgroundTests {
    func frame(_ style: GlassStyle) -> Scene {
        renderHeadless {
            ZStack {}.frame(width: Pixels(120), height: Pixels(60))
                .glassBackground(style, in: RoundedRectangle(cornerRadius: Pixels(10)))
        }
    }

    func box(_ bounds: MUIBounds) -> [Float] {
        [bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height]
    }

    func tintRects(_ scene: Scene) -> [MUIRect] { scene.rects.filter { $0.background.a > 0 } }

    @Test func aBlurringStyleDrawsOneBackdropAndTheThemesTintOverItInTheSameBox() throws {
        let style = GlassStyle(theme: .dracula, surface: .topBar)
        let scene = frame(style)
        let backdrop = try #require(scene.backdrops.first)
        let tint = try #require(tintRects(scene).first)
        #expect(scene.backdrops.count == 1 && tintRects(scene).count == 1)
        #expect(box(backdrop.bounds) == box(tint.bounds), "the tint covers exactly what the material blurs")
        #expect(Array(box(backdrop.bounds)[2...]) == [240, 120], "120 x 60 pt at 2x")
        #expect(backdrop.cornerRadii.topLeft == 20 && tint.cornerRadii.topLeft == 20, "10 pt at 2x")
        let kinds = scene.drawList.map(\.kind)
        let backdropRun = try #require(kinds.firstIndex(of: .backdrop))
        let tintRun = try #require(kinds.firstIndex(of: .rect))
        #expect(backdropRun < tintRun, "the material is painted first, the tint over it: \(kinds)")
    }

    @Test func theTintIsTheThemesColourAtTheOpacityTheStyleSays() throws {
        let style = GlassStyle(theme: .dracula, surface: .topBar)
        let tint = try #require(tintRects(frame(style)).first).background
        let want = style.tint.rgba
        let got = Hsla(h: tint.h, s: tint.s, l: tint.l, a: tint.a).toRgba()
        #expect(abs(got.r - want.x) < 0.01 && abs(got.g - want.y) < 0.01 && abs(got.b - want.z) < 0.01)
        #expect(abs(got.a - want.w) < 0.01, "alpha \(got.a) for \(want.w)")
    }

    @Test func theMaterialIsDrawnInTheThemesSchemeNotTheWindows() throws {
        // A headless window is light, so a dark theme's material being dark proves the style's scheme is the one used.
        let dark = try #require(frame(GlassStyle(theme: .dracula, surface: .topBar)).backdrops.first)
        let light = try #require(frame(GlassStyle(theme: .alucard, surface: .topBar)).backdrops.first)
        #expect(abs(Double(dark.tint.a) - GlassThickness.ultraThin.materialOpacity(isDark: true)) < 1e-4)
        #expect(abs(Double(light.tint.a) - GlassThickness.ultraThin.materialOpacity(isDark: false)) < 1e-4)
        #expect(dark.tint.l < light.tint.l, "dark grey beneath Dracula, light grey beneath Alucard")
    }

    @Test func aStyleThatReducesTransparencyDrawsOnlyTheOpaqueTint() throws {
        let scene = frame(GlassStyle(theme: .dracula, surface: .topBar, reducesTransparency: true))
        #expect(scene.backdrops.isEmpty)
        let tint = try #require(tintRects(scene).first).background
        #expect(tintRects(scene).count == 1 && abs(tint.a - 1) < 0.01)
    }
}

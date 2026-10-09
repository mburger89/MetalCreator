import CreatorEditor
import CreatorKernel
import CreatorStyle
import MetalUI
import MetalUIText
import Testing
@testable import CreatorApp

/// Headless frames of the whole window with the theme editor. They prove it floats where `ThemeEditorLayout` puts
/// it, draws each role's colour, follows edits at once, and that MetalUI's own controls take the theme's tokens.
/// Looks are human checks (group TH).
@MainActor
struct ThemeEditorRenderTests {
    /// A filled rect of a frame, in window points, with its fill as the nearest bytes.
    struct Fill: Equatable {
        let x, y, width, height: Double
        let colour: HexColor
    }

    static let window = Size(width: Pixels(1400), height: Pixels(900))
    static let scale = 2.0

    /// The frame's filled rects: the whole window with the editor, or `AppRoot` alone.
    func fills(_ app: AppModel, _ editor: ThemeEditorModel? = nil) -> [Fill] {
        let input = AppInput(model: app)
        let scene = renderFrame({
            ZStack {
                if let editor {
                    AppWindowRoot(model: app, input: input, themeEditor: editor)
                } else {
                    AppRoot(model: app, input: input)
                }
            }
        }, size: Self.window, scaleFactor: Float(Self.scale), textSystem: CoreTextTextSystem(),
           atlas: GlyphAtlas(width: 1024, height: 1024))
        return scene.rects.map { rect in
            let fill = rect.background
            return Fill(x: Double(rect.bounds.origin.x) / Self.scale, y: Double(rect.bounds.origin.y) / Self.scale,
                        width: Double(rect.bounds.size.width) / Self.scale, height: Double(rect.bounds.size.height) / Self.scale,
                        colour: Self.hex(Hsla(h: fill.h, s: fill.s, l: fill.l, a: fill.a)))
        }
    }

    /// A drawn colour to its nearest bytes, to compare with a theme's.
    static func hex(_ colour: Hsla) -> HexColor {
        let rgba = colour.toRgba()
        func byte(_ value: Float) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return HexColor(byte(rgba.r) << 16 | byte(rgba.g) << 8 | byte(rgba.b), opacity: Double(byte(rgba.a)) / 255)
    }

    func makeApp() async -> (AppModel, ThemeEditorModel) {
        let app = await CreatorAppTests.makeApp()
        return (app, ThemeEditorModel(themes: app.themes))
    }

    @Test func aClosedEditorDrawsNothing() async {
        let (app, editor) = await makeApp()
        let closed = fills(app, editor)
        #expect(closed.count == fills(app).count)
        editor.open()
        #expect(fills(app, editor).count > closed.count)
    }

    @Test func theEditorFloatsAtTheTopRightBelowTheTopBarAndFillsTheHeight() async {
        let (app, editor) = await makeApp()
        editor.open()
        let width = ThemeEditorLayout.width + 2 * GraphPanelLayout.glassPadding
        let x = Double(Self.window.width.value) - AppLayout.margin - width
        let height = Double(Self.window.height.value) - ThemeEditorLayout.top - AppLayout.margin
        let glass = fills(app, editor).filter { fill in
            fill.colour == Palette.dracula.glass.quantized && abs(fill.x - x) < 1 && abs(fill.y - ThemeEditorLayout.top) < 1
        }
        #expect(glass.count == 1, "one glass panel at (\(x), \(ThemeEditorLayout.top))")
        #expect(glass.allSatisfy { abs($0.width - width) < 1 && abs($0.height - height) < 1 })
    }

    /// With the graph panel docked at the bottom, the editor stops a margin above the panel's resize handle, so it
    /// never covers the graph panel.
    @Test func theEditorStopsAboveAGraphPanelDockedAtTheBottom() async {
        let (app, editor) = await makeApp()
        app.editor.setDock(.bottom)
        editor.open()
        let width = ThemeEditorLayout.width + 2 * GraphPanelLayout.glassPadding
        let x = Double(Self.window.width.value) - AppLayout.margin - width
        let windowHeight = Double(Self.window.height.value)
        let graphTop = windowHeight - AppLayout.margin - app.panelHeight
        let height = graphTop - AppLayout.resizeHandle - AppLayout.margin - ThemeEditorLayout.top
        let glass = fills(app, editor).filter { fill in
            fill.colour == Palette.dracula.glass.quantized && abs(fill.x - x) < 1 && abs(fill.y - ThemeEditorLayout.top) < 1
        }
        #expect(glass.count == 1, "one glass panel at (\(x), \(ThemeEditorLayout.top))")
        #expect(glass.allSatisfy { abs($0.height - height) < 1 && $0.y + $0.height < graphTop })
    }

    @Test func theSwatchesShowTheShownThemesColoursAndFollowAnEdit() async throws {
        let (app, editor) = await makeApp()
        editor.select("nord")
        editor.duplicate()
        editor.open()
        func swatches() -> [HexColor] {
            fills(app, editor).filter { fill in
                abs(fill.width - ThemeEditorLayout.swatchWidth) < 0.5 && abs(fill.height - ThemeEditorLayout.swatchHeight) < 0.5
                    && fill.colour.opacity > 0
            }.map(\.colour)
        }
        let surfaces = ThemeRoleGroup.surfaces.roles.map { editor.theme.colors[$0].quantized }
        #expect(Array(swatches().prefix(surfaces.count)) == surfaces, "the first rows are the surfaces, in order")
        editor.setColor(HexColor(0x00ffaa), for: try #require(ThemeRole.named("backgroundTop")))
        #expect(swatches().first == HexColor(0x00ffaa))
    }

    /// MetalUI's own controls (the top bar's buttons, filled with the `surfaceSecondary` token) draw the theme's
    /// tokens, not MetalUI's defaults.
    @Test func metalUIsControlsTakeTheThemesTokens() async {
        let (app, editor) = await makeApp()
        let defaults = [Theme.light.surfaceSecondary, Theme.dark.surfaceSecondary].map(Self.hex)
        #expect(fills(app).contains { defaults.contains($0.colour) }, "without the tokens a button is MetalUI's own")
        let dracula = Set(fills(app, editor).map(\.colour))
        #expect(dracula.isDisjoint(with: defaults))
        #expect(dracula.contains(Self.hex(ColorTheme.dracula.controlTheme.surfaceSecondary)))
        app.themes.select("alucard")
        let alucard = Set(fills(app, editor).map(\.colour))
        #expect(alucard.contains(Self.hex(ColorTheme.alucard.controlTheme.surfaceSecondary)))
        #expect(!alucard.contains(Self.hex(ColorTheme.dracula.controlTheme.surfaceSecondary)))
    }
}

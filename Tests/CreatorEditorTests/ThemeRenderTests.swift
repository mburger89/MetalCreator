import CreatorStyle
import MetalUI
import Testing
@testable import CreatorEditor

/// The editor's views draw the theme of the `ThemeStore` in their environment, and Dracula without one, so a
/// theme switch re-renders them by observation. Headless frames, compared by the colours they paint.
@MainActor
struct ThemeRenderTests {
    /// A glass panel with an inspector section and a row: glass, hairline, hint text and primary text.
    func render(_ store: ThemeStore?) -> [[Float]] {
        let scene = renderHeadless {
            GlassPanel {
                InspectorSectionView(title: "Shape") {
                    LabeledRow(label: "Width") { Spacer() }
                }
            }
            .environment(store)
        }
        let fills = scene.rects.map { [$0.background.h, $0.background.s, $0.background.l, $0.background.a] }
        let borders = scene.rects.map { [$0.borderColor.h, $0.borderColor.s, $0.borderColor.l, $0.borderColor.a] }
        let glyphs = scene.glyphs.map { [$0.color.h, $0.color.s, $0.color.l, $0.color.a] }
        return fills + borders + glyphs
    }

    @Test func withoutAStoreTheViewsDrawDracula() {
        #expect(!render(nil).isEmpty)
        #expect(render(nil) == render(ThemeStore()))
    }

    @Test func selectingAThemeRedrawsTheViewsInIt() {
        let store = ThemeStore()
        let dracula = render(store)
        store.select("alucard")
        let switched = render(store)
        #expect(switched != dracula)
        #expect(switched == render(ThemeStore(preferences: InMemoryThemePreferences(selectedThemeID: "alucard"))))
    }
}

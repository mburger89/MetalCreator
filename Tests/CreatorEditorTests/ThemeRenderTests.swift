import CreatorGeometry
import CreatorGraph
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

    /// The colours `view` paints under `store`.
    func paint<View: ElementGroup>(_ store: ThemeStore?, _ view: () -> View) -> [[Float]] {
        let scene = renderHeadless { view().environment(store) }
        let fills = scene.rects.map { [$0.background.h, $0.background.s, $0.background.l, $0.background.a] }
        let borders = scene.rects.map { [$0.borderColor.h, $0.borderColor.s, $0.borderColor.l, $0.borderColor.a] }
        return fills + borders + scene.glyphs.map { [$0.color.h, $0.color.s, $0.color.l, $0.color.a] }
    }

    /// A view that forgot `@Environment(ThemeStore.self)` would draw Dracula whatever theme is chosen, which the glass
    /// panel test above can't see. Each of these is drawn under Dracula and under Alucard and must differ.
    @Test func eachViewThatPaintsRolesReadsTheStore() throws {
        let alucard = ThemeStore(preferences: InMemoryThemePreferences(selectedThemeID: "alucard"))
        let dracula = ThemeStore()
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let shape = NodeShape(title: "Rib", category: .feature, inputs: [], outputs: [])
        let rect = CanvasRect(origin: .zero, size: Vector2(200, 120))
        let views: [(String, (ThemeStore?) -> [[Float]])] = [
            ("node", { store in
                self.paint(store) {
                    NodeView(shape: shape, rows: [], origin: .zero, flow: .horizontal, isSelected: true, state: nil, shakes: 0)
                }
            }),
            ("note", { store in
                self.paint(store) { StickyView(note: StickyNote(text: "Hi", frame: rect), rect: rect, isSelected: false) }
            }),
            ("frame", { store in
                self.paint(store) { CommentFrameView(box: CommentFrame(title: "Frame", frame: rect), rect: rect, isSelected: false) }
            }),
            ("header", { store in self.paint(store) { GraphPanelHeader(model: editor) } }),
            ("library", { store in self.paint(store) { NodeLibraryView(model: editor, input: GraphPanelInput(model: editor)) } }),
            ("inspector", { store in self.paint(store) { InspectorPanel(model: editor) } }),
            ("status", { store in self.paint(store) { StatusBadgeView(state: .error("No")) } }),
        ]
        editor.selection = [grouped.group]
        for (name, draw) in views {
            #expect(!draw(dracula).isEmpty, "\(name) draws something")
            #expect(draw(alucard) != draw(dracula), "\(name) reads the store's theme")
            #expect(draw(nil) == draw(dracula), "\(name) without a store is Dracula")
        }
    }
}

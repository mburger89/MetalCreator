import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorStyle
import MetalUI
import Testing
@testable import CreatorEditor

/// The node library's views and its drag: drawn inside its `GraphPanelLayout` frame in both docks, gone when
/// hidden, category headers in the theme's header colours, no shadows, and the drag's one gesture and ghost.
@MainActor
struct LibraryViewTests {
    /// In an empty panel every glyph below the header is the library's: what shows of it (inside its clip; the
    /// list scrolls) lies in the library's frame.
    @Test(arguments: [DockSide.left, .bottom])
    func theLibraryIsDrawnInItsFrame(_ dock: DockSide) {
        let editor = makeEditor([], dock: dock)
        let input = GraphPanelInput(model: editor)
        let scene = renderHeadless { GraphPanel(model: editor, input: input) }
        let library = GraphPanelLayout.libraryFrame(inPanelOf: Vector2(900, 600), flow: editor.flow)
        let shown = scene.glyphs.compactMap { glyph -> CanvasRect? in
            let bounds = points(glyph.bounds), mask = points(glyph.contentMask)
            let origin = Vector2(max(bounds.origin.x, mask.origin.x), max(bounds.origin.y, mask.origin.y))
            let corner = Vector2(min(bounds.maxX, mask.maxX), min(bounds.maxY, mask.maxY))
            guard corner.x > origin.x, corner.y > origin.y, origin.y >= library.origin.y else { return nil }
            return CanvasRect(corner: origin, corner)
        }
        #expect(shown.count > 20, "the search field's placeholder, the headers and their types")
        let slack = CanvasRect(origin: library.origin - Vector2(0.5, 0.5), size: library.size + Vector2(1, 1))
        for part in shown {
            #expect(slack.contains(part.origin) && slack.contains(part.origin + part.size), "\(part) is outside \(library)")
        }
    }

    /// Device-pixel bounds in points.
    func points(_ bounds: MUIBounds, scale: Double = 2) -> CanvasRect {
        CanvasRect(origin: Vector2(Double(bounds.origin.x) / scale, Double(bounds.origin.y) / scale),
                   size: Vector2(Double(bounds.size.width) / scale, Double(bounds.size.height) / scale))
    }

    /// One flat list of uniform rows, so MetalUI's `List` builds only those in view: each header, then its types.
    @Test func theListIsEachHeaderThenItsTypes() {
        let editor = makeEditor([])
        editor.setLibraryQuery("e")
        let rows = LibraryItem.rows(editor.librarySections)
        let expected = [
            "header.value", NumberTestNode.typeID, "header.profile", RectangleTestNode.typeID, "header.solid",
            ExtrudeTestNode.typeID, "header.selection", AllEdgesTestNode.typeID, "header.feature", FilletTestNode.typeID,
        ]
        #expect(rows.map(\.id) == expected)
        #expect(rows.filter { $0.entry == nil }.map(\.category) == [.value, .profile, .solid, .selection, .feature])
    }

    @Test func hidingTheLibraryTakesItOutOfThePanel() {
        let editor = makeEditor([], dock: .bottom)
        let input = GraphPanelInput(model: editor)
        let shown = renderHeadless { GraphPanel(model: editor, input: input) }.glyphs.count
        editor.toggleLibrary()
        let hidden = renderHeadless { GraphPanel(model: editor, input: input) }.glyphs.count
        #expect(hidden < shown - 20)
    }

    /// A category's header paints the colour its nodes' headers have, in the current theme.
    @Test(arguments: [nil, "alucard"])
    func aSectionHeaderIsItsCategorysHeaderColour(_ theme: String?) {
        let store = ThemeStore()
        if let theme { store.select(theme) }
        func fills(_ scene: Scene) -> Set<[Float]> {
            Set(scene.rects.map { [$0.background.h, $0.background.s, $0.background.l, $0.background.a] })
        }
        let accent = Palette(store).header(for: .profile)
        let header = fills(renderHeadless { LibrarySectionHeader(category: .profile, title: "Profile").environment(store) })
        let node = fills(renderHeadless { NodeHeaderView(title: "Rectangle", accent: accent, state: nil).environment(store) })
        #expect(!header.isDisjoint(with: node))
    }

    @Test func theLibraryRedrawsInTheChosenTheme() {
        let editor = makeEditor([])
        func render(_ store: ThemeStore) -> [[Float]] {
            let scene = renderHeadless { NodeLibraryView(model: editor, input: GraphPanelInput(model: editor)).environment(store) }
            return scene.rects.map { [$0.background.h, $0.background.s, $0.background.l, $0.background.a] }
                + scene.glyphs.map { [$0.color.h, $0.color.s, $0.color.l, $0.color.a] }
        }
        let store = ThemeStore()
        let dracula = render(store)
        store.select("alucard")
        #expect(render(store) != dracula)
        #expect(render(store) == render(ThemeStore(preferences: InMemoryThemePreferences(selectedThemeID: "alucard"))))
    }

    /// Flat fills and text only: no shadow or path is rasterized, whatever the view rebuilds (PERF-a, PERF-b).
    @Test func theLibraryRasterizesNothing() {
        let editor = makeEditor([])
        #expect(renderHeadless { NodeLibraryView(model: editor, input: GraphPanelInput(model: editor)) }.images.isEmpty)
    }

    /// A row is one zero-distance drag in window points, so the model tells a click from a drag
    /// (`LibraryDrag.threshold`) and maps the release with the host's placement.
    @Test func aRowsGestureIsAZeroDistanceDragInWindowPoints() {
        let editor = makeEditor([])
        let gesture = GraphPanelInput(model: editor).libraryGesture(for: FilletTestNode.typeID)
        #expect(gesture.minimumDistance == Pixels(0))
        #expect(gesture.coordinateSpace == .global)
        #expect(gesture.button == .primary)
    }

    /// The ghost is drawn with its top-left corner at the pointer, in window points, only once the press has moved
    /// far enough to be a drag; a flat row, nothing rasterized.
    @Test func theDragGhostIsDrawnAtThePointerOnlyWhileDragging() throws {
        let editor = makeEditor([])
        #expect(renderHeadless { LibraryDragOverlay(model: editor) }.isEmpty, "nothing without a drag")
        editor.moveLibraryDrag(FilletTestNode.typeID, from: Vector2(40, 300), to: Vector2(44, 303))
        #expect(renderHeadless { LibraryDragOverlay(model: editor) }.isEmpty, "nothing for a click's jitter")
        editor.moveLibraryDrag(FilletTestNode.typeID, from: Vector2(40, 300), to: Vector2(420, 250))
        let scene = renderHeadless { LibraryDragOverlay(model: editor) }
        let ghost = scene.rects.contains { rect in
            let placed = screenFrame(of: rect, in: scene)
            return (placed.origin - Vector2(420, 250)).length < 0.5 && abs(placed.size.x - LibraryDragOverlay.width) < 0.5
        }
        #expect(ghost, "no \(LibraryDragOverlay.width)-wide row at (420, 250)")
        #expect(scene.glyphs.count >= "Fillet".count)
        #expect(scene.images.isEmpty)
        editor.endLibraryDrag(FilletTestNode.typeID, from: Vector2(40, 300), at: Vector2(420, 250))
        #expect(renderHeadless { LibraryDragOverlay(model: editor) }.isEmpty, "gone at the release")
    }
}

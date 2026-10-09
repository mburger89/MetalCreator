import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorEditor

/// The node library ("Nodes", spec §6.2 editor polish): shown by default and saved with the view state, grouped by
/// category over the palette's search, a click adding at the visible canvas's centre clear of other nodes and in view,
/// a drop adding at the drop point, each one undo step.
@MainActor
struct LibraryTests {
    /// The bottom dock's canvas in a 1000 × 700 window: 956 × 244 points.
    func placed(_ editor: EditorModel) -> EditorModel {
        let panel = CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300))
        editor.placement = { PanelPlacement(window: Vector2(1000, 700), panel: panel) }
        return editor
    }

    @Test func itIsShownByDefaultAndItsVisibilityIsSavedButNotAnEdit() throws {
        let editor = makeEditor([])
        #expect(editor.showsLibrary)
        editor.toggleLibrary()
        #expect(!editor.showsLibrary)
        #expect(!editor.document.canUndo, "a view change, not an edit")
        let file = try JSONDecoder().decode(GraphFile.self, from: try editor.document.fileData())
        #expect(!file.viewState.showsLibrary)
        let reopened = EditorModel(document: try DocumentModel(data: try editor.document.fileData(),
                                                               registry: editorTestRegistry, kernel: FakeKernel()))
        #expect(!reopened.showsLibrary)
    }

    @Test func typesAreGroupedByCategoryInOrder() {
        let editor = makeEditor([])
        #expect(editor.librarySections.map(\.title) == ["Value", "Profile", "Solid", "Selection", "Feature", "Output"])
        #expect(editor.librarySections.map { $0.entries.map(\.displayName) }
                == [["Number"], ["Rectangle"], ["Extrude"], ["All Edges"], ["Fillet"], ["Output"]])
    }

    /// The library filters with the palette's search, and empty categories go.
    @Test func theSearchIsThePalettes() {
        let editor = makeEditor([])
        editor.setLibraryQuery("e")
        let flattened = editor.librarySections.flatMap(\.entries).map(\.typeID)
        #expect(Set(flattened) == Set(PaletteSearch.entries(in: editorTestRegistry, matching: "e").map(\.typeID)))
        editor.setLibraryQuery("FIL")
        let fillets = PaletteSearch.entries(in: editorTestRegistry, matching: "fil")
        #expect(editor.librarySections == [LibrarySection(category: .feature, entries: fillets)])
        editor.setLibraryQuery("zzz")
        #expect(editor.librarySections.isEmpty)
    }

    @Test func hoverHelpNamesInputsThenOutputs() {
        let editor = makeEditor([], registry: inspectorTestRegistry)
        #expect(editor.librarySummary(of: ExtrudeTestNode.typeID) == "Extrude: profile, distance, mode, reversed → solid")
        #expect(editor.librarySummary(of: GridPointsTestNode.typeID) == "Grid Points: count x, total → points")
        #expect(editor.librarySummary(of: GraphParameterTestNode.typeID)
                == "Graph Parameter: no inputs → number, integer, bool, vector")
        #expect(editor.librarySummary(of: "plugin.gone") == nil)
    }

    /// The visible canvas's centre comes from the host's placement (without one, a fallback size's).
    @Test func theVisibleCentreIsTheMiddleOfThePlacedCanvas() throws {
        let editor = makeEditor([], dock: .bottom)
        #expect(editor.visibleCanvasCentre == GraphPanelLayout.fallbackCanvasSize * 0.5)
        let canvas = try #require(placed(editor).canvasFrameInWindow)
        #expect(editor.visibleCanvasCentre == canvas.size * 0.5)
    }

    /// Panned and zoomed, the click still lands in the middle of what is on screen.
    @Test func aClickAddsTheTypeCentredInTheVisibleCanvasAsOneStep() throws {
        let editor = placed(makeEditor([], dock: .bottom))
        editor.transform = CanvasTransform(offset: Vector2(10, 20), zoom: 2)
        editor.addFromLibrary(NumberTestNode.typeID)
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        #expect(added.typeID == NumberTestNode.typeID)
        let frame = editor.frame(of: added)
        #expect(editor.transform.toScreen(frame.origin + frame.size * 0.5) == editor.visibleCanvasCentre)
        editor.document.undo()
        #expect(editor.graph.nodes.isEmpty)
        #expect(!editor.document.canUndo, "one step")
    }

    /// Three Extrudes fit side by side in the bottom dock's canvas, each clear of the others.
    @Test func aClickedTypeIsNudgedOffTheNodesAlreadyThere() throws {
        let editor = placed(makeEditor([], dock: .bottom))
        for _ in 0..<3 { editor.addFromLibrary(ExtrudeTestNode.typeID) }
        let frames = editor.graph.nodes.values.map(editor.frame(of:))
        #expect(frames.count == 3)
        for (i, a) in frames.enumerated() {
            for b in frames.dropFirst(i + 1) { #expect(!a.intersects(b), "\(a) overlaps \(b)") }
        }
    }

    /// A crowded view: each clicked type lands wholly inside the visible canvas, wherever it is panned and zoomed,
    /// and once nothing free fits in view it is centred anyway, never pushed off-screen.
    @Test(arguments: [CanvasTransform(), CanvasTransform(offset: Vector2(-300, 40), zoom: 2)])
    func aClickedTypeStaysInViewWhenTheCentreIsCrowded(_ transform: CanvasTransform) throws {
        let editor = placed(makeEditor([], dock: .bottom))
        editor.transform = transform
        let canvas = CanvasRect(origin: .zero, size: editor.visibleCanvasSize)
        for _ in 0..<12 { editor.addFromLibrary(NumberTestNode.typeID) }
        #expect(editor.graph.nodes.count == 12)
        for node in editor.graph.nodes.values {
            let frame = editor.frame(of: node)
            let corners = [frame.origin, frame.origin + frame.size].map(editor.transform.toScreen)
            #expect(corners.allSatisfy(canvas.contains), "\(corners) is outside the visible \(canvas)")
        }
    }

    /// Docked left the canvas shows the transpose, so the centre is found in display points and stored transposed.
    @Test func dockedLeftItIsCentredOnScreenToo() throws {
        let editor = makeEditor([], dock: .left)
        editor.addFromLibrary(NumberTestNode.typeID)
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        let frame = editor.frame(of: added)
        let centre = GraphPanelLayout.fallbackCanvasSize * 0.5
        #expect(frame.origin + frame.size * 0.5 == centre)
        #expect(added.position == Vector2(frame.origin.y, frame.origin.x))
    }

    @Test(arguments: [DockSide.left, .bottom])
    func aDropAddsTheTypeAtTheDropPointAsOneStep(_ dock: DockSide) throws {
        let editor = makeEditor([], dock: dock)
        #expect(editor.dropFromLibrary(FilletTestNode.typeID, atScreen: Vector2(300, 120)))
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        #expect(editor.frame(of: added).origin == Vector2(300, 120))
        editor.document.undo()
        #expect(editor.graph.nodes.isEmpty)
        #expect(!editor.dropFromLibrary("plugin.gone", atScreen: Vector2(300, 120)), "not a type this registry has")
        #expect(editor.graph.nodes.isEmpty)
    }
}

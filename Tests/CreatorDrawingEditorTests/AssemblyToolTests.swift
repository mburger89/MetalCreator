import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The Assembly View tool and the view's part list (DR-5 R1).
@MainActor
@Suite("Assembly tool")
struct AssemblyToolTests {
    private static func option(_ name: String, width: Double) -> DrawingSourceOption {
        DrawingSourceOption(
            id: NodeID(), name: name, bounds: BoundingBox(min: Vector3(0, 0, 0), max: Vector3(width, 50, 30)))
    }

    private func harness(
        views: [DrawingView] = [], sources: [DrawingSourceOption]
    ) -> (EditorHarness, DrawingSheet) {
        let sheet = DrawingSheet(name: "Sheet 1", views: views)
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id, sources: sources)
        return (h, sheet)
    }

    @Test func theToolPlacesEveryOutput() throws {
        let sources = [Self.option("A", width: 100), Self.option("B", width: 100), Self.option("C", width: 100)]
        let (h, _) = harness(sources: sources)
        h.model.press(.assemblyView)
        h.click(150, 150)
        #expect(h.log.commits.map(\.name) == ["Add View"])
        let view = try #require(h.model.document.sheets[0].views.first)
        #expect(view.assembly == sources.map(\.id))
        #expect(view.source == sources[0].id)
        #expect(view.orientation == .standard(.front))
        #expect(h.model.selection == [view.id])
        #expect(h.model.tool == .select)
    }

    @Test func aFirstViewSetsTheScaleFromAllParts() throws {
        let sources = [Self.option("A", width: 100), Self.option("B", width: 1500)]
        let (h, sheet) = harness(sources: sources)
        h.model.press(.assemblyView)
        h.click(150, 150)
        let union = try #require(sources[0].bounds).union(try #require(sources[1].bounds))
        let area = DrawingArea.rect(for: sheet, standard: .iso)
        let expected = ScaleChooser.firstScale(extents: ViewExtents.of(union, frame: StandardOrientation.front.frame), area: area)
        let first = ScaleChooser.firstScale(
            extents: ViewExtents.of(try #require(sources[0].bounds), frame: StandardOrientation.front.frame), area: area)
        #expect(expected != first)
        #expect(h.model.document.sheets[0].scale == expected)
    }

    @Test func projectedViewsCarryTheParts() throws {
        let sources = [Self.option("A", width: 100), Self.option("B", width: 100)]
        let parent = DrawingView(
            kind: .base, source: sources[0].id, orientation: .standard(.front), center: Vector2(150, 150),
            assembly: sources.map(\.id))
        let (h, _) = harness(views: [parent], sources: sources)
        h.model.press(.projectedView)
        h.model.pointerDown(at: h.canvas(150, 150), modifiers: [])
        h.model.pointerDragged(to: h.canvas(200, 150))
        h.model.pointerDragged(to: h.canvas(250, 155))
        h.model.pointerUp(at: h.canvas(250, 155))
        let made = try #require(h.model.document.sheets[0].views.first { $0.kind == .projected })
        #expect(made.assembly == sources.map(\.id))
    }

    @Test func turningAPartOffChangesDescendants() throws {
        let a = NodeID(), b = NodeID(), c = NodeID()
        let parent = DrawingView(
            kind: .base, source: a, orientation: .standard(.front), center: Vector2(100, 150), assembly: [a, b, c])
        let child = DrawingView(
            kind: .projected, source: a, orientation: .standard(.right), center: Vector2(200, 150),
            alignment: ViewAlignment(parent: parent.id, axis: .horizontal), assembly: [a, b, c])
        let (h, _) = harness(views: [parent, child], sources: [])
        h.model.setPart(b, shown: false, of: parent.id)
        #expect(h.log.commits.map(\.name) == ["Change Parts"])
        #expect(h.model.document.sheets[0].view(parent.id)?.assembly == [a, c])
        #expect(h.model.document.sheets[0].view(child.id)?.assembly == [a, c])
        h.model.setPart(b, shown: true, of: parent.id)
        #expect(h.model.document.sheets[0].view(child.id)?.assembly == [a, c, b])
        h.model.setParts([c, a], of: parent.id)
        let after = try #require(h.model.document.sheets[0].view(child.id))
        #expect(after.assembly == [c, a] && after.source == c)
    }

    @Test func theLastPartStays() throws {
        let a = NodeID()
        let parent = DrawingView(kind: .base, source: a, orientation: .standard(.front), center: Vector2(100, 150), assembly: [a])
        let (h, _) = harness(views: [parent], sources: [])
        h.model.setPart(a, shown: false, of: parent.id)
        #expect(h.model.refusal == "An assembly view shows at least one part.")
        #expect(h.log.commits.isEmpty)
        h.model.setParts([], of: parent.id)
        #expect(h.model.refusal == "An assembly view shows at least one part.")
        #expect(h.log.commits.isEmpty)
    }

    @Test func withNoOutputItRefuses() throws {
        let (h, _) = harness(sources: [])
        h.model.press(.assemblyView)
        h.click(150, 150)
        #expect(h.model.refusal == "Add an Output node and wire the part into it first.")
        #expect(h.log.commits.isEmpty)
    }

    @Test func pickContextCarriesTheViewsSpansOnlyForAnAssemblyView() throws {
        let scene = AssemblyScene.make()
        let context = try scene.h.model.pickContext(of: scene.view.id).get()
        #expect(context.parts == scene.spans)
        #expect(context.parts?.map(\.output) == [scene.first, scene.second])
        #expect(context.parts?.map(\.faces) == scene.spans.map(\.faces))
        // The same content on a single-Output view hands over no spans, so its anchors are never wrapped.
        var single = scene.view
        single.assembly = nil
        let sheet = DrawingSheet(name: "Sheet 1", views: [single])
        let content = ViewContent(projection: Projection2D(lines: []), topology: scene.topology, parts: scene.spans)
        let h = EditorHarness(
            document: EditorDocuments.document([sheet]), sheet: sheet.id, sources: [], contents: [single.id: content])
        #expect(try h.model.pickContext(of: single.id).get().parts == nil)
    }
}

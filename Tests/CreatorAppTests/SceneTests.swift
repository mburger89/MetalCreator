import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorStyle
import CreatorViewport
import Testing
@testable import CreatorApp

/// Graph results → viewport items (spec §6.1 preview modes, §6.3, §4.4 ghosts), and the scene following the document.
@MainActor
struct SceneTests {
    @Test func finalPreviewShowsEveryOutputsSolid() async throws {
        var builder = GraphBuilder()
        let first = builder.box(distance: 10)
        _ = builder.box(distance: 20, at: Vector2(0, 300))
        let app = await makeApp(builder.graph)
        #expect(app.viewport.items.count == 2)
        let heights = Set(app.viewport.items.map(\.solid.bounds.size.z))
        #expect(heights == [10, 20])
        #expect(app.viewport.items.allSatisfy { !$0.isGhost })
        let scene = SceneBuilder.scene(shown: [first.output.id], graph: app.document.graph, results: app.document.results,
                                       lastGood: app.document.lastGoodOutputs, selection: [])
        #expect(scene.first?.source == Endpoint(node: first.extrude.id, socket: "solid"),
                "an Output's solid comes from what's wired into it")
    }

    @Test func anErrorUpstreamShowsTheLastGoodResultAsAGhost() async throws {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = await makeApp(builder.graph)
        try app.document.perform(.setInput(box.extrude.id, "distance", .number(-1)))
        await app.settle()
        #expect(app.document.results[box.output.id]?.state.isSuccess == false)
        #expect(app.viewport.items.count == 1)
        #expect(app.viewport.items.first?.isGhost == true)
        #expect(app.viewport.items.first?.solid.bounds.size.z == 10, "the last good box")
    }

    @Test func selectedNodePreviewShowsOnlyTheSelectedNode() async throws {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = await makeApp(builder.graph)
        app.previewMode = .selectedNode
        app.editor.selection = [box.extrude.id]
        await app.settle()
        #expect(app.document.previewNode == box.extrude.id)
        #expect(app.viewport.items.count == 1)
        app.editor.selection = [box.rectangle.id]
        await app.settle()
        #expect(app.viewport.items.isEmpty, "a profile has no solid to show")
        app.editor.selection = []
        await app.settle()
        #expect(app.document.previewNode == nil)
        app.previewMode = .final
        await app.settle()
        #expect(app.viewport.items.count == 1)
    }

    @Test func aRulePreviewedOnItsOwnShowsItsSolidWithItsEdgesSelected() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let edges = builder.add(AllEdgesNode.self, at: Vector2(480, 200))
        builder.wire(box.extrude, "solid", to: edges, "solid")
        let app = await makeApp(builder.graph)
        app.previewMode = .selectedNode
        app.editor.selection = [edges.id]
        await app.settle()
        let item = try #require(app.viewport.items.first)
        #expect(item.solid === solids(app, box.extrude).first)
        #expect(item.selectedEdges.count == 12, "a box's twelve edges glow")
    }

    /// Spec §6.3's glow in Final preview: a selected rule's edges glow on a shown solid that is the rule's own. A
    /// rule feeding a Fillet is on the solid before the fillet; where another Output shows that solid it glows there
    /// and nothing else is added, and where none does the rule's edges come as a guide
    /// (`SceneGuideTests.aRuleWhoseSolidIsNotShownDrawsItsEdgesAsAGuideOverTheFinalPart`, Errata (M6)).
    @Test func aRuleSelectedInFinalPreviewGlowsOnItsOwnShownSolidAndAddsNoGuide() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let edges = builder.add(AllEdgesNode.self, at: Vector2(480, 200))
        let fillet = builder.add(FilletNode.self, at: Vector2(720, 200))
        let filletOutput = builder.add(OutputNode.self, at: Vector2(960, 200))
        builder.wire(box.extrude, "solid", to: edges, "solid")
        builder.wire(edges, "edges", to: fillet, "edges")
        builder.wire(fillet, "solid", to: filletOutput, "solid")
        let app = await makeApp(builder.graph)
        app.editor.selection = [edges.id]
        await app.settle()
        let filleted = try #require(solids(app, fillet).first)
        let plain = try #require(solids(app, box.extrude).first)
        #expect(app.viewport.items.count == 2, "the rule's solid is shown, so its edges need no guide")
        #expect(app.viewport.items.allSatisfy { !$0.isGuide })
        #expect(app.viewport.items.first { $0.solid === filleted }?.selectedEdges.isEmpty == true,
                "the filleted part isn't the rule's solid, so nothing glows on it")
        #expect(app.viewport.items.first { $0.solid === plain }?.selectedEdges.count == 12,
                "the box another Output shows is the rule's solid, so its edges glow")
    }

    @Test func theSceneFollowsTheDocumentWithoutBeingAsked() async throws {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = await makeApp(builder.graph)
        try app.document.perform(.setInput(box.extrude.id, "distance", .number(25)))
        await app.settle()
        #expect(app.viewport.items.first?.solid.bounds.size.z == 25)
        app.document.undo()
        await app.settle()
        #expect(app.viewport.items.first?.solid.bounds.size.z == 10)
    }

    @Test func theViewportOverlaysMoveOutFromUnderThePanels() async {
        let app = await makeApp()
        #expect(app.viewport.modelArea == AppLayout.modelArea(dock: .left, panelWidth: 460, panelHeight: 300))
        #expect(app.viewport.modelArea.leading == 12 + 460 + 8)
        app.editor.setDock(.bottom)
        await app.settle()
        #expect(app.viewport.modelArea.bottom == 12 + 300 + 8)
        #expect(app.viewport.modelArea.leading == 0)
        app.beginPanelResize()
        app.resizePanel(by: -100)
        app.endPanelResize()
        await app.settle()
        #expect(app.panelHeight == 400, "dragging the top edge up grows a bottom-docked panel")
        #expect(app.viewport.modelArea.bottom == 12 + 400 + 8)
    }

    @Test func thePanelResizesWithinItsLimits() async {
        let app = await makeApp()
        app.beginPanelResize()
        #expect(app.isResizingPanel)
        app.resizePanel(by: 40)
        #expect(app.panelWidth == 500)
        app.resizePanel(by: 5_000)
        #expect(app.panelWidth == AppLayout.panelWidths.upperBound)
        app.resizePanel(by: -5_000)
        #expect(app.panelWidth == AppLayout.panelWidths.lowerBound)
        app.endPanelResize()
        app.resizePanel(by: 40)
        #expect(app.panelWidth == AppLayout.panelWidths.lowerBound, "no drag, no resize")
    }

    /// The viewport draws the app's theme (spec §6.6): a switch reaches it without reloading the part, and a new
    /// document's viewport starts in it (themes are app-level, never part of the document).
    @Test func theViewportDrawsTheChosenThemeAcrossDocuments() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let app = await makeApp(builder.graph)
        #expect(app.viewport.theme == .dracula)
        let generation = app.viewport.sceneGeneration
        app.themes.select("nord")
        await app.settle()
        #expect(app.viewport.theme == .nord)
        #expect(app.viewport.sceneGeneration == generation, "a theme switch redraws; it doesn't reload the part")
        app.load(GraphFile(), from: nil)
        await app.settle()
        #expect(app.viewport.theme == .nord, "a new document keeps the theme")
    }
}

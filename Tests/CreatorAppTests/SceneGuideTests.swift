import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// A selected rule's edges over the Final part (spec §6.3, Errata (M6)): when the rule's solid isn't shown, they come
/// as guide items, which the viewport draws over the part.
@MainActor
struct SceneGuideTests {
    /// Rectangle → Extrude → All Edges → Fillet → Output: the Output shows the filleted part, so the box the rule
    /// is on (the Extrude's solid) is shown by no Output.
    struct HiddenRule {
        var graph: Graph
        var extrude: Node
        var edges: Node
        var fillet: Node
    }

    func hiddenRule() -> HiddenRule {
        var builder = GraphBuilder()
        let box = builder.solid()
        let edges = builder.add(AllEdgesNode.self, at: Vector2(480, 200))
        let fillet = builder.add(FilletNode.self, at: Vector2(720, 200))
        let output = builder.add(OutputNode.self, at: Vector2(960, 200))
        builder.wire(box.extrude, "solid", to: edges, "solid")
        builder.wire(edges, "edges", to: fillet, "edges")
        builder.wire(fillet, "solid", to: output, "solid")
        return HiddenRule(graph: builder.graph, extrude: box.extrude, edges: edges, fillet: fillet)
    }

    @Test func aRuleWhoseSolidIsNotShownDrawsItsEdgesAsAGuideOverTheFinalPart() async throws {
        let rule = hiddenRule()
        let app = await makeApp(rule.graph)
        #expect(app.viewport.items.count == 1, "nothing selected: just the part")
        app.editor.selection = [rule.edges.id]
        await app.settle()
        let part = try #require(solids(app, rule.fillet).first)
        let ruleSolid = try #require(solids(app, rule.extrude).first)
        #expect(app.viewport.items.count == 2)
        let shown = try #require(app.viewport.items.first { $0.solid === part })
        #expect(!shown.isGuide && !shown.isGhost && shown.selectedEdges.isEmpty, "the part itself is drawn as before")
        let guide = try #require(app.viewport.items.first { $0.isGuide })
        #expect(guide.solid === ruleSolid)
        #expect(guide.selectedEdges.count == 12, "a box's twelve edges")
        #expect(!guide.isGhost)
        #expect(app.sources[ObjectIdentifier(ruleSolid)] == nil, "a guide is no target for the face menu")
        app.editor.selection = []
        await app.settle()
        #expect(app.viewport.items.count == 1, "deselecting the rule takes its guide away")
    }

    @Test func guidesAppearOnlyInFinalPreview() async throws {
        let rule = hiddenRule()
        let app = await makeApp(rule.graph)
        app.editor.selection = [rule.edges.id]
        await app.settle()
        #expect(app.viewport.items.count == 2)
        app.previewMode = .selectedNode
        await app.settle()
        #expect(app.viewport.items.count == 1, "the rule on its own solid, with its edges selected")
        #expect(app.viewport.items.first?.isGuide == false)
        #expect(app.viewport.items.first?.selectedEdges.count == 12)
        app.editor.selection = [rule.edges.id, rule.fillet.id]
        await app.settle()
        #expect(app.viewport.items.isEmpty, "several selected: the viewport is empty, guides included")
        app.previewMode = .final
        app.editor.selection = [rule.edges.id]
        await app.settle()
        #expect(app.viewport.items.count == 2)
    }

    @Test func aRuleInErrorOrBlockedDrawsNoGuide() async throws {
        let rule = hiddenRule()
        let app = await makeApp(rule.graph)
        try app.document.perform(.setInput(rule.extrude.id, "distance", .number(-1)))
        app.editor.selection = [rule.edges.id]
        await app.settle()
        #expect(app.document.results[rule.edges.id]?.state.isSuccess == false)
        #expect(!app.viewport.items.isEmpty, "the part is still shown, as a ghost")
        #expect(app.viewport.items.allSatisfy { $0.isGhost && !$0.isGuide }, "its last result is stale, so no edges are drawn from it")
    }

    @Test func anUnsuccessfulResultHasNoEdgeSetsToMakeGuidesFrom() async throws {
        let solid = try await FakeKernel().extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10,
                                                   mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        let outputs: [SocketName: Value] = ["edges": .one(.edgeSet(EdgeSet(solid: solid, edges: [EdgeID(1)])))]
        #expect(SceneBuilder.edgeSets(NodeResult(state: .ok(duration: .zero), outputs: outputs)).count == 1)
        #expect(SceneBuilder.edgeSets(NodeResult(state: .error("boom"), outputs: outputs)).isEmpty)
        #expect(SceneBuilder.edgeSets(NodeResult(state: .idle("missing input"), outputs: outputs)).isEmpty)
        #expect(SceneBuilder.guides(for: SceneBuilder.edgeSets(NodeResult(state: .error("boom"), outputs: outputs)),
                                    notShownIn: []).isEmpty)
    }

    @Test func sketchModeShowsNoGuides() async throws {
        var builder = GraphBuilder()
        let sketch = builder.add(SketchNode.self, [NodeSetting.sketch: .sketch(rectangleSketch())])
        let extrude = builder.add(ExtrudeNode.self, ["distance": .number(10)], at: Vector2(240, 0))
        let edges = builder.add(AllEdgesNode.self, at: Vector2(480, 200))
        let fillet = builder.add(FilletNode.self, at: Vector2(720, 200))
        let output = builder.add(OutputNode.self, at: Vector2(960, 200))
        builder.wire(sketch, "profiles", to: extrude, "profile")
        builder.wire(extrude, "solid", to: edges, "solid")
        builder.wire(edges, "edges", to: fillet, "edges")
        builder.wire(fillet, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        app.editor.selection = [edges.id]
        await app.settle()
        #expect(app.viewport.items.contains { $0.isGuide }, "in Final preview the rule's edges are a guide")
        app.editor.selection = [sketch.id]
        app.editor.press(.editSketch, on: sketch.id)
        app.handle(try #require(app.editor.inspectorRequest))
        await app.settle()
        await app.viewport.waitForAnimation()
        #expect(app.sketch != nil)
        app.editor.selection = [sketch.id, edges.id]
        await app.settle()
        #expect(app.sketch != nil)
        #expect(app.viewport.items.allSatisfy { $0.isGhost && !$0.isGuide }, "the dimmed scene, with no guide over it")
    }

    @Test func rulesOnTheSameHiddenSolidShareOneGuide() async throws {
        let kernel = FakeKernel()
        func solid() async throws -> Solid {
            try await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided,
                                     tag: NodeTag(node: NodeID(), item: 0))
        }
        let (hidden, other, shownSolid, ghosted) = (try await solid(), try await solid(), try await solid(), try await solid())
        let scene = [SceneItem(item: ViewportItem(solid: shownSolid), source: nil),
                     SceneItem(item: ViewportItem(solid: ghosted, isGhost: true), source: nil),
        ]
        let sets = [EdgeSet(solid: hidden, edges: [EdgeID(0), EdgeID(1)]),
                    EdgeSet(solid: shownSolid, edges: [EdgeID(2)]),
                    EdgeSet(solid: other, edges: []),
                    EdgeSet(solid: ghosted, edges: [EdgeID(3)]),
                    EdgeSet(solid: hidden, edges: [EdgeID(1), EdgeID(5)]),
        ]
        let guides = SceneBuilder.guides(for: sets, notShownIn: scene)
        #expect(guides.count == 2, "one for the hidden solid, one for the stale ghost's; none for a shown solid or no edges")
        #expect(guides[0].item.solid === hidden)
        #expect(guides[0].item.selectedEdges == [EdgeID(0), EdgeID(1), EdgeID(5)], "both rules' edges, once")
        #expect(guides[1].item.solid === ghosted)
        #expect(guides.allSatisfy { $0.item.isGuide && $0.source == nil })
    }

    @Test func aGuideDrawsDifferentlyFromThePartItShadows() async throws {
        let solid = try await FakeKernel().extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10,
                                                   mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        let part = ViewportItem(solid: solid, selectedEdges: [EdgeID(1)])
        let guide = ViewportItem(solid: solid, selectedEdges: [EdgeID(1)], isGuide: true)
        #expect(!part.drawsTheSame(as: guide))
        #expect(ViewportItem.sameScene([part, guide], [part, guide]))
        #expect(!ViewportItem.sameScene([part], [guide]), "so a guide appearing re-shows the scene")
    }
}

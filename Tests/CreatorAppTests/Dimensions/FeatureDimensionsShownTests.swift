import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
@testable import CreatorViewport
import Testing
@testable import CreatorApp

/// The selected features' dimensions and the pinned ones reach the viewport, and only then (DIM-3 Task 11, spec §3.3).
@MainActor
struct FeatureDimensionsShownTests {
    func ids(_ app: AppModel) -> [String] { app.viewport.dimensions.map(\.id.rawValue) }

    func prefix(_ node: Node) -> String { "feature/\(node.id.rawValue.uuidString)/input/" }

    @Test func selectingAnExtrudeShowsItsDepthAndItsSketchsSizes() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        #expect(app.viewport.dimensions.isEmpty)
        app.editor.selection = [box.extrude.id]
        await app.settle()
        let shown = ids(app)
        #expect(shown.count == 3)
        #expect(shown.contains("\(prefix(box.extrude))distance/0"))
        #expect(shown.contains("\(prefix(box.rectangle))width/0"))
        #expect(shown.contains("\(prefix(box.rectangle))height/0"))
        #expect(app.featureDimensions.count == 3)
    }

    @Test func clearingTheSelectionHidesThem() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.extrude.id]
        await app.settle()
        #expect(!app.viewport.dimensions.isEmpty)
        app.editor.selection = []
        await app.settle()
        #expect(app.viewport.dimensions.isEmpty && app.featureDimensions.isEmpty)
    }

    @Test func enteringAPickSessionEmptiesTheTable() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let rule = builder.add(EdgesByTagNode.self)
        builder.wire(box.extrude, "solid", to: rule, "solid")
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.extrude.id]
        await app.settle()
        #expect(!app.featureDimensions.isEmpty)
        app.beginPick(for: rule.id)
        await app.settle()
        #expect(app.viewport.dimensions.isEmpty)
        #expect(app.featureDimensions.isEmpty, "the table matches what is drawn")
    }

    @Test func severalSelectedNodesEachShowTheirOwn() async throws {
        var builder = GraphBuilder()
        let first = builder.box()
        let second = builder.box(at: Vector2(0, 300))
        let app = await makeApp(builder.graph)
        app.editor.selection = [first.extrude.id, second.extrude.id]
        await app.settle()
        let shown = ids(app)
        #expect(shown.count == 6 && Set(shown).count == 6)
        #expect(shown.contains("\(prefix(first.extrude))distance/0") && shown.contains("\(prefix(second.extrude))distance/0"))
    }

    @Test func aPinnedDimensionStaysWhenTheSelectionMoves() async throws {
        var builder = GraphBuilder()
        let first = builder.box()
        let second = builder.box(at: Vector2(0, 300))
        let app = await makeApp(builder.graph)
        try app.editor.edit(.pinDimension(DimensionPin(node: first.extrude.id, target: .input("distance"))),
                            name: UndoName.pinDimension)
        app.editor.selection = [second.extrude.id]
        await app.settle()
        let shown = app.viewport.dimensions
        #expect(shown.count == 4)
        let pinned = try #require(shown.first { $0.id.rawValue == "\(prefix(first.extrude))distance/0" })
        #expect(pinned.isPinned && !pinned.isGhosted)
        app.editor.selection = []
        await app.settle()
        #expect(ids(app) == ["\(prefix(first.extrude))distance/0"])
    }

    @Test func whileSketchingPinsAreGhostedAndContextualOnesHidden() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let other = builder.box(at: Vector2(0, 300))
        let width = try #require(rectangleSketch().dimensions.first { $0.value.name == "width" }?.key)
        builder.graph.dimensionPins = [
            DimensionPin(node: other.extrude.id, target: .input("distance")),
            DimensionPin(node: box.sketch.id, target: .sketchDimension(width)),
        ].sorted()
        let app = await makeApp(builder.graph)
        app.editor.selection = [other.rectangle.id]
        await app.settle()
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        let shown = app.viewport.dimensions
        #expect(shown.filter { $0.id.rawValue.hasPrefix("sketch/") }.count == 2)
        let features = shown.filter { $0.id.rawValue.hasPrefix("feature/") }
        #expect(features.map(\.id.rawValue) == ["\(prefix(other.extrude))distance/0"], "no contextual and no double of the sketch's own")
        #expect(features.allSatisfy(\.isGhosted) && features.allSatisfy(\.isPinned))
        #expect(shown.filter { $0.id.rawValue.hasPrefix("sketch/") }.allSatisfy { !$0.isGhosted })
        app.finishSketch()
        await app.settle()
        #expect(ids(app).contains("\(prefix(other.extrude))distance/0") && app.viewport.dimensions.allSatisfy { !$0.isGhosted })
    }

    @Test func insideAGroupTheLevelsFeaturesShow() async throws {
        var builder = GraphBuilder()
        let inner = builder.box()
        let outer = builder.box(at: Vector2(0, 300))
        builder.graph.dimensionPins = [DimensionPin(node: outer.extrude.id, target: .input("distance"))]
        let app = await makeApp(builder.graph)
        app.editor.selection = [inner.rectangle.id, inner.extrude.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        app.editor.enterGroup(group)
        await app.settle()
        #expect(app.viewport.dimensions.isEmpty, "the top level's pin is hidden inside, and nothing is selected")
        app.editor.selection = [inner.extrude.id]
        await app.settle()
        let shown = ids(app)
        #expect(shown.count == 3 && shown.contains("\(prefix(inner.extrude))distance/0"))
        #expect(!shown.contains("\(prefix(outer.extrude))distance/0"))
        app.editor.exitGroup()
        app.editor.selection = []
        await app.settle()
        #expect(ids(app) == ["\(prefix(outer.extrude))distance/0"])
    }

    @Test func dimensionsChangeNeitherTheSceneNorItsBounds() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        let bounds = app.viewport.sceneBounds
        let generation = app.viewport.renderKey.sceneGeneration
        app.editor.selection = [box.extrude.id]
        await app.settle()
        #expect(!app.viewport.dimensions.isEmpty)
        #expect(app.viewport.sceneBounds == bounds)
        #expect(app.viewport.renderKey.sceneGeneration == generation)
    }
}

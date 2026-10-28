import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
@testable import CreatorViewport
import Foundation
import Testing
@testable import CreatorApp

/// Pinning a dimension from its context menu, and a reference's source on hover (DIM-3 Task 15, spec §3.3).
@MainActor
struct DimensionPinMenuTests {
    func distanceID(_ node: Node) -> OverlayDimensionID {
        OverlayDimensionID("feature/\(node.id.rawValue.uuidString)/input/distance/0")
    }

    func select(_ app: AppModel, _ node: Node) async {
        app.editor.selection = [node.id]
        await app.settle()
    }

    @Test func aDimensionsMenuOffersPinThenUnpin() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        await select(app, box.extrude)
        let id = distanceID(box.extrude)
        let first = app.dimensionRouter.menuActions(for: id)
        #expect(first.map(\.title) == ["Pin Dimension"] && first.map(\.key) == ["pin"])
        app.dimensionRouter.performMenuAction(first[0], for: id)
        await app.settle()
        #expect(app.document.graph.dimensionPins == [DimensionPin(node: box.extrude.id, target: .input("distance"))])
        #expect(app.undoTitle == "Undo Pin Dimension")
        #expect(app.viewport.dimensions.first { $0.id == id }?.isPinned == true)
        let second = app.dimensionRouter.menuActions(for: id)
        #expect(second.map(\.title) == ["Unpin Dimension"] && second.map(\.key) == ["unpin"])
        app.dimensionRouter.performMenuAction(second[0], for: id)
        await app.settle()
        #expect(app.document.graph.dimensionPins.isEmpty && app.undoTitle == "Undo Unpin Dimension")
        #expect(app.viewport.dimensions.first { $0.id == id }?.isPinned == false)
    }

    @Test func pinsAreSavedAndReopen() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        await select(app, box.extrude)
        let id = distanceID(box.extrude)
        app.dimensionRouter.performMenuAction(app.dimensionRouter.menuActions(for: id)[0], for: id)
        let url = temporaryURL("pins.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try app.save(to: url)

        let reopened = await makeApp()
        try reopened.open(url)
        await reopened.settle()
        #expect(reopened.document.graph.dimensionPins == app.document.graph.dimensionPins)
        #expect(reopened.document.graph.dimensionPins.count == 1)
        reopened.editor.selection = []
        await reopened.settle()
        #expect(reopened.viewport.dimensions.first { $0.id == id }?.isPinned == true, "shown pinned with nothing selected")
    }

    @Test func pinningInsideAGroupPinsInItsDefinition() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.rectangle.id, box.extrude.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        app.editor.enterGroup(group)
        await select(app, box.extrude)
        let id = distanceID(box.extrude)
        let actions = app.dimensionRouter.menuActions(for: id)
        #expect(actions.map(\.key) == ["pin"])
        app.dimensionRouter.performMenuAction(actions[0], for: id)
        await app.settle()
        let pin = DimensionPin(node: box.extrude.id, target: .input("distance"))
        #expect(app.editor.graph.dimensionPins == [pin], "the definition's graph")
        #expect(app.document.graph.dimensionPins.isEmpty, "not the top level")
        #expect(app.dimensionRouter.menuActions(for: id).map(\.key) == ["unpin"])
    }

    @Test func aSketchsOwnDimensionsOfferNoPin() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        await select(app, box.extrude)
        #expect(app.dimensionRouter.menuActions(for: OverlayDimensionID("sketch/1")).isEmpty)
        #expect(app.dimensionRouter.menuActions(for: OverlayDimensionID("feature/gone/input/x/0")).isEmpty)
    }

    @Test func aReferenceNamesItsSourceOnHover() async throws {
        var builder = GraphBuilder()
        var number = builder.add(NumberNode.self, ["value": .number(10)])
        number.name = "width"
        builder.replace(number)
        let rectangle = builder.add(RectangleNode.self)
        builder.graph.nodes[rectangle.id]?.isOutput = true
        builder.wire(number, "value", to: rectangle, "width")
        let app = await makeApp(builder.graph)
        await select(app, rectangle)
        let width = OverlayDimensionID("feature/\(rectangle.id.rawValue.uuidString)/input/width/0")
        #expect(app.dimensionRouter.hoverNote(for: width) == "from Number “width”")
        let height = OverlayDimensionID("feature/\(rectangle.id.rawValue.uuidString)/input/height/0")
        #expect(app.dimensionRouter.hoverNote(for: height) == nil, "a driving dimension has no note")
    }
}

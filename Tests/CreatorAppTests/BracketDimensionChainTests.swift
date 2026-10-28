import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorViewport
#if canImport(CreatorOCCT)
@testable import CreatorOCCT
#endif

/// The §7.2 bracket's dimensions follow each feature's private chain, and the plate's depth is the Wall parameter
/// (DIM-4 Task 8; pins DIM-3's chain rules).
@MainActor
struct BracketDimensionChainTests {
    #if canImport(CreatorOCCT)
    private func makeBracket() async throws -> (app: AppModel, bracket: AppBracket) {
        let app = AppModel(kernel: OCCTKernel())
        let bracket = try AppBracket(in: app)
        await app.settle()
        // Pick the chamfer's edges in the viewport, as a person does.
        app.editor.press(.pickEdgesInView, on: bracket.chamfer.id)
        app.handle(try #require(app.editor.inspectorRequest))
        await app.settle()
        let session = try #require(app.pick)
        for edge in bracket.topCapOutline(session.solid) { app.viewportClicked(.edge(solid: 0, edge)) }
        app.finishPick()
        await app.settle()
        expectAllOK(app, "the bracket")
        return (app, bracket)
    }

    private func select(_ app: AppModel, _ node: Node) async {
        app.editor.selection = [node.id]
        await app.settle()
    }

    private func shown(_ app: AppModel, containing text: String) -> Bool {
        app.viewport.dimensions.contains { $0.text.contains(text) }
    }

    @Test func theChamferShowsItsDistanceButNotTheFilletsRadius() async throws {
        let (app, bracket) = try await makeBracket()
        await select(app, bracket.chamfer)
        #expect(shown(app, containing: "0.5"), "\(app.viewport.dimensions.map(\.text))")
        #expect(!shown(app, containing: "R3"), "the chain never crosses the fillet's solid wire")
    }

    @Test func theFilletShowsItsRadiusWhenSelected() async throws {
        let (app, bracket) = try await makeBracket()
        await select(app, bracket.fillet)
        #expect(shown(app, containing: "R3"), "\(app.viewport.dimensions.map(\.text))")
    }

    @Test func thePlatesDepthIsTheWallParameter() async throws {
        let (app, bracket) = try await makeBracket()
        await select(app, bracket.plate)
        let depth = try #require(app.viewport.dimensions.first { $0.text == "6" }, "\(app.viewport.dimensions.map(\.text))")
        #expect(depth.tint == .dimensionDriving)
        #expect(app.dimensionRouter.valueBoxContent(for: depth.id)?.note == "Wall (parameter, used by 1 feature)")

        #expect(app.viewport.openValueBox(for: depth.id))
        app.viewport.valueBoxDraftChanged("8")
        await app.viewport.submitValueBox()
        await app.settle()
        #expect(app.document.graph.parameters.first { $0.id == bracket.wall.id }?.value == .number(8))
        #expect(app.document.undoName == UndoName.changeParameter)
        #expect(app.document.graph.nodes[bracket.flange.id]?.inputValues["distance"] == .number(8), "the flange's own distance")
        #expect(!app.document.graph.links.contains { $0.to == Endpoint(node: bracket.flange.id, socket: "distance") })
        expectAllOK(app, "Wall 8")

        app.undo()
        await app.settle()
        #expect(app.document.graph.parameters.first { $0.id == bracket.wall.id }?.value == .number(6))
    }

    @Test func aParameterOutsideItsRangeIsRefusedInTheBox() async throws {
        let (app, bracket) = try await makeBracket()
        await select(app, bracket.plate)
        let depth = try #require(app.viewport.dimensions.first { $0.text == "6" })
        let undoBefore = app.undoTitle
        let graph = app.document.graph
        #expect(app.viewport.openValueBox(for: depth.id))
        app.viewport.valueBoxDraftChanged("40")
        await app.viewport.submitValueBox()
        await app.settle()
        #expect(app.viewport.valueBox?.message == "Wall must be between 1 mm and 20 mm.")
        #expect(app.document.graph.parameters.first { $0.id == bracket.wall.id }?.value == .number(6))
        #expect(app.undoTitle == undoBefore, "no undo step")
        #expect(app.document.graph == graph)
    }
    #endif
}

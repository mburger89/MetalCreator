import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor

/// A sketch value typed into the viewport's box is checked against the part like a feature's (DIM-3 Task 14, spec §7).
@MainActor
struct SketchCommitCheckTests {
    /// Sketch rectangle (60 × 40) → Extrude 10 → Fillet radius 4 (all edges) → Output, with the sketch open.
    func filletedSketch() async throws -> (app: AppModel, sketch: Node, width: OverlayDimensionID) {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let edges = builder.add(AllEdgesNode.self, at: Vector2(480, 200))
        let fillet = builder.add(FilletNode.self, ["radius": .number(4)], at: Vector2(720, 200))
        let output = builder.add(OutputNode.self, at: Vector2(960, 200))
        builder.wire(box.extrude, "solid", to: edges, "solid")
        builder.wire(edges, "edges", to: fillet, "edges")
        builder.wire(fillet, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        let editor = try #require(app.sketch?.editor)
        let width = try #require(editor.sketch.dimensions.first { $0.value.name == "width" }?.key)
        return (app, box.sketch, SketchDimensionDrawing.overlayID(width))
    }

    func storedWidth(_ app: AppModel, _ node: Node) -> Double? {
        guard case .sketch(let sketch)? = app.document.graph.nodes[node.id]?.inputValues[NodeSetting.sketch] else { return nil }
        return sketch.dimensions.first { $0.value.name == "width" }?.value.value
    }

    func editorWidth(_ app: AppModel) -> Double? {
        app.sketch?.editor.sketch.dimensions.first { $0.value.name == "width" }?.value.value
    }

    @Test func aSketchValueThatBreaksTheExtrudeIsRefusedAndTakenBack() async throws {
        let (app, sketch, width) = try await filletedSketch()
        let undoTitle = app.undoTitle
        let canUndo = app.document.canUndo
        let outcome = await app.dimensionRouter.commitValue("6", to: width)
        guard case .refused(let message) = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
        #expect(message.hasPrefix("Fillet: "))
        await app.settle()
        #expect(storedWidth(app, sketch) == 60)
        #expect(editorWidth(app) == 60)
        #expect(app.undoTitle == undoTitle)
        #expect(app.document.canUndo == canUndo)
        #expect(!app.document.canRedo)
        #expect(!app.document.isHoldingResults)
    }

    @Test func aGoodSketchValueIsOneStep() async throws {
        let (app, sketch, width) = try await filletedSketch()
        let outcome = await app.dimensionRouter.commitValue("30", to: width)
        #expect(outcome == .accepted)
        await app.settle()
        #expect(storedWidth(app, sketch) == 30)
        #expect(editorWidth(app) == 30)
        #expect(app.undoTitle == "Undo Change Dimension")
        #expect(!app.document.isHoldingResults)
        app.undo()
        await app.settle()
        #expect(storedWidth(app, sketch) == 60)
    }

    @Test func theHoldIsReleasedWhenTheEditorRefusesFirst() async throws {
        let (app, _, width) = try await filletedSketch()
        let outcome = await app.dimensionRouter.commitValue("abc", to: width)
        guard case .refused = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
        #expect(!app.document.isHoldingResults)
        #expect(!app.document.canUndo)
    }
}

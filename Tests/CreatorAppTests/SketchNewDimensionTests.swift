import CreatorGeometry
import Foundation
import CreatorGraph
import CreatorKernel
import CreatorSketch
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor
@testable import CreatorViewport

/// The D tool through the app (spec §4.2): the second pick opens the viewport's box, Esc leaves nothing, and the placing click is
/// one "Add Dimension" step.
@MainActor
struct SketchNewDimensionTests {
    /// A 60 × 40 rectangle held by horizontal, vertical and a fixed corner but with no size dimensions, so a new dimension drives.
    func freeRectangle() -> Sketch {
        var sketch = Sketch(plane: .fixed(.xy))
        let corners = [Vector2(0, 0), Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)].map { sketch.addPoint($0) }
        let lines = (0..<4).map { sketch.addLine(from: corners[$0], to: corners[($0 + 1) % 4]) }
        sketch.add(.horizontal(lines[0]))
        sketch.add(.horizontal(lines[2]))
        sketch.add(.vertical(lines[1]))
        sketch.add(.vertical(lines[3]))
        sketch.add(.fix(corners[0], at: .zero))
        return sketch
    }

    /// The rectangle open for editing with the D tool chosen.
    func openSketch(_ sketch: Sketch? = nil) async throws -> (app: AppModel, node: Node, editor: SketchEditorModel) {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(sketch ?? freeRectangle())
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        await app.viewport.waitForAnimation()
        let editor = try #require(app.sketch?.editor)
        editor.choose(.dimension)
        return (app, box.sketch, editor)
    }

    func screenPoint(_ app: AppModel, _ p: Vector2) throws -> ScreenPoint {
        try #require(ViewportProjector(pose: app.viewport.pose, size: app.viewport.viewSize).screenPoint(of: Plane.xy.point(p)))
    }

    func click(_ app: AppModel, _ p: Vector2) async throws {
        app.viewport.click(at: try screenPoint(app, p))
        await app.settle()
    }

    /// Two picks on the rectangle's diagonal corners; the box is then open.
    func pickDiagonal(_ app: AppModel) async throws {
        try await click(app, Vector2(0, 0))
        try await click(app, Vector2(60, 40))
    }

    @Test func theDToolOpensTheViewportsBox() async throws {
        let (app, _, editor) = try await openSketch()
        let undo = app.undoTitle
        try await pickDiagonal(app)
        #expect(app.viewport.valueBox?.id == OverlayDimensionID("sketch/new"))
        #expect(app.undoTitle == undo)
        #expect(editor.pending != nil)
    }

    @Test func placingIsOneUndoStep() async throws {
        let (app, _, editor) = try await openSketch()
        let count = editor.sketch.dimensionIDs.count
        try await pickDiagonal(app)
        app.viewport.valueBoxDraftChanged("80")
        await app.viewport.submitValueBox()
        await app.settle()
        #expect(app.viewport.valueBox == nil)
        try await click(app, Vector2(30, 60))
        #expect(app.undoTitle == "Undo Add Dimension")
        #expect(editor.sketch.dimensionIDs.count == count + 1)
        app.document.undo()
        await app.settle()
        #expect(editor.sketch.dimensionIDs.count == count, "the sketch has no new dimension")
    }

    @Test func escapeInTheBoxLeavesNoStep() async throws {
        let (app, _, editor) = try await openSketch()
        let undo = app.undoTitle
        try await pickDiagonal(app)
        app.viewport.cancelValueBox()
        await app.settle()
        #expect(app.undoTitle == undo)
        #expect(editor.pending == nil)
        #expect(app.viewport.valueBox == nil)
    }

    @Test func finishingTheSketchWhilePlacingAddsNothing() async throws {
        let (app, node, editor) = try await openSketch()
        let count = editor.sketch.dimensionIDs.count
        let undo = app.undoTitle
        try await pickDiagonal(app)
        app.viewport.valueBoxDraftChanged("80")
        await app.viewport.submitValueBox()
        await app.settle()
        #expect(editor.pending != nil, "placing")
        app.finishSketch()
        await app.settle()
        #expect(app.undoTitle == undo)
        guard case .sketch(let stored)? = app.document.graph.nodes[node.id]?.inputValues[NodeSetting.sketch] else {
            Issue.record("the node holds no sketch")
            return
        }
        #expect(stored.dimensionIDs.count == count)
    }

    @Test func aDraggedLabelIsSavedAndReopens() async throws {
        let (app, node, editor) = try await openSketch(rectangleSketch())
        let width = try #require(editor.sketch.dimensionIDs.first)
        let id = SketchDimensionDrawing.overlayID(width)
        let projector = ViewportProjector(pose: app.viewport.pose, size: app.viewport.viewSize)
        #expect(editor.dragBegan(onDimension: id, at: try screenPoint(app, Vector2(30, -5)), modifiers: [], projector: projector))
        editor.dragEnded(at: try screenPoint(app, Vector2(30, -15)), modifiers: [], projector: projector)
        await app.settle()
        #expect(app.undoTitle == "Undo Place Dimension")
        let label = try #require(editor.sketch.dimensions[width]?.labelPoint)
        let url = temporaryURL("label.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try app.save(to: url)
        let reopened = await makeApp()
        try reopened.open(url)
        await reopened.settle()
        guard case .sketch(let stored)? = reopened.document.graph.nodes[node.id]?.inputValues[NodeSetting.sketch] else {
            Issue.record("the node holds no sketch")
            return
        }
        #expect(stored.dimensions[width]?.labelPoint == label)
    }
}

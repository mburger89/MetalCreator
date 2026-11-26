// Test fixture file: an app over FakeKernel with a box into an Output, and the drawing editor driven the way a person does.
import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// A rectangle (`width` by 10) extruded 10 into an Output, plus the nodes.
@MainActor
struct DrawingBox {
    var builder = GraphBuilder()
    let rectangle: Node
    let extrude: Node
    let output: Node

    init(width: Double = 20) {
        let rectangle = builder.add(RectangleNode.self, ["width": .number(width)])
        let (extrude, output) = (builder.add(ExtrudeNode.self, ["distance": .number(10)]), builder.add(OutputNode.self))
        builder.wire(rectangle, "profile", to: extrude, "profile")
        builder.wire(extrude, "solid", to: output, "solid")
        (self.rectangle, self.extrude, self.output) = (rectangle, extrude, output)
    }

    var graph: Graph { builder.graph }
}

extension AppModel {
    /// The app showing `graph`, evaluated, in Drawing mode with one sheet.
    static func inDrawing(
        _ graph: Graph, kernel: any Kernel = FakeKernel(), sheet: Bool = true, templates: DrawingTemplateStore = DrawingTemplateStore()
    ) async -> AppModel {
        let app = AppModel(kernel: kernel, file: GraphFile(graph: graph), templates: templates)
        await app.settle()
        app.setMode(.drawing)
        if sheet { app.drawing.editor.addSheet() }
        await app.settle()
        return app
    }

    /// A click of the Base View tool at a sheet point (millimetres); returns the new view.
    @discardableResult
    func placeBaseView(at point: Vector2 = Vector2(150, 150)) async -> ViewID? {
        let editor = drawing.editor
        let before = Set(editor.document.sheets.flatMap(\.views).map(\.id))
        editor.press(.baseView)
        editor.primaryEnded(at: editor.transform.screenPoint(point), modifiers: [])
        await settle()
        return editor.document.sheets.flatMap(\.views).map(\.id).first { !before.contains($0) }
    }

    /// The lines a view draws now.
    func lines(of view: ViewID) -> [ProjectedLine] {
        drawing.editor.contents[view]?.projection?.lines ?? []
    }

    /// The width of a view's frame on the sheet, millimetres.
    func frameWidth(of view: ViewID) -> Double? {
        drawing.editor.picture?.viewFrames[view]?.width
    }
}

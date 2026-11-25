// Test fixture file: a box with a dimension on its bottom edge, a way to lose that edge, and the picture's numbers.
import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// A box (`width` by 10 by 10) into an Output, and a second box nothing shows: wiring the Output to it makes the first box's edges
/// vanish (the names a dimension holds are the first box's).
@MainActor
struct DimensionPlate {
    var box: DrawingBox
    let spareExtrude: Node

    init(width: Double = 40) {
        var box = DrawingBox(width: width)
        let rectangle = box.builder.add(RectangleNode.self, ["width": .number(width)])
        let extrude = box.builder.add(ExtrudeNode.self, ["distance": .number(10)])
        box.builder.wire(rectangle, "profile", to: extrude, "profile")
        (self.box, spareExtrude) = (box, extrude)
    }

    var graph: Graph { box.graph }

    /// The edit that makes the Output show the other box.
    var loseTheEdge: GraphCommand {
        .connect(Link(from: Endpoint(node: spareExtrude.id, socket: "solid"), to: Endpoint(node: box.output.id, socket: "solid")))
    }

    func setWidth(_ width: Double) -> GraphCommand { .setInput(box.rectangle.id, "width", .number(width)) }
}

extension AppModel {
    /// The dimension tool: a click on the bottom edge of `view`, then a click `distance` mm below it. Returns the new annotation.
    @discardableResult
    func dimensionBottomEdge(of view: ViewID, below distance: Double = 8) async -> AnnotationID? {
        let editor = drawing.editor
        guard let sheet = editor.currentSheet.flatMap({ editor.document.sheet($0) }), let drawn = sheet.view(view),
            let projection = editor.contents[view]?.projection, let bounds = projection.bounds,
            let center = ViewPlacement.centers(in: sheet)[view],
            let mapping = ViewMapping.of(projection: projection, center: center, scale: (drawn.scale ?? sheet.scale).value)
        else { return nil }
        let before = Set(sheet.annotations.map(\.id))
        let bottom = mapping.sheet(Vector2(bounds.center.x, bounds.min.y))
        editor.press(.dimension)
        editor.primaryEnded(at: editor.transform.screenPoint(bottom), modifiers: [])
        editor.primaryEnded(at: editor.transform.screenPoint(bottom - Vector2(0, distance)), modifiers: [])
        await settle()
        return editor.document.sheet(sheet.id)?.annotations.map(\.id).first { !before.contains($0) }
    }

    /// Every text the open sheet draws for `annotation`, as typed.
    func texts(of annotation: AnnotationID) -> [String] {
        drawing.editor.picture?.texts.filter { $0.annotation == annotation }.map(\.original) ?? []
    }

    /// The annotation's report on the open sheet.
    func report(of annotation: AnnotationID) -> AnnotationReport? {
        drawing.editor.picture?.annotationReports[annotation]
    }

    /// The drawings with `annotation` copied `count` times under new IDs, as one edit.
    func duplicateAnnotation(_ annotation: AnnotationID, times count: Int) throws {
        var drawings = drawing.editor.document
        guard let index = drawings.sheets.firstIndex(where: { $0.annotation(annotation) != nil }),
            let original = drawings.sheets[index].annotation(annotation)
        else { return }
        for _ in 0..<count {
            var copy = original
            copy.id = AnnotationID()
            drawings.sheets[index].setAnnotation(copy)
        }
        try document.perform(.setDrawings(drawings), name: "Duplicate")
        refreshDrawing()
    }
}

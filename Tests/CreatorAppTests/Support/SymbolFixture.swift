// Test fixture file: the symbol tools driven by clicks on a view's edges and dimensions.
import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import Foundation
@testable import CreatorApp

extension AppModel {
    /// A symbol tool's two clicks: on the middle of a side of `view` (`.bottom` or `.left`), then `distance` mm away from it (below or
    /// left). Returns the new annotation.
    @discardableResult
    func placeSymbol(_ tool: DrawingTool, on view: ViewID, side: SymbolSide = .bottom, distance: Double = 8) async -> AnnotationID? {
        let editor = drawing.editor
        guard let sheet = editor.currentSheet.flatMap({ editor.document.sheet($0) }), let drawn = sheet.view(view),
            let projection = editor.contents[view]?.projection, let bounds = projection.bounds,
            let center = ViewPlacement.centers(in: sheet)[view],
            let mapping = ViewMapping.of(projection: projection, center: center, scale: (drawn.scale ?? sheet.scale).value)
        else { return nil }
        let before = Set(sheet.annotations.map(\.id))
        let (point, away): (Vector2, Vector2) = switch side {
        case .bottom: (Vector2(bounds.center.x, bounds.min.y), Vector2(0, -distance))
        case .left: (Vector2(bounds.min.x, bounds.center.y), Vector2(-distance, 0))
        }
        let click = mapping.sheet(point)
        editor.press(tool)
        editor.primaryEnded(at: editor.transform.screenPoint(click), modifiers: [])
        editor.primaryEnded(at: editor.transform.screenPoint(click + away), modifiers: [])
        await settle()
        return editor.document.sheet(sheet.id)?.annotations.map(\.id).first { !before.contains($0) }
    }

    /// A symbol tool's two clicks on a dimension's label, then `offset` away from it.
    @discardableResult
    func placeSymbol(_ tool: DrawingTool, onDimension id: AnnotationID, offset: Vector2 = Vector2(0, -6)) async -> AnnotationID? {
        let editor = drawing.editor
        guard let sheet = editor.currentSheet.flatMap({ editor.document.sheet($0) }),
            let label = report(of: id)?.textCenter else { return nil }
        let before = Set(sheet.annotations.map(\.id))
        editor.press(tool)
        editor.primaryEnded(at: editor.transform.screenPoint(label), modifiers: [])
        editor.primaryEnded(at: editor.transform.screenPoint(label + offset), modifiers: [])
        await settle()
        return editor.document.sheet(sheet.id)?.annotations.map(\.id).first { !before.contains($0) }
    }
}

enum SymbolSide { case bottom, left }

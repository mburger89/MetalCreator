// Test fixture file: section, detail and auxiliary views made the way a person makes them, in an app over FakeKernel.
import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorApp

extension AppModel {
    /// The mapping of a view on the open sheet, from what it shows now.
    func mapping(of id: ViewID) -> ViewMapping? {
        let editor = drawing.editor
        guard let sheet = editor.currentSheet.flatMap({ editor.document.sheet($0) }), let view = sheet.view(id),
              let content = editor.contents[id] else { return nil }
        let center = ViewPlacement.centers(in: sheet)[id] ?? view.center
        return ViewMapping.of(content: content, center: center, scale: (view.scale ?? sheet.scale).value)
    }

    /// The Section tool: a straight line across the middle of `parent`'s drawing, finished, then a click at `drop`. Returns the new view.
    @discardableResult
    func addSection(on parent: ViewID, dropAt drop: Vector2 = Vector2(150, 60)) async -> ViewID? {
        let editor = drawing.editor
        guard let mapping = mapping(of: parent), let box = editor.contents[parent]?.projection?.bounds else { return nil }
        let before = Set(editor.document.sheets.flatMap(\.views).map(\.id))
        editor.press(.section)
        let y = box.center.y
        for x in [box.min.x + 1, box.max.x - 1] {
            editor.primaryEnded(at: editor.transform.screenPoint(mapping.sheet(Vector2(x, y))), modifiers: [])
        }
        _ = editor.keyPressed(.finish)
        editor.primaryEnded(at: editor.transform.screenPoint(drop), modifiers: [])
        await settle()
        return editor.document.sheets.flatMap(\.views).map(\.id).first { !before.contains($0) }
    }

    /// The Detail tool: a circle of `radius` model millimetres at the middle of `parent`'s drawing, then a click at `drop`.
    @discardableResult
    func addDetail(on parent: ViewID, radius: Double = 4, dropAt drop: Vector2 = Vector2(260, 150)) async -> ViewID? {
        let editor = drawing.editor
        guard let mapping = mapping(of: parent), let box = editor.contents[parent]?.projection?.bounds else { return nil }
        let before = Set(editor.document.sheets.flatMap(\.views).map(\.id))
        editor.press(.detail)
        let center = mapping.sheet(box.center)
        let edge = center + Vector2(radius * mapping.scale, 0)
        editor.primaryChanged(to: editor.transform.screenPoint(center), modifiers: [])
        editor.primaryChanged(to: editor.transform.screenPoint(edge), modifiers: [])
        editor.primaryEnded(at: editor.transform.screenPoint(edge), modifiers: [])
        editor.primaryEnded(at: editor.transform.screenPoint(drop), modifiers: [])
        await settle()
        return editor.document.sheets.flatMap(\.views).map(\.id).first { !before.contains($0) }
    }

    /// Replaces view `id` by `change` as one step, the way an editor commit would.
    func editView(_ id: ViewID, _ change: (inout DrawingView) -> Void) async throws {
        var document = drawing.editor.document
        for s in document.sheets.indices {
            guard var view = document.sheets[s].view(id) else { continue }
            change(&view)
            document.sheets[s].setView(view)
        }
        try self.document.perform(.setDrawings(document), name: "Change View")
        refreshDrawing()
        await settle()
    }
}

extension AppModel {
    /// The Dimension tool: a click on the edge of `view` through `point` (model plane), then a click `offset` sheet millimetres from
    /// it. Returns the new annotation.
    @discardableResult
    func dimensionEdge(of view: ViewID, at point: Vector2, offset: Vector2 = Vector2(0, -8)) async -> AnnotationID? {
        let editor = drawing.editor
        guard let sheet = editor.currentSheet.flatMap({ editor.document.sheet($0) }), let mapping = mapping(of: view) else {
            return nil
        }
        let before = Set(sheet.annotations.map(\.id))
        let spot = mapping.sheet(point)
        editor.press(.dimension)
        editor.primaryEnded(at: editor.transform.screenPoint(spot), modifiers: [])
        editor.primaryEnded(at: editor.transform.screenPoint(spot + offset), modifiers: [])
        await settle()
        return editor.document.sheet(sheet.id)?.annotations.map(\.id).first { !before.contains($0) }
    }

    /// The strokes the open sheet's picture draws for the mark of `view`.
    func markStrokes(of view: ViewID) -> [SheetStroke] {
        drawing.editor.picture?.strokes.filter { $0.mark == view } ?? []
    }

    /// The notices (sentences about a view) the open sheet's picture holds for `view`.
    func notices(of view: ViewID) -> [String] {
        drawing.editor.picture?.texts.filter { $0.isNotice && $0.view == view }.map(\.original) ?? []
    }
}

extension AppModel {
    /// A section of `parent` made from `cutter` exactly (the Section tool's own clicks can't start outside a view), placed at `center`.
    @discardableResult
    func insertSection(on parent: ViewID, cutter: SectionCutter, center: Vector2 = Vector2(150, 60)) async throws -> ViewID {
        var drawings = drawing.editor.document
        guard let index = drawings.sheets.firstIndex(where: { $0.view(parent) != nil }), let base = drawings.sheets[index].view(parent)
        else { throw AppProblem("No view", "The parent isn't on a sheet.") }
        let view = DrawingView(
            kind: .section, source: base.source, orientation: .custom(SectionFrame.frame(for: cutter)), center: center,
            showsLabel: true, derivation: .section(SectionLine(parent: parent, cutter: cutter)), letter: "A")
        drawings.sheets[index].setView(view)
        try document.perform(.setDrawings(drawings), name: "Add View")
        refreshDrawing()
        await settle()
        return view.id
    }

    /// A drag of the Select tool from model point `from` of `parent`'s plane by `delta` model millimetres.
    func dragMark(on parent: ViewID, from point: Vector2, by delta: Vector2) async {
        let editor = drawing.editor
        guard let mapping = mapping(of: parent) else { return }
        let start = mapping.sheet(point)
        editor.press(.select)
        editor.primaryChanged(to: editor.transform.screenPoint(start), modifiers: [])
        let end = start + delta * mapping.scale
        for step in 1...6 {
            let at = start + (end - start) * (Double(step) / 6)
            editor.primaryChanged(to: editor.transform.screenPoint(at), modifiers: [])
        }
        editor.primaryEnded(at: editor.transform.screenPoint(end), modifiers: [])
        await settle()
    }
}

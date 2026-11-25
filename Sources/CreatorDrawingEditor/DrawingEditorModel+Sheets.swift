import CreatorDrawing
import CreatorGeometry
import MetalUI

extension DrawingEditorModel {
    /// Adds a sheet after the last, named "Sheet N" with the smallest unused N, and shows it.
    public func addSheet() {
        let settings = document.settings
        let used = Set(document.sheets.map(\.name))
        var number = 1
        while used.contains("Sheet \(number)") { number += 1 }
        var block = settings.titleBlockDefaults
        block.date = today()
        let sheet = DrawingSheet(
            name: "Sheet \(number)", size: settings.standard == .asme ? .ansiB : .a3, orientation: .landscape,
            titleBlock: block)
        commit(DrawingStepName.addSheet) { document in
            document.sheets.append(sheet)
            if document.settings.generalTolerance.isEmpty {
                document.settings.generalTolerance = GeneralTolerance.standardDefault(
                    for: document.settings.standard, inches: self.standardUnitsAreInches)
            }
        }
        show(sheet: sheet.id)
    }

    public func renameSheet(_ id: SheetID, to name: String) {
        guard !name.isEmpty else { return }
        commitSheet(id, DrawingStepName.renameSheet) { $0.name = name }
    }

    public func duplicateSheet(_ id: SheetID) {
        guard let index = document.sheets.firstIndex(where: { $0.id == id }) else { return }
        let original = document.sheets[index]
        var views = original.views
        var renamed: [ViewID: ViewID] = [:]
        for view in views { renamed[view.id] = ViewID() }
        for position in views.indices {
            views[position].id = renamed[views[position].id] ?? views[position].id
            if let alignment = views[position].alignment {
                views[position].alignment = renamed[alignment.parent].map {
                    ViewAlignment(parent: $0, axis: alignment.axis)
                }
            }
        }
        let annotations = original.annotations.map { annotation -> DrawingAnnotation in
            var copied = annotation
            copied.id = AnnotationID()
            copied.view = annotation.view.flatMap { renamed[$0] }
            return copied
        }
        let copy = DrawingSheet(
            name: original.name + " Copy", size: original.size, orientation: original.orientation, scale: original.scale,
            titleBlock: original.titleBlock, views: views, annotations: annotations)
        commit(DrawingStepName.duplicateSheet) { $0.sheets.insert(copy, at: index + 1) }
        show(sheet: copy.id)
    }

    public func deleteSheet(_ id: SheetID) {
        guard let index = document.sheets.firstIndex(where: { $0.id == id }) else { return }
        commit(DrawingStepName.deleteSheet) { $0.sheets.remove(at: index) }
        guard currentSheet == id else { return }
        let sheets = document.sheets
        show(sheet: sheets.isEmpty ? nil : sheets[Swift.min(index, sheets.count - 1)].id)
    }

    public func moveSheet(_ id: SheetID, by offset: Int) {
        guard let index = document.sheets.firstIndex(where: { $0.id == id }) else { return }
        let target = Swift.min(Swift.max(index + offset, 0), document.sheets.count - 1)
        guard target != index else { return }
        commit(DrawingStepName.moveSheet) { document in
            let moved = document.sheets.remove(at: index)
            document.sheets.insert(moved, at: target)
        }
    }

    /// Shows a sheet; not a commit.
    public func selectSheet(_ id: SheetID) {
        guard document.sheet(id) != nil else { return }
        show(sheet: id)
    }
}

// MARK: Renaming in place

extension DrawingEditorModel {
    /// Opens the tab's field with the whole name selected, so typing replaces it.
    public func beginRenaming(_ id: SheetID) {
        guard let sheet = document.sheet(id) else { return }
        renaming = SheetRename(
            sheet: id, draft: sheet.name, selection: TextSelection(range: sheet.name.startIndex..<sheet.name.endIndex))
    }

    public func renameDraftChanged(_ text: String) {
        renaming?.draft = text
    }

    public func renameSelectionChanged(_ selection: TextSelection?) {
        renaming?.selection = selection
    }

    /// Return, or the field losing focus: one "Rename Sheet" step when the name changed and isn't empty.
    public func commitRename() {
        guard let rename = renaming else { return }
        renaming = nil
        guard let sheet = document.sheet(rename.sheet), rename.draft != sheet.name else { return }
        renameSheet(rename.sheet, to: rename.draft)
    }

    /// Esc: the name stays as it was.
    public func cancelRename() {
        renaming = nil
    }
}

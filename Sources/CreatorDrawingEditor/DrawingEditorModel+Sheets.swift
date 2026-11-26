import CreatorDrawing
import CreatorGeometry
import Foundation
import MetalUI

extension DrawingEditorModel {
    /// Adds a sheet after the last, named "Sheet N" with the smallest unused N, and shows it.
    public func addSheet() {
        let settings = document.settings
        var block = settings.titleBlockDefaults
        block.date = today()
        let sheet = DrawingSheet(
            name: nextSheetName(), size: settings.standard == .asme ? .ansiB : .a3, orientation: .landscape,
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

    /// "Sheet N" with the smallest unused N.
    func nextSheetName() -> String {
        let used = Set(document.sheets.map { Self.trimmed($0.name) })
        var number = 1
        while used.contains("Sheet \(number)") { number += 1 }
        return "Sheet \(number)"
    }

    /// The sentence for a blank sheet name.
    static let blankSheetNameSentence = "A sheet needs a name."
    /// The sentence for a name another sheet has.
    static let duplicateSheetNameSentence = "Another sheet already has that name."

    /// Renames to the trimmed text; a blank name or one another sheet has is refused in words and makes no step (R11).
    public func renameSheet(_ id: SheetID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            refuse(Self.blankSheetNameSentence)
            return
        }
        guard !document.sheets.contains(where: { $0.id != id && Self.trimmed($0.name) == trimmed }) else {
            refuse(Self.duplicateSheetNameSentence)
            return
        }
        commitSheet(id, DrawingStepName.renameSheet) { $0.name = trimmed }
    }

    private static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func duplicateSheet(_ id: SheetID) {
        guard let index = document.sheets.firstIndex(where: { $0.id == id }) else { return }
        let original = document.sheets[index]
        let blank = DrawingSheet(
            name: uniqueCopyName(of: original.name), size: original.size, orientation: original.orientation, scale: original.scale,
            titleBlock: original.titleBlock, notes: original.notes)
        let copied = SheetCopy.copy(
            views: original.views, annotations: original.annotations, onto: blank, offset: .zero, keepingLetters: true)
        let copy = copied.sheet
        commit(DrawingStepName.duplicateSheet) { $0.sheets.insert(copy, at: index + 1) }
        show(sheet: copy.id)
    }

    /// "\(name) copy", then "\(name) copy 2", "\(name) copy 3"…: the first free one, names compared trimmed and exactly (R11).
    private func uniqueCopyName(of name: String) -> String {
        let used = Set(document.sheets.map { Self.trimmed($0.name) })
        let base = Self.trimmed(name) + " copy"
        guard used.contains(base) else { return base }
        var number = 2
        while used.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
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

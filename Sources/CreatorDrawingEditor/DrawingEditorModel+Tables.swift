import CreatorDrawing
import CreatorGeometry

/// The Parts List and Revision Table tools and how a table stands (DR-5 R7, R9, R16).
extension DrawingEditorModel {
    static let partsListExistsSentence = "This sheet has a parts list already; drag it to move it."
    static let revisionTableExistsSentence = "This sheet has a revision table already; drag it to move it."
    /// How near a click must be to the title block's top right (or the frame's inside top right) for a table to stand there.
    static let standingDistance = 10.0

    /// The title block's top right corner, where a standing parts list has its bottom right.
    static func blockTopRight(of sheet: DrawingSheet, standard: DrawingStandard) -> Vector2 {
        let origin = TitleBlockLayout.origin(for: sheet, standard: standard)
        return Vector2(origin.x + TitleBlockLayout.width, origin.y + TitleBlockLayout.height)
    }

    // MARK: Placing

    /// A press-and-release of the Parts List or Revision Table tool: one click places the table, standing when it is near its corner.
    func tableClick(at point: Vector2) {
        guard let sheet else { return }
        let standard = document.settings.standard
        let added: Bool
        if tool == .partsList {
            guard !sheet.annotations.contains(where: { if case .partsList = $0.kind { true } else { false } }) else {
                refuse(Self.partsListExistsSentence)
                return
            }
            let stands = (point - Self.blockTopRight(of: sheet, standard: standard)).length <= Self.standingDistance
            added = addAnnotation(
                .partsList(PartsList(bottomRight: stands ? nil : point)), view: nil, name: DrawingStepName.addPartsList)
        } else {
            guard !sheet.annotations.contains(where: { if case .revisionTable = $0.kind { true } else { false } }) else {
                refuse(Self.revisionTableExistsSentence)
                return
            }
            let stands = (point - SheetFrame.rect(for: sheet, standard: standard).max).length <= Self.standingDistance
            added = addAnnotation(
                .revisionTable(RevisionTable(topRight: stands ? nil : point)), view: nil, name: DrawingStepName.addRevisionTable)
        }
        if added { tool = .select }
    }

    // MARK: Standing

    /// The inspector's "Stand on Title Block": the sheet's parts list goes back to the block's top right.
    public func standPartsListOnTitleBlock() {
        commitSheet(DrawingStepName.movePartsList) { sheet in
            for annotation in sheet.annotations {
                guard case .partsList(var list) = annotation.kind else { continue }
                list.bottomRight = nil
                var updated = annotation
                updated.kind = .partsList(list)
                sheet.setAnnotation(updated)
            }
        }
    }

    /// The inspector's "Move to Corner": the sheet's revision table goes back to the frame's inside top right.
    public func moveRevisionTableToCorner() {
        commitSheet(DrawingStepName.moveRevisionTable) { sheet in
            for annotation in sheet.annotations {
                guard case .revisionTable(var table) = annotation.kind else { continue }
                table.topRight = nil
                var updated = annotation
                updated.kind = .revisionTable(table)
                sheet.setAnnotation(updated)
            }
        }
    }
}

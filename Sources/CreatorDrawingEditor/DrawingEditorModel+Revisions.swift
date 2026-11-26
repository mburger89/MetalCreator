import CreatorDrawing

/// One typed column of a revision row.
public enum RevisionField: Hashable, Sendable {
    case description, date, approved
}

/// The revision table's rows (DR-5 R8, R9, R16).
extension DrawingEditorModel {
    static let noRevisionTableSentence = "Add a revision table first."
    static let revisionFromTableSentence = "The revision comes from the revision table."

    /// Appends the next letter with an empty description, date and approval; the date is the person's to type.
    public func addRevision() {
        guard let (id, table) = sheet?.revisionTable else {
            refuse(Self.noRevisionTableSentence)
            return
        }
        change(table: id, DrawingStepName.addRevision) { $0.rows.append(RevisionRow(letter: RevisionLetters.next(after: table.rows))) }
    }

    public func setRevision(_ field: RevisionField, text: String, row: Int) {
        guard let (id, table) = sheet?.revisionTable, table.rows.indices.contains(row) else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        change(table: id, DrawingStepName.changeRevision) {
            switch field {
            case .description: $0.rows[row].description = value
            case .date: $0.rows[row].date = value
            case .approved: $0.rows[row].approved = value
            }
        }
    }

    /// Only the last row can be removed.
    public func removeLastRevision() {
        guard let (id, table) = sheet?.revisionTable, !table.rows.isEmpty else { return }
        change(table: id, DrawingStepName.removeRevision) { $0.rows.removeLast() }
    }

    private func change(table id: AnnotationID, _ name: String, _ edit: (inout RevisionTable) -> Void) {
        commitSheet(name) { sheet in
            guard var annotation = sheet.annotation(id), case .revisionTable(var table) = annotation.kind else { return }
            edit(&table)
            annotation.kind = .revisionTable(table)
            sheet.setAnnotation(annotation)
        }
    }
}

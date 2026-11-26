import CreatorDrawing
import MetalUI

/// The revision table's page (DR-5 R8, R9): a row per revision with its letter and the three columns to type, New Revision (the
/// date stays the person's to type) and Remove Last Revision (only the last row can go). Delete removes the table.
struct RevisionTableInspector: Component {
    let model: DrawingEditorModel
    let table: RevisionTable
    let colors: DrawingColors

    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(8)) {
            Text("Revision table").font(.headline).foregroundStyle(colors.primary.color)
            ForEach(table.rows.indices, id: \.self) { index in
                let row = table.rows[index]
                VStack(alignment: .leading, spacing: Pixels(4)) {
                    Text(row.letter).font(.callout).foregroundStyle(colors.primary.color)
                    DrawingRow("Description", colors: colors) {
                        DrawingField(model: model, text: row.description, width: 150) {
                            model.setRevision(.description, text: $0, row: index)
                        }
                    }
                    DrawingRow("Date", colors: colors) {
                        DrawingField(model: model, text: row.date, width: 150) { model.setRevision(.date, text: $0, row: index) }
                    }
                    DrawingRow("Approved", colors: colors) {
                        DrawingField(model: model, text: row.approved, width: 150) {
                            model.setRevision(.approved, text: $0, row: index)
                        }
                    }
                }
            }
            Button("New Revision") { model.addRevision() }
            Button("Remove Last Revision") { model.removeLastRevision() }
                .disabled(table.rows.isEmpty)
            if let refusal = model.refusal {
                Text(refusal).font(.caption).foregroundStyle(colors.warning.color)
            }
            Button("Delete") { model.deleteSelection() }
        }
        .frame(width: drawingInspectorWidth.px)
    }
}

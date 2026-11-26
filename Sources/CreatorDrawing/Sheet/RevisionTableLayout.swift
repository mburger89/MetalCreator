import CreatorGeometry

/// The revision table (DR-5 R9): the header at the top, the rows below it, oldest first.
public enum RevisionTableLayout {
    public static func columns(for standard: DrawingStandard) -> [TableColumn] {
        func column(_ id: String, _ iso: String, _ asme: String, _ width: Double, _ alignment: TableColumn.Alignment) -> TableColumn {
            TableColumn(id: id, title: standard == .iso ? iso : asme, width: width, alignment: alignment)
        }
        return [
            column("letter", "Rev.", "REV", 15, .centred), column("description", "Description", "DESCRIPTION", 100, .left),
            column("date", "Date", "DATE", 30, .left), column("approved", "Approved", "APPROVED", 35, .left),
        ]
    }

    /// The table hanging from `topRight`.
    public static func draw(
        _ table: RevisionTable, topRight: Vector2, standard: DrawingStandard, h: Double
    ) -> AnnotationDrawing {
        let columns = columns(for: standard)
        var rows: [[String]] = [columns.map(\.title)]
        for row in table.rows { rows.append([row.letter, row.description, row.date, row.approved]) }
        let width = columns.reduce(0) { $0 + $1.width }
        let rowHeight = PartsListLayout.rowHeight
        let bottomLeft = Vector2(topRight.x - width, topRight.y - rowHeight * Double(rows.count))
        return SheetTable.draw(
            columns: columns, rows: rows, headerRow: 0, rowHeight: rowHeight, bottomLeft: bottomLeft, h: h)
    }
}

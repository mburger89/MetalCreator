import CreatorGeometry

/// One column of a sheet table (the parts list, the revision table: DR-5 R7 and R9).
public struct TableColumn: Hashable, Sendable {
    public enum Alignment: Hashable, Sendable { case centred, left }

    /// Names what the column holds, so a layout finds its cell whatever the standard calls it.
    public var id: String
    public var title: String
    public var width: Double
    public var alignment: Alignment

    public init(id: String, title: String, width: Double, alignment: Alignment) {
        self.id = id
        self.title = title
        self.width = width
        self.alignment = alignment
    }
}

/// The shared row and cell drawing of the tables: an outline, the lines between rows and columns, and fitted cells.
public enum SheetTable {
    public static let insetX = 1.5

    /// Draws `rows` (top to bottom, each one cell per column) with `headerRow` among them. `bottomLeft` is the table's
    /// bottom-left corner. `boxes[0]` is the outline, `segments` the inner lines, and the first `labelCount` texts the header's.
    public static func draw(
        columns: [TableColumn], rows: [[String]], headerRow: Int, rowHeight: Double, bottomLeft: Vector2, h: Double
    ) -> AnnotationDrawing {
        let width = columns.reduce(0) { $0 + $1.width }
        let height = rowHeight * Double(rows.count)
        var drawing = AnnotationDrawing()
        let minX = bottomLeft.x, minY = bottomLeft.y
        drawing.boxes = [
            [
                bottomLeft, Vector2(minX + width, minY), Vector2(minX + width, minY + height), Vector2(minX, minY + height),
                bottomLeft,
            ],
        ]
        if rows.count > 1 {
            for line in 1..<rows.count {
                let y = minY + height - rowHeight * Double(line)
                drawing.segments.append(.line(Vector2(minX, y), Vector2(minX + width, y)))
            }
        }
        var x = minX
        for column in columns.dropLast() {
            x += column.width
            drawing.segments.append(.line(Vector2(x, minY), Vector2(x, minY + height)))
        }
        var header: [PlacedText] = []
        var cells: [PlacedText] = []
        for (index, row) in rows.enumerated() {
            let top = minY + height - rowHeight * Double(index)
            var left = minX
            for (column, text) in zip(columns, row) {
                defer { left += column.width }
                guard !text.isEmpty else { continue }
                let fit = DrawingText.fitted(text, height: h, width: column.width - 2 * insetX)
                let startX = column.alignment == .centred ? left + (column.width - fit.run.width) / 2 : left + insetX
                let placed = PlacedText(
                    run: fit.run, original: text, origin: Vector2(startX, top - rowHeight / 2 - fit.height / 2),
                    height: fit.height, angle: 0)
                if index == headerRow { header.append(placed) } else { cells.append(placed) }
            }
        }
        drawing.texts = header + cells
        drawing.labelCount = header.count
        drawing.fitFrame()
        return drawing
    }
}

import CreatorGeometry
import CreatorKernel

/// The parts list (DR-5 R7; ISO 7573, ASME Y14.34): the header at the bottom and item 1 just above it, rising.
public enum PartsListLayout {
    public static let rowHeight = 7.0

    /// The list's height with `rows` item rows and the header.
    public static func height(rows: Int) -> Double { Double(rows + 1) * rowHeight }

    public static func columns(for standard: DrawingStandard, showsPartNumber: Bool) -> [TableColumn] {
        let fixed = 15.0 + 15.0 + 40.0 + (showsPartNumber ? 40.0 : 0)
        let name = TitleBlockLayout.width - fixed
        func column(_ id: String, _ iso: String, _ asme: String, _ width: Double, _ alignment: TableColumn.Alignment) -> TableColumn {
            TableColumn(id: id, title: standard == .iso ? iso : asme, width: width, alignment: alignment)
        }
        let item = column("item", "Item", "ITEM", 15, .centred)
        let quantity = column("quantity", "Qty", "QTY", 15, .centred)
        let nameColumn = column("name", "Name", "DESCRIPTION", name, .left)
        let number = column("partNumber", "Part number", "PART NO.", 40, .left)
        let material = column("material", "Material", "MATERIAL", 40, .left)
        switch standard {
        case .iso: return [item, quantity, nameColumn] + (showsPartNumber ? [number] : []) + [material]
        case .asme: return [quantity] + (showsPartNumber ? [number] : []) + [nameColumn, material, item]
        }
    }

    /// The list standing on `bottomRight`, one row per item and a header at the bottom.
    public static func draw(
        _ items: [NumberedItem], facts: [NodeID: PartFacts], bottomRight: Vector2, standard: DrawingStandard, h: Double
    ) -> AnnotationDrawing {
        let columns = columns(for: standard, showsPartNumber: items.contains { !$0.partNumber.isEmpty })
        var rows: [[String]] = []
        // Top to bottom: the last item first, item 1 above the header.
        for item in items.reversed() {
            rows.append(columns.map { cell($0.id, of: item, facts: facts[item.part]) })
        }
        rows.append(columns.map(\.title))
        let bottomLeft = Vector2(bottomRight.x - TitleBlockLayout.width, bottomRight.y)
        return SheetTable.draw(
            columns: columns, rows: rows, headerRow: rows.count - 1, rowHeight: rowHeight, bottomLeft: bottomLeft, h: h)
    }

    private static func cell(_ id: String, of item: NumberedItem, facts: PartFacts?) -> String {
        switch id {
        case "item": return String(item.number)
        case "quantity": return facts?.quantity.map { String($0) } ?? "?"
        case "name":
            guard let facts else { return "?" }
            if facts.isRemoved && facts.name != "?" { return facts.name + "?" }
            return facts.name
        case "partNumber": return item.partNumber
        default: return item.material
        }
    }
}

import CreatorDrawing
import CreatorKernel
import MetalUI

/// The parts list's page (DR-5 R5, R7): every numbered item of the drawing with its material and part number to type, its quantity
/// (read only, "?" while the part has no result), and Move Up and Move Down. Delete removes the list.
struct PartsListInspector: Component {
    let model: DrawingEditorModel
    let colors: DrawingColors

    var content: some ElementGroup {
        let items = PartItems.numbered(model.document, names: model.partNames)
        VStack(alignment: .leading, spacing: Pixels(8)) {
            Text("Parts list").font(.headline).foregroundStyle(colors.primary.color)
            if items.isEmpty {
                Text("The drawing shows no parts yet.").font(.caption).foregroundStyle(colors.secondary.color)
            }
            ForEach(items, id: \.part.rawValue) { item in
                PartItemRows(model: model, item: item, count: items.count, colors: colors)
            }
            Button("Delete") { model.deleteSelection() }
        }
        .frame(width: drawingInspectorWidth.px)
    }
}

/// One item of the list.
struct PartItemRows: Component {
    let model: DrawingEditorModel
    let item: NumberedItem
    let count: Int
    let colors: DrawingColors

    var content: some ElementGroup {
        let facts = model.partFacts[item.part]
        let name = model.partNames[item.part] ?? "?"
        VStack(alignment: .leading, spacing: Pixels(4)) {
            Text(BalloonInspector.itemText(number: item.number, name: name)).font(.callout).foregroundStyle(colors.primary.color)
            DrawingRow("Quantity", colors: colors) {
                Text(facts?.quantity.map(String.init) ?? "?").font(.callout).foregroundStyle(colors.primary.color)
            }
            DrawingRow("Material", colors: colors) {
                DrawingField(model: model, text: item.material, width: 150) { model.setItemMaterial($0, of: item.part) }
            }
            DrawingRow("Part number", colors: colors) {
                DrawingField(model: model, text: item.partNumber, width: 150) { model.setItemPartNumber($0, of: item.part) }
            }
            HStack(spacing: Pixels(8)) {
                Button("Move Up") { model.moveItem(item.part, by: -1) }
                    .disabled(item.number == 1)
                Button("Move Down") { model.moveItem(item.part, by: 1) }
                    .disabled(item.number == count)
            }
        }
    }
}

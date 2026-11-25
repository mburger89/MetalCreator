import CreatorDrawing
import MetalUI

/// The inspector with no view selected: the open sheet and the drawing's settings (plan R22).
struct SheetInspector: Component {
    let model: DrawingEditorModel
    let sheet: DrawingSheet
    let colors: DrawingColors

    private static let sizes: [DrawingStandard: [SheetSize]] = [
        .iso: [.a4, .a3, .a2, .a1, .a0], .asme: [.ansiA, .ansiB, .ansiC, .ansiD, .ansiE],
    ]

    /// Every size of the drawing's standard, and the sheet's own when it is another's.
    var sizes: [SheetSize] {
        let standard = model.document.settings.standard
        let own = Self.sizes[standard] ?? SheetSize.allCases
        return own.contains(sheet.size) ? own : own + [sheet.size]
    }

    private func typed(_ key: TitleBlockKey) -> String {
        switch key {
        case .owner: sheet.titleBlock.owner
        case .drawnBy: sheet.titleBlock.drawnBy
        case .date: sheet.titleBlock.date
        case .title: sheet.titleBlock.title
        case .material: sheet.titleBlock.material
        case .drawingNumber: sheet.titleBlock.drawingNumber
        case .revision: sheet.titleBlock.revision
        case .tolerance: model.document.settings.generalTolerance
        case .mass, .scale, .projection, .size, .sheet: ""
        }
    }

    /// The typed title-block fields in the block's reading order, with the inspector's labels.
    static let fields: [(TitleBlockKey, String)] = [
        (.title, "Title"), (.drawingNumber, "Drawing number"), (.revision, "Revision"), (.owner, "Owner"),
        (.drawnBy, "Drawn by"), (.date, "Date"), (.material, "Material"), (.tolerance, "Tolerances"),
    ]

    var content: some ElementGroup {
        let settings = model.document.settings
        VStack(alignment: .leading, spacing: Pixels(8)) {
            Text("Sheet").font(.headline).foregroundStyle(colors.primary.color)
            DrawingRow("Name", colors: colors) {
                DrawingField(model: model, text: sheet.name, width: 150) { model.renameSheet(sheet.id, to: $0) }
            }
            DrawingRow("Size", colors: colors) {
                DrawingMenu(options: sizes.map(\.title), selected: sizes.firstIndex(of: sheet.size)) {
                    model.setSheetSize(sizes[$0])
                }
            }
            DrawingRow("Orientation", colors: colors) {
                DrawingSegments(options: ["Landscape", "Portrait"], selected: sheet.orientation == .landscape ? 0 : 1) {
                    model.setSheetOrientation($0 == 0 ? .landscape : .portrait)
                }
            }
            DrawingRow("Scale", colors: colors) {
                ScaleControl(model: model, current: sheet.scale, allowsSheetScale: false, standard: settings.standard) { scale in
                    if let scale { model.setSheetScale(scale) }
                }
            }
            DrawingRow("Standard", colors: colors) {
                DrawingSegments(options: ["ISO", "ASME"], selected: settings.standard == .iso ? 0 : 1) {
                    model.setStandard($0 == 0 ? .iso : .asme)
                }
            }
            Text("TITLE BLOCK").font(.caption2).foregroundStyle(colors.secondary.color)
            ForEach(Self.fields, id: \.0) { field in
                DrawingRow(field.1, colors: colors) {
                    DrawingField(model: model, text: typed(field.0), width: 150) { model.setTitleField(field.0, to: $0) }
                }
            }
            DrawingRow("Density g/cm³", colors: colors) {
                DrawingField(model: model, text: sheet.titleBlock.density.map { String($0) } ?? "", width: 150) { text in
                    model.setDensity(text: text)
                }
            }
            if let refusal = model.refusal {
                Text(refusal).font(.caption).foregroundStyle(colors.warning.color)
            }
        }
        .frame(width: drawingInspectorWidth.px)
    }
}

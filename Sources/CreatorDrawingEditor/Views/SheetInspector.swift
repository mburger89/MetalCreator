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
        case .mass, .scale, .projection, .size, .sheet, .tolerance: ""
        }
    }

    /// The typed title-block fields in the block's reading order, with the inspector's labels.
    static let fields: [(TitleBlockKey, String)] = [
        (.title, "Title"), (.drawingNumber, "Drawing number"), (.revision, "Revision"), (.owner, "Owner"),
        (.drawnBy, "Drawn by"), (.date, "Date"), (.material, "Material"),
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
            generalToleranceRows(settings)
            if settings.standard == .iso {
                DrawingRow("Decimal sign", colors: colors) {
                    DrawingSegments(options: ["Point", "Comma"], selected: settings.decimalSign == .point ? 0 : 1) {
                        model.setDecimalSign($0 == 0 ? .point : .comma)
                    }
                }
            }
            Text("TITLE BLOCK").font(.caption2).foregroundStyle(colors.secondary.color)
            ForEach(Self.fields, id: \.0) { field in
                DrawingRow(field.1, colors: colors) {
                    if field.0 == .revision, !sheet.revisionIsTyped {
                        Text("From the revision table").font(.callout).foregroundStyle(colors.secondary.color)
                    } else {
                        DrawingField(model: model, text: typed(field.0), width: 150) { model.setTitleField(field.0, to: $0) }
                    }
                }
            }
            DrawingRow("Logo", colors: colors) {
                HStack(spacing: Pixels(8)) {
                    Button("Choose Logo…") { model.request(.chooseLogo(sheet.id)) }
                    if sheet.titleBlock.logo != nil {
                        Button("Remove Logo") { model.setLogo(nil, of: sheet.id) }
                    }
                }
            }
            DrawingRow("Density g/cm³", colors: colors) {
                DrawingField(model: model, text: sheet.titleBlock.density.map { String($0) } ?? "", width: 150) { text in
                    model.setDensity(text: text)
                }
            }
            SheetNotesSection(model: model, sheet: sheet, colors: colors)
            TemplatesSection(model: model, sheet: sheet, colors: colors)
            lostReferences
            if let refusal = model.refusal {
                Text(refusal).font(.caption).foregroundStyle(colors.warning.color)
            }
        }
        .frame(width: drawingInspectorWidth.px)
    }
}

extension SheetInspector {
    static let geometricOptions = ["None"] + ISO2768GeometricClass.allCases.map(\.rawValue)

    /// The drawing's general tolerance (plan R10, R20): ISO's size class and geometric class in menus, ASME's table as a field per
    /// row of decimals, a legacy text as typed.
    @ElementBuilder
    func generalToleranceRows(_ settings: DrawingSettings) -> some ElementGroup {
        switch settings.generalTolerance {
        case .iso2768(let size, let geometric):
            let sizes = ISO2768Class.allCases
            DrawingRow("General tolerance", colors: colors) {
                DrawingMenu(options: sizes.map(\.rawValue), selected: sizes.firstIndex(of: size)) {
                    model.setGeneralTolerance(.iso2768(sizes[$0], geometric))
                }
            }
            DrawingRow("Geometric", colors: colors) {
                let classes = ISO2768GeometricClass.allCases
                DrawingMenu(
                    options: Self.geometricOptions, selected: geometric.flatMap { classes.firstIndex(of: $0) }.map { $0 + 1 } ?? 0) {
                    model.setGeneralTolerance(.iso2768(size, $0 == 0 ? nil : classes[$0 - 1]))
                }
            }
        case .asme(let table):
            Text("GENERAL TOLERANCE (\(table.unit.symbol))").font(.caption2).foregroundStyle(colors.secondary.color)
            ForEach(table.rows, id: \.places) { row in
                DrawingRow(row.places == 1 ? "1 decimal" : "\(row.places) decimals", colors: colors) {
                    DrawingField(model: model, text: row.text, width: 90) { model.setASMEToleranceRow(places: row.places, text: $0) }
                }
            }
        case .text(let text):
            DrawingRow("General tolerance", colors: colors) {
                DrawingField(model: model, text: text, width: 150) { model.setGeneralTolerance(.text($0)) }
            }
        }
    }

    /// The annotations that lost what they were attached to, with why (plan R15, R20).
    @ElementBuilder
    var lostReferences: some ElementGroup {
        let lost = model.lostAnnotations
        if !lost.isEmpty {
            Text("LOST REFERENCES").font(.caption2).foregroundStyle(colors.warning.color)
            ForEach(lost.indices, id: \.self) { index in
                Text("\(lost[index].label): \(lost[index].reason)").font(.caption).foregroundStyle(colors.warning.color)
            }
        }
    }
}

extension DrawingSheet {
    /// Whether the title block's Revision field is the person's to type: it is, unless the sheet's revision table has rows (DR-5 R9).
    var revisionIsTyped: Bool { revisionTable?.table.rows.isEmpty ?? true }
}

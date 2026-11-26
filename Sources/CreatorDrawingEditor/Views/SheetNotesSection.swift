import CreatorDrawing
import MetalUI

/// The sheet page's NOTES (one note per line), Edge break (two fields) and General surface (DR-4 R15), then CHECKS: what each
/// symbol's rules say, listed as "label: sentence".
struct SheetNotesSection: Component {
    let model: DrawingEditorModel
    let sheet: DrawingSheet
    let colors: DrawingColors

    static let requirementOptions = ["None", "Any", "Removal required", "Removal prohibited"]
    static let parameterOptions = SurfaceInspector.parameterOptions

    private var format: NumberFormat { NumberFormat(units: model.units, settings: model.document.settings) }

    private static func index(of requirement: SurfaceRequirement?) -> Int {
        guard let requirement else { return 0 }
        return 1 + (SurfaceInspector.processes.firstIndex(of: requirement.process) ?? 0)
    }

    var content: some ElementGroup {
        let notes = sheet.notes
        VStack(alignment: .leading, spacing: Pixels(8)) {
            Text("NOTES").font(.caption2).foregroundStyle(colors.secondary.color)
            NoteTextEntry(model: model, text: notes.lines.joined(separator: "\n")) { model.setGeneralNotes($0) }
            DrawingRow("Edge break", colors: colors) {
                HStack(spacing: Pixels(6)) {
                    DrawingField(model: model, text: edge(notes.edgeBreak?.minimum), width: 60) {
                        model.setEdgeBreak(minimumText: $0, maximumText: edge(notes.edgeBreak?.maximum))
                    }
                    DrawingField(model: model, text: edge(notes.edgeBreak?.maximum), width: 60) {
                        model.setEdgeBreak(minimumText: edge(notes.edgeBreak?.minimum), maximumText: $0)
                    }
                }
            }
            surface(notes.surface)
            checks
        }
    }

    private func edge(_ value: Double?) -> String { value.map { GDTNumber.tolerance($0, format: format) } ?? "" }

    @ElementBuilder
    private func surface(_ requirement: SurfaceRequirement?) -> some ElementGroup {
        let unit = model.standardUnitsAreInches ? "µin" : "µm"
        let valueText = requirement?.value.map { GDTNumber.roughness($0, format: format) } ?? ""
        DrawingRow("General surface", colors: colors) {
            DrawingMenu(options: Self.requirementOptions, selected: Self.index(of: requirement)) {
                if $0 == 0 {
                    model.setGeneralSurface(nil)
                } else {
                    var next = requirement ?? SurfaceRequirement()
                    next.process = SurfaceInspector.processes[$0 - 1]
                    model.setGeneralSurface(next)
                }
            }
        }
        if let requirement {
            DrawingRow("Parameter", colors: colors) {
                DrawingMenu(options: Self.parameterOptions, selected: SurfaceInspector.parameterIndex(requirement.parameter)) {
                    var next = requirement
                    next.parameter = $0 == 0 ? nil : ($0 == 1 ? .ra : .rz)
                    if next.parameter == nil { next.value = nil } else if next.value == nil { next.value = 3.2 }
                    model.setGeneralSurface(next)
                }
            }
            if requirement.parameter != nil {
                DrawingRow("Value (\(unit))", colors: colors) {
                    DrawingField(model: model, text: valueText, width: 90) { model.setGeneralSurfaceValue(text: $0) }
                }
            }
        }
    }

    @ElementBuilder
    private var checks: some ElementGroup {
        let found = model.checks
        if !found.isEmpty {
            Text("CHECKS").font(.caption2).foregroundStyle(colors.warning.color)
            ForEach(found.indices, id: \.self) { index in
                Text("\(found[index].label): \(found[index].warning)").font(.caption).foregroundStyle(colors.warning.color)
            }
        }
    }
}

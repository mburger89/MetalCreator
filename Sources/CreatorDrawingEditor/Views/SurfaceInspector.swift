import CreatorDrawing
import MetalUI

/// The inspector for one surface texture symbol (DR-4 R15): the process, the roughness parameter and value (µm, or µin in an inch
/// document), the lay and where it stands, then the shared tail.
struct SurfaceInspector: Component {
    let model: DrawingEditorModel
    let id: AnnotationID
    let texture: SurfaceTexture
    let report: AnnotationReport?
    let colors: DrawingColors

    static let processOptions = ["Any", "Removal required", "Removal prohibited"]
    static let parameterOptions = ["None", "Ra", "Rz"]
    static let layOptions = ["None", "Parallel", "Perpendicular", "Crossed", "Multidirectional", "Circular", "Radial", "Particulate"]
    static let standsOptions = ["Stands on the line", "On a leader"]
    static let processes: [SurfaceProcess] = [.any, .removalRequired, .removalProhibited]

    private var format: NumberFormat { NumberFormat(units: model.units, settings: model.document.settings) }

    static func parameterIndex(_ parameter: RoughnessParameter?) -> Int {
        switch parameter {
        case nil: 0
        case .ra?: 1
        case .rz?: 2
        }
    }

    var content: some ElementGroup {
        let requirement = texture.requirement
        let lays = SurfaceLay.allCases
        VStack(alignment: .leading, spacing: Pixels(8)) {
            Text("Surface symbol").font(.headline).foregroundStyle(colors.primary.color)
            DrawingRow("Process", colors: colors) {
                DrawingMenu(options: Self.processOptions, selected: Self.processes.firstIndex(of: requirement.process)) {
                    model.setSurfaceProcess(Self.processes[$0], of: id)
                }
            }
            DrawingRow("Parameter", colors: colors) {
                DrawingMenu(options: Self.parameterOptions, selected: Self.parameterIndex(requirement.parameter)) {
                    model.setRoughness(
                        parameter: $0 == 0 ? nil : ($0 == 1 ? .ra : .rz), valueText: valueText(requirement), of: id)
                }
            }
            if let parameter = requirement.parameter {
                DrawingRow("Value (\(model.standardUnitsAreInches ? "µin" : "µm"))", colors: colors) {
                    DrawingField(model: model, text: valueText(requirement), width: 90) {
                        model.setRoughness(parameter: parameter, valueText: $0, of: id)
                    }
                }
            }
            DrawingRow("Lay", colors: colors) {
                DrawingMenu(options: Self.layOptions, selected: texture.lay.flatMap { lays.firstIndex(of: $0) }.map { $0 + 1 } ?? 0) {
                    model.setLay($0 == 0 ? nil : lays[$0 - 1], of: id)
                }
            }
            DrawingRow("Stands", colors: colors) {
                DrawingMenu(options: Self.standsOptions, selected: texture.offset == nil ? 0 : 1) {
                    model.setSurfaceStands($0 == 0, of: id)
                }
            }
            SymbolPageTail(model: model, attachment: .feature(texture.feature), report: report, colors: colors)
        }
        .frame(width: drawingInspectorWidth.px)
    }

    private func valueText(_ requirement: SurfaceRequirement) -> String {
        requirement.value.map { GDTNumber.roughness($0, format: format) } ?? ""
    }
}

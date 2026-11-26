import CreatorDrawing
import Foundation
import MetalUI

/// The inspector with one view selected (plan R22): its source, orientation (base views), scale and display flags.
struct ViewInspector: Component {
    let model: DrawingEditorModel
    let sheet: DrawingSheet
    let view: DrawingView
    let colors: DrawingColors

    static func orientationTitle(_ orientation: StandardOrientation) -> String {
        switch orientation {
        case .isometricFrontRight: "Isometric, front right"
        case .isometricFrontLeft: "Isometric, front left"
        default: orientation.title
        }
    }

    /// The page's heading: "Base view", "Projected view", "Section A-A", "Detail B" or "View C" (DR-3 R13).
    static func title(of view: DrawingView) -> String {
        let letter = view.letter ?? ""
        switch view.kind {
        case .base: return "Base view"
        case .projected: return "Projected view"
        case .section: return letter.isEmpty ? "Section" : "Section \(letter)-\(letter)"
        case .detail: return letter.isEmpty ? "Detail" : "Detail \(letter)"
        case .auxiliary: return letter.isEmpty ? "View" : "View \(letter)"
        }
    }

    /// "Straight" for one cut, "Stepped (N cuts)" for more (read only).
    static func cutText(of view: DrawingView) -> String? {
        guard case .section(let line)? = view.derivation else { return nil }
        let cuts = line.cutter.cutIndices.count
        return cuts <= 1 ? "Straight" : "Stepped (\(cuts) cuts)"
    }

    private var isDerived: Bool { view.derivation != nil }

    @ElementBuilder
    private var derivedRows: some ElementGroup {
        if let cut = Self.cutText(of: view) {
            DrawingRow("Cut", colors: colors) { Text(cut).font(.callout).foregroundStyle(colors.primary.color) }
        }
        if case .detail(let circle)? = view.derivation {
            let value = model.units.value(fromMillimetres: circle.radius)
            let text = String(format: "%.\(model.units.fractionDigits)f", value)
            DrawingRow("Radius", colors: colors) {
                DrawingField(model: model, text: text, width: 80) { typed in
                    if let radius = Double(typed.trimmingCharacters(in: .whitespaces)) {
                        model.setDetailRadius(radius, of: view.id)
                    } else {
                        model.setDetailRadius(0, of: view.id)
                    }
                }
            }
        }
    }

    var content: some ElementGroup {
        let standard = model.document.settings.standard
        let orientations = StandardOrientation.allCases
        VStack(alignment: .leading, spacing: Pixels(8)) {
            Text(Self.title(of: view)).font(.headline).foregroundStyle(colors.primary.color)
            if !isDerived {
                DrawingRow("Source", colors: colors) {
                    DrawingMenu(options: model.sources.map(\.name), selected: model.sources.firstIndex { $0.id == view.source }) {
                        model.setSource(model.sources[$0].id, of: view.id)
                    }
                }
            }
            derivedRows
            if view.kind == .base {
                DrawingRow("Orientation", colors: colors) {
                    let selected: Int? = {
                        if case let .standard(current) = view.orientation { return orientations.firstIndex(of: current) }
                        return nil
                    }()
                    DrawingMenu(options: orientations.map(Self.orientationTitle), selected: selected) {
                        model.setOrientation(orientations[$0], of: view.id)
                    }
                }
            }
            DrawingRow("Scale", colors: colors) {
                ScaleControl(model: model, current: view.scale, allowsSheetScale: true, standard: standard, sheetScale: sheet.scale) {
                    model.setScale($0, of: view.id)
                }
            }
            Toggle("Hidden lines", isOn: Binding(get: { view.showsHidden }, set: { model.setShowsHidden($0, of: view.id) }))
            Toggle("Tangent edges", isOn: Binding(get: { view.showsTangent }, set: { model.setShowsTangent($0, of: view.id) }))
            Toggle("Label", isOn: Binding(get: { view.showsLabel }, set: { model.setShowsLabel($0, of: view.id) }))
            Toggle(
                "Centre marks",
                isOn: Binding(get: { view.showsCentreMarks }, set: { model.setShowsCentreMarks($0, of: view.id) }))
            if let refusal = model.refusal {
                Text(refusal).font(.caption).foregroundStyle(colors.warning.color)
            }
        }
        .frame(width: drawingInspectorWidth.px)
    }
}

import CreatorDrawing
import MetalUI

/// A dimension's tolerance (plan R10, R20): the kind in a menu, then the fields that kind has. Values are typed in the document's
/// unit (degrees for an angle) and committed through the model's setters, which refuse a bad number in words. A fit shows its
/// Hole or Shaft, letter and grade and "Show deviations".
struct ToleranceControls: Component {
    let model: DrawingEditorModel
    let id: AnnotationID
    let dimension: DrawingDimension
    let colors: DrawingColors

    static let kinds = ["General", "Symmetric", "Deviation", "Limits", "Reference", "Basic", "Fit"]

    static func index(of tolerance: DimensionTolerance) -> Int {
        switch tolerance {
        case .general: 0
        case .symmetric: 1
        case .deviation: 2
        case .limits: 3
        case .reference: 4
        case .basic: 5
        case .fit: 6
        }
    }

    private var isAngle: Bool {
        if case .angle = dimension.kind { true } else { false }
    }

    /// The tolerance a kind starts from: 0.1 in the document's unit, or 0.1 degrees.
    func starting(_ index: Int) -> DimensionTolerance {
        let amount = isAngle ? 0.1 * .pi / 180 : model.units.millimetres(fromValue: 0.1)
        switch index {
        case 1: return .symmetric(amount)
        case 2: return .deviation(upper: amount, lower: -amount)
        case 3: return .limits(upper: amount, lower: -amount)
        case 4: return .reference
        case 5: return .basic
        case 6:
            if case .diameter = dimension.kind { return .fit(.hole(.H, grade: 7), showsDeviations: true) }
            return .fit(.shaft(.h, grade: 6), showsDeviations: true)
        default: return .general
        }
    }

    /// A tolerance value as the document shows it: millimetres in the unit, radians as degrees; four decimals at most, no
    /// trailing zeros, never through a locale.
    func text(_ value: Double) -> String {
        let shown = isAngle ? value * 180 / .pi : model.units.value(fromMillimetres: value)
        let scaled = Int((abs(shown) * 10_000).rounded())
        var whole = String(scaled / 10_000)
        var fraction = String(scaled % 10_000)
        fraction = String(repeating: "0", count: 4 - fraction.count) + fraction
        while fraction.last == "0" { fraction.removeLast() }
        if !fraction.isEmpty { whole += "." + fraction }
        return (shown < 0 && scaled != 0 ? "-" : "") + whole
    }

    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(6)) {
            DrawingRow("Tolerance", colors: colors) {
                DrawingMenu(options: Self.kinds, selected: Self.index(of: dimension.tolerance)) { index in
                    if index != Self.index(of: dimension.tolerance) { model.setTolerance(starting(index), of: id) }
                }
            }
            if case .symmetric(let value) = dimension.tolerance {
                DrawingRow("±", colors: colors) {
                    DrawingField(model: model, text: text(value), width: 90) { model.setTolerance(symmetricText: $0, of: id) }
                }
            }
            if case .deviation(let upper, let lower) = dimension.tolerance {
                limitRows(upper, lower, limits: false)
            }
            if case .limits(let upper, let lower) = dimension.tolerance {
                limitRows(upper, lower, limits: true)
            }
            if case .fit(let designation, let shows) = dimension.tolerance {
                fitRows(designation, shows)
            }
        }
    }

    @ElementBuilder
    private func limitRows(_ upper: Double, _ lower: Double, limits: Bool) -> some ElementGroup {
        DrawingRow("Upper", colors: colors) {
            DrawingField(model: model, text: text(upper), width: 90) {
                model.setToleranceUpper(text: $0, limits: limits, of: id)
            }
        }
        DrawingRow("Lower", colors: colors) {
            DrawingField(model: model, text: text(lower), width: 90) {
                model.setToleranceLower(text: $0, limits: limits, of: id)
            }
        }
    }

    @ElementBuilder
    private func fitRows(_ designation: FitDesignation, _ shows: Bool) -> some ElementGroup {
        let isHole: Bool = {
            if case .hole = designation { return true }
            return false
        }()
        DrawingRow("Fit", colors: colors) {
            DrawingSegments(options: ["Hole", "Shaft"], selected: isHole ? 0 : 1) { choice in
                guard (choice == 0) != isHole else { return }
                let grade = designation.grade
                model.setTolerance(
                    .fit(choice == 0 ? .hole(.H, grade: grade) : .shaft(.h, grade: grade), showsDeviations: shows), of: id)
            }
        }
        DrawingRow("Letter", colors: colors) {
            switch designation {
            case .hole(let letter, let grade):
                let letters = HoleFitLetter.allCases
                DrawingMenu(options: letters.map(\.rawValue), selected: letters.firstIndex(of: letter)) {
                    model.setTolerance(.fit(.hole(letters[$0], grade: grade), showsDeviations: shows), of: id)
                }
            case .shaft(let letter, let grade):
                let letters = ShaftFitLetter.allCases
                DrawingMenu(options: letters.map(\.rawValue), selected: letters.firstIndex(of: letter)) {
                    model.setTolerance(.fit(.shaft(letters[$0], grade: grade), showsDeviations: shows), of: id)
                }
            }
        }
        DrawingRow("Grade", colors: colors) {
            let grades = Array(FitDesignation.grades)
            DrawingMenu(options: grades.map { "IT\($0)" }, selected: grades.firstIndex(of: designation.grade)) { index in
                switch designation {
                case .hole(let letter, _):
                    model.setTolerance(.fit(.hole(letter, grade: grades[index]), showsDeviations: shows), of: id)
                case .shaft(let letter, _):
                    model.setTolerance(.fit(.shaft(letter, grade: grades[index]), showsDeviations: shows), of: id)
                }
            }
        }
        Toggle(
            "Show deviations",
            isOn: Binding(get: { shows }, set: { model.setTolerance(.fit(designation, showsDeviations: $0), of: id) }))
    }
}

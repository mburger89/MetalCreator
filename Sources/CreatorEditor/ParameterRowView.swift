import CreatorGraph
import MetalUI

/// One document parameter: its name, a slider over its range and a number field.
struct ParameterRowView: Component {
    let row: ParameterRow
    let model: EditorModel

    var content: some ElementGroup {
        let parameter = row.parameter
        let number: Double = if case .integer(let value) = parameter.value {
            Double(value)
        } else if case .number(let value) = parameter.value {
            value
        } else {
            row.range.lowerBound
        }
        // `setParameterNumber` rounds for an integer parameter and refuses what no `Int` holds.
        let write: @MainActor (Double, Bool) -> Void = { value, continuous in
            model.setParameterNumber(parameter.id, to: value, continuous: continuous)
        }
        return LabeledRow(label: parameter.name) {
            Slider(value: Binding(get: { number }, set: { write($0, true) }), in: row.range)
            NumberEntry(text: ValueText.format(number, unit: .none)) { write($0, false) }
        }
    }
}

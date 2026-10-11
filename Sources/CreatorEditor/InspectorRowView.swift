import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorStyle
import MetalUI

/// Draws one `InspectorRow` with MetalUI controls bound to the model (spec §6.4).
struct InspectorRowView: Component {
    let row: InspectorRow
    let model: EditorModel
    let node: NodeID?
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        switch row {
        case .slider(let field, let range):
            LabeledRow(label: field.label) {
                Slider(value: Binding(get: { field.number ?? range.lowerBound },
                                      set: { model.setNumber(field, to: $0, continuous: true) }),
                       in: range, onEditingChanged: { model.sliderEditingChanged($0) })
                NumberEntry(model: model, text: ValueText.format(field.value, unit: field.unit)) {
                    model.setNumber(field, to: $0)
                }
            }
        case .number(let field), .integer(let field):
            // `setNumber` writes a whole number for an integer socket, or refuses one no `Int` holds.
            // An optional input shows "Not set" while unset, and emptying the field clears it.
            LabeledRow(label: field.label) {
                Spacer()
                NumberEntry(model: model, text: Self.text(field), placeholder: field.isOptional ? "Not set" : "Value",
                            clear: Self.clear(field, model)) {
                    model.setNumber(field, to: $0)
                }
            }
        case .toggle(let field, let label):
            Toggle(label, isOn: Binding(get: { if case .bool(true)? = field.value { true } else { false } },
                                        set: { model.setInput(field, to: .bool($0)) }))
        case .segmented(let field, let options, let selected):
            Picker(field.label, selection: Binding(get: { selected ?? -1 }, set: { index in
                if let value = InspectorBuilder.segmentValue(index, options: options, type: field.type) {
                    model.setInput(field, to: value)
                }
            })) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index]).tag(index)
                }
            }
            .pickerStyle(.segmented)
        case .planePicker(let field, let selected):
            Picker(field.label, selection: Binding(get: { selected }, set: { choice in
                guard let choice else { return }
                var plane = choice.plane
                if case .plane(let current)? = field.value { plane.origin = current.origin }
                model.setInput(field, to: .plane(plane))
            })) {
                ForEach(PlaneChoice.allCases, id: \.self) { choice in
                    Text(choice.rawValue).tag(Optional(choice))
                }
            }
            .pickerStyle(.segmented)
        case .vector(let field):
            // Three compact fields, x y z; each writes the whole vector with one component replaced.
            // An unset optional vector (M3's Transform `axisDirection`) shows empty fields, and
            // emptying any field clears it.
            LabeledRow(label: field.label) {
                Spacer()
                ForEach(0..<3) { axis in
                    NumberEntry(model: model, text: Self.text(field, axis: axis), placeholder: field.isOptional ? "–" : "Value",
                                width: 52, clear: Self.clear(field, model)) {
                        model.setVectorComponent(field, axis: axis, to: $0)
                    }
                }
            }
        case .anchorGrid(let field, let selected):
            LabeledRow(label: field.label) {
                Spacer()
                AnchorGridView(selected: selected) { model.setInput(field, to: .integer($0)) }
            }
        case .treeShape(let tree):
            TreeShapeView(row: tree, model: model)
        case .text(let field):
            LabeledRow(label: field.label) {
                Spacer()
                TextEntry(model: model, text: Self.settingText(field), placeholder: "Text", width: 170) {
                    model.setInput(field, to: .text($0))
                }
            }
        case .parameterPicker(let field, let options, let selected):
            if options.isEmpty {
                LabeledRow(label: field.label) {
                    Spacer()
                    Text("No parameters").font(.callout).foregroundStyle(palette.secondaryText.color)
                }
            } else {
                Picker(field.label, selection: Binding(get: { selected }, set: { id in
                    if let id { model.chooseParameter(id, for: field) }
                })) {
                    ForEach(options, id: \.id) { parameter in
                        Text(parameter.name).tag(Optional(parameter.id))
                    }
                }
                .pickerStyle(.menu)
            }
        case .ruleSummary(let label, let summary):
            LabeledRow(label: label) {
                Spacer()
                Text(summary).font(.callout).foregroundStyle(palette.selection.color)
            }
        case .button(let title, let action):
            Button(title) { if let node { model.press(action, on: node) } }
        case .wired(let label, let source):
            LabeledRow(label: label) {
                Spacer()
                Text(source).font(.callout).foregroundStyle(palette.secondaryText.color)
            }
        case .readOnly(let label, let text):
            LabeledRow(label: label) {
                Spacer()
                Text(text).font(.callout).foregroundStyle(palette.secondaryText.color)
            }
        }
    }

    /// The text a `.text` setting holds; empty when none is stored.
    static func settingText(_ field: InputField) -> String {
        if case .text(let text)? = field.value { text } else { "" }
    }

    /// A field's text: empty while an optional input is unset, else its value (one component of a vector).
    static func text(_ field: InputField, axis: Int? = nil) -> String {
        guard field.value != nil else { return "" }
        guard let axis else { return ValueText.format(field.value, unit: field.unit) }
        return ValueText.format(field.vectorComponents[axis], unit: .none)
    }

    /// What emptying the field does: clears an optional input, nothing for a required one.
    static func clear(_ field: InputField, _ model: EditorModel) -> (@MainActor () -> Void)? {
        guard field.isOptional else { return nil }
        return { model.clearInput(field) }
    }
}

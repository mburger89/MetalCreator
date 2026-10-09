import CreatorEditor
import CreatorStyle
import MetalUI

/// The shown theme: a menu of every theme, Duplicate, Delete…, Import… and Export…, its name and its Dark controls
/// toggle. A built-in's name and toggle are disabled, with a line saying how to make it your own.
struct ThemeEditorControls: Component {
    let model: ThemeEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?
    @FocusState var nameFocused: Bool

    var content: some ElementGroup {
        let palette = Palette(themes)
        return VStack(alignment: .leading, spacing: ThemeEditorLayout.spacing.px) {
            Picker("Theme", selection: Binding(get: { model.theme.id }, set: { model.select($0) })) {
                ForEach(model.themes.themes, id: \.id) { theme in
                    Text(theme.name).tag(theme.id)
                }
            }
            .pickerStyle(.menu)
            HStack(spacing: ThemeEditorLayout.spacing.px) {
                Button("Duplicate") { model.duplicate() }
                Button("Delete…") { model.requestDelete() }
                    .disabled(!model.isEditable)
                Button("Import…") { model.withFilePicker { await model.importTheme(using: $0) } }
                Button("Export…") { model.withFilePicker { await model.exportTheme(using: $0) } }
            }
            HStack(spacing: ThemeEditorLayout.spacing.px) {
                Text("Name").font(.callout).foregroundStyle(palette.primaryText.color)
                TextField("Name", text: model.nameText, onChange: { model.typeName($0) })
                    .focused($nameFocused)
                    .onSubmit { model.commitName() }
                    .disabled(!model.isEditable)
            }
            .onChange(of: nameFocused) { wasFocused, focused in
                if wasFocused, !focused { model.commitName() }
            }
            Toggle("Dark controls", isOn: Binding(get: { model.theme.isDark }, set: { model.setDark($0) }))
                .disabled(!model.isEditable)
            if !model.isEditable {
                Text("Built-in themes are read-only. Duplicate one to make it your own.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
            }
        }
    }
}

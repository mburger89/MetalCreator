import MetalUI

/// A text field that keeps its draft while typing and submits it on Return or when it loses focus; the shown text
/// comes back whenever the model's changes (a refused entry snaps back).
struct DimensionField: Component {
    let text: String
    let width: Double
    let submit: @MainActor (String) -> Void
    @State var draft: String?
    @FocusState var isFocused: Bool

    var content: some ElementGroup {
        TextField("", text: draft ?? text, onChange: { draft = $0 })
            .focused($isFocused)
            .onSubmit { commit() }
            .frame(width: Pixels(Float(width)))
            .onChange(of: text) { draft = nil }
            .onChange(of: isFocused) { wasFocused, focused in
                if wasFocused, !focused { commit() }
            }
    }

    private func commit() {
        guard let typed = draft else { return }
        draft = nil
        submit(typed)
    }
}

import MetalUI

/// The text field of the value box (spec §7). It takes focus as it appears and reports every edit and selection to the model.
/// Return submits, Esc cancels, and losing focus cancels (a press elsewhere on the canvas clears focus); after a refusal it
/// takes focus back. The keys are `onKeyPress` handlers on the field itself, so they run only while it has focus and before
/// its own editing. Pattern: `CommentEditorField`.
struct DimensionValueBoxField: Component {
    let model: ViewportModel
    let box: DimensionValueBox
    @FocusState var isFocused: Bool

    var content: some ElementGroup {
        TextField("", text: box.draft, selection: box.selection,
                  onChange: { model.valueBoxDraftChanged($0) },
                  onSelectionChange: { model.valueBoxSelectionChanged($0) })
            .font(.caption)
            .focused($isFocused)
            .onSubmit { Task { await model.submitValueBox() } }
            .onKeyPress(.escape) {
                model.cancelValueBox()
                return .handled
            }
            .disabled(box.isChecking)
            .onAppear { isFocused = true }
            .onChange(of: isFocused) { wasFocused, focused in
                if wasFocused, !focused { model.valueBoxLostFocus() }
            }
            .onChange(of: box.isChecking) { wasChecking, checking in
                if wasChecking, !checking { isFocused = true }
            }
    }
}

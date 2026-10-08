import Foundation
import MetalUI

/// A number field. While typing, the draft is kept locally so a partial value ("6" on the way to "60") never
/// reaches the graph. Each keystroke records it with the model as a `PendingEntry` carrying this field's own
/// actions, and the entry is committed on Return, when the field loses focus, and when the model commits it
/// (a canvas press, a selection change, the shell saving or exporting), so clicking away never drops it. An
/// unreadable entry is discarded. With `clear`, an emptied field submits a clear instead (an optional input).
struct NumberEntry: Component {
    let model: EditorModel
    let text: String
    var placeholder = "Value"
    var width = 72.0
    var clear: (@MainActor () -> Void)?
    let commit: @MainActor (Double) -> Void
    @State var draft: String?
    @FocusState var isFocused: Bool
    @State var owner = UUID()

    var content: some ElementGroup {
        HStack(spacing: Pixels(0)) {
            TextField(placeholder, text: draft ?? text, onChange: { typed in
                draft = typed
                model.notePendingEntry(PendingEntry(owner: owner, text: typed, commit: commit, clear: clear))
            })
            .focused($isFocused)
            .onSubmit {
                model.commitPendingEntry()
                draft = nil
            }
        }
        .frame(width: width.px)
        .onChange(of: text) {
            draft = nil
            model.discardPendingEntry(ownedBy: owner)
        }
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused, !focused { model.commitPendingEntry() }
        }
    }
}

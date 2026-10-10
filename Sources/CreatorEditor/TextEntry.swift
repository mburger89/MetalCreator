import Foundation
import MetalUI

/// A text field for a name. As `NumberEntry` does for numbers, it keeps the draft locally and records each keystroke
/// with the model as a `PendingEntry`, committed on Return, when the field loses focus, and when the model commits
/// it (a canvas press, a selection change), so clicking away never drops it. An empty entry is committed too: the
/// command refuses it with a plain message.
struct TextEntry: Component {
    let model: EditorModel
    let text: String
    var placeholder = "Name"
    var width = 120.0
    let commit: @MainActor (String) -> Void
    @State var draft: String?
    @FocusState var isFocused: Bool
    @State var owner = UUID()

    var content: some ElementGroup {
        HStack(spacing: Pixels(0)) {
            TextField(placeholder, text: draft ?? text, onChange: { typed in
                draft = typed
                model.notePendingEntry(PendingEntry(owner: owner, text: typed, commitText: commit))
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
            if wasFocused, !focused {
                model.commitPendingEntry()
                draft = nil
            }
        }
    }
}

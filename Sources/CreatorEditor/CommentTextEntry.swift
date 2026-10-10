import CreatorGraph
import Foundation
import MetalUI

/// A note's multi-line text field in the inspector (canvas comments spec 2026-10-09 §7). While typing, the draft is
/// kept locally and recorded with the model as a text `PendingEntry`; it is committed (one "Edit Note" undo step)
/// on ⌘↩ (an `onKeyPress` on the field, MetalUI C9's answer to gap CM-a: the key reaches the handler before the
/// editor, and plain Return still breaks the line), when the field loses focus and when the model commits it (a
/// canvas press, a selection change, the shell saving), so clicking away never drops it.
struct CommentTextEntry: Component {
    let model: EditorModel
    let id: CommentID
    let text: String
    @State var draft: String?
    @FocusState var isFocused: Bool
    @State var owner = UUID()

    var content: some ElementGroup {
        TextEditor("Note", text: draft ?? text, onChange: { typed in
            draft = typed
            model.notePendingEntry(PendingEntry(owner: owner, text: typed, textCommit: { [model, id] in
                model.setNoteText(id, to: $0)
            }))
        })
        .focused($isFocused)
        .onKeyPress(keys: [.return]) { press in
            guard CommentKeys.commitsNote(press.modifiers) else { return .ignored }
            model.commitPendingEntry()
            draft = nil
            return .handled
        }
        .frame(width: Pixels(256), height: Pixels(96))
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

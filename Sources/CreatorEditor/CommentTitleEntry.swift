import CreatorGraph
import Foundation
import MetalUI

/// A frame's title field in the inspector (canvas comments spec 2026-10-09 §7): committed on Return (and, as number
/// fields are, when the field loses focus or the model commits it), as one "Edit Frame" undo step. An empty title is
/// refused (`EditorModel.setFrameTitle`) and the field shows the title again.
struct CommentTitleEntry: Component {
    let model: EditorModel
    let id: CommentID
    let title: String
    @State var draft: String?
    @FocusState var isFocused: Bool
    @State var owner = UUID()

    var content: some ElementGroup {
        TextField("Title", text: draft ?? title, onChange: { typed in
            draft = typed
            model.notePendingEntry(PendingEntry(owner: owner, text: typed, textCommit: { [model, id] in
                model.setFrameTitle(id, to: $0)
            }))
        })
        .focused($isFocused)
        .onSubmit {
            model.commitPendingEntry()
            draft = nil
        }
        .onChange(of: title) {
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

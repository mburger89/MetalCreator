import CreatorDrawing
import Foundation
import MetalUI

/// The inspector for one note (plan R20): its text in a `TextEditor`, committed on ⌘↩ (⌃↩ off macOS) or when it loses focus (one
/// "Edit Note" step), and its leaders: Add Leader, then a Remove for each.
struct NoteInspector: Component {
    let model: DrawingEditorModel
    let id: AnnotationID
    let note: DrawingNote
    let colors: DrawingColors

    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(8)) {
            Text("Note").font(.headline).foregroundStyle(colors.primary.color)
            NoteTextEntry(model: model, text: note.text) { model.setNoteText($0, of: id) }
            Text("LEADERS").font(.caption2).foregroundStyle(colors.secondary.color)
            ForEach(note.leaders.indices, id: \.self) { index in
                HStack(spacing: Pixels(8)) {
                    Text("Leader").font(.callout).foregroundStyle(colors.primary.color)
                        .frame(width: Pixels(96), alignment: .leading)
                    Button("Remove") { model.removeLeader(at: index, of: id) }
                }
            }
            Button(model.addingLeader == id ? "Click a line…" : "Add Leader") { model.beginLeader(for: id) }
            if let refusal = model.refusal {
                Text(refusal).font(.caption).foregroundStyle(colors.warning.color)
            }
        }
        .frame(width: drawingInspectorWidth.px)
    }
}

/// A multi-line text box: the draft stays local while typing and is recorded with the model, so Save, Undo or a click
/// elsewhere commits it first (as `DrawingField` does for a line of text). `submit` takes the committed text: a note's, or the
/// sheet's general notes.
struct NoteTextEntry: Component {
    let model: DrawingEditorModel
    let text: String
    let submit: @MainActor (String) -> Void
    @State var draft: String?
    @State var owner = UUID()
    @FocusState var isFocused: Bool

    var content: some ElementGroup {
        TextEditor("Note", text: draft ?? text, onChange: { typed in
            draft = typed
            model.notePendingDraft(owner: owner) { if typed != text { submit(typed) } }
        })
        .focused($isFocused)
        .onKeyPress(keys: [.return]) { press in
            guard press.modifiers.contains(.primary) else { return .ignored }
            commit()
            return .handled
        }
        .frame(width: Pixels(256), height: Pixels(96))
        .onChange(of: text) {
            draft = nil
            model.discardPendingDraft(ownedBy: owner)
        }
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused, !focused { commit() }
        }
    }

    private func commit() {
        guard let typed = draft else { return }
        draft = nil
        model.discardPendingDraft(ownedBy: owner)
        if typed != text { submit(typed) }
    }
}

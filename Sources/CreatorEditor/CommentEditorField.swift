import CreatorGraph
import MetalUI

/// The field a comment is typed into on the canvas (comments typing plan; spec 2026-10-09 §8): a multi-line
/// `TextEditor` over a note, a single-line `TextField` over a frame's title bar. It takes focus as it appears, and
/// reports every edit to the model (`commentDraftChanged`). Return in a title and ⌘↩ in a note commit, Esc cancels,
/// and losing focus commits (a press elsewhere on the canvas clears focus: it is a key region, MetalUI C9's M5-g). The
/// keys are `onKeyPress` handlers on the field itself, so they run only while it has focus and before its own editing.
/// It is drawn under the canvas's pan and zoom (`CommentEditorLayer`), so `editor.rect` is in canvas points.
struct CommentEditorField: Component {
    let model: EditorModel
    let editor: CommentEditor
    @FocusState var isFocused: Bool

    var content: some ElementGroup {
        let rect = editor.rect
        switch editor.edit.kind {
        case .noteText:
            TextEditor("Note", text: editor.edit.draft, onChange: { model.commentDraftChanged($0) })
                .font(.callout)
                .focused($isFocused)
                .onKeyPress(keys: [.return]) { press in
                    guard CommentKeys.commitsNote(press.modifiers) else { return .ignored }
                    model.commitCommentEdit()
                    return .handled
                }
                .onKeyPress(.escape) {
                    model.cancelCommentEdit()
                    return .handled
                }
                .frame(width: rect.size.x.px, height: rect.size.y.px)
                .offset(x: rect.origin.x.px, y: rect.origin.y.px)
                .onAppear { isFocused = true }
                .onChange(of: isFocused) { wasFocused, focused in
                    if wasFocused, !focused { model.commitCommentEdit() }
                }
        case .frameTitle:
            TextField("Title", text: editor.edit.draft, onChange: { model.commentDraftChanged($0) })
                .font(.system(.caption, weight: .semibold))
                .focused($isFocused)
                .onKeyPress(.escape) {
                    model.cancelCommentEdit()
                    return .handled
                }
                .onSubmit { model.commitCommentEdit() }
                .frame(width: rect.size.x.px, height: rect.size.y.px)
                .offset(x: rect.origin.x.px, y: rect.origin.y.px)
                .onAppear { isFocused = true }
                .onChange(of: isFocused) { wasFocused, focused in
                    if wasFocused, !focused { model.commitCommentEdit() }
                }
        }
    }
}

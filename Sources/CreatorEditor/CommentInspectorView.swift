import CreatorStyle
import MetalUI

/// The inspector's page for the selected comments (canvas comments spec 2026-10-09 §7): a note's text and accent, a
/// frame's title and accent, or "N comments selected".
struct CommentInspectorView: Component {
    let page: CommentPage
    let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        switch page {
        case .note(let id, let text, let accent):
            InspectorSectionView(title: "Note") {
                CommentTextEntry(model: model, id: id, text: text)
                LabeledRow(label: "Accent") {
                    AccentPicker(selected: accent) { model.setCommentAccent(id, to: $0) }
                }
            }
        case .frame(let id, let title, let accent):
            InspectorSectionView(title: "Frame") {
                LabeledRow(label: "Title") { CommentTitleEntry(model: model, id: id, title: title) }
                LabeledRow(label: "Accent") {
                    AccentPicker(selected: accent) { model.setCommentAccent(id, to: $0) }
                }
            }
        case .several(let count):
            InspectorSectionView(title: "Comments") {
                Text("\(count) comments selected").font(.callout).foregroundStyle(Palette(themes).primaryText.color)
            }
        }
    }
}

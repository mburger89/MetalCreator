import CreatorEditor
import CreatorStyle
import MetalUI

/// The theme editor's glass panel: its header, the theme's controls, the last problem, and every role's colour
/// under its group's heading, scrolling. A press or a scroll on its glass is caught here, so it never reaches the
/// viewport or the inspector beneath. Delete… asks first, naming the theme it asked about.
struct ThemeEditorPanel: Component {
    let model: ThemeEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        let width = ThemeEditorLayout.width + 2 * GraphPanelLayout.glassPadding
        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: Pixels(0)))
                .onScrollWheel { _ in true }
            GlassPanel {
                VStack(alignment: .leading, spacing: ThemeEditorLayout.spacing.px) {
                    ThemeEditorHeader(model: model)
                    ThemeEditorControls(model: model)
                    if let message = model.message {
                        Text(message).font(.caption).foregroundStyle(palette.statusError.color)
                    }
                    ScrollView {
                        ThemeRoleList(model: model)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(width: ThemeEditorLayout.width.px)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: width.px)
        .frame(maxHeight: .infinity, alignment: .top)
        .confirmationDialog(model.deleteTitle, isPresented: Binding(get: { model.isConfirmingDelete },
                                                                    set: { model.isConfirmingDelete = $0 })) {
            Button("Delete", role: .destructive) { model.confirmDelete() }
            Button("Cancel", role: .cancel) { model.isConfirmingDelete = false }
        } message: {
            Text("Its file is removed from the themes folder. Export it first to keep a copy.")
        }
    }
}

import CreatorGraph
import CreatorStyle
import MetalUI

/// The graph panel's header: the title as breadcrumbs (`BreadcrumbBar`), then borderless icon buttons in groups: Add
/// (opens the palette), Library (shows or hides the node library, lit while it shows), the zoom buttons (beside pinch and
/// ⌘-scroll on the canvas, and the +/− keys), the dock as a segmented Left / Bottom picker and Hide. The bundled glyphs
/// carry no accessibility label, so each control passes its own, the same words as its tooltip.
struct GraphPanelHeader: Component {
    let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    static let groupSpacing = Pixels(2)

    var content: some ElementGroup {
        let palette = Palette(themes)
        HStack(spacing: Pixels(6)) {
            // Lowest priority: when the row is short (a wide font, a narrow panel) the path is what truncates, not
            // a button's label.
            BreadcrumbBar(model: model)
                .layoutPriority(-1)
            Spacer(minLength: Pixels(0))
            HStack(spacing: Self.groupSpacing) {
                Button { model.openPalette() } label: { Text("Add") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(HeaderText.add)
                    .help(HeaderText.add)
                Button { model.toggleLibrary() } label: {
                    Image(systemName: "sidebar.left")
                        .foregroundStyle((model.showsLibrary ? palette.selection : palette.primaryText).color)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(model.showsLibrary ? HeaderText.hideLibrary : HeaderText.showLibrary)
                .help(model.showsLibrary ? HeaderText.hideLibrary : HeaderText.showLibrary)
            }
            HStack(spacing: Self.groupSpacing) {
                Button { model.zoom(in: false) } label: { Image(systemName: "minus.magnifyingglass") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(HeaderText.zoomOut)
                    .help(HeaderText.zoomOut)
                Button { model.zoom(in: true) } label: { Image(systemName: "plus.magnifyingglass") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(HeaderText.zoomIn)
                    .help(HeaderText.zoomIn)
            }
            HStack(spacing: Self.groupSpacing) {
                Picker("Dock", selection: Binding(get: { model.dock }, set: { model.setDock($0) })) {
                    Image(systemName: "rectangle.lefthalf.inset.filled")
                        .accessibilityLabel(HeaderText.dockLeftName)
                        .help(HeaderText.dockLeft)
                        .tag(DockSide.left)
                    Image(systemName: "rectangle.bottomhalf.inset.filled")
                        .accessibilityLabel(HeaderText.dockBottomName)
                        .help(HeaderText.dockBottom)
                        .tag(DockSide.bottom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button { model.setDock(.hidden) } label: { Image(systemName: "eye.slash") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(HeaderText.hide)
                    .help(HeaderText.hide)
            }
        }
    }
}

/// The header's tooltips, which are also its accessibility labels.
public enum HeaderText {
    public static let add = "Add a node (Space)"
    public static let showLibrary = "Show the node library"
    public static let hideLibrary = "Hide the node library"
    public static let zoomOut = "Zoom out (−)"
    public static let zoomIn = "Zoom in (+)"
    public static let dockLeftName = "Dock left"
    public static let dockBottomName = "Dock bottom"
    public static let dockLeft = "Dock left: the graph flows down"
    public static let dockBottom = "Dock at the bottom: the graph flows right"
    public static let hide = "Hide the graph (Tab)"
}

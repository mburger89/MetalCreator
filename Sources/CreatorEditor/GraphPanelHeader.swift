import CreatorGraph
import CreatorStyle
import MetalUI

/// The graph panel's header: the title, Add (opens the palette), Library (shows or hides the node
/// library), zoom buttons (beside pinch and ⌘-scroll on the canvas, and the +/− keys) and the dock
/// buttons (Left, Bottom, Hide).
struct GraphPanelHeader: Component {
    let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        HStack(spacing: Pixels(6)) {
            Text("Graph").font(.headline).foregroundStyle(Palette(themes).primaryText.color)
            Spacer()
            Button("Add") { model.openPalette() }
                .help("Add a node (Space)")
            Button("Library") { model.toggleLibrary() }
                .help(model.showsLibrary ? "Hide the node library" : "Show the node library")
            Button("−") { model.zoom(in: false) }
                .help("Zoom out (−)")
            Button("+") { model.zoom(in: true) }
                .help("Zoom in (+)")
            Button("Left") { model.setDock(.left) }
                .help("Dock left: the graph flows down")
                .disabled(model.dock == .left)
            Button("Bottom") { model.setDock(.bottom) }
                .help("Dock at the bottom: the graph flows right")
                .disabled(model.dock == .bottom)
            Button("Hide") { model.setDock(.hidden) }
                .help("Hide the graph (Tab)")
        }
    }
}

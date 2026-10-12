// Test fixture file: the app's real root in a real MetalUI window over MetalUITesting's headless platform.
import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import MetalUITesting
@testable import CreatorApp

/// `MetalCreatorApp`'s window without a screen: `AppWindowRoot` over `FakeKernel` in a `TestWindow`, with the app's
/// menu bar and input hooks installed as `main.swift` installs them (`AppCommands`, `AppInput`). Clicks and keys reach it
/// through MetalUI's own routing, so key regions, focus and gestures run as in the app.
///
/// MetalUI does not run a `MetalView`'s draw headless (its ruling HT-Q), and the app learns its window's size from the
/// viewport's draw (gap M4-a), so `model.panelPlacement` stays `nil` here. The panel is where `AppLayout` puts it for
/// `size`, and `point(inCanvas:)` and `canvasFrame` compute from that, the way the app's layout numbers do.
@MainActor
struct AppWindow {
    static let defaultSize = Vector2(1440, 900)

    let model: AppModel
    let themeEditor: ThemeEditorModel
    let testApp: TestApp
    let window: TestWindow
    let size: Vector2

    /// The app showing `graph` (docked as `dock`, the node library hidden, the canvas zoomed as given), evaluated, with
    /// the first frame drawn. The editor's double-click recogniser reads a clock that never moves, so two clicks in a row
    /// are always a double click, however loaded the machine is.
    static func open(_ graph: Graph = Graph(), dock: DockSide = .bottom, zoom: Double = 1,
                     recordsLayout: Bool = true) async throws -> AppWindow {
        let size = defaultSize
        let viewState = ViewState(dock: dock, canvasZoom: zoom, showsLibrary: false)
        let model = AppModel(kernel: FakeKernel(), file: GraphFile(graph: graph, viewState: viewState))
        await model.settle()
        let instant = ContinuousClock.now
        model.editor.now = { instant }
        let themeEditor = ThemeEditorModel(themes: model.themes)
        let input = AppInput(model: model)
        let testApp = try TestApp()
        AppCommands.install(on: testApp.app, model: model, themeEditor: themeEditor)
        let window = try testApp.openWindow(
            title: "MetalCreator", size: Size(width: Pixels(Float(size.x)), height: Pixels(Float(size.y))),
            recordsLayout: recordsLayout
        ) {
            ZStack { AppWindowRoot(model: model, input: input, themeEditor: themeEditor) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        input.install(on: window.window)
        return AppWindow(model: model, themeEditor: themeEditor, testApp: testApp, window: window, size: size)
    }

    var editor: EditorModel { model.editor }

    /// The graph canvas in window points, from `AppLayout` and `GraphPanelLayout`.
    var canvasFrame: CanvasRect {
        guard let placement = model.panelPlacement(inWindowOf: size) else { return CanvasRect(origin: .zero, size: .zero) }
        let local = GraphPanelLayout.canvasFrame(inPanelOf: placement.panel.size, flow: editor.flow,
                                                 showsLibrary: editor.showsLibrary)
        return CanvasRect(origin: placement.panel.origin + local.origin, size: local.size)
    }

    /// The window point of a point in canvas coordinates (a note's corner, say), through the canvas's pan and zoom.
    func point(inCanvas point: Vector2) -> Point<Pixels> {
        windowPoint(canvasFrame.origin + editor.transform.toScreen(point))
    }

    /// The window point of a canvas-local screen point.
    func point(inCanvasView local: Vector2) -> Point<Pixels> {
        windowPoint(canvasFrame.origin + local)
    }

    /// The window point at the middle of the comment `id` as the canvas draws it (docks and zoom included).
    func centre(ofComment id: CommentID) -> Point<Pixels> {
        guard let rect = editor.frame(ofComment: id) else { return windowPoint(.zero) }
        return point(inCanvas: rect.origin + rect.size * 0.5)
    }

    /// The window point at the middle of the frame `id`'s title bar.
    func titleBarCentre(ofFrame id: CommentID) -> Point<Pixels> {
        guard let rect = editor.frame(ofComment: id) else { return windowPoint(.zero) }
        let bar = CommentLayout.titleBar(of: rect)
        return point(inCanvas: bar.origin + bar.size * 0.5)
    }

    /// The window x where the inspector's column starts (it floats at the window's right edge).
    var inspectorColumnStart: Double { size.x - AppLayout.margin - AppLayout.inspectorWidth }

    /// A window point from a vector.
    func windowPoint(_ vector: Vector2) -> Point<Pixels> {
        Point(x: Pixels(Float(vector.x)), y: Pixels(Float(vector.y)))
    }
}

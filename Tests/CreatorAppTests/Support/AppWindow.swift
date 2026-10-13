// Test fixture file: the app's real root in a real MetalUI window over MetalUITesting's headless platform.
import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// `MetalCreatorApp`'s window without a screen: `AppWindowRoot` over `FakeKernel` in a `TestWindow`, with the app's
/// menu bar and input hooks installed as `main.swift` installs them (`AppCommands`, `AppInput`) and its hidden title bar
/// (`AppLayout.windowStyle`; the headless title bar insets are zero until a test sets them). Clicks and keys reach it
/// through MetalUI's own routing, so key regions, focus and gestures run as in the app.
///
/// MetalUI does not run a `MetalView`'s draw headless (its ruling HT-Q), so nothing here depends on one: the panel and
/// the viewport report their frames from `onGeometryChange` (gaps EP-a, M4-a), which does run, and `canvasFrame` is the
/// canvas the panel measured (`model.panelPlacement`), the frame MetalUI routes the pointer to.
@MainActor
struct AppWindow {
    static let defaultSize = Vector2(1440, 900)

    let model: AppModel
    let themeEditor: ThemeEditorModel
    let testApp: TestApp
    let window: TestWindow
    let size: Vector2

    /// The app showing `graph` (docked as `dock`, the node library hidden, the canvas zoomed as given), evaluated, with
    /// the first frame drawn. A double click is `TestWindow.doubleClick(at:)`, whose second press carries click count 2, as
    /// the platform's does.
    static func open(_ graph: Graph = Graph(), dock: DockSide = .bottom, zoom: Double = 1,
                     recordsLayout: Bool = true, windowStyle: WindowStyle = AppLayout.windowStyle,
                     options: HeadlessPlatformWindow.Options? = nil) async throws -> AppWindow {
        let size = defaultSize
        let viewState = ViewState(dock: dock, canvasZoom: zoom, showsLibrary: false)
        let model = AppModel(kernel: FakeKernel(), file: GraphFile(graph: graph, viewState: viewState))
        await model.settle()
        let themeEditor = ThemeEditorModel(themes: model.themes)
        let input = AppInput(model: model)
        let testApp = try TestApp()
        AppCommands.install(on: testApp.app, model: model, themeEditor: themeEditor)
        let window = try testApp.openWindow(
            title: "MetalCreator", size: Size(width: Pixels(Float(size.x)), height: Pixels(Float(size.y))),
            windowStyle: windowStyle, options: options, recordsLayout: recordsLayout
        ) {
            ZStack { AppWindowRoot(model: model, input: input, themeEditor: themeEditor) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        input.install(on: window.window)
        // The panel and the viewport report their frames after the build that laid them out, which draws once more.
        try await window.runUntilIdle()
        return AppWindow(model: model, themeEditor: themeEditor, testApp: testApp, window: window, size: size)
    }

    var editor: EditorModel { model.editor }

    /// The graph canvas in window points, as the panel measured itself (`EditorModel.canvasFrameInWindow`: the measured
    /// panel less the library, the header and the refusal line).
    var canvasFrame: CanvasRect {
        guard let frame = editor.canvasFrameInWindow else {
            Issue.record("the graph panel has not reported where it is: the canvas has no frame")
            return CanvasRect(origin: .zero, size: .zero)
        }
        return frame
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
        guard let rect = editor.frame(ofComment: id) else {
            Issue.record("no comment \(id) in the editor: it has no centre")
            return windowPoint(.zero)
        }
        return point(inCanvas: rect.origin + rect.size * 0.5)
    }

    /// The window point at the middle of the frame `id`'s title bar.
    func titleBarCentre(ofFrame id: CommentID) -> Point<Pixels> {
        guard let rect = editor.frame(ofComment: id) else {
            Issue.record("no frame \(id) in the editor: it has no title bar")
            return windowPoint(.zero)
        }
        let bar = CommentLayout.titleBar(of: rect)
        return point(inCanvas: bar.origin + bar.size * 0.5)
    }

    /// The add-node palette, once it is open: MetalUI publishes an `anchoredOverlay` as a `popover` node, so its frame is
    /// where the overlay put the glass.
    var palettePanel: TestElement? {
        (try? window.elements(role: .popover))?.first
    }

    /// The window x where the inspector's column starts (it floats at the window's right edge).
    var inspectorColumnStart: Double { size.x - AppLayout.margin - AppLayout.inspectorWidth }

    /// Draws one more frame with nothing changed, as a display link would after something marked the window dirty.
    func redraw() {
        window.window.setNeedsRedraw()
        window.tick()
    }

    /// A window point from a vector.
    func windowPoint(_ vector: Vector2) -> Point<Pixels> {
        Point(x: Pixels(Float(vector.x)), y: Pixels(Float(vector.y)))
    }
}

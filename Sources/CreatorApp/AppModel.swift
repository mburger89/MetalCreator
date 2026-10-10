import CreatorEditor
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorStyle
import CreatorViewport
import Foundation
import Observation

/// The app shell's state and behaviour (spec §3.2: observable state in a `@MainActor @Observable` model, views
/// thin). It is the only place that joins the graph, the nodes, the viewport and the editor:
/// - it owns the open document with its editor, graph-panel input and viewport, replaced together on New and Open;
/// - it turns graph results into `ViewportItem`s (`SceneBuilder`) and `HandleSpec`s into `ViewportHandle`s
///   (`HandleBuilder`), and turns viewport events back into graph commands (`AppModel+Viewport`);
/// - it opens, saves (`AppModel+Files`) and exports (`AppModel+Export`);
/// - it holds the app's colour theme (`themes`), which outlives every document and is never saved in one.
@MainActor
@Observable
public final class AppModel {
    public let registry: NodeRegistry
    /// The theme the window shows (spec §6.6). The views read it from the environment; the viewport is handed it.
    public let themes: ThemeStore
    public private(set) var document: DocumentModel
    public private(set) var editor: EditorModel
    public private(set) var graphInput: GraphPanelInput
    public private(set) var viewport: ViewportModel
    /// Where the document was last opened from or saved to; `nil` for a new one.
    public internal(set) var fileURL: URL?
    /// The graph and its group definitions as they were last opened or saved. The document is edited while they differ.
    var savedContent: GraphContent
    public var previewMode: PreviewMode = .final
    /// "Pick edges in view…" in progress.
    public internal(set) var pick: PickSession?
    /// A Sketch node being edited in the viewport (sketcher spec §8), or `nil`. Sketch mode works on the top level's
    /// graph, so the graph panel keeps the level it shows while one is open (`EditorModel.isLevelLocked`).
    public internal(set) var sketch: SketchSession? {
        didSet { editor.isLevelLocked = sketch != nil }
    }
    public var alert: AppAlert?
    /// The docked graph panel's width (docked left) and height (docked at the bottom), in points.
    public internal(set) var panelWidth = AppLayout.defaultPanelWidth
    public internal(set) var panelHeight = AppLayout.defaultPanelHeight

    @ObservationIgnored let kernel: any Kernel
    /// The window's open and save panels. The app sets it once the window is open.
    @ObservationIgnored public var filePicker: (any FilePicker)?
    /// Clears the window's text focus. `AppInput.install(on:)` sets it.
    @ObservationIgnored public var releaseTextFocus: (@MainActor () -> Void)?
    @ObservationIgnored var pendingDiscard: DiscardAction?
    @ObservationIgnored var handleTargets: [String: HandleTarget] = [:]
    /// The output socket behind each shown solid, by identity.
    @ObservationIgnored var sources: [ObjectIdentifier: Endpoint] = [:]
    /// The scene last sent to the current viewport (`refreshScene()`); emptied when the parts are replaced.
    @ObservationIgnored var requestedScene: [ViewportItem] = []
    @ObservationIgnored var resizeStart: Double?
    @ObservationIgnored var observationGeneration = 0
    @ObservationIgnored var sceneTask: Task<Void, Never>?

    /// `kernel` evaluates the document and tessellates for the viewport (`OCCTKernel` in the app, `FakeKernel`
    /// in tests). `file` is the document to start with, `fileURL` where it came from, `themes` the app's themes.
    public init(kernel: any Kernel, registry: NodeRegistry = BuiltInNodes.registry, file: GraphFile = GraphFile(),
                fileURL: URL? = nil, themes: ThemeStore = ThemeStore()) {
        self.kernel = kernel
        self.registry = registry
        self.themes = themes
        let parts = DocumentParts(file, registry: registry, kernel: kernel)
        document = parts.document
        editor = parts.editor
        graphInput = parts.input
        viewport = parts.viewport
        self.fileURL = fileURL
        savedContent = GraphContent(graph: file.graph, definitions: file.definitions)
        connectParts()
    }

    /// True while the graph or a group definition differs from the one last opened or saved. Camera, dock and canvas
    /// changes are saved with the file but don't count as edits.
    public var isEdited: Bool { document.content != savedContent }

    /// The file's name, or "Untitled".
    public var displayName: String { fileURL?.lastPathComponent ?? "Untitled" }

    /// Replaces the open document (New, Open). The pick and the preview mode start over.
    func load(_ file: GraphFile, from url: URL?) {
        let parts = DocumentParts(file, registry: registry, kernel: kernel)
        pick = nil
        sketch?.stop()
        sketch = nil
        previewMode = .final
        document = parts.document
        editor = parts.editor
        graphInput = parts.input
        viewport = parts.viewport
        fileURL = url
        savedContent = GraphContent(graph: file.graph, definitions: file.definitions)
        requestedScene = []
        connectParts()
    }

    /// Wires the current parts to this model, then shows their first scene and starts following them.
    private func connectParts() {
        graphInput.releaseTextFocus = { [weak self] in self?.releaseTextFocus?() }
        editor.placement = { [weak self] in self?.panelPlacement }
        connectViewportEvents()
        sceneInputsChanged()
    }

    /// Waits until the document has evaluated and the viewport shows the result.
    public func settle() async {
        repeat {
            await document.waitForEvaluation()
            if let sceneTask { await sceneTask.value }
        } while document.isEvaluating || sceneTask != nil
        await viewport.waitForMeshes()
    }
}

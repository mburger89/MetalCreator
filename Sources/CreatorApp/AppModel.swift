import CreatorEditor
import CreatorGraph
import CreatorImplicit
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
    /// The field preview of the selected node (fields spec §6): the tint on the shown parts and the slice through them. It
    /// belongs to the open document and is replaced with it; its toggles are view state, never saved.
    private(set) var fieldPreview: FieldPreviewModel
    /// The progressive preview of meshes (implicit spec §4.3): finer passes for the meshes on screen, and the "Preview 0.4 mm" badge.
    let meshRefinement: MeshRefinementModel
    /// The cut view (implicit spec §5.1): a plane that cuts the scene open. View state, never saved; off in a new document.
    let cutView = CutViewModel()
    /// The solids that display the meshes of the scene, one per mesh.
    @ObservationIgnored let meshSolids = MeshSolids()
    /// The engine implicit solids run on: Metal in the app, the CPU in tests.
    @ObservationIgnored let implicitEngine: ImplicitEngineChoice
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
    /// The export in progress, shown in the export sheet, or `nil` (implicit spec §5.3).
    public internal(set) var exportRun: ExportRun?
    /// The close or quit question in progress (`AppModel+Closing`).
    public internal(set) var closeRequest = CloseRequestState.idle
    /// The docked graph panel's width (docked left) and height (docked at the bottom), in points.
    public internal(set) var panelWidth = AppLayout.defaultPanelWidth
    public internal(set) var panelHeight = AppLayout.defaultPanelHeight

    /// Routes the viewport's dimension edits (value boxes, menus) to the open sketch or, later, the model.
    let dimensionRouter = AppDimensionEditing()

    @ObservationIgnored let kernel: any Kernel
    /// The last length unit chosen, which a new document starts in (`AppModel+Units`).
    @ObservationIgnored let unitPreference: any UnitPreference
    /// The window's open and save panels. The app sets it once the window is open.
    @ObservationIgnored public var filePicker: (any FilePicker)?
    /// Answers the window's pending close request (`Window.replyToCloseRequest`). The app sets it once the window is open.
    @ObservationIgnored public var replyToCloseRequest: (@MainActor (Bool) -> Void)?
    @ObservationIgnored var pendingDiscard: DiscardAction?
    @ObservationIgnored var handleTargets: [String: HandleTarget] = [:]
    /// The output socket behind each shown solid, by identity.
    @ObservationIgnored var sources: [ObjectIdentifier: Endpoint] = [:]
    /// The scene last sent to the current viewport (`refreshScene()`); emptied when the parts are replaced.
    @ObservationIgnored var requestedScene: [ViewportItem] = []
    @ObservationIgnored var resizeStart: Double?
    @ObservationIgnored var observationGeneration = 0
    @ObservationIgnored var sceneTask: Task<Void, Never>?
    /// The documents (by identity) with an image button waiting on a file panel (`performImage`); another press on the same
    /// document meanwhile is ignored, but a different document's buttons work.
    @ObservationIgnored var imageActionDocuments: Set<ObjectIdentifier> = []

    /// `kernel` evaluates the document and tessellates for the viewport (`OCCTKernel` in the app, `FakeKernel`
    /// in tests). `unitPreference` remembers the unit for new documents. `file` is the document to start with, `fileURL` where it came from, `themes` the app's themes.
    public init(kernel: any Kernel, registry: NodeRegistry = BuiltInNodes.registry, file: GraphFile = GraphFile(),
                fileURL: URL? = nil, themes: ThemeStore = ThemeStore(), implicitEngine: ImplicitEngineChoice = .cpu,
                unitPreference: any UnitPreference = InMemoryUnitPreference()) {
        self.kernel = kernel
        self.unitPreference = unitPreference
        self.registry = registry
        self.themes = themes
        self.implicitEngine = implicitEngine
        meshRefinement = MeshRefinementModel(engine: implicitEngine)
        let parts = DocumentParts(file, registry: registry, kernel: kernel, documentURL: fileURL, implicitEngine: implicitEngine)
        document = parts.document
        editor = parts.editor
        graphInput = parts.input
        viewport = parts.viewport
        fieldPreview = Self.makeFieldPreview(kernel: kernel, parts: parts)
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
        let parts = DocumentParts(file, registry: registry, kernel: kernel, documentURL: url, implicitEngine: implicitEngine)
        meshRefinement.reset()
        pick = nil
        sketch?.stop()
        sketch = nil
        previewMode = .final
        cutView.turnOff()
        fieldPreview.stop()
        document = parts.document
        editor = parts.editor
        graphInput = parts.input
        viewport = parts.viewport
        fieldPreview = Self.makeFieldPreview(kernel: kernel, parts: parts)
        fileURL = url
        savedContent = GraphContent(graph: file.graph, definitions: file.definitions)
        requestedScene = []
        connectParts()
    }

    /// Wires the current parts to this model, then shows their first scene and starts following them.
    private func connectParts() {
        dimensionRouter.app = self
        viewport.dimensionEditor = dimensionRouter
        connectViewportEvents()
        sceneInputsChanged()
    }

    /// Waits until the document has evaluated and the viewport shows the result.
    public func settle() async {
        repeat {
            await document.waitForEvaluation()
            if let sceneTask { await sceneTask.value }
            await fieldPreview.waitForSampling()
        } while document.isEvaluating || sceneTask != nil || fieldPreview.isSampling
        await viewport.waitForMeshes()
    }
}

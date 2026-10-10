import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Observation

/// The graph panel's state and behaviour: selection, the canvas transform, the dock, drags,
/// wiring, clipboard, the add-node palette and the node library. Every edit goes through `DocumentModel.perform`,
/// so it is undoable. Views hold no logic; tests drive this class directly (spec §3.2, §8).
@MainActor
@Observable
public final class EditorModel {
    public let document: DocumentModel

    /// Everything selected on the canvas (`EditorModel+Selection`, spec 2026-10-09 §3). Changing it commits a typed
    /// but uncommitted inspector value (to the node it was typed for) and ends any slider drag's undo coalescing.
    /// View state: never undone, never saved.
    public var canvasSelection = CanvasSelection() {
        didSet {
            guard canvasSelection != oldValue else { return }
            commitPendingEntry()
            document.endCoalescing()
        }
    }

    /// The selected nodes. Setting it replaces the whole canvas selection (comments too, once sub-project B adds
    /// them), so code that selects nodes (a click, a paste, the app's Show Producing Node) leaves nothing else
    /// selected; to keep other items, go through `select(_:mode:)` or `canvasSelection`.
    public var selection: Set<NodeID> {
        get { canvasSelection.nodes }
        set { canvasSelection = CanvasSelection(nodes: newValue) }
    }

    /// The pointer over the canvas, in canvas-local screen points; `nil` when it is elsewhere.
    public var pointerLocation: Vector2?
    public private(set) var interaction: CanvasInteraction?
    public private(set) var refusal: RefusalFeedback?
    /// True for a moment after a refusal, while the refused node shakes.
    public private(set) var isShaking = false
    public var palette: SearchPaletteState?
    /// What the node library's search field holds (`EditorModel+Library`). Not saved.
    public internal(set) var libraryQuery = ""
    /// A library type being dragged toward the canvas, once it has moved far enough to be a drag
    /// (`EditorModel+Library`); `LibraryDragOverlay` draws it at the pointer.
    public internal(set) var libraryDrag: LibraryDrag?
    public private(set) var clipboard: NodeClipboard?
    /// The last inspector button pressed, for the viewport to act on (M4/M6).
    public private(set) var inspectorRequest: InspectorRequest?
    /// Where the host lays the panel out in its window (`EditorModel+Placement`). The app shell and
    /// `GraphPanelPreview` set it; it is asked, not stored, so it always reads the current dock and sizes.
    @ObservationIgnored public var placement: (@MainActor () -> PanelPlacement?)?

    /// The dock to return to when the hidden panel is shown again.
    @ObservationIgnored private var lastVisibleDock: DockSide = .left
    @ObservationIgnored private var pressStart: Vector2?
    @ObservationIgnored private var pressHit: CanvasHit = .empty
    /// The modifiers held at the press (MetalUI's `DragGesture.Value.modifiers` at its first change).
    @ObservationIgnored private var pressModifiers: CanvasModifiers = []
    /// Esc cancelled the press's drag (`cancelPress()`): the rest of the press, to its release, is ignored.
    @ObservationIgnored private var pressCancelled = false
    /// Where the middle-button press now panning, or last panning, the canvas began (`EditorModel+MiddlePan`); `nil`
    /// once released.
    @ObservationIgnored var middlePanStart: Vector2?
    @ObservationIgnored private var pasteCount = 0
    @ObservationIgnored private var refusalSerial = 0
    @ObservationIgnored var requestSerial = 0
    /// What an inspector field holds but hasn't committed (`EditorModel+PendingEntry`).
    @ObservationIgnored var pendingEntry: PendingEntry?
    /// The undo coalescing key of the arrow-key run under way (`EditorModel+Nudge`).
    @ObservationIgnored var nudgeKey: String?
    /// Whether the trackpad scroll under way zooms (it began with ⌘ held) or pans; `nil` between scrolls
    /// (`EditorModel+Scroll`).
    @ObservationIgnored var scrollZooms: Bool?
    /// The pinch under way (`EditorModel+Pinch`).
    @ObservationIgnored var pinchStart: CanvasPinch?
    /// A ⌘-scroll ended and its glide, until its momentum ends, is ignored (`EditorModel+Scroll`).
    @ObservationIgnored var scrollGlideIgnored = false

    public init(document: DocumentModel) {
        self.document = document
        if document.viewState.dock != .hidden { lastVisibleDock = document.viewState.dock }
    }

    public var graph: Graph { document.graph }
    public var registry: NodeRegistry { document.registry }

    // MARK: - Dock and transform

    public var dock: DockSide { document.viewState.dock }
    public var flow: CanvasFlow { CanvasFlow(dock) }
    public var isPanelVisible: Bool { dock != .hidden }

    public func setDock(_ dock: DockSide) {
        if dock != .hidden { lastVisibleDock = dock }
        // The canvas moves or unmounts, so its last hover location no longer says where the pointer is.
        if dock != document.viewState.dock { pointerLocation = nil }
        document.viewState.dock = dock
    }

    /// ⇥: hides a visible panel, or shows a hidden one on the side it was last docked.
    public func toggleHidden() {
        setDock(isPanelVisible ? .hidden : lastVisibleDock)
    }

    public var transform: CanvasTransform {
        get { CanvasTransform(document.viewState) }
        set {
            document.viewState.canvasOffset = newValue.offset
            document.viewState.canvasZoom = newValue.zoom
        }
    }

    /// Zooms by one step about the pointer, or about the canvas origin when the pointer is elsewhere.
    public func zoom(in zoomIn: Bool) {
        let factor = zoomIn ? CanvasTransform.zoomStep : 1 / CanvasTransform.zoomStep
        transform = transform.zoomed(by: factor, around: pointerLocation ?? .zero)
    }

    // MARK: - Geometry

    public func shape(of node: Node) -> NodeShape { NodeShape(node, in: graph, registry: registry) }

    /// Where `node` is drawn, in display canvas points.
    public func displayOrigin(of node: Node) -> Vector2 { flow.display(node.position) }

    public func frame(of node: Node) -> CanvasRect {
        CanvasRect(origin: displayOrigin(of: node), size: NodeLayout.size(shape(of: node)))
    }

    /// A socket's centre in display canvas points.
    public func anchor(of socket: SocketRef) -> Vector2? {
        guard let node = graph.nodes[socket.endpoint.node],
              let offset = NodeLayout.socketOffset(socket.endpoint.socket, isInput: socket.isInput,
                                                   in: shape(of: node), flow: flow) else { return nil }
        return displayOrigin(of: node) + offset
    }

    /// Nodes back to front: by ID, with the selection raised above the rest.
    public var drawOrder: [Node] {
        graph.nodes.values.sorted { a, b in
            let aSelected = selection.contains(a.id), bSelected = selection.contains(b.id)
            return aSelected != bSelected ? bSelected : a.id < b.id
        }
    }

    /// What is under `screen` (canvas-local screen points): the frontmost node's socket within
    /// `NodeLayout.socketHitRadius` screen points, else the frontmost node, else empty canvas.
    public func hitTest(_ screen: Vector2) -> CanvasHit {
        let point = transform.toCanvas(screen)
        let radius = NodeLayout.socketHitRadius / transform.zoom
        for node in drawOrder.reversed() {
            let shape = shape(of: node)
            let origin = displayOrigin(of: node)
            for (sockets, isInput) in [(shape.inputs, true), (shape.outputs, false)] {
                for socket in sockets {
                    guard let offset = NodeLayout.socketOffset(socket.name, isInput: isInput, in: shape, flow: flow) else { continue }
                    if (origin + offset - point).length <= radius {
                        return .socket(SocketRef(Endpoint(node: node.id, socket: socket.name), isInput: isInput))
                    }
                }
            }
            if CanvasRect(origin: origin, size: NodeLayout.size(shape)).contains(point) { return .node(node.id) }
        }
        return .empty
    }

    /// Nodes whose drawn frame meets `rect` (display canvas points).
    public func nodes(intersecting rect: CanvasRect) -> Set<NodeID> {
        Set(graph.nodes.values.filter { frame(of: $0).intersects(rect) }.map(\.id))
    }

    // MARK: - Feedback

    func refuse(_ message: String, node: NodeID?) {
        refusalSerial += 1
        let serial = refusalSerial
        refusal = RefusalFeedback(message: message, node: node, serial: serial)
        isShaking = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            if self?.refusal?.serial == serial { self?.isShaking = false }
            try? await Task.sleep(for: .seconds(2))
            if self?.refusal?.serial == serial { self?.refusal = nil }
        }
    }

    /// Clears the refusal message (for example when the user starts another edit).
    public func clearRefusal() {
        refusal = nil
        isShaking = false
    }

    func setClipboard(_ clipboard: NodeClipboard) {
        self.clipboard = clipboard
        pasteCount = 0
    }

    func nextPasteOffset() -> Vector2 {
        pasteCount += 1
        return Vector2(24, 24) * Double(pasteCount)
    }

    func setInspectorRequest(_ request: InspectorRequest) { inspectorRequest = request }

    // MARK: - Press bookkeeping (used by EditorModel+Pointer)

    func beginPress(at screen: Vector2, modifiers: CanvasModifiers) {
        pressStart = screen
        pressHit = hitTest(screen)
        pressModifiers = modifiers
        pressCancelled = false
    }

    var currentPress: (point: Vector2, hit: CanvasHit, modifiers: CanvasModifiers)? {
        pressStart.map { ($0, pressHit, pressModifiers) }
    }

    func endPress() {
        pressStart = nil
        pressHit = .empty
        pressModifiers = []
        pressCancelled = false
        interaction = nil
    }

    /// Ends the drag under way without finishing it; the press's later changes and its release do nothing.
    func cancelPress() {
        interaction = nil
        pressCancelled = true
    }

    /// Whether Esc cancelled the press under way (`cancelPress()`).
    var isPressCancelled: Bool { pressCancelled }

    func setInteraction(_ interaction: CanvasInteraction?) { self.interaction = interaction }
}

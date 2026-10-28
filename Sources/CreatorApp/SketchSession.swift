import CreatorGraph
import CreatorKernel
import CreatorSketchEditor
import CreatorViewport
import Observation

/// One Sketch node being edited in the viewport (sketcher spec §8). It owns the editor, makes it the viewport's tool,
/// and keeps the viewport's overlay following the editor's drawing (hover, rubber band, solve) without a scene
/// refresh. `stop()` hands the viewport back.
@MainActor
public final class SketchSession {
    public let node: NodeID
    public let editor: SketchEditorModel
    private weak var viewport: ViewportModel?
    private(set) var isFollowing = false
    /// Called whenever the dimensions the viewport should show may have changed (the app's `refreshDimensions`), and when
    /// the session stops.
    var dimensionsChanged: (@MainActor () -> Void)?
    private var refreshPending = false
    /// Whether the node's plane had a result at the last refresh (a wired plane can lose it); the app says so once
    /// when it is lost.
    var hasPlane = false

    init(node: NodeID, editor: SketchEditorModel, viewport: ViewportModel) {
        self.node = node
        self.editor = editor
        self.viewport = viewport
    }

    /// Makes the editor the viewport's tool and starts drawing its overlay.
    func start() {
        isFollowing = true
        viewport?.tool = editor
        // The D tool's second pick: the dimension is shown first, then the viewport's box opens on it.
        editor.events.openValueBox = { [weak self] id in
            self?.dimensionsChanged?()
            self?.viewport?.openValueBox(for: id)
        }
        follow()
    }

    /// Gives the viewport back: no tool, no overlay.
    func stop() {
        isFollowing = false
        guard let viewport else { return }
        if viewport.tool === editor { viewport.tool = nil }
        // A box open on one of this sketch's dimensions goes with the sketch, even one being checked (its late answer is dropped).
        viewport.closeValueBox()
        viewport.showOverlay(ViewportOverlay())
        dimensionsChanged?()
    }

    /// Shows the editor's overlay and dimensions and follows them once more: the first change schedules one redraw, which follows again.
    private func follow() {
        guard isFollowing, let viewport else { return }
        let overlay = withObservationTracking {
            // Both are read inside the tracking, so a change to either schedules the next follow.
            _ = editor.dimensions
            return editor.overlay
        } onChange: { [weak self] in
            // Observation calls this as a tracked property is about to change, on the main actor that changes it.
            MainActor.assumeIsolated { self?.scheduleFollow() }
        }
        viewport.showOverlay(overlay)
        dimensionsChanged?()
    }

    private func scheduleFollow() {
        guard !refreshPending else { return }
        refreshPending = true
        Task { [weak self] in
            self?.refreshPending = false
            self?.follow()
        }
    }

    /// Waits until the overlay shows the editor's latest state (tests).
    func settle() async {
        while refreshPending { await Task.yield() }
    }
}

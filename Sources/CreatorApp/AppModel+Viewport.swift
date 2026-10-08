import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport

extension AppModel {
    /// The viewport's events, turned into graph commands and document state.
    func connectViewportEvents() {
        viewport.events.showProducingNode = { [weak self] in self?.showProducingNode($0) }
        viewport.events.handleChanged = { [weak self] id, value, phase in self?.handleChanged(id, value, phase) }
        viewport.events.nodeName = { [weak self] in self?.document.graph.nodes[$0]?.name }
        // The camera reaches the file only when it comes to rest, never per frame: writing `viewState` invalidates
        // the editor, which reads its dock and canvas transform from it (M4 carry-over, spec §7.3).
        viewport.events.cameraSettled = { [weak self] in self?.document.viewState.camera = $0 }
        viewport.events.homeChanged = { [weak self] in self?.document.viewState.homeCamera = $0 }
        // A viewport press gives the keys back, as a canvas press does (gap M5-g), and commits a typed value.
        viewport.events.pressed = { [weak self] in
            self?.editor.commitPendingEntry()
            self?.releaseTextFocus?()
        }
    }

    /// A handle drag edits its input: every step of one drag is one undo step (spec §6.5, §4.5).
    func handleChanged(_ id: String, _ value: Double, _ phase: HandleDragPhase) {
        guard let target = handleTargets[id] else { return }
        do {
            try document.perform(.setInput(target.node, target.socket, .number(value)), coalescingKey: "handle-\(id)")
        } catch {
            alert = .problem(AppProblem("The value couldn't be changed", error.message))
        }
        if phase == .ended { document.endCoalescing() }
    }

    /// "Show Producing Node": selects the node and scrolls the graph to it, showing a hidden panel first.
    func showProducingNode(_ id: NodeID) {
        guard let node = document.graph.nodes[id] else { return }
        if !editor.isPanelVisible { editor.toggleHidden() }
        editor.selection = [id]
        let zoom = editor.transform.zoom
        editor.transform = CanvasTransform(offset: AppLayout.revealPoint - editor.displayOrigin(of: node) * zoom, zoom: zoom)
    }
}
